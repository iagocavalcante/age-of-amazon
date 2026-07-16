#!/usr/bin/env python3
"""Generate the full painted sprite set via OpenAI gpt-image-1.

Resumable: raws land in RAW_DIR and finished sprites in assets/sprites/;
existing files are skipped, so re-running only does what's missing.
A hard call cap protects the budget. See docs/art/ai-sprite-generation.md
for the art direction this encodes.

Usage:  python3 tools/generate_sprites.py [--dry-run]
"""
import base64
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, ".sprite_raws")  # gitignored
OUT_DIR = os.path.join(ROOT, "assets", "sprites")
TOKEN = open(os.path.join(ROOT, ".token")).read().strip()
MAX_CALLS = 120  # hard budget cap (~$6 at medium quality)
calls_made = 0

MASTER = (
    "Pixel art sprite for a 16-bit isometric RTS game set in the Amazon "
    "rainforest, in the style of Age of Empires II graphics. Large chunky "
    "pixels, hard dark brown outline, flat cel shading with maximum 3 shades "
    "per material, NO anti-aliasing, NO gradients, NO ground shadow. Flat "
    "solid bright green #00FF00 background. Player-color accents painted in "
    "flat pure magenta #FF00FF. Earthy palette: skin #C49064, wood #7A5630, "
    "thatch #98803E, leaf green #547A3A. "
)
SIDE = "Strict side view facing right, full body, centered. "

TRIBE_MOTIFS = {
    0: "a tall vertical headdress of long straight feathers, painted flat magenta",
    1: "a spiky mohawk feather crest painted flat magenta, and diagonal warpaint stripes",
    2: "a wide circular woven straw hat with a flat magenta band",
    3: "a jaguar-pelt hood with rounded ears draped over the head, trimmed in flat magenta",
}
UNIT_BASE = {
    "villager": "A tribal villager. Simple magenta tunic, bare feet, carrying "
                "nothing, standing relaxed with arms at sides.",
    "warrior": "A tribal warrior. Magenta chest wrap, wooden spear held "
               "vertically in right hand, small round hide shield on left arm, "
               "stone spear tip. Standing relaxed idle pose.",
    "archer": "A tribal archer. Magenta sash, wooden longbow held in left hand "
              "at side, quiver of arrows on back, slighter build than a warrior. "
              "Standing relaxed idle pose.",
}
UNIT_SIZE = (20, 30)

BUILDINGS = {
    "town_center": ((120, 96), "A stepped rainforest pyramid of packed earth and "
        "stone, 3 tiers, central stairway, doorway at base, two flat magenta "
        "banner flags on poles."),
    "house": ((56, 52), "A small rainforest hut: timber plank walls, layered "
        "palm thatch roof, doorway with a flat magenta lintel banner."),
    "barracks": ((116, 78), "A wide tribal longhouse: ridged thatch roof, timber "
        "walls, a rack of spears beside the door, a flat magenta round shield "
        "hung on the wall."),
    "watchtower": ((52, 92), "A tall lookout tower on four wooden stilts with "
        "cross bracing, railed platform, small thatch cap roof, long flat "
        "magenta pennant at the top."),
    "monument": ((96, 120), "A tall carved jade monolith on a two-step stone "
        "plinth: glowing green jade with gold inlay bands and carved glyphs, "
        "jade capstone, small flat magenta pennant. Sacred and imposing."),
}

# Environment trees — three real Amazon species with distinct silhouettes,
# sized against the 20x30 unit so the forest towers over people instead of
# reading as shrubs (kapok ~2.4x a villager; real ones are 40x, but tiles
# are 64x32 and readability wins).
TREES = {
    "kapok": ((56, 72), "A giant kapok tree (samauma), emergent giant of the "
        "Amazon: massive pale grey-brown trunk flaring into wide buttress "
        "roots at the base, broad flat umbrella-shaped crown held high, a few "
        "thick horizontal limbs visible below the crown."),
    "brazil_nut": ((44, 64), "A Brazil nut tree (castanheira): very tall "
        "straight cylindrical trunk, bare of branches, with a single dense "
        "rounded crown only at the very top."),
    "acai": ((28, 52), "An acai palm: tall vertical composition, two very "
        "slender ringed grey-green stems side by side, each stem five times "
        "taller than its crown, topped with a small burst of arching feathery "
        "fronds and small dark purple berry clusters just under the crowns."),
}

ANIMALS = {
    "capybara": ((30, 22), "A capybara, brown fur, rounded and calm."),
    "jaguar": ((30, 22), "A jaguar, golden coat with dark rosette spots, prowling."),
    "tapir": ((36, 26), "A lowland tapir, dark grey-brown, stocky with a short trunk."),
    "bush_dog": ((26, 20), "A bush dog, small, rusty-brown fur, short legs, alert."),
    "caiman": ((40, 16), "A black caiman: long, low, armored olive-dark body with "
        "scutes, long tail, short legs, elongated snout."),
}

WALK_EDIT = ("Exact same pixel art character, art style, palette, outline, "
             "proportions and flat #00FF00 background. The character is now "
             "mid-stride walking with the {leg} leg forward. Feet stay on the "
             "same ground baseline.")
ANIMAL_WALK_EDIT = ("Exact same pixel art animal, art style, palette, outline "
                    "and flat #00FF00 background. The animal is now mid-stride "
                    "walking, {leg} foreleg forward. Feet on the same baseline.")


