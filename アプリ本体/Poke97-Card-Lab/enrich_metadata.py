#!/usr/bin/env python3
"""Fill exact type membership from official filtered search results."""

from card_db import OfficialClient, connect, rebuild_group_keys


TYPES = ("grass", "fire", "water", "electric", "psychic", "fighting", "dark", "steel", "dragon", "none")
CATEGORIES = (("pokemon", "ポケモン"), ("trainer", "トレーナーズ"), ("energy", "エネルギー"))
# The official detail HTML and type-filter result both omit the type for this
# print, while the official card image clearly shows the Grass icon.
OFFICIAL_IMAGE_TYPE_OVERRIDES = {"50459": "grass"}


def main() -> None:
    db = connect()
    client = OfficialClient(delay=0.25)
    assigned = 0
    for search_value, label in CATEGORIES:
        base = {"regulation_sidebar_form": "XY", "regulation": "XY", "se_ta": search_value}
        first = client.search_page({**base, "page": 1})
        if f"カードの種別：{label}" not in first.get("searchCondition", []):
            raise RuntimeError(f"種別条件が反映されませんでした: {label}")
        for page in range(1, int(first["maxPage"]) + 1):
            payload = first if page == 1 else client.search_page({**base, "page": page})
            for item in payload["cardList"]:
                db.execute("UPDATE cards SET category=? WHERE card_id=? AND is_standard=1", (label, str(item["cardID"])))
                assigned += 1
            db.commit()
        print(f"種別 {label}: {first['hitCnt']}件", flush=True)
    db.execute("UPDATE cards SET subcategory='' WHERE is_standard=1 AND category='ポケモン'")
    db.commit()
    for card_type in TYPES:
        base = {
            "regulation_sidebar_form": "XY", "regulation": "XY", "se_ta": "pokemon",
            f"sc_pm_type_{card_type}": 1,
        }
        first = client.search_page({**base, "page": 1})
        conditions = first.get("searchCondition", [])
        if not any(text.startswith("タイプ：") for text in conditions):
            raise RuntimeError(f"タイプ条件が反映されませんでした: {card_type} / {conditions}")
        for page in range(1, int(first["maxPage"]) + 1):
            payload = first if page == 1 else client.search_page({**base, "page": page})
            for item in payload["cardList"]:
                db.execute("UPDATE cards SET pokemon_type=? WHERE card_id=? AND is_standard=1", (card_type, str(item["cardID"])))
                assigned += 1
            db.commit()
        print(f"タイプ {card_type}: {first['hitCnt']}件", flush=True)
    for card_id, card_type in OFFICIAL_IMAGE_TYPE_OVERRIDES.items():
        db.execute("UPDATE cards SET pokemon_type=? WHERE card_id=? AND is_standard=1", (card_type, card_id))
    db.commit()
    missing = db.execute("SELECT COUNT(*) FROM cards WHERE is_standard=1 AND category='ポケモン' AND pokemon_type='' ").fetchone()[0]
    # Category and type are rewritten above, so the same-card grouping is stale.
    rebuild_group_keys(db)
    print(f"タイプ照合完了 / 延べ{assigned}件 / 未設定{missing}件")


if __name__ == "__main__":
    main()
