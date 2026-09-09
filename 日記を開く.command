#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DIARY_PERSONAL_ROOT="$PWD/日記アプリ個人用"
exec env DIARY_LIBRARY_PATH="$DIARY_PERSONAL_ROOT" DIARY_PERSONAL_COPY="$DIARY_PERSONAL_ROOT" DIARY_ENABLE_JOURNAL_WRITES=1 "$PWD/アプリ本体/diary-viewer/dist/DiaryViewer.app/Contents/MacOS/DiaryViewer"
