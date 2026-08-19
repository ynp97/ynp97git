#!/usr/bin/env python3
"""日本語の質問を、ローカルDBの検索条件へ翻訳して答える窓。

なぜ二段にするか
----------------
AIにカードを思い出させると、実在しないカードや古いテキストが混ざる。
逆にAIを使わないと、「特性で水エネルギーを持ってくる」のような聞き方が
検索条件に落ちない。そこで役割を分ける。

  1段目（AI）  質問 → 検索条件。**広めに** 出させる。取りこぼしが一番の敵。
  2段目（DB）  条件でローカルDBを全件走査。ここだけが事実の出どころ。
  3段目（AI）  DBが返した候補**だけ**を読んで、質問に合うものを選び理由を書く。

AIが名前を挙げてよいのは3段目に渡した候補の中だけ。候補に無いカードを
書いたら、その場で「DBに無い」と印をつけて返す（作り話の混入を見えるようにする）。

接続先はOpenAI互換なら何でもよい。既定はLM Studio（無料・端末内で完結）。
外部APIを使うときは base_url と api_key を差し替える。
"""

from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path
from typing import Any

import requests

from card_db import query_cards

CONFIG_PATH = Path(__file__).resolve().parent / "data" / "ai_config.json"

DEFAULT_CONFIG: dict[str, Any] = {
    # LM Studio の「Local Server」を起動しておく（既定ポート1234）。
    "base_url": "http://127.0.0.1:1234/v1",
    "api_key": "",
    "model": "",           # 空ならサーバーが持っている最初のモデルを使う
    "max_cards": 60,       # 3段目でAIに読ませる候補の上限
    "timeout": 300,
    "temperature": 0.2,
}

FIELD_GUIDE = """使える検索条件（JSONのキー）:
- q            名前・本文・特性・ワザを合わせた全文。空白で区切ると AND
- name_q       カード名だけ
- ability_q    特性の名前と文だけ（「特性で〜できる」はここを使う）
- attack_q     ワザの名前と文だけ
- attack_energy ワザに必要なエネルギー1色（water/fire/grass/electric/psychic/fighting/dark/steel/dragon/none）
- category     ポケモン / トレーナーズ / エネルギー
- subcategory  グッズ / サポート / スタジアム / ポケモンのどうぐ / 基本エネルギー / 特殊エネルギー
- type         ポケモンのタイプ（上と同じ英語の色名）
- stage        たね / 1進化 / 2進化
- ability      yes（特性あり）/ no（特性なし）
- hp_min, hp_max   数字
- damage_min       ワザのダメージ下限（×・＋つきは「要計算」として残る）
- damage_certain   "yes" にすると印刷ダメージで確定するものだけ

カード本文の書き方（大事）:
- エネルギーとタイプは本文中で 【水】【炎】【草】【雷】【超】【闘】【悪】【鋼】【ドラゴン】【無色】 と書かれている。
  例:「自分の山札から基本【水】エネルギーを1枚選び、自分のポケモンにつける。」
- だから「水エネルギー」で探しても当たらない。【水】 と エネルギー を別の語として並べる。
- 言い回しは一定しない（山札から／トラッシュから／手札から／つける／つけ替える／加える）。
  **動詞は条件に入れず、広めに残す。** 絞り込みは3段目の読みでやる。
"""

PLAN_SYSTEM = f"""あなたはポケモンカードのローカルDBの検索係です。
日本語の質問を、下の条件へ翻訳してください。

{FIELD_GUIDE}
守ること:
- **取りこぼしを一番きらう。** 迷ったら条件をゆるくする。語は少なく。
- 言い回しの違いを拾うため、検索は最大3件まで並べてよい（結果は合算される）。
- ダメージが足りるかどうかを印刷ダメージだけで切らない。
- JSONだけを返す。説明文やコードブロックの記号は書かない。

返す形:
{{"searches": [{{"ability_q": "【水】 エネルギー", "category": "ポケモン"}}],
 "reading": "質問をどう読んだかを1文で"}}"""

