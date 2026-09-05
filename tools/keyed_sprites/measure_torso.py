"""One-off: copy the 5 new boss/elite villain PNGs into
game/assets/story/villains/ (source art untouched, just copied under the
enemy id it's mapped to) and measure each one's real opaque-pixel bounding
box to compute a correct `torso_y` fraction — replacing the fixed 0.44
constant in enemy_actor.gd that assumed every enemy image has similar
padding. A high alpha threshold isolates the solid character body from the
soft glow/aura halos these renders have, which is exactly why the fixed
ratio broke: the halos vary a lot more than the character does.
"""
from PIL import Image
import shutil

SRC_DIR = r"C:\Users\Administrator\Downloads\War of Love"
DST_DIR = "game/assets/story/villains"

# enemy_id -> source filename (mapped by aura-color / theme match, verified
# against game/data/enemies.json's aura field and the game's canonical
# jinn_portrait.png, which is NOT touched by this pass)
MAPPING = {
    "poison_beast":   "ChatGPT Image Sep 5, 2026, 04_12_12 PM.png",   # green-fire skull
    "dark_knight":    "ChatGPT Image Sep 4, 2026, 09_43_37 PM.png",   # purple-flame assassin
    "chaos_sorcerer": "ChatGPT Image Sep 4, 2026, 09_38_12 PM.png",  # fire-demon swordsman
    "ice_wraith":     "ChatGPT Image Sep 4, 2026, 09_36_01 PM.png",  # blue-lightning knight
    "stone_golem":    "ChatGPT Image Sep 5, 2026, 04_04_20 PM.png",  # sand/desert golem
}

ALPHA_SOLID = 200  # threshold that isolates the solid character from soft glow

def measure(path):
    im = Image.open(path).convert("RGBA")
    alpha = im.getchannel("A")
    solid = alpha.point(lambda a: 255 if a >= ALPHA_SOLID else 0)
    bbox = solid.getbbox()
    w, h = im.size
    if bbox is None:
        return 0.44, w, h
    top, bottom = bbox[1], bbox[3]
    # torso ~ upper-third of the solid body (chest/torso sits above the
    # vertical midpoint for a standing/lunging pose), not the dead center.
    torso_y_px = top + (bottom - top) * 0.38
    return round(torso_y_px / h, 3), w, h

def main():
    results = {}
    for enemy_id, fname in MAPPING.items():
        src = f"{SRC_DIR}\\{fname}"
        dst = f"{DST_DIR}/{enemy_id}.png"
        shutil.copyfile(src, dst)
        torso_y, w, h = measure(src)
        results[enemy_id] = torso_y
        print(f"{enemy_id:16s} <- {fname}  size={w}x{h}  torso_y={torso_y}")
    print()
    print("enemies.json torso_y patch:")
    for k, v in results.items():
        print(f'  "{k}": {v},')

if __name__ == "__main__":
    main()
