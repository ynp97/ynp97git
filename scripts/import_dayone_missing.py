#!/usr/bin/env python3
"""Import only missing Day One entries into the Obsidian journal."""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import tempfile
import urllib.parse
import zipfile
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


WEEKDAYS = "月火水木金土日"
HEADER_RE = re.compile(r"^## (\d{4}-\d{2}-\d{2})（([月火水木金土日])）(\d{1,2}:\d{2}:\d{2})$", re.M)
PHOTO_MARKER_RE = re.compile(r"!\[\]\(dayone-moment://([^)]+)\)")
WEATHER_MAP = {
    "Clear": "快晴", "Mostly Clear": "ほぼ快晴", "Mostly Sunny": "ほぼ快晴",
    "Partly Cloudy": "晴れ時々曇り", "Mostly Cloudy": "ほぼ曇り", "Cloudy": "曇り",
    "Overcast": "曇り", "Light Rain": "小雨", "Possible Light Rain": "小雨の可能性",
    "Rain": "雨", "Rain Showers": "にわか雨", "Showers": "にわか雨",
    "Showers Nearby": "付近でにわか雨", "Patchy Fog": "所により霧",
    "Mist and Fog": "霧",
}
THEMES = {
    "教会": ["教会"],
    "説教・釈義": ["説教", "釈義", "メッセージ"],
    "筋トレ・運動": ["筋トレ", "運動", "ジム", "ヨガ", "走る"],
    "映画": ["映画"],
    "音楽": ["音楽", "録音", "ギター", "曲"],
    "ゲーム": ["ゲーム"],
    "ポケカ": ["ポケカ", "カード", "デッキ"],
    "AI": ["AI", "人工知能", "ChatGPT", "Codex", "Claude"],
}


def load_archive(path: Path) -> dict:
    with zipfile.ZipFile(path) as archive:
        json_names = [name for name in archive.namelist() if name.lower().endswith(".json")]
        if len(json_names) != 1:
            raise RuntimeError(f"Expected one JSON in {path.name}, found {len(json_names)}")
        data = json.loads(archive.read(json_names[0]))
        label = urllib.parse.unquote(Path(json_names[0]).stem)
        media = {Path(name).name: name for name in archive.namelist() if name.startswith("photos/")}
    return {"path": path, "label": label, "entries": data["entries"], "media": media}


def entry_datetime(entry: dict) -> datetime:
    raw = entry["creationDate"].replace("Z", "+00:00")
    value = datetime.fromisoformat(raw)
    zone_name = entry.get("timeZone") or (entry.get("location") or {}).get("timeZoneName") or "Asia/Tokyo"
    try:
        zone = ZoneInfo(zone_name)
    except Exception:
        zone = ZoneInfo("Asia/Tokyo")
    return value.astimezone(zone)


def heading_for(entry: dict) -> str:
    value = entry_datetime(entry)
    return f"## {value:%Y-%m-%d}（{WEEKDAYS[value.weekday()]}）{value.hour}:{value:%M:%S}"


def photo_filename(photo: dict, media_names: dict[str, str]) -> str | None:
    md5 = photo.get("md5")
    if not md5:
        return None
    matches = sorted(name for name in media_names if name.startswith(md5 + "."))
    return matches[0] if matches else None


def rich_text_fallback(entry: dict) -> str:
    raw = entry.get("richText")
    if not raw:
        return ""
    try:
        rich = json.loads(raw)
    except Exception:
        return ""
    chunks = []
    for item in rich.get("contents", []):
        if isinstance(item.get("text"), str):
            chunks.append(item["text"])
    return "".join(chunks)