JUDGE_SYSTEM = """あなたはポケモンカードの読み手です。
下に、ローカルDBが返した候補カードの全文があります。

守ること:
- **候補の中からだけ選ぶ。** ここに無いカードの名前を書かない。記憶から補わない。
- 質問に合うものを選び、カードの文のどこが根拠かを短く書く。
- 迷うもの（条件つき・解釈が割れる）は「たぶん」に分けて、理由を書く。
- 候補の中に答えが無さそうなら、無いと書く。取り繕わない。
- 検索の条件が原因で漏れていそうなら、missing にどう探し直すべきか書く。
- JSONだけを返す。説明文やコードブロックの記号は書かない。

返す形:
{"hits": [{"card_id": "50416", "name": "パーモット", "why": "特性『はつでんタッチ』が…"}],
 "maybe": [{"card_id": "…", "name": "…", "why": "…"}],
 "answer": "全体の答えを2〜4文で",
 "missing": "漏れの心配があれば書く。無ければ空文字"}"""


def load_config() -> dict[str, Any]:
    config = dict(DEFAULT_CONFIG)
    if CONFIG_PATH.is_file():
        try:
            config.update(json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            pass
    return config


def save_config(values: dict[str, Any]) -> dict[str, Any]:
    config = load_config()
    for key in DEFAULT_CONFIG:
        if key in values:
            config[key] = values[key]
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")
    return config


class AIUnavailable(RuntimeError):
    """接続先が動いていない、または応答が読めない。質問票を手で渡す道へ落とす。"""


def list_models(config: dict[str, Any]) -> list[str]:
    url = config["base_url"].rstrip("/") + "/models"
    headers = {"Authorization": f"Bearer {config['api_key']}"} if config.get("api_key") else {}
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
    except requests.RequestException as exc:
        raise AIUnavailable(f"{url} につながりません（{exc.__class__.__name__}）") from exc
    return [item.get("id", "") for item in response.json().get("data", []) if item.get("id")]


def chat(config: dict[str, Any], system: str, user: str) -> str:
    model = config.get("model") or ""
    if not model:
        models = list_models(config)
        if not models:
            raise AIUnavailable("接続先にモデルが1つもありません")
        model = models[0]
    url = config["base_url"].rstrip("/") + "/chat/completions"
    headers = {"Content-Type": "application/json"}
    if config.get("api_key"):
        headers["Authorization"] = f"Bearer {config['api_key']}"
    payload = {
        "model": model,
        "temperature": config.get("temperature", 0.2),
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
    }
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=config.get("timeout", 300))
        response.raise_for_status()
    except requests.RequestException as exc:
        raise AIUnavailable(f"{url} への問い合わせが失敗しました（{exc}）") from exc
    try:
        return response.json()["choices"][0]["message"]["content"]
    except (KeyError, IndexError, ValueError) as exc:
        raise AIUnavailable(f"応答の形が想定と違います: {response.text[:300]}") from exc


def extract_json(text: str) -> dict[str, Any]:
    """モデルは ```json や <think> を付けてくることがある。最初の { から釣り合う } まで取る。"""
    text = re.sub(r"<think>.*?</think>", "", text or "", flags=re.S)
    start = text.find("{")
    if start < 0:
        raise AIUnavailable(f"JSONが見つかりません: {text[:300]}")
    depth = 0
    in_string = False
    escape = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start:index + 1])
                except json.JSONDecodeError as exc:
                    raise AIUnavailable(f"JSONを読めません: {exc}") from exc
    raise AIUnavailable(f"JSONが閉じていません: {text[:300]}")


ALLOWED_KEYS = {"q", "name_q", "ability_q", "attack_q", "attack_energy", "category",
                "subcategory", "type", "stage", "ability", "hp_min", "hp_max",
                "damage_min", "damage_certain"}


def run_searches(db: sqlite3.Connection, searches: list[dict[str, Any]], limit_each: int = 200) -> tuple[list[dict], list[dict], int]:
    """条件ごとに全件走査し、同じカード（group_key）は1件に畳んで合算する。"""
    used: list[dict] = []
    merged: dict[str, dict] = {}
    total = 0
    for raw in searches[:3]:
        params = {key: str(value) for key, value in (raw or {}).items() if key in ALLOWED_KEYS and str(value).strip()}
        if not params:
            continue
        params["limit"] = str(limit_each)
        result = query_cards(db, params)
        used.append({**{k: v for k, v in params.items() if k != "limit"}, "該当": result["total"]})
        total += result["total"]
        for card in result["cards"]:
            merged.setdefault(card["group_key"], card)
    return used, list(merged.values()), total