def api(kind, prompt, ref=None):
    global calls_made
    if calls_made >= MAX_CALLS:
        raise SystemExit(f"BUDGET CAP: {MAX_CALLS} calls reached, stopping.")
    calls_made += 1
    if kind == "gen":
        cmd = ["curl", "-s", "-m", "300", "https://api.openai.com/v1/images/generations",
               "-H", f"Authorization: Bearer {TOKEN}", "-H", "Content-Type: application/json",
               "-d", json.dumps({"model": "gpt-image-1", "prompt": prompt,
                                 "size": "1024x1024", "quality": "medium"})]
    else:
        cmd = ["curl", "-s", "-m", "300", "https://api.openai.com/v1/images/edits",
               "-H", f"Authorization: Bearer {TOKEN}",
               "-F", "model=gpt-image-1", "-F", f"image=@{ref}",
               "-F", f"prompt={prompt}", "-F", "size=1024x1024", "-F", "quality=medium"]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    data = json.loads(out)
    if "error" in data:
        raise RuntimeError(f"API error: {data['error'].get('message', '')[:200]}")
    return base64.b64decode(data["data"][0]["b64_json"])


def raw_path(name):
    return os.path.join(RAW_DIR, name + ".png")


def ensure_raw(name, kind, prompt, ref=None):
    path = raw_path(name)
    if os.path.exists(path):
        return path
    print(f"  gen [{kind}] {name}", flush=True)
    png = api(kind, prompt, ref)
    open(path, "wb").write(png)
    return path


def process(src, out_name, target):
    from PIL import Image
    out = os.path.join(OUT_DIR, out_name + ".png")
    if os.path.exists(out):
        return
    img = Image.open(src).convert("RGBA")
    px = img.load()
    # Flood-fill key from the corners: kills the green screen even when the
    # model drifts its exact tone, and never punches holes in same-colored
    # paint inside the sprite (learned from batch one).
    w, h = img.width, img.height
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    bg = px[0, 0]
    def near(c):
        return abs(c[0] - bg[0]) < 70 and abs(c[1] - bg[1]) < 70 and abs(c[2] - bg[2]) < 70
    stack = [s2 for s2 in seeds if near(px[s2[0], s2[1]])]
    seen = set(stack)
    while stack:
        x, y = stack.pop()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x+1, y), (x-1, y), (x, y+1), (x, y-1)):
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen:
                c = px[nx, ny]
                if c[3] > 0 and near(c):
                    seen.add((nx, ny))
                    stack.append((nx, ny))
    box = img.getbbox()
    if box is None:
        raise RuntimeError(f"{src}: keyed to nothing")
    img = img.crop(box)
    scale = min(target[0] / img.width, target[1] / img.height)
    size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
    img = img.resize(size, Image.NEAREST)
    alpha = img.getchannel("A")
    q = img.convert("RGB").quantize(colors=14, dither=Image.NONE).convert("RGBA")
    q.putalpha(alpha.point(lambda a: 255 if a > 96 else 0))
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    canvas.alpha_composite(q, ((target[0] - size[0]) // 2, target[1] - size[1]))
    canvas.save(out)
    print(f"  ok  {out_name} {size}", flush=True)


def main():
    dry = "--dry-run" in sys.argv
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    plan = []

    # Units: generic idle -> per-tribe idle (edit) -> walk frames (edits)
    for utype, base in UNIT_BASE.items():
        plan.append((f"unit_{utype}_generic_idle", "gen", MASTER + SIDE + base, None, None))
        for tribe, motif in TRIBE_MOTIFS.items():
            tid = f"unit_{utype}_idle_t{tribe}"
            plan.append((tid, "edit",
                "Exact same pixel art character, style, palette, outline and flat "
                f"#00FF00 background, but now wearing {motif}. Keep everything "
                "else identical.", f"unit_{utype}_generic_idle",
                (f"unit_{utype}_idle_t{tribe}", UNIT_SIZE)))
            for frame, leg in [("walk_a", "LEFT"), ("walk_b", "RIGHT")]:
                plan.append((f"unit_{utype}_{frame}_t{tribe}", "edit",
                    WALK_EDIT.format(leg=leg), tid,
                    (f"unit_{utype}_{frame}_t{tribe}", UNIT_SIZE)))

    for btype, (size, prompt) in BUILDINGS.items():
        plan.append((f"building_{btype}", "gen",
            MASTER + "Three-quarter isometric game-building view, centered. " + prompt,
            None, (f"building_{btype}", size)))

    for species, (size, prompt) in TREES.items():
        plan.append((f"tree_{species}", "gen",
            MASTER + "Full tree, centered, ground-level base. " + prompt +
            " NO magenta anywhere.", None, (f"tree_{species}", size)))

    for species, (size, prompt) in ANIMALS.items():
        base = f"animal_{species}_idle"
        plan.append((base, "gen", MASTER + SIDE + prompt + " NO magenta anywhere.",
            None, (base, size)))
        for frame, leg in [("walk_a", "left"), ("walk_b", "right")]:
            plan.append((f"animal_{species}_{frame}", "edit",
                ANIMAL_WALK_EDIT.format(leg=leg), base,
                (f"animal_{species}_{frame}", size)))

    todo = [p for p in plan if not (p[4] and os.path.exists(
        os.path.join(OUT_DIR, p[4][0] + ".png")))]
    print(f"plan: {len(plan)} steps, {len(todo)} to do, cap {MAX_CALLS} calls", flush=True)
    if dry:
        for p in plan:
            print(" ", p[0])
        return

    for name, kind, prompt, ref, out in plan:
        try:
            ref_path = raw_path(ref) if ref else None
            if ref_path and not os.path.exists(ref_path):
                print(f"  SKIP {name}: missing ref {ref}", flush=True)
                continue
            src = ensure_raw(name, kind, prompt, ref_path)
            if out:
                process(src, out[0], out[1])
        except Exception as exc:
            print(f"  FAIL {name}: {exc}", flush=True)

    print(f"DONE. API calls this run: {calls_made} (~${calls_made * 0.05:.2f})", flush=True)


if __name__ == "__main__":
    main()
