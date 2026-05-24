#!/usr/bin/env python3
"""Generates the x_logger banner and square logo (run with /usr/bin/python3)."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ARIAL_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
ARIAL = "/System/Library/Fonts/Supplemental/Arial.ttf"
MONO = "/System/Library/Fonts/Monaco.ttf"

# Palette
TOP = (26, 27, 46)
BOTTOM = (11, 12, 16)
ACCENT = (129, 140, 248)
WHITE = (244, 245, 250)
GREY = (158, 164, 172)
DIM = (120, 125, 138)

TERM_BG = (12, 12, 12)
TERM_BAR = (38, 38, 44)
TERM_BORDER = (52, 54, 66)
DOT_R = (255, 95, 86)
DOT_Y = (255, 189, 46)
DOT_G = (39, 201, 63)

C_DEBUG = (140, 140, 140)
C_INFO = (78, 201, 176)
C_WARN = (220, 220, 170)
C_ERROR = (241, 96, 96)
C_TS = (108, 112, 122)


def draw_logo(d, X, Y, L, bw):
    """A rounded-square 'log' mark: three colored log lines. Device pixels."""
    r = int(L * 0.22)
    d.rounded_rectangle([X, Y, X + L, Y + L], radius=r,
                        fill=(17, 18, 24), outline=ACCENT, width=bw)
    pad = L * 0.25
    inner = L - 2 * pad
    bar_h = L * 0.105
    gap = L * 0.11
    widths = [0.62, 0.42, 0.52]
    cols = [C_INFO, C_WARN, C_ERROR]
    bx, by = X + pad, Y + pad
    for i, (w, c) in enumerate(zip(widths, cols)):
        y0 = by + i * (bar_h + gap)
        d.rounded_rectangle([bx, y0, bx + inner * w, y0 + bar_h],
                            radius=bar_h / 2, fill=c)


def make_banner(path, SS=2):
    W, H = 1280, 400
    sc = lambda v: int(round(v * SS))
    fnt = lambda p, sz: ImageFont.truetype(p, sc(sz))

    img = Image.new("RGB", (W * SS, H * SS), BOTTOM)
    d = ImageDraw.Draw(img)

    # Vertical gradient
    for y in range(H * SS):
        t = y / (H * SS)
        d.line([(0, y), (W * SS, y)],
               fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)))

    # Soft indigo glow behind the left block
    glow = Image.new("RGB", img.size, BOTTOM)
    ImageDraw.Draw(glow).ellipse([sc(-120), sc(40), sc(540), sc(420)],
                                 fill=(40, 38, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(sc(60)))
    img = Image.blend(img, glow, 0.45)
    d = ImageDraw.Draw(img)

    # Logo mark (left), vertically aligned with the title
    draw_logo(d, sc(72), sc(92), sc(92), max(2, sc(1.6)))

    tx = 192  # text starts right of the logo
    title_f = fnt(ARIAL_BOLD, 66)
    tag_f = fnt(ARIAL, 21)
    small_f = fnt(ARIAL, 16)

    ty = 96
    w_pre = d.textlength("x_", font=title_f)
    d.text((sc(tx), sc(ty)), "x_", font=title_f, fill=ACCENT)
    d.text((sc(tx) + w_pre, sc(ty)), "logger", font=title_f, fill=WHITE)

    d.rounded_rectangle([sc(tx), sc(ty + 86), sc(tx + 118), sc(ty + 92)],
                        radius=sc(3), fill=ACCENT)

    d.text((sc(tx), sc(ty + 118)), "Configurable Flutter logging",
           font=tag_f, fill=GREY)
    d.text((sc(tx), sc(ty + 148)), "pretty  ·  JSON  ·  color  ·  file export",
           font=tag_f, fill=GREY)
    d.text((sc(tx), sc(ty + 190)), "Android · iOS · macOS · Windows · Linux",
           font=small_f, fill=DIM)

    # Right: terminal window
    a, b, c, e = 632, 64, 1200, 336
    d.rounded_rectangle([sc(a), sc(b), sc(c), sc(e)], radius=sc(16),
                        fill=TERM_BG, outline=TERM_BORDER, width=max(2, sc(1.5)))
    bar_h = 34
    d.rounded_rectangle([sc(a), sc(b), sc(c), sc(b + bar_h)], radius=sc(16),
                        fill=TERM_BAR)
    d.rectangle([sc(a), sc(b + bar_h - 16), sc(c), sc(b + bar_h)], fill=TERM_BAR)
    dy = b + bar_h / 2
    for i, col in enumerate((DOT_R, DOT_Y, DOT_G)):
        cx = a + 20 + i * 22
        d.ellipse([sc(cx - 6), sc(dy - 6), sc(cx + 6), sc(dy + 6)], fill=col)
    d.text((sc(a + 92), sc(b + 9)), "app.log — x_logger", font=fnt(ARIAL, 13),
           fill=GREY)

    mono = fnt(MONO, 14)
    rows = [
        ("09:12:03  ", "[DEBUG] (Database) cache warmed", C_DEBUG),
        ("09:12:03  ", "[INFO]  (QuranReader) ayah rendered", C_INFO),
        ("09:12:03  ", "[WARN]  (AudioPlayer) buffering", C_WARN),
        ("09:12:03  ", "[ERROR] (AudioPlayer) playback stopped", C_ERROR),
    ]
    lx, ly = a + 26, b + bar_h + 24
    for ts, rest, col in rows:
        d.text((sc(lx), sc(ly)), ts, font=mono, fill=C_TS)
        d.text((sc(lx) + d.textlength(ts, font=mono), sc(ly)), rest,
               font=mono, fill=col)
        ly += 46
    d.text((sc(lx), sc(ly + 2)), "$ _", font=mono, fill=(106, 153, 85))

    img.resize((W, H), Image.LANCZOS).save(path, optimize=True)
    print("banner:", path)


def make_logo(path, size=512, SS=2):
    """Standalone square logo on a transparent background."""
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    margin = int(size * SS * 0.11)
    L = size * SS - 2 * margin
    draw_logo(d, margin, margin, L, max(2, int(size * SS * 0.012)))
    img.resize((size, size), Image.LANCZOS).save(path)
    print("logo:", path)


if __name__ == "__main__":
    import os
    repo = "/Users/xman/Developer/wacyi/x_logger"
    shared = "/Users/xman/Developer/wacyi"
    os.makedirs(f"{repo}/doc", exist_ok=True)
    make_banner(f"{repo}/doc/banner.png")
    make_logo(f"{repo}/doc/logo.png")
    # Reusable copies you can grab from anywhere:
    make_banner(f"{shared}/x_logger-banner.png")
    make_logo(f"{shared}/x_logger-logo.png")