def body_for(entry: dict, media_names: dict[str, str]) -> tuple[str, list[str]]:
    photos = entry.get("photos") or []
    identifier_map = {}
    photo_files = []
    for photo in photos:
        filename = photo_filename(photo, media_names)
        if filename:
            photo_files.append(filename)
            if photo.get("identifier"):
                identifier_map[photo["identifier"]] = filename

    text = entry.get("text")
    if not isinstance(text, str):
        text = rich_text_fallback(entry)

    embedded = set()

    def replace_photo(match: re.Match[str]) -> str:
        filename = identifier_map.get(match.group(1))
        if not filename:
            return ""
        embedded.add(filename)
        return f"![[{filename}]]"

    text = PHOTO_MARKER_RE.sub(replace_photo, text)
    text = re.sub(r"\\([.!?])", r"\1", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    not_embedded = [name for name in photo_files if name not in embedded]
    if not_embedded:
        suffix = "\n\n".join(f"![[{name}]]" for name in not_embedded)
        text = f"{text}\n\n{suffix}".strip()
    return text, photo_files


def location_text(entry: dict) -> str | None:
    location = entry.get("location") or {}
    parts = []
    for key in ("placeName", "localityName", "administrativeArea", "country"):
        value = location.get(key)
        if value and value not in parts:
            parts.append(str(value))
    return ", ".join(parts) if parts else None


def weather_text(entry: dict) -> str | None:
    weather = entry.get("weather") or {}
    temperature = weather.get("temperatureCelsius")
    condition = weather.get("conditionsDescription")
    if condition:
        condition = WEATHER_MAP.get(condition, condition)
    parts = []
    if isinstance(temperature, (int, float)):
        shown = str(int(temperature)) if float(temperature).is_integer() else f"{temperature:.1f}"
        parts.append(f"{shown}°C")
    if condition:
        parts.append(str(condition))
    return " ".join(parts) if parts else None


def section_for(entry: dict, archive: dict) -> tuple[str, list[str]]:
    heading = heading_for(entry)
    body, photo_files = body_for(entry, archive["media"])
    meta_parts = []
    weather = weather_text(entry)
    location = location_text(entry)
    if weather:
        meta_parts.append(f"🌤 {weather}")
    if location:
        meta_parts.append(f"📍 {location}")
    meta_lines = []
    if meta_parts:
        meta_lines.append("> " + " ｜ ".join(meta_parts))
    tags = entry.get("tags") or []
    tag_names = [tag.get("name") if isinstance(tag, dict) else str(tag) for tag in tags]
    tag_names = [name for name in tag_names if name]
    if tag_names:
        meta_lines.append("> 🏷 " + ", ".join(tag_names))
    flags = []
    if entry.get("starred"):
        flags.append("⭐ お気に入り")
    if entry.get("isPinned"):
        flags.append("📌 固定")
    if flags:
        meta_lines.append("> " + " ｜ ".join(flags))

    uuid = entry.get("uuid", "")
    comment = f"<!-- dayone-uuid: {uuid} | journal: {archive['label']} -->"
    chunks = [heading, "", comment]
    if meta_lines:
        chunks.extend(["", "\n".join(meta_lines)])
    if body:
        chunks.extend(["", body])
    return "\n".join(chunks).rstrip() + "\n", photo_files


def journal_prefix(year: int, count: int) -> str:
    return (
        "---\n"
        f"title: ジャーナル {year}\n"
        "type: journal\n"
        f"year: {year}\n"
        f"entries: {count}\n"
        "---\n\n"
        f"# ジャーナル {year}\n\n"
        "[[_ジャーナル目次|← 目次]]\n\n"
    )


def parse_sections(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    matches = list(HEADER_RE.finditer(text))
    sections = {}
    for index, match in enumerate(matches):
        start = match.start()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections[match.group(0)] = text[start:end].strip() + "\n"
    return sections


def heading_sort_key(heading: str) -> datetime:
    match = HEADER_RE.match(heading)
    if not match:
        return datetime.max
    return datetime.strptime(match.group(1) + " " + match.group(3), "%Y-%m-%d %H:%M:%S")


def year_counts(journal_dir: Path) -> dict[int, int]:
    counts = {}
    for path in sorted(journal_dir.glob("[0-9][0-9][0-9][0-9].md")):
        counts[int(path.stem)] = len(HEADER_RE.findall(path.read_text(encoding="utf-8")))
    return counts


def write_index(journal_dir: Path, photo_count: int) -> None:
    counts = year_counts(journal_dir)
    total = sum(counts.values())
    start_year, end_year = min(counts), max(counts)
    rows = "\n".join(f"| {year} | {count} | [[{year}]] |" for year, count in counts.items())
    text = f"""---
title: ジャーナル目次
type: journal-index
total_entries: {total}
period: {start_year}–{end_year}
photos: {photo_count}
---

# 📔 ジャーナル目次

日記アプリからの書き出し（2013年7月〜2026年7月）。全 **{total:,}** エントリを年ごとのノートに整理しています。和暦は西暦に変換済みです。

## 📖 まず読むなら

[[13年の振り返り ── 2013-2026]] ── 旧924件を通読して作成した振り返りエッセイ。今回追加した記録は未反映です。

## 年別

| 年 | エントリ数 | ノート |
| --- | ---: | --- |
{rows}
| **合計** | **{total:,}** | |

## 写真

{photo_count:,} 枚の写真を `media/ジャーナル写真/` に取り込みました。一覧は [[ジャーナル写真一覧]] を参照してください。
"""
    (journal_dir / "_ジャーナル目次.md").write_text(text, encoding="utf-8")


def write_gallery(journal_dir: Path, media_dir: Path) -> None:
    names = sorted(path.name for path in media_dir.iterdir() if path.is_file())
    embeds = "\n".join(f"![[{name}]]" for name in names)
    text = f"""---
title: ジャーナル写真一覧
type: gallery
count: {len(names)}
---

# 🖼 ジャーナル写真一覧

[[_ジャーナル目次|← 目次]]

日記書き出しに含まれていた写真 {len(names):,} 枚です。2026-07-18追加分は該当する日記本文にも紐付けて表示しています。

{embeds}
"""
    (journal_dir / "ジャーナル写真一覧.md").write_text(text, encoding="utf-8")


def analytics_for(archives: list[dict]) -> dict:
    records = []
    for archive in archives:
        for entry in archive["entries"]:
            dt = entry_datetime(entry)
            text, _ = body_for(entry, archive["media"])
            records.append((dt, entry, text))
    records.sort(key=lambda item: item[0])
    years = sorted({item[0].year for item in records})
    year_index = {year: index for index, year in enumerate(years)}
    entries_per_year = [0] * len(years)
    chars_per_year = [0] * len(years)
    hour_counts = [0] * 24
    weekday_counts = [0] * 7
    month_counter = Counter()
    location_counter = Counter()
    temp_counter = Counter()
    theme_trends = {name: [0] * len(years) for name in THEMES}
    weights = []
    movie_scores = []

    for dt, entry, text in records:
        index = year_index[dt.year]
        entries_per_year[index] += 1
        chars_per_year[index] += len(text)
        hour_counts[dt.hour] += 1
        weekday_counts[dt.weekday()] += 1
        month_counter[f"{dt.year:04d}-{dt.month:02d}"] += 1
        locality = (entry.get("location") or {}).get("localityName")
        if locality:
            location_counter[locality] += 1
        temperature = (entry.get("weather") or {}).get("temperatureCelsius")
        if isinstance(temperature, (int, float)):
            temp_counter[str(math.floor(float(temperature) / 5) * 5)] += 1
        for name, words in THEMES.items():
            theme_trends[name][index] += sum(text.count(word) for word in words)
        for match in re.finditer(r"(?<!\d)(\d{2}(?:[.,]\d)?)\s*(?:kg|キロ)", text, re.I):
            value = float(match.group(1).replace(",", "."))
            if 50 <= value <= 120:
                weights.append([f"{dt:%Y-%m-%d}", value])
        for match in re.finditer(r"(?<!\d)(\d{1,3})\s*点", text):
            value = int(match.group(1))
            if 0 <= value <= 100:
                movie_scores.append(value)

    months = []
    cursor_year, cursor_month = records[0][0].year, 1
    end_year = records[-1][0].year
    while cursor_year <= end_year:
        months.append(f"{cursor_year:04d}-{cursor_month:02d}")
        cursor_month += 1
        if cursor_month == 13:
            cursor_month = 1
            cursor_year += 1
    movie_buckets = Counter(str((score // 10) * 10) for score in movie_scores)
    days = (records[-1][0].date() - records[0][0].date()).days
    return {
        "years": years,
        "entriesPerYear": entries_per_year,
        "charsPerYear": chars_per_year,
        "months": months,
        "monthCounts": [month_counter[month] for month in months],
        "hourCounts": hour_counts,
        "weekdayCounts": weekday_counts,
        "weight": weights,
        "tempBuckets": dict(sorted(temp_counter.items(), key=lambda item: int(item[0]))),
        "movieScores": dict(sorted(movie_buckets.items(), key=lambda item: int(item[0]))),
        "movieCount": len(movie_scores),
        "movieAvg": round(sum(movie_scores) / len(movie_scores), 1) if movie_scores else 0,
        "locations": [[name, count] for name, count in location_counter.most_common(8)],
        "themeTrends": theme_trends,
        "totals": {
            "entries": len(records),
            "chars": sum(len(text) for _, _, text in records),
            "photos": sum(len(entry.get("photos") or []) for _, entry, _ in records),
            "days": days,
        },
    }


def update_dashboard(path: Path, archives: list[dict]) -> None:
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    data = analytics_for(archives)
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    text, count = re.subn(r"const D = \{.*?\};\n", f"const D = {payload};\n", text, count=1)
    if count != 1:
        raise RuntimeError("Dashboard data block was not found")
    text = re.sub(r"<p class=\"sub\">.*?</p>", '<p class="sub">2013年7月 – 2026年7月 ／ 全1,113エントリの可視化</p>', text, count=1)
    text = text.replace("13年間の月別エントリ数。2021–2022年の空白がはっきり見えます。", "13年間の月別エントリ数。Day Oneの2冊の日記を統合しています。")
    path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", type=Path, required=True)
    parser.add_argument("--zip", type=Path, action="append", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    vault = args.vault.resolve()
    journal_dir = vault / "ジャーナル"
    media_dir = vault / "media" / "ジャーナル写真"
    archives = [load_archive(path.resolve()) for path in args.zip]

    existing_headings = set()
    for path in journal_dir.glob("[0-9][0-9][0-9][0-9].md"):
        existing_headings.update(match.group(0) for match in HEADER_RE.finditer(path.read_text(encoding="utf-8")))

    missing = []
    duplicate_headings = []
    for archive in archives:
        for entry in archive["entries"]:
            heading = heading_for(entry)
            if heading in existing_headings:
                duplicate_headings.append(heading)
            else:
                missing.append((archive, entry, heading))

    by_archive = Counter(archive["label"] for archive, _, _ in missing)
    by_year = Counter(entry_datetime(entry).year for _, entry, _ in missing)
    photo_names = set()
    for archive, entry, _ in missing:
        _, names = body_for(entry, archive["media"])
        photo_names.update(names)

    report = {
        "existingEntries": len(existing_headings),
        "sourceEntries": sum(len(archive["entries"]) for archive in archives),
        "missingEntries": len(missing),
        "missingByJournal": dict(sorted(by_archive.items())),
        "missingByYear": dict(sorted(by_year.items())),
        "missingPhotos": len(photo_names),
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))

    first_import = len(existing_headings) == 924 and len(missing) == 189 and len(photo_names) == 178
    already_complete = len(existing_headings) == 1113 and len(missing) == 0 and len(photo_names) == 0
    if not (first_import or already_complete):
        raise RuntimeError("Safety check failed: source and Obsidian counts do not match an expected state")
    if already_complete:
        print(json.dumps({"status": "already-complete"}, ensure_ascii=False, indent=2))
        return
    if not args.apply:
        return

    backup_dir = Path(tempfile.mkdtemp(prefix="dayone_obsidian_backup_"))
    for path in [
        journal_dir / "2020.md", journal_dir / "2023.md", journal_dir / "2026.md",
        journal_dir / "_ジャーナル目次.md", journal_dir / "ジャーナル写真一覧.md",
        journal_dir / "ジャーナル・ダッシュボード.html",
    ]:
        if path.exists():
            shutil.copy2(path, backup_dir / path.name)

    new_sections_by_year: dict[int, dict[str, str]] = defaultdict(dict)
    for archive, entry, heading in missing:
        section, _ = section_for(entry, archive)
        new_sections_by_year[entry_datetime(entry).year][heading] = section

    for year, new_sections in sorted(new_sections_by_year.items()):
        path = journal_dir / f"{year}.md"
        sections = parse_sections(path)
        overlap = set(sections).intersection(new_sections)
        if overlap:
            raise RuntimeError(f"Duplicate section during merge: {sorted(overlap)[:3]}")
        sections.update(new_sections)
        ordered = sorted(sections, key=heading_sort_key)
        content = journal_prefix(year, len(ordered)) + "\n".join(sections[key].rstrip() for key in ordered) + "\n"
        path.write_text(content, encoding="utf-8")

    media_dir.mkdir(parents=True, exist_ok=True)
    for archive in archives:
        needed = set()
        for source_archive, entry, _ in missing:
            if source_archive is archive:
                _, names = body_for(entry, archive["media"])
                needed.update(names)
        with zipfile.ZipFile(archive["path"]) as zip_file:
            for filename in sorted(needed):
                destination = media_dir / filename
                if destination.exists():
                    continue
                member = archive["media"].get(filename)
                if not member:
                    raise RuntimeError(f"Missing archive member for {filename}")
                temp_path = destination.with_suffix(destination.suffix + ".tmp")
                temp_path.write_bytes(zip_file.read(member))
                temp_path.replace(destination)

    write_gallery(journal_dir, media_dir)
    write_index(journal_dir, len([path for path in media_dir.iterdir() if path.is_file()]))
    update_dashboard(journal_dir / "ジャーナル・ダッシュボード.html", archives)
    print(json.dumps({"status": "completed", "backup": str(backup_dir)}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
