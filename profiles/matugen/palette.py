#!/usr/bin/env python3
"""Custom matugen scheme: wallpaper-derived ANSI hues with color-theory-safe contrast.

Dumps matugen's Material (scheme-expressive) palette for UI chrome, then
samples the wallpaper's actual hue distribution to fill the six ANSI hue
slots (Material fixed hues as fallback for empty slots). For each slot the
lightness is *solved* against the real terminal background so every color
meets WCAG contrast (normal >= 4.5:1, bright >= 6.5:1):

  - dark mode:  normal = darkest readable, bright = lighter (pops)
  - light mode: normal = lightest readable, bright = darker (rich)

Usage: palette.py <wallpaper> <mode>   (mode: dark|light)
Writes ~/.cache/matugen/scheme.json and renders config.toml + kitty.toml.
"""
import colorsys
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

MATUGEN = "matugen"
CONFIG = "~/.config/matugen/config.toml"
KITTY = "~/.config/matugen/kitty.toml"
OUT = Path("~/.cache/matugen/scheme.json").expanduser()
CACHE = Path("~/.cache/matugen").expanduser()

# canonical fixed-palette hues per ANSI slot (Material's standard accents)
SLOTS = {
    "red":     0,
    "yellow":  50,
    "green":   140,
    "cyan":    190,
    "blue":    235,
    "magenta": 300,
}

# adopt a wallpaper hue only if it lands within this range of the slot's
# canonical hue, so adjacent warm/cool clusters don't collapse into one slot
ADOPT_RANGE = 20

# fallback (canonical-hue) colors stay muted so they don't fight the
# wallpaper-derived tones; adopted colors keep the wallpaper's own saturation.
# Kept near the material palette's muted secondary/tertiary (~0.3-0.45) so
# terminal colors read at the same intensity as app chrome (large colour
# areas feel louder than small accents).
SAT_FALLBACK = 0.28
# light mode: backgrounds are bright, so lift saturation to keep colors punchy
SAT_LIGHT_BOOST = 1.35
SAT_MAX = 0.55

# Terminal chrome saturation cap (absolute, 0..1): bg/fg saturation is clamped
# to this, so the terminal looks the same regardless of how saturated the
# wallpaper's material background is. Binary-searched with the user; ANSI
# contrast is unaffected (clamping keeps lightness).
TERMINAL_BG_SAT = 0.10

# WCAG targets (AA normal text, bright pops brighter/darker)
CONTRAST_NORMAL = 4.5
CONTRAST_BRIGHT = 6.5


