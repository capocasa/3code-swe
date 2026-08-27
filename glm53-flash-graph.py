#!/usr/bin/env python3
"""16:9 GLM-5.3-Flash SWE-bench poster. Numeric meme for X mobile."""

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
from matplotlib.patches import FancyBboxPatch, Rectangle
from PIL import Image

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "glm53-flash-benchmark.png"
OUT_OG = ROOT / "glm53-flash-benchmark-og.png"
TTF = Path("/usr/share/fonts/TTF")

BG = "#06202a"
BG_CARD = "#0a2d3a"
BG_DEEP = "#041820"
FG = "#e8f4f2"
FG_DIM = "#a8c5c3"
FG_BRIGHT = "#ffffff"
ACCENT = "#74c8c1"
ACCENT_2 = "#4fa9a1"
MUTED = "#5e8584"

AGENTS = ["pi", "3code", "zcode", "opencode", "hermes"]
TOKENS = {
    "zcode": 3_588_296,
    "opencode": 3_634_988,
    "3code": 3_322_964,
    "pi": 2_154_415,
    "hermes": 5_002_974,
}
RESOLVED = {
    "zcode": 7,
    "opencode": 7,
    "3code": 6,
    "pi": 6,
    "hermes": 4,
}
LEADER = TOKENS["zcode"]
TOKEN_MAX = 5_400_000
W, H = 16.0, 9.0


def fp(kind: str, weight: str = "Regular") -> FontProperties:
    files = {
        "sans": {
            "Regular": "IBMPlexSans-Regular.ttf",
            "Medium": "IBMPlexSans-Medium.ttf",
            "Bold": "IBMPlexSans-Bold.ttf",
        },
        "mono": {
            "Regular": "JetBrainsMono-Regular.ttf",
            "Medium": "JetBrainsMono-Medium.ttf",
            "Bold": "JetBrainsMono-Bold.ttf",
        },
    }
    return FontProperties(fname=str(TTF / files[kind][weight]))


SANS_MD = fp("sans", "Medium")
SANS_BD = fp("sans", "Bold")
MONO_MD = fp("mono", "Medium")
MONO_BD = fp("mono", "Bold")


def rbox(ax, x, y, w, h, fc, radius=0.08, z=3):
    p = FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f"round,pad=0,rounding_size={radius}",
        facecolor=fc, edgecolor="none", linewidth=0,
        mutation_aspect=1, zorder=z, clip_on=False,
    )
    ax.add_patch(p)
    return p


def txt(ax, x, y, s, font, size, color, ha="left", va="center", z=6):
    ax.text(
        x, y, s, fontproperties=font, fontsize=size,
        color=color, ha=ha, va=va, zorder=z, clip_on=False,
    )


def flatten(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    rgb = Image.new("RGB", im.size, (6, 32, 42))
    rgb.paste(im, mask=im.split()[-1])
    rgb.save(path, "PNG", optimize=True)
    return rgb


def main() -> None:
    fig = plt.figure(figsize=(W, H), dpi=220, facecolor=BG)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, W)
    ax.set_ylim(0, H)
    ax.set_axis_off()
    ax.add_patch(Rectangle((0, 0), W, H, fc=BG, ec="none", zorder=0))

    txt(
        ax, 0.70, 8.48,
        "5 agents  ·  10 SWE-bench tasks  ·  1 model (GLM-5.3-Flash)",
        SANS_BD, 40, FG_BRIGHT,
    )

    n = len(AGENTS)
    top, bot = 7.48, 0.72
    row_h = (top - bot) / n
    bar_h = 0.62

    name_x = 0.70
    score_x = 4.48
    bar_x = 5.72
    bar_w = 4.95
    tok_x = 12.42
    pct_x = 15.30

    hdr_y = top + 0.32
    txt(ax, score_x, hdr_y, "tasks", SANS_MD, 26, MUTED, ha="center")
    txt(ax, tok_x, hdr_y, "tokens", SANS_MD, 26, MUTED, ha="right")
    txt(ax, pct_x, hdr_y, "vs zcode", SANS_MD, 26, MUTED, ha="right")

    for i, agent in enumerate(AGENTS):
        y_top = top - i * row_h
        y_mid = y_top - row_h / 2
        winner = RESOLVED[agent] == 7
        pct = round(TOKENS[agent] / LEADER * 100)

        if winner:
            rbox(
                ax, 0.40, y_top - row_h + 0.10,
                15.20, row_h - 0.18,
                BG_CARD, radius=0.18, z=1,
            )
            rbox(
                ax, 0.40, y_top - row_h + 0.10,
                0.12, row_h - 0.18,
                ACCENT, radius=0.06, z=2,
            )

        txt(
            ax, name_x, y_mid, agent,
            MONO_BD if winner else MONO_MD, 36,
            FG_BRIGHT if winner else FG,
        )
        txt(
            ax, score_x, y_mid, f"{RESOLVED[agent]}/10",
            MONO_BD, 52,
            ACCENT if winner else MUTED, ha="center",
        )

        y_bar = y_mid - bar_h / 2
        rbox(ax, bar_x, y_bar, bar_w, bar_h, BG_DEEP if winner else BG_CARD, radius=0.14, z=3)
        tw = bar_w * (TOKENS[agent] / TOKEN_MAX)
        rbox(
            ax, bar_x, y_bar, tw, bar_h,
            ACCENT if winner else ACCENT_2,
            radius=0.14, z=4,
        )
        txt(
            ax, tok_x, y_mid, f"{TOKENS[agent] / 1e6:.1f}M",
            MONO_BD if winner else MONO_MD, 36,
            FG_BRIGHT if winner else FG_DIM, ha="right",
        )
        txt(
            ax, pct_x, y_mid, f"{pct}%",
            MONO_BD if winner else MONO_MD, 36,
            ACCENT if winner else FG_DIM, ha="right",
        )

    fig.savefig(OUT, dpi=220, facecolor=BG, edgecolor="none")
    rgb = flatten(OUT)
    og = rgb.resize((1600, 900), Image.Resampling.LANCZOS)
    og.save(OUT_OG, "PNG", optimize=True)
    print(OUT, rgb.size, OUT.stat().st_size)
    print(OUT_OG, og.size, OUT_OG.stat().st_size)


if __name__ == "__main__":
    main()
