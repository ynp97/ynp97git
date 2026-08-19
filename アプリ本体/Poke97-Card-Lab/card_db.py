#!/usr/bin/env python3
"""Official Japanese Pokemon Card data importer and local search helpers."""

from __future__ import annotations

import hashlib
import html
import json
import re
import sqlite3
import time
import unicodedata
import warnings
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlencode

warnings.filterwarnings("ignore", message="urllib3 v2 only supports OpenSSL.*")
import requests


BASE = "https://www.pokemon-card.com"
LIST_URL = f"{BASE}/card-search/resultAPI.php"
DETAIL_URL = f"{BASE}/card-search/details.php/card/{{card_id}}"
IMAGE_BASE = BASE
DEFAULT_DB = Path(__file__).resolve().parent / "data" / "cards.sqlite3"
USER_AGENT = "Poke97CardLab/0.1 (personal local research; polite sequential fetch)"

SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS cards (
  card_id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  subcategory TEXT NOT NULL DEFAULT '',
  stage TEXT NOT NULL DEFAULT '',
  hp INTEGER,
  pokemon_type TEXT NOT NULL DEFAULT '',
  weakness TEXT NOT NULL DEFAULT '',
  resistance TEXT NOT NULL DEFAULT '',
  retreat INTEGER,
  set_code TEXT NOT NULL DEFAULT '',
  card_number TEXT NOT NULL DEFAULT '',
  rarity TEXT NOT NULL DEFAULT '',
  illustrator TEXT NOT NULL DEFAULT '',
  product TEXT NOT NULL DEFAULT '',
  image_url TEXT NOT NULL DEFAULT '',
  official_url TEXT NOT NULL DEFAULT '',
  body_text TEXT NOT NULL DEFAULT '',
  search_text TEXT NOT NULL DEFAULT '',
  is_standard INTEGER NOT NULL DEFAULT 1,
  detail_status TEXT NOT NULL DEFAULT 'pending',
  detail_error TEXT NOT NULL DEFAULT '',
  source_hash TEXT NOT NULL DEFAULT '',
  listed_at TEXT NOT NULL DEFAULT '',
  fetched_at TEXT NOT NULL DEFAULT '',
  group_key TEXT NOT NULL DEFAULT '',
  frame_rank INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_cards_standard ON cards(is_standard);
CREATE INDEX IF NOT EXISTS idx_cards_name ON cards(name);
CREATE INDEX IF NOT EXISTS idx_cards_category ON cards(category);
CREATE INDEX IF NOT EXISTS idx_cards_type ON cards(pokemon_type);
CREATE TABLE IF NOT EXISTS abilities (
  card_id TEXT NOT NULL REFERENCES cards(card_id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  text TEXT NOT NULL DEFAULT '',
  PRIMARY KEY(card_id, ordinal)
);
CREATE TABLE IF NOT EXISTS attacks (
  card_id TEXT NOT NULL REFERENCES cards(card_id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  energy TEXT NOT NULL DEFAULT '',
  printed_damage TEXT NOT NULL DEFAULT '',
  base_damage INTEGER,
  damage_modifier TEXT NOT NULL DEFAULT '',
  text TEXT NOT NULL DEFAULT '',
  PRIMARY KEY(card_id, ordinal)
);
CREATE INDEX IF NOT EXISTS idx_attacks_damage ON attacks(base_damage);
CREATE TABLE IF NOT EXISTS import_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at TEXT NOT NULL,
  completed_at TEXT NOT NULL DEFAULT '',
  scope TEXT NOT NULL,
  listed_count INTEGER NOT NULL DEFAULT 0,
  fetched_count INTEGER NOT NULL DEFAULT 0,
  error_count INTEGER NOT NULL DEFAULT 0,
  note TEXT NOT NULL DEFAULT ''
);
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def connect(db_path: Path | str = DEFAULT_DB) -> sqlite3.Connection:
    path = Path(db_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    db.executescript(SCHEMA)
    existing = {row["name"] for row in db.execute("PRAGMA table_info(cards)")}
    for column, ddl in (("group_key", "TEXT NOT NULL DEFAULT ''"), ("frame_rank", "INTEGER NOT NULL DEFAULT 1")):
        if column not in existing:
            db.execute(f"ALTER TABLE cards ADD COLUMN {column} {ddl}")
    db.execute("CREATE INDEX IF NOT EXISTS idx_cards_group ON cards(group_key)")
    ensure_group_keys(db)
    return db


# --- Same-card grouping -----------------------------------------------------
# The official standard list intentionally contains many prints of one card:
# alternate-art rares, deck/promo reprints, and older sets whose wording differs
# but whose effect is identical. Searching for deck building should answer with
# cards, not with prints, so every row gets a group_key.
#
# Pokemon: same name AND same printed effect (stage/HP/type/weakness/resistance/
# retreat/abilities/attacks/body). Same-name Pokemon are frequently different
# cards, so the effect must be part of the key.
# Trainers and Energy: same name and subtype. A same-name Trainer is the same
# card by the game's own rules -- that is why old prints remain standard-legal --
# and their reprints only differ in wording and spacing.
#
# No row is ever deleted or merged in storage. Every print stays queryable by
# card_id so the sales side can still tell the versions apart.

def normalize_effect_text(value: str) -> str:
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", value or ""))


def frame_rank_of(card_number: str) -> int:
    """2=通常枠 / 1=プロモ等の番号 / 0=番号が分母を超える別枠レア（AR・SR・SAR等）."""
    match = re.match(r"^(\d+)\s*/\s*(\d+)$", (card_number or "").strip())
    if not match:
        return 1
    return 2 if int(match.group(1)) <= int(match.group(2)) else 0


def group_key_of(card: dict[str, Any], abilities: list[Any], attacks: list[Any]) -> str:
    name = normalize_effect_text(card["name"])
    if card["category"] != "ポケモン":
        return "X|" + "|".join([card["category"], card["subcategory"], name])
    payload = "|".join([
        name, str(card["stage"]), str(card["hp"]), str(card["pokemon_type"]),
        normalize_effect_text(card["weakness"]), normalize_effect_text(card["resistance"]),
        str(card["retreat"]),
        *(normalize_effect_text(f"{a[0]}/{a[1]}") for a in abilities),
        "#",
        *(normalize_effect_text(f"{a[0]}/{a[1]}/{a[2]}/{a[3]}") for a in attacks),
        "#", normalize_effect_text(card["body_text"]),
    ])
    return "P|" + name + "|" + hashlib.sha1(payload.encode("utf-8")).hexdigest()[:16]


def rebuild_group_keys(db: sqlite3.Connection) -> int:
    """Recompute grouping for every stored card. Reads the DB only; never refetches."""
    abilities: dict[str, list[Any]] = {}
    attacks: dict[str, list[Any]] = {}
    for row in db.execute("SELECT card_id,name,text FROM abilities ORDER BY card_id,ordinal"):
        abilities.setdefault(row["card_id"], []).append((row["name"], row["text"]))
    for row in db.execute("SELECT card_id,name,energy,printed_damage,text FROM attacks ORDER BY card_id,ordinal"):
        attacks.setdefault(row["card_id"], []).append(
            (row["name"], row["energy"], row["printed_damage"], row["text"]))
    updates = []
    for row in db.execute("""SELECT card_id,name,category,subcategory,stage,hp,pokemon_type,
      weakness,resistance,retreat,card_number,body_text FROM cards"""):
        card = dict(row)
        key = group_key_of(card, abilities.get(card["card_id"], []), attacks.get(card["card_id"], []))
        updates.append((key, frame_rank_of(card["card_number"]), card["card_id"]))
    db.executemany("UPDATE cards SET group_key=?, frame_rank=? WHERE card_id=?", updates)
    db.commit()
    return len(updates)


def ensure_group_keys(db: sqlite3.Connection) -> None:
    stale = db.execute("SELECT 1 FROM cards WHERE group_key='' LIMIT 1").fetchone()
    if stale:
        rebuild_group_keys(db)


def strip_tags(fragment: str) -> str:
    fragment = re.sub(r"<br\s*/?>", "\n", fragment, flags=re.I)
    fragment = re.sub(r"<[^>]+>", "", fragment)
    return re.sub(r"[ \t\r\f\v]+", " ", html.unescape(fragment)).strip()


def first(pattern: str, source: str, flags: int = re.S, default: str = "") -> str:
    match = re.search(pattern, source, flags)
    return strip_tags(match.group(1)) if match else default


def class_icons(fragment: str) -> list[str]:
    return re.findall(r'class="[^"]*\bicon-([a-z]+)\b[^"]*"', fragment)


# The official page prints energy and type inside rules text as an icon element,
# not as a word. strip_tags() deletes those elements, which silently changes what
# the card says:
#   「基本[水]エネルギーを1枚」        -> 「基本エネルギーを1枚」
#   「自分の[鋼]または[超]ポケモンに」 -> 「自分のまたはポケモンに」
# Both text search and any AI reading the text then answer the wrong card set, and
# the second example is not even a grammatical sentence. Keep the icon as 【水】.
ICON_JA = {
    "grass": "草", "fire": "炎", "water": "水", "electric": "雷", "lightning": "雷",
    "psychic": "超", "fighting": "闘", "dark": "悪", "darkness": "悪",
    "steel": "鋼", "metal": "鋼", "dragon": "ドラゴン", "fairy": "フェアリー",
    "none": "無色", "colorless": "無色",
}


def text_with_icons(fragment: str) -> str:
    def mark(match: re.Match[str]) -> str:
        label = ICON_JA.get(match.group(1), match.group(1))
        return f"【{label}】" if label else ""

    marked = re.sub(r'<\w+\b[^>]*\bclass="[^"]*\bicon-([a-z]+)\b[^"]*"[^>]*>', mark, fragment, flags=re.I)
    return strip_tags(marked)


def parse_damage(value: str) -> tuple[int | None, str]:
    value = value.strip()
    match = re.search(r"(\d+)", value)
    if not match:
        return None, value
    modifier = value[match.end():].strip()
    return int(match.group(1)), modifier


def parse_detail(card_id: str, source: str) -> dict[str, Any]:
    """Parse stable semantic regions of the official detail page.

    The source HTML is deliberately not persisted. A hash is kept so a future
    refresh can detect source changes without bulk-copying page markup/images.
    """
    name = first(r'<h1[^>]*class="[^"]*Heading1[^"]*"[^>]*>(.*?)</h1>', source)
    image_path = first(r'<img[^>]*class="[^"]*fit[^"]*"[^>]*src="([^"]+)"', source)
    category = ""
    if "_P_" in image_path:
        category = "ポケモン"
    elif "_T_" in image_path:
        category = "トレーナーズ"
    elif "_E_" in image_path:
        category = "エネルギー"

    subtext_match = re.search(r'<div class="subtext[^>]*>(.*?)</div>', source, re.S)
    subtext = subtext_match.group(1) if subtext_match else ""
    set_code_match = re.search(r'class="img-regulation"[^>]*alt="([^"]+)"', subtext)
    set_code = html.unescape(set_code_match.group(1)).strip() if set_code_match else ""
    number_match = re.search(r'&nbsp;\s*([^<&]+?)\s*&nbsp;\s*/\s*&nbsp;\s*([^<&]+?)\s*&nbsp;', subtext)
    card_number = f"{number_match.group(1).strip()}/{number_match.group(2).strip()}" if number_match else ""
    rarity_match = re.search(r'/rarity/ic_rare_([^./"]+)', subtext)
    rarity = rarity_match.group(1).upper() if rarity_match else ""
    illustrator = first(r'<div class="author">.*?<a[^>]*>(.*?)</a>', source)
    products = [strip_tags(x) for x in re.findall(r'<li class="List_item">\s*<a[^>]*>(.*?)</a>', source, re.S)]

    right_match = re.search(r'<div class="RightBox-inner">(.*?)</div>\s*</div>\s*<div class="clear">', source, re.S)
    right = right_match.group(1) if right_match else ""
    stage = re.sub(r"\s+", "", first(r'<span class="type">(.*?)</span>', right))
    hp_text = first(r'<span class="hp-num">(.*?)</span>', right)
    hp = int(hp_text) if hp_text.isdigit() else None
    top_match = re.search(r'<div class="TopInfo[^>]*>(.*?)(?=<h2\b|<table\b)', right, re.S)
    top = top_match.group(1) if top_match else ""
    pokemon_types = class_icons(top)
    pokemon_type = pokemon_types[-1] if pokemon_types else ""

    weakness = resistance = ""
    retreat = None
    table_match = re.search(r'<table[^>]*>.*?<tr>.*?</tr>\s*<tr>(.*?)</tr>\s*</table>', right, re.S)
    if table_match:
        cells = re.findall(r'<td[^>]*>(.*?)</td>', table_match.group(1), re.S)
        if len(cells) >= 3:
            weak_icons = class_icons(cells[0])
            resist_icons = class_icons(cells[1])
            weakness = ((weak_icons[0] + " ") if weak_icons else "") + strip_tags(cells[0])
            resistance = ((resist_icons[0] + " ") if resist_icons else "") + strip_tags(cells[1])
            retreat = len(class_icons(cells[2]))

    # Read h2/h4/p in document order. This preserves ability/attack pairing.
    tokens = re.findall(r'<(h2|h4|p)\b[^>]*>(.*?)</\1>', right, re.S | re.I)
    section = ""
    subcategory = ""
    abilities: list[dict[str, Any]] = []
    attacks: list[dict[str, Any]] = []
    body_parts: list[str] = []
    pending: tuple[str, dict[str, Any]] | None = None
    for tag, fragment in tokens:
        tag = tag.lower()
        # Rules text (<p>) keeps its energy/type icons as 【水】; see text_with_icons.
        plain = text_with_icons(fragment) if tag == "p" else strip_tags(fragment)
        if not plain and tag != "h4":
            continue
        if tag == "h2":
            section = plain
            pending = None
            if category != "ポケモン" and plain not in {"特性", "ワザ", "進化"} and not subcategory:
                subcategory = plain
            continue
        if tag == "h4" and section == "特性":
            item = {"name": plain, "text": ""}
            abilities.append(item)
            pending = ("ability", item)
        elif tag == "h4" and section == "ワザ":
            damage = first(r'<span class="f_right[^>]*>(.*?)</span>', fragment)
            name_fragment = re.sub(r'<span class="f_right[^>]*>.*?</span>', '', fragment, flags=re.S)
            item = {
                "name": strip_tags(name_fragment),
                "energy": ",".join(class_icons(name_fragment)),
                "printed_damage": damage,
                "text": "",
            }
            item["base_damage"], item["damage_modifier"] = parse_damage(damage)
            attacks.append(item)
            pending = ("attack", item)
        elif tag == "p":
            body_parts.append(plain)
            if pending:
                pending[1]["text"] = (pending[1]["text"] + "\n" + plain).strip()

    # Trainer/Energy pages usually have their rules text directly after a subtype h2.
    if not subcategory and category == "エネルギー":
        subcategory = "エネルギー"
    all_text = "\n".join(body_parts)
    search_fields: Iterable[str] = [
        name, category, subcategory, stage, pokemon_type, weakness, resistance,
        set_code, card_number, rarity, illustrator, " ".join(products), all_text,
        *(a["name"] + " " + a["text"] for a in abilities),
        *(a["name"] + " " + a["printed_damage"] + " " + a["text"] for a in attacks),
    ]
    return {
        "card_id": str(card_id), "name": name, "category": category,
        "subcategory": subcategory, "stage": stage, "hp": hp,
        "pokemon_type": pokemon_type, "weakness": weakness.strip(),
        "resistance": resistance.strip(), "retreat": retreat,
        "set_code": set_code, "card_number": card_number, "rarity": rarity,
        "illustrator": illustrator, "product": " / ".join(products),
        "image_url": IMAGE_BASE + image_path if image_path.startswith("/") else image_path,
        "official_url": DETAIL_URL.format(card_id=card_id), "body_text": all_text,
        "search_text": "\n".join(x for x in search_fields if x),
        "source_hash": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "abilities": abilities, "attacks": attacks,
    }


@dataclass
class OfficialClient:
    delay: float = 0.35
    timeout: float = 30.0
    retries: int = 3

    def __post_init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": USER_AGENT, "Accept-Language": "ja"})
        self._last_request = 0.0

    def _wait(self) -> None:
        remaining = self.delay - (time.monotonic() - self._last_request)
        if remaining > 0:
            time.sleep(remaining)

    def get(self, url: str, **kwargs: Any) -> requests.Response:
        error: Exception | None = None
        for attempt in range(self.retries):
            try:
                self._wait()
                response = self.session.get(url, timeout=self.timeout, **kwargs)
                self._last_request = time.monotonic()
                response.raise_for_status()
                return response
            except requests.RequestException as exc:
                error = exc
                time.sleep(min(2 ** attempt, 5))
        raise RuntimeError(f"公式サイトの取得に失敗: {error}")

    def list_page(self, page: int, scope: str = "standard") -> dict[str, Any]:
        regulation = "XY" if scope == "standard" else "all"
        params = {"regulation_sidebar_form": regulation, "regulation": regulation, "page": page}
        return self.search_page(params)

    def search_page(self, params: dict[str, Any]) -> dict[str, Any]:
        response = self.get(LIST_URL, params=params)
        payload = response.json()
        if payload.get("result") != 1:
            raise RuntimeError(f"公式検索APIエラー: {payload.get('errMsg', '不明')}")
        if params.get("regulation") == "XY" and "レギュレーション：スタンダード" not in payload.get("searchCondition", []):
            raise RuntimeError("公式検索にスタンダード条件が反映されませんでした")
        return payload

    def detail(self, card_id: str) -> str:
        response = self.get(DETAIL_URL.format(card_id=card_id))
        response.encoding = response.apparent_encoding or "utf-8"
        return response.text


def save_detail(db: sqlite3.Connection, parsed: dict[str, Any]) -> None:
    fields = [
        "name", "category", "subcategory", "stage", "hp", "pokemon_type",
        "weakness", "resistance", "retreat", "set_code", "card_number", "rarity",
        "illustrator", "product", "image_url", "official_url", "body_text",
        "search_text", "source_hash",
    ]
    assignments = ", ".join(f"{field}=?" for field in fields)
    values = [parsed[field] for field in fields]
    db.execute(
        f"UPDATE cards SET {assignments}, detail_status='ok', detail_error='', fetched_at=?, group_key='' WHERE card_id=?",
        [*values, now_iso(), parsed["card_id"]],
    )
    db.execute("DELETE FROM abilities WHERE card_id=?", (parsed["card_id"],))
    db.execute("DELETE FROM attacks WHERE card_id=?", (parsed["card_id"],))
    db.executemany(
        "INSERT INTO abilities(card_id, ordinal, name, text) VALUES(?,?,?,?)",
        [(parsed["card_id"], i, x["name"], x["text"]) for i, x in enumerate(parsed["abilities"], 1)],
    )
    db.executemany(
        """INSERT INTO attacks(card_id, ordinal, name, energy, printed_damage, base_damage, damage_modifier, text)
           VALUES(?,?,?,?,?,?,?,?)""",
        [(parsed["card_id"], i, x["name"], x["energy"], x["printed_damage"],
          x["base_damage"], x["damage_modifier"], x["text"]) for i, x in enumerate(parsed["attacks"], 1)],
    )


def stats(db: sqlite3.Connection) -> dict[str, Any]:
    row = db.execute("""SELECT COUNT(*) total,
        SUM(detail_status='ok') ready, SUM(detail_status='error') errors,
        SUM(category='ポケモン') pokemon, SUM(category='トレーナーズ') trainers,
        SUM(category='エネルギー') energy
        FROM cards WHERE is_standard=1""").fetchone()
    latest = db.execute("SELECT MAX(fetched_at) FROM cards").fetchone()[0] or ""
    kinds = db.execute("""SELECT COUNT(DISTINCT group_key) FROM cards
        WHERE is_standard=1 AND detail_status='ok'""").fetchone()[0]
    # 2026-08-07以前に取得した本文には、エネルギーとタイプのアイコンが入っていない
    # （strip_tags が消していた）。その状態で「【水】エネルギーを持ってくる特性」を
    # 探すと、正しく0件が返る。取り直し前だと分かるように印を返す。
    icons = db.execute("SELECT COUNT(*) FROM abilities WHERE text LIKE '%【%'").fetchone()[0] \
        + db.execute("SELECT COUNT(*) FROM attacks WHERE text LIKE '%【%'").fetchone()[0]
    return {**dict(row), "latest": latest, "kinds": kinds, "icon_texts": icons}


def query_cards(db: sqlite3.Connection, params: dict[str, str]) -> dict[str, Any]:
    where = ["c.is_standard=1", "c.detail_status='ok'"]
    values: list[Any] = []
    def terms_of(value: str) -> list[str]:
        return [t.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
                for t in re.split(r"\s+", value.strip()) if t]

    q = params.get("q", "").strip()
    for term in terms_of(q):
        where.append("c.search_text LIKE ? ESCAPE '\\'")
        values.append(f"%{term}%")
    for term in terms_of(params.get("name_q", "")):
        where.append("c.name LIKE ? ESCAPE '\\'")
        values.append(f"%{term}%")
    # 「特性で〜できるポケモン」を答えるには、本文全体ではなく特性の文だけを見る必要がある。
    # 全文検索だと、同じ語がワザの文に書いてあるカードが混ざって区別できない。
    # 複数語は「同じ1つの特性（ワザ）の中に全部ある」ことを求める。
    for scope, table, alias, column in (
        ("ability_q", "abilities", "ab", "ab.name || ' ' || ab.text"),
        ("attack_q", "attacks", "ax2", "ax2.name || ' ' || ax2.printed_damage || ' ' || ax2.text"),
    ):
        scope_terms = terms_of(params.get(scope, ""))
        if not scope_terms:
            continue
        conds = " AND ".join([f"{column} LIKE ? ESCAPE '\\'"] * len(scope_terms))
        where.append(f"EXISTS (SELECT 1 FROM {table} {alias} WHERE {alias}.card_id=c.card_id AND {conds})")
        values.extend(f"%{term}%" for term in scope_terms)
    attack_energy = params.get("attack_energy", "").strip()
    if attack_energy:
        where.append("EXISTS (SELECT 1 FROM attacks ax3 WHERE ax3.card_id=c.card_id AND ax3.energy LIKE ?)")
        values.append(f"%{attack_energy}%")
    mappings = {
        "category": "c.category", "subcategory": "c.subcategory", "stage": "c.stage",
        "type": "c.pokemon_type", "set_code": "c.set_code",
    }
    for key, column in mappings.items():
        value = params.get(key, "").strip()
        if value:
            where.append(f"{column}=?")
            values.append(value)
    if params.get("ability") == "yes":
        where.append("EXISTS (SELECT 1 FROM abilities ab WHERE ab.card_id=c.card_id)")
    elif params.get("ability") == "no":
        where.append("NOT EXISTS (SELECT 1 FROM abilities ab WHERE ab.card_id=c.card_id)")
    for key, op in (("hp_min", ">="), ("hp_max", "<=")):
        value = params.get(key, "").strip()
        if value.isdigit():
            where.append(f"c.hp {op} ?")
            values.append(int(value))
    # A printed number below the threshold does not mean the attack cannot reach
    # it: '×', '＋' and text conditions are decided at play time. Those attacks
    # stay in the result and are labelled 要計算 rather than silently dropped.
    damage_min = params.get("damage_min", "").strip()
    damage_certain_only = params.get("damage_certain") == "yes"
    if damage_min.isdigit():
        if damage_certain_only:
            where.append("EXISTS (SELECT 1 FROM attacks ax WHERE ax.card_id=c.card_id AND ax.base_damage>=?)")
            values.append(int(damage_min))
        else:
            where.append("""EXISTS (SELECT 1 FROM attacks ax WHERE ax.card_id=c.card_id
              AND (ax.base_damage>=? OR ax.damage_modifier!=''))""")
            values.append(int(damage_min))
    limit = min(max(int(params.get("limit", "100") or 100), 1), 500)
    offset = max(int(params.get("offset", "0") or 0), 0)
    where_sql = " AND ".join(where)
    total = db.execute(f"SELECT COUNT(DISTINCT c.group_key) FROM cards c WHERE {where_sql}", values).fetchone()[0]
    prints = db.execute(f"SELECT COUNT(*) FROM cards c WHERE {where_sql}", values).fetchone()[0]
    # One row per card, not per print. The representative is the newest regular
    # print (frame_rank 2), falling back to promos, then to alternate-art rares.
    rows = db.execute(f"""SELECT * FROM (
        SELECT c.*, COUNT(*) OVER (PARTITION BY c.group_key) variant_count,
          ROW_NUMBER() OVER (PARTITION BY c.group_key
            ORDER BY c.frame_rank DESC, CAST(c.card_id AS INTEGER) DESC) pick
        FROM cards c WHERE {where_sql}
      ) WHERE pick=1
      ORDER BY CAST(card_id AS INTEGER) DESC LIMIT ? OFFSET ?""", [*values, limit, offset]).fetchall()
    threshold = int(damage_min) if damage_min.isdigit() else None
    cards = []
    for row in rows:
        item = dict(row)
        item["match_reason"] = " / ".join(filter(None, [
            q and f"本文: {q}",
            params.get("name_q") and f"名前: {params['name_q']}",
            params.get("ability_q") and f"特性の文: {params['ability_q']}",
            params.get("attack_q") and f"ワザの文: {params['attack_q']}",
            params.get("attack_energy") and f"ワザのエネルギー: {params['attack_energy']}",
            params.get("category"), params.get("type"),
        ])) or "全件"
        item["abilities"] = [dict(x) for x in db.execute("SELECT name,text FROM abilities WHERE card_id=? ORDER BY ordinal", (row["card_id"],))]
        item["attacks"] = [dict(x) for x in db.execute("SELECT name,energy,printed_damage,base_damage,damage_modifier,text FROM attacks WHERE card_id=? ORDER BY ordinal", (row["card_id"],))]
        if threshold is not None:
            for attack in item["attacks"]:
                base = attack["base_damage"]
                if base is not None and base >= threshold:
                    attack["damage_note"] = "確定"
                elif attack["damage_modifier"]:
                    attack["damage_note"] = f"要計算（{attack['printed_damage']}・条件しだいで{threshold}以上）"
                else:
                    attack["damage_note"] = ""
        item["variants"] = [dict(x) for x in db.execute(
            """SELECT card_id,set_code,card_number,rarity,product,official_url,frame_rank
               FROM cards WHERE group_key=? AND is_standard=1 AND detail_status='ok'
               ORDER BY frame_rank DESC, CAST(card_id AS INTEGER) DESC""", (row["group_key"],))]
        cards.append(item)
    return {"total": total, "prints": prints, "limit": limit, "offset": offset, "cards": cards}
