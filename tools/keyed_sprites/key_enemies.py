#!/usr/bin/env python3
"""Keys the checkerboard out of assets/story/enemies_and_bosses.png (see
key_checkerboard.py for why). Writes game/assets/story/enemies_keyed.png —
same art, same layout, original PNG untouched.

    python tools/keyed_sprites/key_enemies.py
"""
import os
from key_checkerboard import key_image

HERE = os.path.dirname(__file__)
SRC = os.path.abspath(os.path.join(HERE, "..", "..", "game", "assets", "story", "enemies_and_bosses.png"))
DST = os.path.abspath(os.path.join(HERE, "..", "..", "game", "assets", "story", "enemies_keyed.png"))

if __name__ == "__main__":
    key_image(SRC, DST)
