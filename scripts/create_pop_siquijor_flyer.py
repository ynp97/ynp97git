from pathlib import Path

from reportlab.lib.colors import HexColor, white
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.graphics import renderPDF
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf" / "POP_Siquijor_Cafe_Invitation_2027.pdf"
FORM_URL = "https://forms.gle/1DPfTFVDQX8n9kTU6"

TEAL = HexColor("#075E62")
DEEP = HexColor("#123B43")
SEA = HexColor("#1C8C91")
MINT = HexColor("#DCEDEA")
CREAM = HexColor("#FAF5E9")
SAND = HexColor("#EAD7B0")
CORAL = HexColor("#EC744E")
GOLD = HexColor("#F1B84B")
INK = HexColor("#173136")
MUTED = HexColor("#4F686B")
PALE = HexColor("#F2E9D7")


def register_fonts():
    pdfmetrics.registerFont(TTFont("Arial", "/System/Library/Fonts/Supplemental/Arial.ttf"))
    pdfmetrics.registerFont(TTFont("Arial-Bold", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"))
    pdfmetrics.registerFont(TTFont("Georgia", "/System/Library/Fonts/Supplemental/Georgia.ttf"))
    pdfmetrics.registerFont(TTFont("Georgia-Bold", "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"))


def para(c, text, x, y_top, width, style):
    p = Paragraph(text, style)
    _, h = p.wrap(width, 1000)
    p.drawOn(c, x, y_top - h)
    return h


def pill(c, x, y, w, h, label, fill, text_color=white):
    c.setFillColor(fill)
    c.roundRect(x, y, w, h, h / 2, fill=1, stroke=0)
    c.setFont("Arial-Bold", 8.3)
    c.setFillColor(text_color)
    c.drawCentredString(x + w / 2, y + h / 2 - 2.8, label)


def draw_people_and_cafe(c, x, y, scale=1):
    # A small, friendly line illustration: an open cafe and four connected people.
    c.saveState()
    c.setLineWidth(2.0 * scale)
    c.setStrokeColor(DEEP)
    c.setFillColor(white)

    # Cafe roof and counter.
    c.line(x, y + 34 * scale, x + 94 * scale, y + 34 * scale)
    c.line(x + 8 * scale, y + 34 * scale, x + 23 * scale, y + 54 * scale)
    c.line(x + 23 * scale, y + 54 * scale, x + 79 * scale, y + 54 * scale)
    c.line(x + 79 * scale, y + 54 * scale, x + 94 * scale, y + 34 * scale)
    c.line(x + 17 * scale, y + 34 * scale, x + 17 * scale, y + 7 * scale)
    c.line(x + 85 * scale, y + 34 * scale, x + 85 * scale, y + 7 * scale)
    c.setFillColor(CORAL)
    c.roundRect(x + 32 * scale, y + 12 * scale, 38 * scale, 16 * scale, 3 * scale, fill=1, stroke=0)

    # Connected people.
    colors = [GOLD, CORAL, SEA, SAND]
    centers = [x + 4 * scale, x + 31 * scale, x + 70 * scale, x + 99 * scale]
    for i, cx in enumerate(centers):
        c.setFillColor(colors[i])
        c.setStrokeColor(DEEP)
        c.circle(cx, y + 4 * scale, 4.5 * scale, fill=1, stroke=1)
    c.setStrokeColor(DEEP)
    c.line(centers[0] + 5 * scale, y + 4 * scale, centers[1] - 5 * scale, y + 4 * scale)
    c.line(centers[1] + 5 * scale, y + 4 * scale, centers[2] - 5 * scale, y + 4 * scale)
    c.line(centers[2] + 5 * scale, y + 4 * scale, centers[3] - 5 * scale, y + 4 * scale)
    c.restoreState()


def draw_qr(c, value, x, y, size):
    qr = QrCodeWidget(value)
    bounds = qr.getBounds()
    qr_width = bounds[2] - bounds[0]
    qr_height = bounds[3] - bounds[1]
    drawing = Drawing(
        size,
        size,
        transform=[size / qr_width, 0, 0, size / qr_height, 0, 0],
    )
    drawing.add(qr)
    renderPDF.draw(drawing, c, x, y)


def build():
    register_fonts()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    c = canvas.Canvas(str(OUTPUT), pagesize=A4)
    width, height = A4

    c.setTitle("POP Siquijor Cafe Invitation - Late March 2027")
    c.setAuthor("Yoshiaki Nagumo / Project of Purpose")

    # Background.
    c.setFillColor(CREAM)
    c.rect(0, 0, width, height, fill=1, stroke=0)

    # Hero block.
    hero_h = 82 * mm
    c.setFillColor(TEAL)
    c.rect(0, height - hero_h, width, hero_h, fill=1, stroke=0)

    # Abstract sun and waves.
    c.setFillColor(GOLD)
    c.circle(width - 48 * mm, height - 29 * mm, 17 * mm, fill=1, stroke=0)
    c.setStrokeColor(HexColor("#50A7A5"))
    c.setLineWidth(1.5)
    for i in range(4):
        yy = height - hero_h + 13 * mm + i * 7 * mm
        c.bezier(width - 82 * mm, yy, width - 65 * mm, yy + 5 * mm,
                 width - 48 * mm, yy - 5 * mm, width - 25 * mm, yy)

    left = 18 * mm
    c.setFont("Arial-Bold", 9.5)
    c.setFillColor(HexColor("#BEE5DF"))
    c.drawString(left, height - 14 * mm, "POP  |  PROJECT OF PURPOSE")

    title_style = ParagraphStyle(
        "title", fontName="Georgia-Bold", fontSize=29, leading=30,
        textColor=white, alignment=TA_LEFT, spaceAfter=0,
    )
    para(c, "COME CREATE<br/>A CAFE IN SIQUIJOR", left, height - 23 * mm, 122 * mm, title_style)

    c.setFillColor(white)
    c.setFont("Arial-Bold", 11)
    c.drawString(left, height - 61 * mm, "LATE MARCH 2027  |  ONE WEEK  |  SIQUIJOR, PHILIPPINES")

    hero_quote = ParagraphStyle(
        "hero_quote", fontName="Arial", fontSize=10.4, leading=14,
        textColor=HexColor("#E8F4F1"), alignment=TA_LEFT,
    )
    para(
        c,
        "We begin with joy. People meet. Each person brings something. "
        "From those connections, new projects can grow.",
        left, height - 70 * mm, 105 * mm, hero_quote,
    )

    draw_people_and_cafe(c, width - 69 * mm, height - hero_h + 13 * mm, 1.0)

    # Main two-column content.
    body_top = height - hero_h - 10 * mm
    col_gap = 9 * mm
    col_w = (width - 36 * mm - col_gap) / 2
    col1_x = 18 * mm
    col2_x = col1_x + col_w + col_gap

    section_label = ParagraphStyle(
        "section_label", fontName="Arial-Bold", fontSize=8.4, leading=10,
        textColor=CORAL, alignment=TA_LEFT,
    )
    heading = ParagraphStyle(
        "heading", fontName="Georgia-Bold", fontSize=18, leading=20,
        textColor=DEEP, alignment=TA_LEFT,
    )
    body = ParagraphStyle(
        "body", fontName="Arial", fontSize=9.0, leading=12.2,
        textColor=INK, alignment=TA_LEFT,
    )
    small = ParagraphStyle(
        "small", fontName="Arial", fontSize=8.1, leading=10.7,
        textColor=MUTED, alignment=TA_LEFT,
    )
    bullet = ParagraphStyle(
        "bullet", fontName="Arial", fontSize=7.9, leading=9.8,
        textColor=INK, leftIndent=9, firstLineIndent=-7, bulletIndent=0,
    )

    y1 = body_top
    y1 -= para(c, "FIRST", col1_x, y1, col_w, section_label) + 2 * mm
    y1 -= para(c, "Enjoy creating<br/>the cafe together.", col1_x, y1, col_w, heading) + 3 * mm
    y1 -= para(
        c,
        "In late March 2027, a small team will gather in Siquijor to run the cafe together for one week. "
        "We will not come only as guests. We will become the first co-creators.",
        col1_x, y1, col_w, body,
    ) + 4 * mm

    c.setFillColor(PALE)
    c.roundRect(col1_x, y1 - 40 * mm, col_w, 40 * mm, 4 * mm, fill=1, stroke=0)
    c.setFillColor(DEEP)
    c.setFont("Arial-Bold", 9)
    c.drawString(col1_x + 6 * mm, y1 - 8 * mm, "BRING WHAT YOU ENJOY")
    items = [
        "Food and coffee", "Hospitality and conversation", "Music and events",
        "Photography and video", "Design and making", "Translation and technology",
        "Or simply curiosity",
    ]
    yy = y1 - 13 * mm
    for item in items:
        para(c, f"<bullet>&#8226;</bullet>{item}", col1_x + 6 * mm, yy, col_w - 12 * mm, bullet)
        yy -= 4.05 * mm

    y2 = body_top
    y2 -= para(c, "THEN", col2_x, y2, col_w, section_label) + 2 * mm
    y2 -= para(c, "Let the next project<br/>grow from connection.", col2_x, y2, col_w, heading) + 3 * mm
    y2 -= para(
        c,
        "We will listen to local people, travelers, Pastor Dennis and the people who join us. "
        "Together we may discover a next project for children, community welfare, education, work, or another need rooted in Siquijor.",
        col2_x, y2, col_w, body,
    ) + 4 * mm

    c.setFillColor(MINT)
    c.roundRect(col2_x, y2 - 40 * mm, col_w, 40 * mm, 4 * mm, fill=1, stroke=0)
    c.setFillColor(DEEP)
    c.setFont("Arial-Bold", 9)
    c.drawString(col2_x + 6 * mm, y2 - 8 * mm, "WE DO NOT DECIDE EVERYTHING FIRST")
    para(
        c,
        "The people we meet will help shape what comes next. If a new project is born, people around the world may join through skills, travel, storytelling and crowdfunding.",
        col2_x + 6 * mm, y2 - 14 * mm, col_w - 12 * mm, small,
    )

    # Flow strip.
    flow_y = 78 * mm
    c.setFillColor(DEEP)
    c.roundRect(18 * mm, flow_y, width - 36 * mm, 29 * mm, 5 * mm, fill=1, stroke=0)
    labels = ["ENJOY", "CONNECT", "CREATE", "GIVE BACK", "BEGIN AGAIN"]
    x_positions = [31, 63, 97, 132, 169]
    for idx, (label, xpos) in enumerate(zip(labels, x_positions)):
        c.setFillColor(GOLD if idx in (0, 4) else white)
        c.setFont("Arial-Bold", 8.2 if label != "GIVE BACK" else 7.6)
        c.drawCentredString(xpos * mm, flow_y + 14.8 * mm, label)
        if idx < len(labels) - 1:
            c.setFillColor(HexColor("#73AAA9"))
            c.setFont("Arial-Bold", 11)
            c.drawCentredString((xpos + x_positions[idx + 1]) / 2 * mm, flow_y + 14.3 * mm, ">")
    c.setFont("Arial", 7.8)
    c.setFillColor(HexColor("#C9E0DC"))
    c.drawCentredString(width / 2, flow_y + 6.5 * mm, "A circle of joy, participation and change")

    # Footer call to action.
    footer_y = 19 * mm
    c.setFillColor(CORAL)
    c.roundRect(18 * mm, footer_y, width - 36 * mm, 50 * mm, 6 * mm, fill=1, stroke=0)

    c.setFillColor(white)
    c.setFont("Arial-Bold", 8.5)
    c.drawString(25 * mm, footer_y + 38 * mm, "THIS IS POP - PROJECT OF PURPOSE")

    footer_head = ParagraphStyle(
        "footer_head", fontName="Georgia-Bold", fontSize=17.5, leading=19,
        textColor=white, alignment=TA_LEFT,
    )
    para(c, "Joy connects people.<br/>Connected people create change.", 25 * mm, footer_y + 34 * mm, 108 * mm, footer_head)

    c.setFillColor(white)
    c.setFont("Arial-Bold", 10)
    c.drawString(25 * mm, footer_y + 9 * mm, "WHAT COULD YOU BRING?")

    # VLOG notification form.
    qr_x = width - 66 * mm
    qr_y = footer_y + 7 * mm
    c.setFillColor(white)
    c.roundRect(qr_x, qr_y, 40 * mm, 36 * mm, 4 * mm, fill=1, stroke=0)
    c.setFillColor(DEEP)
    c.setFont("Arial-Bold", 8)
    c.drawCentredString(qr_x + 20 * mm, qr_y + 29.5 * mm, "GET THE VLOG")
    draw_qr(c, FORM_URL, qr_x + 8.5 * mm, qr_y + 3.2 * mm, 23 * mm)

    c.setFillColor(MUTED)
    c.setFont("Arial", 6.8)
    c.drawRightString(width - 18 * mm, 8 * mm, "Concept flyer v0.1  |  August 2026")

    c.showPage()
    c.save()
    print(OUTPUT)


if __name__ == "__main__":
    build()
