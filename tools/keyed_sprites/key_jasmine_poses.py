#!/usr/bin/env python3
"""Keys the checkerboard out of assets/story/jasmine_poses_8.png (RGB, no
alpha, baked light-grey checker — same bug class as enemies_and_bosses.png,
see key_checkerboard.py). Writes game/assets/story/jasmine_poses_8_keyed.png
— the same clean 4x2 pose grid, original PNG untouched.

    python tools/keyed_sprites/key_jasmine_poses.py
"""
import os
from key_checkerboard import key_image

HERE = os.path.dirname(__file__)
SRC = os.path.abspath(os.path.join(HERE, "..", "..", "game", "assets", "story", "jasmine_poses_8.png"))
DST = os.path.abspath(os.path.join(HERE, "..", "..", "game", "assets", "story", "jasmine_poses_8_keyed.png"))

if __name__ == "__main__":
    key_image(SRC, DST)