def rel_lum(hexc: str) -> float:
    h = hexc.lstrip("#")
    r, g, b = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    def f(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = map(f, (r, g, b))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: str, b: str) -> float:
    la, lb = rel_lum(a), rel_lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def hue_dist(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


def hex_from_hsl(h: float, s: float, l: float) -> str:
    r, g, b = colorsys.hls_to_rgb(h / 360, l / 100, s)
    return "#{:02x}{:02x}{:02x}".format(*(round(c * 255) for c in (r, g, b)))


def clamp_sat(hexs: str, cap: float) -> str:
    """Clamp HSL saturation to `cap` (0..1), keeping lightness and hue."""
    hexs = hexs.lstrip("#")
    r, g, b = int(hexs[0:2], 16) / 255, int(hexs[2:4], 16) / 255, int(hexs[4:6], 16) / 255
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    s = min(s, cap)
    return hex_from_hsl(h * 360, s, l * 100)


def probe_background(scheme: dict, mode: str) -> str:
    """Render the chrome background exactly as kitty-colors.tmpl does, so ANSI
    contrast is solved against the real terminal background."""
    cfg = CACHE / "probe.toml"
    inp = CACHE / "probe.conf"
    out = CACHE / "probe.out"
    inp.write_text("{{ colors.background.default.hex | auto_lightness: 10 }}")
    cfg.write_text(
        f'[config]\nprefer = "darkness"\n[templates.probe]\n'
        f'input_path = "{inp}"\noutput_path = "{out}"\n'
    )
    subprocess.run(
        [MATUGEN, "json", str(OUT), "-c", str(cfg)], check=True, capture_output=True,
    )
    return out.read_text().strip()


def solve_lightness(hue: float, sat: float, bg: str, dark: bool, role: str) -> float:
    """Smallest lightness meeting the role's contrast target, or a sane fallback."""
    target = CONTRAST_BRIGHT if role == "bright" else CONTRAST_NORMAL
    if dark:
        cand = range(15, 96)  # ascending: darkest readable
    elif role == "bright":
        cand = range(20, 61)  # dark, rich
    elif role == "normal":
        cand = range(90, 19, -1)  # descending: lightest readable
    for li in cand:
        if contrast(hex_from_hsl(hue, sat, li), bg) >= target:
            return float(li)
    return 90.0 if dark else (20.0 if role == "bright" else 85.0)


def sample_wallpaper(image: str) -> dict:
    """Return per-slot (hue, sat) samples from the wallpaper's saturated pixels."""
    im = Image.open(image).convert("RGB")
    im.thumbnail((128, 128))
    px = im.getdata()
    clusters = {k: [] for k in SLOTS}
    for r, g, b in px:
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        hh = h * 360
        if s < 0.35 or not (0.15 < l < 0.85):
            continue
        slot = min(SLOTS, key=lambda k: hue_dist(hh, SLOTS[k]))
        clusters[slot].append((hh, s))
    return clusters


def slot_hue_sat(clusters: dict, slot: str, mode: str) -> tuple[float, float]:
    """(hue, sat) for a slot, pulling from wallpaper when its hue is present."""
    nominal = SLOTS[slot]
    pts = clusters[slot]
    if len(pts) >= 25:
        pts.sort(key=lambda p: -p[1])
        top = pts[: max(1, len(pts) // 2)]
        rep = sum(p[0] * p[1] for p in top) / sum(p[1] for p in top)
        if hue_dist(rep, nominal) <= ADOPT_RANGE:
            hue = rep
            sat = min(max(sum(p[1] for p in top) / len(top), 0.28), 0.42)
        else:
            hue, sat = nominal, SAT_FALLBACK
    else:
        hue, sat = nominal, SAT_FALLBACK
    if mode == "light":
        sat = min(sat * SAT_LIGHT_BOOST, SAT_MAX)
    return hue, sat


def slot_colors(clusters: dict, slot: str, mode: str, bg: str) -> tuple[str, str]:
    """(normal_hex, bright_hex) with per-hue solved lightness."""
    hue, sat = slot_hue_sat(clusters, slot, mode)
    dark = mode == "dark"
    nl = solve_lightness(hue, sat, bg, dark, "normal")
    bl = solve_lightness(hue, sat, bg, dark, "bright")
    if dark:
        bl = max(bl, nl + 2)  # bright must be lighter than normal
    else:
        bl = min(bl, nl - 2)  # bright must be darker than normal
    return hex_from_hsl(hue, sat, nl), hex_from_hsl(hue, sat, bl)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    image, mode = sys.argv[1], sys.argv[2]
    if mode not in ("dark", "light"):
        print("mode must be dark or light")
        return 1

    dump = subprocess.run(
        [MATUGEN, "image", image, "-m", mode, "-t", "scheme-expressive", "-j", "hex"],
        capture_output=True, text=True, check=True,
    )
    scheme = json.loads(dump.stdout)

    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(scheme))
    bg = probe_background(scheme, mode)

    clusters = sample_wallpaper(image)
    for slot in SLOTS:
        normal, bright = slot_colors(clusters, slot, mode, bg)
        scheme["colors"][slot] = {"default": {"color": normal}}
        scheme["colors"][f"{slot}_bright"] = {"default": {"color": bright}}
    bg = scheme["colors"]["background"]["default"]["color"]
    fg = scheme["colors"]["on_background"]["default"]["color"]
    scheme["colors"]["terminal_background"] = {"default": {"color": clamp_sat(bg, TERMINAL_BG_SAT)}}
    scheme["colors"]["terminal_foreground"] = {"default": {"color": clamp_sat(fg, TERMINAL_BG_SAT)}}
    OUT.write_text(json.dumps(scheme))

    for cfg in (CONFIG, KITTY):
        subprocess.run(
            [MATUGEN, "json", str(OUT), "-c", Path(cfg).expanduser()],
            check=True,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
