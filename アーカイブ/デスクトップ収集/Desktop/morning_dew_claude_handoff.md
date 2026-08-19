---
元ファイル: morning_dew_claude_handoff.md
取り込み日: 2026-06-13
区分: アーカイブ（Desktop）
---

# Morning Dew YouTube Automation Handoff

## Goal

Automate the daily Morning Dew YouTube workflow for:

Yachiyo Alliance Mission Church 八千代福音キリスト教会 / `@yamc-jp`

The automation should prepare the daily video, update/create the thumbnail, upload to YouTube, apply metadata, set the thumbnail, and report the resulting video URL.

It must not upload to the wrong channel. If channel identity cannot be verified, stop.

## Current Workspace

```text
/Users/yoshiakinagumo/Documents/Codex/2026-06-04/oauth-codex-workspace-morning-dew
```

User-facing generated files are under:

```text
outputs/
```

Recent prepared assets:

```text
outputs/jun05_living_life_thumbnail.png
outputs/morning_dew_preflight_2026-06-05.json
outputs/morning_dew_final_confirmation_2026-06-05.md
```

Desktop copy:

```text
/Users/yoshiakinagumo/Desktop/jun05_living_life_thumbnail.png
```

## Daily Inputs

Source videos are in:

```text
/Users/yoshiakinagumo/Movies
```

Example 2026-06-05 selected video:

```text
/Users/yoshiakinagumo/Movies/2026-06-05 06-00-57.mov
```

Alternative small file ignored:

```text
/Users/yoshiakinagumo/Movies/2026-06-05 06-00-46.mov
```

Selection rule:

- Use the execution date in Asia/Tokyo.
- Ignore Sundays.
- Choose the newest plausible Morning Dew recording for that date.
- Exclude obviously tiny/short files that look like accidental captures.

## Metadata Pattern

Title:

```text
YYYY・M・D（曜） 聖書箇所 Morning Dew
```

Example:

```text
2026・6・5（金） 第一コリント12:12-20 Morning Dew
```

Description currently used:

```text
聖書講解メッセージを配信しています。
教会ホームページ
https://yamc-jp.com/
オンライン献金
https://yamc-jp.com/offering
```

Privacy:

```text
private or unlisted only
```

Never publish as `public` automatically.

## Thumbnail

Canva design:

```text
DAHCL4Kc7nA
```

Use this design for the thumbnail. Keep the original font and layout.

Current Canva plugin can edit and save the design, but the available tool path only provided a 600x338 preview PNG, not a reliable 1280x720 export.

For full automation, one of these is needed:

- A Canva export/download tool that can produce 1280x720 PNG.
- A deterministic local PNG generator matching the Canva layout.
- A browser/API route to download the Canva design export.

## What Failed

YouTube Studio GUI automation failed and should not be treated as real automation.

Observed problems:

- Chrome focused the wrong tab/window.
- The wrong channel was initially open: `Nagumo Yoshiaki`.
- Correct public channel `@yamc-jp` could be opened, but public channel view is not enough.
- Correct Studio channel later appeared as channel id:

```text
UC6e113ZCd1tYKq5Y-n2mnsw
```

- YouTube Studio upload dialog buttons did not reliably respond to AppleScript coordinate clicks.
- File picker and thumbnail picker were not reliably automatable.
- User had to manually choose the video.

Conclusion:

Do not rely on YouTube Studio GUI for final automation.

## Required Robust Path

Use YouTube Data API, not YouTube Studio GUI.

Needed files:

```text
client_secret.json
token.json
upload-curl.sh
```

These existed in an earlier workspace but are not visible now:

```text
/Users/yoshiakinagumo/Documents/Codex/2026-05-21/new-chat/youtube-api
```

Current search under `/Users/yoshiakinagumo/Documents/Codex` did not find them.

The automation must first locate or recreate this API folder.

## API Safety Requirements

Before upload:

1. Load OAuth credentials from `client_secret.json` and `token.json`.
2. Refresh the access token if needed.
3. Call `youtube.channels.list({ mine: true, part: ["snippet"] })`.
4. Verify that the active authenticated channel is the church channel, not the personal channel.

Expected target:

```text
Yachiyo Alliance Mission Church 八千代福音キリスト教会
@yamc-jp
```

Known correct Studio channel id seen in URL:

```text
UC6e113ZCd1tYKq5Y-n2mnsw
```

If API channel identity differs, stop immediately.

## Upload Workflow

If API assets are present and channel verification passes:

1. Select daily video from `/Users/yoshiakinagumo/Movies`.
2. Update/generate thumbnail.
3. Upload video with `privacyStatus` set to `private` or `unlisted`.
4. Set title and description.
5. Set thumbnail.
6. Verify uploaded video via `videos.list`.
7. Report URL.

If API assets are absent:

1. Prepare video/thumbnail/metadata only.
2. Do not attempt YouTube Studio GUI automation.
3. Report: `API assets missing; upload not automated`.

## Codex Automation Current State

Automation id:

```text
morning-dew-youtube-upload
```

Current desired behavior:

- Daily at 06:50 Asia/Tokyo.
- API-first only.
- No GUI upload attempts.
- Stop clearly if API assets are missing.

## Recommended Next Implementation

Build a single local script, for example:

```text
work/morning-dew-api-upload.js
```

Responsibilities:

- Find daily video.
- Read config.
- Validate OAuth/API files.
- Verify channel.
- Upload video.
- Set thumbnail.
- Save JSON log.

Suggested config:

```json
{
  "timezone": "Asia/Tokyo",
  "videoDir": "/Users/yoshiakinagumo/Movies",
  "youtubeApiDir": "/path/to/youtube-api",
  "targetChannelId": "UC6e113ZCd1tYKq5Y-n2mnsw",
  "targetHandle": "@yamc-jp",
  "privacy": "private",
  "description": "聖書講解メッセージを配信しています。\\n教会ホームページ\\nhttps://yamc-jp.com/\\nオンライン献金\\nhttps://yamc-jp.com/offering"
}
```

Main missing dependency:

Recover the old `youtube-api` directory or recreate OAuth credentials and `token.json`.

