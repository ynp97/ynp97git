#!/usr/bin/env python3
"""CLI used by poke97/Codex so card conditions do not consume web-page tokens."""

from __future__ import annotations

import argparse
import json

from card_db import connect, query_cards, stats


def main() -> None:
    parser = argparse.ArgumentParser(description="poke97 ローカルカード検索")
    parser.add_argument("q", nargs="?", default="", help="名前・本文のAND検索。空白で語を分ける")
    parser.add_argument("--name", default="", help="カード名だけを検索する")
    parser.add_argument("--ability-text", default="", help="特性の文だけを検索する（ワザの文は当てない）")
    parser.add_argument("--attack-text", default="", help="ワザの文だけを検索する（特性の文は当てない）")
    parser.add_argument("--attack-energy", default="", help="ワザに必要なエネルギー（water / fire など）")
    parser.add_argument("--category", choices=("ポケモン", "トレーナーズ", "エネルギー"), default="")
    parser.add_argument("--subcategory", default="", help="グッズ / サポート / スタジアム / ポケモンのどうぐ など")
    parser.add_argument("--type", default="")
    parser.add_argument("--stage", default="")
    parser.add_argument("--ability", choices=("yes", "no"), default="")
    parser.add_argument("--hp-min", default="")
    parser.add_argument("--hp-max", default="")
    parser.add_argument("--damage-min", default="", help="条件つきダメージ（×・＋）も要計算として残す")
    parser.add_argument("--damage-certain", action="store_true", help="印刷ダメージだけで確定するワザに絞る")
    parser.add_argument("--limit", default="100")
    parser.add_argument("--versions", action="store_true", help="各カードの版（セット・番号）も並べる")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    db = connect()
    result = query_cards(db, {
        "q": args.q, "name_q": args.name, "ability_q": args.ability_text,
        "attack_q": args.attack_text, "attack_energy": args.attack_energy,
        "category": args.category, "subcategory": args.subcategory,
        "type": args.type, "stage": args.stage, "ability": args.ability,
        "hp_min": args.hp_min, "hp_max": args.hp_max,
        "damage_min": args.damage_min,
        "damage_certain": "yes" if args.damage_certain else "",
        "limit": args.limit,
    })
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
        return
    info = stats(db)
    print(f"該当 {result['total']}種（表示 {len(result['cards'])}種・版は{result['prints']}枚）"
          f" / DB準備状況 {info['ready']}枚＝{info['kinds']}種")
    for card in result["cards"]:
        identity = " ".join(filter(None, [card["set_code"], card["card_number"]]))
        others = len(card["variants"]) - 1
        suffix = f"（他{others}版）" if others > 0 else ""
        print(f"{card['name']}｜{identity}{suffix}｜{card['official_url']}")
        for attack in card["attacks"]:
            if attack.get("damage_note", "").startswith("要計算"):
                print(f"    ↳ {attack['name']} {attack['printed_damage']}｜{attack['damage_note']}")
        if args.versions:
            for variant in card["variants"]:
                mark = {2: "通常枠", 1: "プロモ等", 0: "別枠レア"}[variant["frame_rank"]]
                print(f"    ・{variant['set_code']} {variant['card_number']} {variant['rarity'] or '-'}｜{mark}")


if __name__ == "__main__":
    main()
