#!/usr/bin/env python3
"""
Generate the rice colour set from a wallpaper and fan it out to the consumers.
One histogram pass yields both the area-dominant chromatic hue (binned by hue
family so a small vivid accent never hijacks the theme) and the mean lightness.
The mean lightness drives the pill's whole tone: a bright wallpaper makes a light
pill with dark text, a dark or OLED-black one makes a near-black pill with cream
text, so the surfaces and the text flip together for contrast across the full
range. The dominant hue tints every tier in HSL. An achromatic wallpaper drops to
a neutral grey ramp. matugen still builds the dark base16 the always-dark terminal
reads; the pill JSON carries surfaces, accent and the contrast-matched text.
"""
import colorsys
import json
import re
import subprocess
import sys
from pathlib import Path

CACHE = Path.home() / ".cache" / "ricelin"

SURF_NAMES = ["surface", "surface_container_low", "surface_container",
              "surface_container_high", "surface_container_highest", "outline_variant"]
DARK_STEPS = [0.0, 0.025, 0.045, 0.075, 0.120, 0.250]
LIGHT_STEPS = [0.0, -0.045, -0.075, -0.115, -0.160, -0.340]
TEXT_KEYS = ["cream", "bright", "subtle", "dim", "faint", "icon_dim", "tick_rest"]
DARK_TEXT = [(0.92, 0.04), (0.98, 0.02), (0.76, 0.06), (0.58, 0.05),
             (0.46, 0.04), (0.83, 0.06), (0.77, 0.07)]
LIGHT_TEXT = [(0.20, 0.18), (0.10, 0.20), (0.36, 0.14), (0.48, 0.10),
              (0.56, 0.08), (0.28, 0.12), (0.34, 0.12)]


