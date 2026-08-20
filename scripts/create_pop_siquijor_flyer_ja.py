from pathlib import Path

from reportlab.lib.colors import HexColor, white
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from create_pop_siquijor_flyer import (
    CORAL,
    CREAM,
    DEEP,
    FORM_URL,
    GOLD,
    INK,
    MINT,
    MUTED,
    PALE,
    SAND,
    SEA,
    TEAL,
    draw_people_and_cafe,
    draw_qr,
    para,
)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf" / "POP_シキホールカフェ参加チラシ_2027_日本語.pdf"
JP_SANS = "ArialUnicodeJP"
JP_SERIF = "ArialUnicodeJP-Heading"


def register_fonts():
    font_path = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
    pdfmetrics.registerFont(TTFont(JP_SANS, font_path))
    pdfmetrics.registerFont(TTFont(JP_SERIF, font_path))


def build():
    register_fonts()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUTPUT), pagesize=A4)
    width, height = A4

    c.setTitle("POP シキホールカフェ参加チラシ - 2027年3月下旬")
    c.setAuthor("南雲嘉明 / Project of Purpose")

    c.setFillColor(CREAM)
    c.rect(0, 0, width, height, fill=1, stroke=0)

    hero_h = 82 * mm
    c.setFillColor(TEAL)
    c.rect(0, height - hero_h, width, hero_h, fill=1, stroke=0)

    c.setFillColor(GOLD)
    c.circle(width - 48 * mm, height - 29 * mm, 17 * mm, fill=1, stroke=0)
    c.setStrokeColor(HexColor("#50A7A5"))
    c.setLineWidth(1.5)
    for i in range(4):
        yy = height - hero_h + 13 * mm + i * 7 * mm
        c.bezier(
            width - 82 * mm,
            yy,
            width - 65 * mm,
            yy + 5 * mm,
            width - 48 * mm,
            yy - 5 * mm,
            width - 25 * mm,
            yy,
        )

    left = 18 * mm
    c.setFont(JP_SANS, 9.5)
    c.setFillColor(HexColor("#BEE5DF"))
    c.drawString(left, height - 14 * mm, "POP  |  PROJECT OF PURPOSE")

    title_style = ParagraphStyle(
        "title_ja",
        fontName=JP_SERIF,
        fontSize=25,
        leading=30,
        textColor=white,
        alignment=TA_LEFT,
        spaceAfter=0,
    )
    para(c, "シキホールで<br/>カフェを一緒につくりませんか", left, height - 23 * mm, 126 * mm, title_style)

    c.setFillColor(white)
    c.setFont(JP_SANS, 10.5)
    c.drawString(left, height - 61 * mm, "2027年3月下旬  |  1週間  |  フィリピン・シキホール島")

    hero_quote = ParagraphStyle(
        "hero_quote_ja",
        fontName=JP_SANS,
        fontSize=9.4,
        leading=13.2,
        textColor=HexColor("#E8F4F1"),
        alignment=TA_LEFT,
    )
    para(
        c,
        "まず、楽しむことから始めます。人と人が出会い、それぞれができることを持ち寄ります。そこから、次の活動も生まれていくかもしれません。",
        left,
        height - 66 * mm,
        108 * mm,
        hero_quote,
    )

    draw_people_and_cafe(c, width - 69 * mm, height - hero_h + 13 * mm, 1.0)

    body_top = height - hero_h - 10 * mm
    col_gap = 9 * mm
    col_w = (width - 36 * mm - col_gap) / 2
    col1_x = 18 * mm
    col2_x = col1_x + col_w + col_gap

    section_label = ParagraphStyle(
        "section_label_ja",
        fontName=JP_SANS,
        fontSize=8.4,
        leading=10,
        textColor=CORAL,
        alignment=TA_LEFT,
    )
    heading = ParagraphStyle(
        "heading_ja",
        fontName=JP_SERIF,
        fontSize=16.2,
        leading=20.5,
        textColor=DEEP,
        alignment=TA_LEFT,
    )
    body = ParagraphStyle(
        "body_ja",
        fontName=JP_SANS,
        fontSize=8.5,
        leading=12.4,
        textColor=INK,
        alignment=TA_LEFT,
    )
    small = ParagraphStyle(
        "small_ja",
        fontName=JP_SANS,
        fontSize=7.8,
        leading=11.1,
        textColor=MUTED,
        alignment=TA_LEFT,
    )
    bullet = ParagraphStyle(
        "bullet_ja",
        fontName=JP_SANS,
        fontSize=7.6,
        leading=9.6,
        textColor=INK,
        leftIndent=9,
        firstLineIndent=-7,
        bulletIndent=0,
    )

    y1 = body_top
    y1 -= para(c, "最初の一歩", col1_x, y1, col_w, section_label) + 2 * mm
    y1 -= para(c, "一週間、カフェを<br/>一緒に動かします", col1_x, y1, col_w, heading) + 3 * mm
    y1 -= para(
        c,
        "2027年3月下旬、シキホール島に小さなチームが集まり、一週間、カフェを一緒に動かす予定です。お客様として訪れるだけでなく、最初のつくり手の一人として参加していただけます。",
        col1_x,
        y1,
        col_w,
        body,
    ) + 4 * mm

    c.setFillColor(PALE)
    c.roundRect(col1_x, y1 - 40 * mm, col_w, 40 * mm, 4 * mm, fill=1, stroke=0)
    c.setFillColor(DEEP)
    c.setFont(JP_SANS, 8.8)
    c.drawString(col1_x + 6 * mm, y1 - 8 * mm, "楽しんでいることを持ち寄る")
    items = [
        "料理とコーヒー",
        "おもてなしと会話",
        "音楽とイベント",
        "写真と動画",
        "デザインとものづくり",
        "翻訳とIT",
        "まず見てみたい、という気持ち",
    ]
    yy = y1 - 13 * mm
    for item in items:
        para(c, f"・{item}", col1_x + 6 * mm, yy, col_w - 12 * mm, bullet)
        yy -= 3.9 * mm

    y2 = body_top
    y2 -= para(c, "その次へ", col2_x, y2, col_w, section_label) + 2 * mm
    y2 -= para(c, "出会った人の声から<br/>次の活動を考えます", col2_x, y2, col_w, heading) + 3 * mm
    y2 -= para(
        c,
        "島の人、旅行者、デニス牧師、参加する皆さんの声を聞きます。子ども、福祉、教育、仕事づくりなど、シキホールで必要とされる活動が見つかるかもしれません。",
        col2_x,
        y2,
        col_w,
        body,
    ) + 4 * mm

    c.setFillColor(MINT)
    c.roundRect(col2_x, y2 - 40 * mm, col_w, 40 * mm, 4 * mm, fill=1, stroke=0)
    c.setFillColor(DEEP)
    c.setFont(JP_SANS, 8.8)
    c.drawString(col2_x + 6 * mm, y2 - 8 * mm, "内容を先に決めすぎません")
    para(
        c,
        "次に何をするかは、現地で出会った人たちの声を聞きながら考えます。新しい活動が生まれたときは、技術、旅、発信、クラウドファンディングなどを通して、世界から参加できる形も考えていきます。",
        col2_x + 6 * mm,
        y2 - 14 * mm,
        col_w - 12 * mm,
        small,
    )

    flow_y = 78 * mm
    c.setFillColor(DEEP)
    c.roundRect(18 * mm, flow_y, width - 36 * mm, 29 * mm, 5 * mm, fill=1, stroke=0)
    labels = ["楽しむ", "出会う", "つくる", "役立てる", "また始める"]
    x_positions = [31, 63, 97, 132, 169]
    for idx, (label, xpos) in enumerate(zip(labels, x_positions)):
        c.setFillColor(GOLD if idx in (0, 4) else white)
        c.setFont(JP_SANS, 8.2 if label != "役立てる" else 7.8)
        c.drawCentredString(xpos * mm, flow_y + 14.8 * mm, label)
        if idx < len(labels) - 1:
            c.setFillColor(HexColor("#73AAA9"))
            c.setFont(JP_SANS, 11)
            c.drawCentredString((xpos + x_positions[idx + 1]) / 2 * mm, flow_y + 14.3 * mm, ">")
    c.setFont(JP_SANS, 7.5)
    c.setFillColor(HexColor("#C9E0DC"))
    c.drawCentredString(width / 2, flow_y + 6.5 * mm, "喜びと参加が、人のつながりを広げていく循環")

    footer_y = 19 * mm
    c.setFillColor(CORAL)
    c.roundRect(18 * mm, footer_y, width - 36 * mm, 50 * mm, 6 * mm, fill=1, stroke=0)

    c.setFillColor(white)
    c.setFont(JP_SANS, 8.5)
    c.drawString(25 * mm, footer_y + 38 * mm, "POP - PROJECT OF PURPOSE")

    footer_head = ParagraphStyle(
        "footer_head_ja",
        fontName=JP_SERIF,
        fontSize=16.8,
        leading=20,
        textColor=white,
        alignment=TA_LEFT,
    )
    para(c, "人と出会い、<br/>一緒につくるところから。", 25 * mm, footer_y + 34 * mm, 108 * mm, footer_head)

    c.setFillColor(white)
    c.setFont(JP_SANS, 9.4)
    c.drawString(25 * mm, footer_y + 9 * mm, "あなたは、何を持って参加しますか？")

    qr_x = width - 66 * mm
    qr_y = footer_y + 7 * mm
    c.setFillColor(white)
    c.roundRect(qr_x, qr_y, 40 * mm, 36 * mm, 4 * mm, fill=1, stroke=0)
    c.setFillColor(DEEP)
    c.setFont(JP_SANS, 7.4)
    c.drawCentredString(qr_x + 20 * mm, qr_y + 29.5 * mm, "VLOG完成時にお知らせ")
    draw_qr(c, FORM_URL, qr_x + 8.5 * mm, qr_y + 3.2 * mm, 23 * mm)

    c.setFillColor(MUTED)
    c.setFont(JP_SANS, 6.5)
    c.drawRightString(width - 18 * mm, 8 * mm, "構想チラシ v0.1  |  2026年8月")

    c.showPage()
    c.save()
    print(OUTPUT)


if __name__ == "__main__":
    build()
