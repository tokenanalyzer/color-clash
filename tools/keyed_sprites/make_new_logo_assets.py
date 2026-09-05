"""One-off: build wordmark.png + regenerated Android icon set from the new
War of Love crest PNG. Source crest is left untouched; every output is a
fresh composite/copy. Run once from repo root: python tools/keyed_sprites/make_new_logo_assets.py
"""
from PIL import Image

SRC = r"C:\Users\Administrator\Downloads\War of Love\ChatGPT Image Sep 5, 2026, 05_34_35 PM.png"
BRANDING = "game/assets/branding"

def trimmed(im):
    bbox = im.getchannel("A").getbbox()
    return im.crop(bbox) if bbox else im

def fit_canvas(im, canvas_size, frac):
    """Paste `im` (already trimmed to content) centered on a transparent
    square canvas, scaled so its longer side is `frac` of canvas_size."""
    out = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    scale = (canvas_size * frac) / max(im.size)
    w, h = int(im.width * scale), int(im.height * scale)
    resized = im.resize((w, h), Image.LANCZOS)
    out.paste(resized, ((canvas_size - w) // 2, (canvas_size - h) // 2), resized)
    return out

def main():
    crest = Image.open(SRC).convert("RGBA")
    crest = trimmed(crest)
    print("crest trimmed size:", crest.size)

    # 1. wordmark.png — main-menu logo slot (AssetLibrary &"brand_wordmark").
    #    Generous canvas, no padding logic needed here: main_menu.gd fits it
    #    by aspect ratio itself, so just ship the trimmed art at good res.
    wordmark = crest.copy()
    wordmark.save(f"{BRANDING}/wordmark.png")
    print("wrote wordmark.png", wordmark.size)

    # 2. icon_fg.png — adaptive-icon foreground layer (transparent, crest
    #    scaled to sit inside Android's ~66% safe zone).
    fg = fit_canvas(crest, 432, 0.62)
    fg.save(f"{BRANDING}/icon_fg.png")
    print("wrote icon_fg.png")

    # 3. icon_mono.png — white silhouette version (Android themed icon),
    #    same placement as fg, alpha-only shape recolored solid white.
    mono_src = fit_canvas(crest, 432, 0.62)
    alpha = mono_src.getchannel("A")
    white = Image.new("RGBA", mono_src.size, (255, 255, 255, 0))
    white.putalpha(alpha)
    white.save(f"{BRANDING}/icon_mono.png")
    print("wrote icon_mono.png")

    # 4. icon_bg.png — untouched, existing gradient background layer reused.
    bg = Image.open(f"{BRANDING}/icon_bg.png").convert("RGB")

    # 5. icon_512.png — flat launcher icon = fg composited onto bg, both at 512.
    bg512 = bg.resize((512, 512), Image.LANCZOS)
    fg512 = fit_canvas(crest, 512, 0.72).convert("RGBA")
    flat = bg512.convert("RGBA")
    flat.alpha_composite(fg512)
    flat.convert("RGB").save(f"{BRANDING}/icon_512.png")
    print("wrote icon_512.png")

if __name__ == "__main__":
    main()
