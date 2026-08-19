#!/usr/bin/env python3
"""Resumable importer for the official Japanese card search."""

from __future__ import annotations

import argparse
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from card_db import (DEFAULT_DB, OfficialClient, connect, now_iso, parse_detail,
                     rebuild_group_keys, save_detail, stats)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="poke97 公式カードデータ更新")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--delay", type=float, default=0.35, help="公式アクセス間隔（秒）")
    parser.add_argument("--workers", type=int, default=1, choices=(1, 2), help="詳細取得の同時数（最大2）")
    parser.add_argument("--limit", type=int, default=0, help="詳細取得数の上限。0は全件")
    parser.add_argument("--list-only", action="store_true", help="一覧だけ更新")
    parser.add_argument("--retry-errors", action="store_true", help="前回失敗分も再取得")
    parser.add_argument("--refresh-all", action="store_true", help="取得済み詳細も再取得")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    db = connect(args.db)
    client = OfficialClient(delay=max(args.delay, 0.2))
    started = now_iso()
    run = db.execute("INSERT INTO import_runs(started_at,scope) VALUES(?,?)", (started, "standard"))
    run_id = run.lastrowid
    db.commit()
    try:
        first = client.list_page(1)
        max_page = int(first["maxPage"])
        hit_count = int(first["hitCnt"])
        print(f"公式一覧: {hit_count}件 / {max_page}ページ", flush=True)
        # Keep the previous complete snapshot visible until every list page has
        # arrived. Interrupting during the list phase must not leave a partial DB.
        db.execute("CREATE TEMP TABLE IF NOT EXISTS standard_seen(card_id TEXT PRIMARY KEY)")
        db.execute("DELETE FROM standard_seen")
        listed = 0
        for page in range(1, max_page + 1):
            payload = first if page == 1 else client.list_page(page)
            for item in payload["cardList"]:
                db.execute("""INSERT INTO cards(card_id,name,image_url,official_url,is_standard,listed_at)
                  VALUES(?,?,?,?,1,?) ON CONFLICT(card_id) DO UPDATE SET
                  name=excluded.name,image_url=excluded.image_url,official_url=excluded.official_url,
                  is_standard=1,listed_at=excluded.listed_at""",
                  (str(item["cardID"]), item["cardNameViewText"],
                   "https://www.pokemon-card.com" + item["cardThumbFile"],
                   f"https://www.pokemon-card.com/card-search/details.php/card/{item['cardID']}", now_iso()))
                db.execute("INSERT OR IGNORE INTO standard_seen(card_id) VALUES(?)", (str(item["cardID"]),))
                listed += 1
            db.commit()
            print(f"一覧 {page}/{max_page}ページ（{listed}件）", flush=True)
        if listed != hit_count:
            raise RuntimeError(f"公式件数{hit_count}に対し一覧保存が{listed}件でした")
        db.execute("UPDATE cards SET is_standard=0 WHERE card_id NOT IN (SELECT card_id FROM standard_seen)")
        db.execute("UPDATE import_runs SET listed_count=? WHERE id=?", (listed, run_id))
        db.commit()
        if args.list_only:
            db.execute("UPDATE import_runs SET completed_at=?,note='list only' WHERE id=?", (now_iso(), run_id))
            db.commit()
            print(stats(db))
            return 0

        condition = "is_standard=1"
        if not args.refresh_all:
            allowed = "('pending'" + (",'error'" if args.retry_errors else "") + ")"
            condition += f" AND detail_status IN {allowed}"
        rows = db.execute(f"SELECT card_id,name FROM cards WHERE {condition} ORDER BY CAST(card_id AS INTEGER) DESC").fetchall()
        if args.limit:
            rows = rows[:args.limit]
        print(f"詳細取得対象: {len(rows)}件（途中停止しても次回続きから再開）", flush=True)
        fetched = errors = 0
        thread_state = threading.local()

        def fetch_one(row):
            try:
                if not hasattr(thread_state, "client"):
                    thread_state.client = OfficialClient(delay=max(args.delay, 0.25))
                source = thread_state.client.detail(row["card_id"])
                parsed = parse_detail(row["card_id"], source)
                if not parsed["name"]:
                    raise ValueError("カード名を読み取れませんでした")
                return row, parsed, None
            except Exception as exc:  # preserve progress; error is visible and retryable
                return row, None, exc

        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for index, (row, parsed, exc) in enumerate(pool.map(fetch_one, rows), 1):
                if exc is None:
                    save_detail(db, parsed)
                    fetched += 1
                else:
                    db.execute("UPDATE cards SET detail_status='error',detail_error=? WHERE card_id=?", (str(exc)[:500], row["card_id"]))
                    errors += 1
                db.commit()
                if index == 1 or index % 25 == 0 or index == len(rows):
                    print(f"詳細 {index}/{len(rows)}（成功{fetched}・失敗{errors}） {row['name']}", flush=True)
        rebuild_group_keys(db)
        db.execute("UPDATE import_runs SET completed_at=?,fetched_count=?,error_count=? WHERE id=?", (now_iso(), fetched, errors, run_id))
        db.commit()
        print("更新完了", stats(db), flush=True)
        return 0 if errors == 0 else 2
    except KeyboardInterrupt:
        db.execute("UPDATE import_runs SET completed_at=?,note='interrupted' WHERE id=?", (now_iso(), run_id))
        db.commit()
        print("\n停止しました。保存済み地点から再開できます。", file=sys.stderr)
        return 130
    except Exception as exc:
        db.execute("UPDATE import_runs SET completed_at=?,note=? WHERE id=?", (now_iso(), str(exc)[:500], run_id))
        db.commit()
        raise


if __name__ == "__main__":
    raise SystemExit(main())