def analyze(wallpaper):
    out = subprocess.run(
        ["magick", wallpaper, "-alpha", "off", "-resize", "200x200", "-colors", "48",
         "-format", "%c", "histogram:info:-"],
        capture_output=True, text=True).stdout
    buckets, total, lum, chroma = {}, 0, 0.0, 0
    for line in out.splitlines():
        m = re.search(r"\s*(\d+):\s*\([^)]*\)\s*#([0-9A-Fa-f]{6})", line)
        if not m:
            continue
        count, hex_str = int(m.group(1)), m.group(2)
        r, g, b = (int(hex_str[i:i + 2], 16) / 255 for i in (0, 2, 4))
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        total += count
        lum += count * l
        if s < 0.15 or l < 0.05 or l > 0.92:
            continue
        chroma += count
        bucket = buckets.setdefault((int(h * 360) // 30) % 12, {"wsat": 0.0, "best": None})
        bucket["wsat"] += count * s
        score = count * s * (1 if 0.12 < l < 0.55 else 0.4)
        if not bucket["best"] or score > bucket["best"][0]:
            bucket["best"] = (score, h, s)
    mean_l = lum / total if total else 0.0
    if not buckets or chroma < 0.08 * total:
        return None, 0.0, mean_l
    win = max(buckets.values(), key=lambda v: v["wsat"])
    return win["best"][1], win["best"][2], mean_l


def matugen(source_hex):
    out = subprocess.run(
        ["matugen", "color", "hex", source_hex, "-m", "dark", "-j", "hex"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


def tint(hue, sat, light):
    r, g, b = colorsys.hls_to_rgb(hue % 1.0, max(0.0, min(1.0, light)), max(0.0, min(1.0, sat)))
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def lerp(x, x0, x1, y0, y1):
    t = max(0.0, min(1.0, (x - x0) / (x1 - x0)))
    return y0 + t * (y1 - y0)


def hex_to_kde(h):
    """#rrggbb → r,g,b"""
    return "%d,%d,%d" % (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))


def _colorscheme_effects_block():
    """The two static [ColorEffects:*] sections, identical across every wallpaper."""
    return [
        "[ColorEffects:Disabled]",
        "Color=%d,%d,%d" % (56, 56, 56),
        "ColorAmount=0",
        "ColorEffect=0",
        "ContrastAmount=0.65",
        "ContrastEffect=1",
        "IntensityAmount=0.1",
        "IntensityEffect=2",
        "",
        "[ColorEffects:Inactive]",
        "ChangeSelectionColor=true",
        "Color=%d,%d,%d" % (112, 111, 110),
        "ColorAmount=0.025",
        "ColorEffect=2",
        "ContrastAmount=0.1",
        "ContrastEffect=2",
        "Enable=false",
        "IntensityAmount=0",
        "IntensityEffect=0",
        "",
    ]


def _colorscheme_sections(pill):
    """
    Build the 7 [Colors:*] sections. They share almost every key (accent,
    negative/positive/neutral, normal foreground/background) and differ only
    in which surface tier backs them and, for Selection, which text sits on
    top of the accent instead of the surface. `common` holds the shared keys;
    each section only states its overrides.
    """
    p = pill
    bg_win = hex_to_kde(p["surface_container_highest"])
    bg_view = hex_to_kde(p["surface_container"])
    bg_btn = hex_to_kde(p["surface_container_high"])
    bg_sel = hex_to_kde(p["primary"])
    fg = hex_to_kde(p["bright"])
    fg_dim = hex_to_kde(p["subtle"])
    fg_sel = hex_to_kde(p["cream"])
    accent = hex_to_kde(p["primary"])
    white = hex_to_kde("#ffffff")
    neg = hex_to_kde("#da4453")
    neut = hex_to_kde(p["dim"])

    common = {
        "DecorationFocus": accent,
        "DecorationHover": accent,
        "ForegroundActive": accent,
        "ForegroundInactive": fg_dim,
        "ForegroundLink": accent,
        "ForegroundNegative": neg,
        "ForegroundNeutral": neut,
        "ForegroundNormal": fg,
        "ForegroundPositive": "39,174,96",
        "ForegroundVisited": fg_dim,
    }

    return {
        "Colors:Button": {**common, "BackgroundAlternate": bg_win, "BackgroundNormal": bg_btn},
        "Colors:Complementary": {**common, "BackgroundAlternate": bg_view,
                                  "BackgroundNormal": hex_to_kde(p["surface"]),
                                  "ForegroundVisited": accent},
        "Colors:Header": {**common, "BackgroundAlternate": bg_view, "BackgroundNormal": bg_btn,
                           "ForegroundVisited": accent},
        "Colors:Selection": {**common, "BackgroundAlternate": accent, "BackgroundNormal": bg_sel,
                              "DecorationFocus": white, "DecorationHover": white,
                              "ForegroundActive": fg_sel, "ForegroundLink": fg_sel,
                              "ForegroundNormal": fg_sel, "ForegroundVisited": fg_sel},
        "Colors:Tooltip": {**common, "BackgroundAlternate": bg_view,
                            "BackgroundNormal": hex_to_kde(p["surface_container_low"])},
        "Colors:View": {**common, "BackgroundAlternate": hex_to_kde(p["surface_container_low"]),
                         "BackgroundNormal": bg_view},
        "Colors:Window": {**common, "BackgroundAlternate": hex_to_kde(p["surface_container_high"]),
                           "BackgroundNormal": bg_win},
    }


def render_colorscheme(pill, light):
    out = _colorscheme_effects_block()

    for section_name, colors in _colorscheme_sections(pill).items():
        out.append("[%s]" % section_name)
        for key, val in colors.items():
            out.append("%s=%s" % (key, val))
        out.append("")

    out.append("[General]")
    out.append("ColorScheme=Ricelin-Dynamic")
    out.append("Name=Ricelin-Dynamic")
    out.append("shadeSortColumn=true")
    out.append("")
    out.append("[KDE]")
    out.append("contrast=4")
    out.append("")
    out.append("[WM]")
    out.append("activeBackground=" + hex_to_kde(pill["surface_container_high"]))
    out.append("activeForeground=" + hex_to_kde(pill["bright"]))
    out.append("inactiveBackground=" + hex_to_kde(pill["surface_container"]))
    out.append("inactiveForeground=" + hex_to_kde(pill["dim"]))

    return "\n".join(out) + "\n"


def render_fastfetch(pill):
    """
    Recolour the fastfetch readout from the same pill palette. fastfetch has no
    daemon, so writing the rendered config is enough, the next run picks it up.
    The accent drives the keys and the torii, the surface ramp the lantern body,
    and a dim text tone the section rules, so it tracks the wallpaper like the
    pill and terminal do.
    """
    ff = Path.home() / ".config" / "fastfetch"
    tmpl = ff / "config.jsonc.in"
    if not tmpl.is_file():
        print("wallcolors: config.jsonc.in missing in ~/.config/fastfetch, skipping "
              "fastfetch recolour (apply the Ricelin update or re-run the installer)",
              file=sys.stderr)
        return
    seq = lambda h: "%d;%d;%d" % tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
    repl = {
        "__LANTERN__": str(ff / "lantern.txt"),
        "__KEYS__": seq(pill["primary"]),
        "__SEP__": seq(pill["dim"]),
        "__LOGO1__": seq(pill["primary"]),
        "__LOGO2__": seq(pill["on_primary_container"]),
        "__LOGO3__": seq(pill["surface_container"]),
        "__LOGO4__": seq(pill["surface_container_high"]),
        "__LOGO5__": seq(pill["subtle"]),
        "__LOGO6__": seq(pill["outline"]),
        "__LOGO7__": seq(pill["bright"]),
    }
    out = tmpl.read_text()
    for key, val in repl.items():
        out = out.replace(key, val)
    (ff / "config.jsonc").write_text(out)


def resolve_source(argv):
    """
    Turn CLI args into (hue, sat, mean_l, chromatic), or None if there's
    nothing to do. Two entry points: `--hue <deg> [light|dark] [sat]` for
    manual/testing use, or a wallpaper path for the real histogram analysis.
    """
    if len(argv) < 2:
        return None
    if argv[1] == "--hue":
        hue = (float(argv[2]) % 360) / 360.0
        mode = argv[3] if len(argv) > 3 else "dark"
        sat = max(0.0, min(1.0, float(argv[4]) if len(argv) > 4 else 0.5))
        mean_l = 0.85 if mode == "light" else 0.12
        return hue, sat, mean_l, sat > 0.02

    wallpaper = argv[1]
    if not Path(wallpaper).is_file():
        return None
    hue, sat, mean_l = analyze(wallpaper)
    chromatic = hue is not None
    if not chromatic:
        hue, sat = 0.09, 0.0
    return hue, sat, mean_l, chromatic


def build_pill(hue, sat, mean_l, chromatic):
    """
    Turn (hue, sat, mean_l) into the 15-colour pill dict plus the `light`
    flag consumers need alongside it. All the tone math lives here: how
    saturated the surfaces get, how far the accent lifts off them, and
    which lightness ramp (light vs dark) frames the whole thing.
    """
    light = mean_l >= 0.40
    surf_sat = min(sat, 0.26) if light else min(max(sat, 0.30 if chromatic else 0.0), 0.45)
    acc_sat = (min(sat + 0.18, 0.85) if light else min(max(sat, 0.35) + 0.15, 0.88)) if chromatic else 0.05
    if light:
        base = lerp(mean_l, 0.40, 0.66, 0.80, 0.93)
        steps, text, acc_l, deep_l, glow_l = LIGHT_STEPS, LIGHT_TEXT, 0.42, 0.30, 0.55
    else:
        base = lerp(mean_l, 0.0, 0.40, 0.015, 0.12)
        steps, text, acc_l, deep_l, glow_l = DARK_STEPS, DARK_TEXT, 0.75, 0.34, 0.88

    pill = {name: tint(hue, surf_sat, base + step) for name, step in zip(SURF_NAMES, steps)}
    pill["primary"] = tint(hue, acc_sat, acc_l)
    pill["primary_container"] = tint(hue, min(acc_sat + 0.08, 0.9), deep_l)
    pill["on_primary_container"] = tint(hue, min(acc_sat, 0.45), glow_l)
    pill["outline"] = tint(hue, surf_sat, base + (-0.35 if light else 0.35))
    for key, (lit, st) in zip(TEXT_KEYS, text):
        pill[key] = tint(hue, st, lit)
    return pill, light


def write_pill_and_kde(pill, light):
    """colors.json, fastfetch, the Ricelin-Dynamic KDE scheme + its symlink."""
    (CACHE / "colors.json").write_text(json.dumps(pill, indent=2) + "\n")
    render_fastfetch(pill)
    colors_text = render_colorscheme(pill, light)
    (CACHE / "Ricelin-Dynamic.colors").write_text(colors_text)

    schemes = Path.home() / ".local" / "share" / "color-schemes"
    schemes.mkdir(parents=True, exist_ok=True)
    link = schemes / "Ricelin-Dynamic.colors"
    if link.exists() or link.is_symlink():
        link.unlink()
    link.symlink_to(CACHE / "Ricelin-Dynamic.colors")
    write_kdeglobals(colors_text)
    write_qt6ct_colors(pill)


def write_qt6ct_colors(p):
    """Write colors in qt6ct palette config format so Qt6ct style engine applies them."""
    def hex_to_rgb(h):
        return tuple(int(h[i:i+2], 16) for i in (1, 3, 5))
    def rgb_to_hex_qt(r, g, b, a=255):
        return '#%02x%02x%02x%02x' % (a, r, g, b)
    def get_color_list(roles_map):
        res = []
        for role_hex in roles_map:
            color = p.get(role_hex, role_hex)
            r, g, b = hex_to_rgb(color)
            res.append(rgb_to_hex_qt(r, g, b))
        return ', '.join(res)

    roles = [
        'bright',                   # 0: WindowText
        'surface_container_high',    # 1: Button
        'bright',                    # 2: Light (frequently text/borders in light mode, keep bright)
        'surface_container_highest', # 3: Midlight
        'surface_container_low',     # 4: Dark
        'outline',                  # 5: Mid
        'bright',                   # 6: Text
        'cream',                    # 7: BrightText
        'bright',                   # 8: ButtonText
        'surface',                  # 9: Base (Main window/list background, MUST be dark surface)
        'surface_container',        # 10: Window (Main panel backgrounds, MUST be dark surface_container)
        '#000000',                  # 11: Shadow
        'primary',                  # 12: Highlight
        'cream',                    # 13: HighlightedText
        'primary',                  # 14: Link
        'dim',                      # 15: LinkVisited
        'surface_container_low',    # 16: AlternateBase (Alternating rows, MUST be dark surface_container_low)
        'surface',                  # 17: NoRole
        'surface_container_low',    # 18: ToolTipBase
        'bright',                   # 19: ToolTipText
        'dim'                       # 20: PlaceholderText
    ]

    cfg_dir = Path.home() / ".config" / "qt6ct" / "colors"
    cfg_dir.mkdir(parents=True, exist_ok=True)
    cfg_path = cfg_dir / "Ricelin-Dynamic.conf"
    
    colors_list = get_color_list(roles)
    content = (
        "[ColorScheme]\n"
        f"active_colors={colors_list}\n"
        f"disabled_colors={colors_list}\n"
        f"inactive_colors={colors_list}\n"
    )
    cfg_path.write_text(content)



def write_kdeglobals(colors_text):
    """Sync the [Colors:*] sections and widgetStyle into ~/.config/kdeglobals."""
    import configparser
    kg = configparser.ConfigParser(interpolation=None)
    kg.optionxform = str
    kgpath = Path.home() / ".config" / "kdeglobals"
    try:
        kg.read_string(kgpath.read_text())
    except (FileNotFoundError, configparser.Error):
        return

    cols = configparser.ConfigParser(interpolation=None)
    cols.optionxform = str
    cols.read_string(colors_text)

    for sec in cols.sections():
        if sec.startswith("ColorEffects:") or sec.startswith("Colors:"):
            kg[sec] = cols[sec]

    if kg.has_section("General"):
        # Remove lowercase duplicates to avoid conflict with case-sensitive readers
        kg["General"].pop("widgetstyle", None)
        kg["General"].pop("colorscheme", None)
        kg["General"]["widgetStyle"] = "Breeze"
        kg["General"]["ColorScheme"] = "Ricelin-Dynamic"

    # Preserving exact cases for General section and section titles
    lines = []
    for s in kg.sections():
        lines.append("[%s]" % s)
        for k, v in kg[s].items():
            # If writing back keys in General, keep their PascalCase representation
            if s == "General":
                if k.lower() == "widgetstyle":
                    lines.append("widgetStyle=%s" % v)
                    continue
                if k.lower() == "colorscheme":
                    lines.append("ColorScheme=%s" % v)
                    continue
            lines.append("%s=%s" % (k, v))
        lines.append("")

    kgpath.write_text("\n".join(lines) + "\n")


def notify_apps(light):
    """
    Notify running Qt/KDE and GTK apps of the colour-scheme change without
    requiring a restart. Failures are silently ignored — both calls are
    best-effort; the files written above are always the source of truth.
    """
    # Qt/KDE apps reload their palette in-process via this D-Bus signal
    subprocess.run(
        ["dbus-send", "--session", "--type=signal",
         "/KDEPlatformTheme", "org.kde.KDEPlatformTheme.refreshAll"],
        capture_output=True)

    # GTK3/4 apps: switch theme and color-scheme preference in-process
    gtk_theme = "Adwaita" if light else "Adwaita-dark"
    scheme = "prefer-light" if light else "prefer-dark"
    for key, val in [
        ("gtk-theme", gtk_theme),
        ("color-scheme", scheme),
    ]:
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", key, val],
            capture_output=True)

    # Also write gtk settings.ini files so the theme persists across restarts
    gtk_prefer_dark = "0" if light else "1"
    for ver in ("gtk-3.0", "gtk-4.0"):
        ini = Path.home() / ".config" / ver / "settings.ini"
        if ini.is_file():
            text = ini.read_text()
            text = re.sub(r"(?m)^gtk-theme-name=.*$",
                          f"gtk-theme-name={gtk_theme}", text)
            text = re.sub(r"(?m)^gtk-application-prefer-dark-theme=.*$",
                          f"gtk-application-prefer-dark-theme={gtk_prefer_dark}", text)
            ini.write_text(text)


def write_matugen_terminal_colors(pill, hue, sat, chromatic):
    """
    hypr-colors.lua and ghostty-colors both read matugen's dark base16, keyed
    off the same source colour as the pill's accent. If matugen fails (not
    installed, bad output, ...) the pill/KDE outputs above still
    landed, so we just skip these two rather than aborting the whole run.
    """
    try:
        b = {k: v["dark"]["color"] for k, v in
             matugen(tint(hue, sat, 0.45) if chromatic else "#787878")["base16"].items()}
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f"wallcolors: matugen step skipped ({exc})", file=sys.stderr)
        return

    (CACHE / "hypr-colors.lua").write_text(
        'return {\n    active = "%s",\n    inactive = "%s",\n}\n'
        % (pill["primary"], b["base01"]))

    lines = [
        f'background = {b["base00"]}',
        f'foreground = {b["base07"]}',
        f'cursor-color = {pill["primary"]}',
        f'selection-background = {b["base02"]}',
        f'selection-foreground = {b["base07"]}',
    ]
    ansi_map = [
        "base00", "base08", "base0b", "base0a", "base0d", "base0e", "base0c", "base05",
        "base03", "base08", "base0b", "base0a", "base0d", "base0e", "base0c", "base07"
    ]
    for i, base_key in enumerate(ansi_map):
        lines.append(f'palette = {i}={b[base_key]}')
    (CACHE / "ghostty-colors").write_text("\n".join(lines) + "\n")


FIREFOX_CUSTOM = (Path.home() /
                  ".config/mozilla/firefox/io44grgs.default-release/chrome/parfait/custom.css")


def write_firefox_accent(pill):
    """
    Push the wallpaper accent into Firefox/Parfait's custom.css so the theme
    accent tracks the wallpaper (--pf-accent-color). Only that line is
    managed; the rest of the file (blur veil, etc.) is left untouched.
    """
    css = FIREFOX_CUSTOM.read_text() if FIREFOX_CUSTOM.is_file() else ""
    accent_line = f'  --pf-accent-color: {pill["surface_container_highest"]} !important;'
    if re.search(r"--pf-accent-color\s*:", css):
        css = re.sub(r"--pf-accent-color\s*:\s*[^;]+;", accent_line, css, count=1)
    elif ":root {" in css:
        css = css.replace(":root {", ":root {\n" + accent_line, 1)
    else:
        css += f"\n:root {{\n{accent_line}\n}}\n"
    FIREFOX_CUSTOM.parent.mkdir(parents=True, exist_ok=True)
    FIREFOX_CUSTOM.write_text(css)


def main():
    source = resolve_source(sys.argv)
    if source is None:
        return 0 if len(sys.argv) >= 2 else 1
    hue, sat, mean_l, chromatic = source

    CACHE.mkdir(parents=True, exist_ok=True)
    pill, light = build_pill(hue, sat, mean_l, chromatic)

    write_pill_and_kde(pill, light)
    write_matugen_terminal_colors(pill, hue, sat, chromatic)
    write_firefox_accent(pill)
    notify_apps(light)
    return 0


if __name__ == "__main__":
    sys.exit(main())
