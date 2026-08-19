#!/usr/bin/env python3
"""Automated whole-PDF checks plus low-cost all-page contact sheets for st97."""

from __future__ import annotations

import argparse
import json
import logging
import math
from pathlib import Path
import re
import shutil
import subprocess
import unicodedata

import pdfplumber
from PIL import Image, ImageDraw


A4_WIDTH = 595.28
A4_HEIGHT = 841.89

logging.getLogger("pdfminer").setLevel(logging.ERROR)


def normalize_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value)
    return re.sub(r"\s+", "", value)


def create_contact_sheets(images: list[Path], output_dir: Path) -> list[Path]:
    sheets = []
    per_sheet = 12
    thumb_width = 330
    gap = 22
    label_height = 32
    columns = 3

    for start in range(0, len(images), per_sheet):
        chunk = images[start:start + per_sheet]
        thumbs = []
        for path in chunk:
            with Image.open(path) as source:
                image = source.convert("RGB")
                height = round(image.height * thumb_width / image.width)
                image.thumbnail((thumb_width, height), Image.Resampling.LANCZOS)
                thumbs.append(image.copy())
        rows = math.ceil(len(thumbs) / columns)
        cell_height = max(image.height for image in thumbs) + label_height
        sheet = Image.new(
            "RGB",
            (columns * thumb_width + (columns + 1) * gap, rows * cell_height + (rows + 1) * gap),
            "#dfe4e7",
        )
        draw = ImageDraw.Draw(sheet)
        for offset, image in enumerate(thumbs):
            row, col = divmod(offset, columns)
            x = gap + col * (thumb_width + gap)
            y = gap + row * cell_height
            sheet.paste(image, (x, y + label_height))
            draw.text((x + 4, y + 5), f"page {start + offset + 1}", fill="#111111")
        output = output_dir / f"contact_sheet_{len(sheets) + 1}.png"
        sheet.save(output, optimize=True)
        sheets.append(output)
    return sheets


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("payload", type=Path)
    parser.add_argument("qa_dir", type=Path)
    args = parser.parse_args()

    data = json.loads(args.payload.read_text(encoding="utf-8"))
    args.qa_dir.mkdir(parents=True, exist_ok=True)
    for old in args.qa_dir.glob("page-*.png"):
        old.unlink()
    for old in args.qa_dir.glob("contact_sheet_*.png"):
        old.unlink()

    problems: list[str] = []
    page_texts: list[str] = []
    with pdfplumber.open(args.pdf) as document:
        if not document.pages:
            problems.append("PDF has no pages")
        for number, page in enumerate(document.pages, start=1):
            if abs(page.width - A4_WIDTH) > 3 or abs(page.height - A4_HEIGHT) > 3:
                problems.append(f"page {number}: not A4 ({page.width:.1f} x {page.height:.1f} pt)")
            text = page.extract_text() or ""
            page_texts.append(text)
            if len(text.strip()) < 40:
                problems.append(f"page {number}: blank or nearly blank")
            for char in page.chars:
                if char["x0"] < -1 or char["x1"] > page.width + 1 or char["top"] < -1 or char["bottom"] > page.height + 1:
                    problems.append(f"page {number}: text outside page bounds")
                    break

    all_text = normalize_text("\n".join(page_texts))
    required = ["全体の流れと結論", "全体のまとめ", "五段階の適用", "ハルシネーションチェック"]
    required.extend(verse["label"] for section in data["sections"] for verse in section["verses"])
    for marker in required:
        if normalize_text(marker) not in all_text:
            problems.append(f"missing expected text: {marker}")

    pdftoppm = shutil.which("pdftoppm")
    if not pdftoppm:
        raise RuntimeError("pdftoppm is not available")
    subprocess.run(
        [pdftoppm, "-png", "-r", "105", str(args.pdf), str(args.qa_dir / "page")],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    page_images = sorted(args.qa_dir.glob("page-*.png"))
    sheets = create_contact_sheets(page_images, args.qa_dir)

    report = args.qa_dir / "qa_report.txt"
    lines = [
        f"PDF: {args.pdf}",
        f"Pages: {len(page_texts)}",
        f"Automated checks: {'PASS' if not problems else 'REVIEW'}",
    ]
    lines.extend(f"- {problem}" for problem in problems)
    lines.append("Contact sheets:")
    lines.extend(f"- {sheet}" for sheet in sheets)
    report.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(report.read_text(encoding="utf-8"), end="")
    return 2 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