def compact(card: dict[str, Any]) -> str:
    head = " / ".join(filter(None, [
        card.get("category"), card.get("subcategory"), card.get("stage"),
        card.get("pokemon_type"), card.get("hp") and f"HP{card['hp']}",
    ]))
    lines = [f"[{card['card_id']}] {card['name']}（{head}）"]
    for ability in card.get("abilities", []):
        lines.append(f"  特性 {ability['name']}: {ability['text']}")
    for attack in card.get("attacks", []):
        cost = attack.get("energy") or "-"
        lines.append(f"  ワザ {attack['name']}[{cost}] {attack.get('printed_damage') or ''} {attack.get('text') or ''}".rstrip())
    return "\n".join(lines)


def build_packet(question: str, cards: list[dict[str, Any]], used: list[dict]) -> str:
    """AIが動かないときに、そのままClaude等へ貼れる質問票。"""
    conditions = "\n".join(f"- {json.dumps(u, ensure_ascii=False)}" for u in used) or "- （検索条件なし）"
    body = "\n".join(compact(card) for card in cards)
    return (f"【質問】{question}\n\n【ローカルDBで使った条件】\n{conditions}\n\n"
            f"【候補カード {len(cards)}種（この中からだけ選ぶこと）】\n{body}\n")


def ask(db: sqlite3.Connection, question: str, config: dict[str, Any] | None = None) -> dict[str, Any]:
    config = config or load_config()
    question = (question or "").strip()
    if not question:
        raise ValueError("質問が空です")

    plan_raw = chat(config, PLAN_SYSTEM, question)
    plan = extract_json(plan_raw)
    searches = plan.get("searches") or []
    if isinstance(searches, dict):
        searches = [searches]
    used, cards, hit_total = run_searches(db, searches)

    max_cards = int(config.get("max_cards", 60))
    trimmed = len(cards) > max_cards
    shown = cards[:max_cards]
    packet = build_packet(question, shown, used)

    judged: dict[str, Any] = {}
    judge_error = ""
    if shown:
        try:
            judged = extract_json(chat(config, JUDGE_SYSTEM, packet))
        except AIUnavailable as exc:
            judge_error = str(exc)

    # AIが候補に無いカードを書いていないか、こちらで突き合わせる。
    known = {card["card_id"]: card["name"] for card in shown}
    known_names = set(known.values())
    invented: list[str] = []
    for bucket in ("hits", "maybe"):
        for item in judged.get(bucket) or []:
            name = str(item.get("name", "")).strip()
            card_id = str(item.get("card_id", "")).strip()
            if card_id in known:
                item["name"] = known[card_id]
            elif name in known_names:
                item["card_id"] = next(cid for cid, n in known.items() if n == name)
            else:
                item["unverified"] = True
                invented.append(name or card_id or "（名前なし）")

    return {
        "question": question,
        "reading": plan.get("reading", ""),
        "searches": used,
        "hit_total": hit_total,
        "candidate_count": len(cards),
        "trimmed": trimmed,
        "max_cards": max_cards,
        "cards": shown,
        "judged": judged,
        "judge_error": judge_error,
        "invented": invented,
        "packet": packet,
        "model": config.get("model") or "（接続先の既定モデル）",
    }


def main() -> None:
    import argparse

    from card_db import connect

    parser = argparse.ArgumentParser(description="poke97 AIへの質問窓（CLI）")
    parser.add_argument("question")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--packet-only", action="store_true", help="AIを呼ばず、貼り付け用の質問票だけ作る")
    args = parser.parse_args()
    db = connect()
    if args.packet_only:
        used, cards, _ = run_searches(db, [{"q": args.question}])
        print(build_packet(args.question, cards[:60], used))
        return
    result = ask(db, args.question)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
        return
    print(f"読み取り: {result['reading']}")
    for search in result["searches"]:
        print(f"条件: {json.dumps(search, ensure_ascii=False)}")
    print(f"候補 {result['candidate_count']}種")
    judged = result["judged"]
    print("\n" + (judged.get("answer") or result["judge_error"] or "（AIの答えなし）"))
    for label, key in (("該当", "hits"), ("たぶん", "maybe")):
        for item in judged.get(key) or []:
            mark = " ※DBに無い名前" if item.get("unverified") else ""
            print(f"  [{label}] {item.get('name')}{mark} — {item.get('why', '')}")
    if judged.get("missing"):
        print(f"\n漏れの心配: {judged['missing']}")


if __name__ == "__main__":
    main()
