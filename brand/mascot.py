"""The GassiPass mascot: an apricot mini poodle with a teddy bear cut, as SVG."""

import math, random, sys

OUT = "#5B3417"      # outline, dark brown
FUR = "#EDA567"      # apricot
FUR_D = "#D4884A"    # ears / shadow
FUR_L = "#F8C996"    # muzzle / highlights

def cluster(cx, cy, rx, ry, n, r, jitter=0.0, seed=1, rot=0):
    """Circles on the rim of an ellipse plus a filled core: a curly blob."""
    rnd = random.Random(seed)
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        c, s = math.cos(rot), math.sin(rot)
        x, y = x * c - y * s, x * s + y * c
        rr = r * (1 + rnd.uniform(-jitter, jitter))
        pts.append((cx + x, cy + y, rr))
    return pts

def blob(pts, core, fill, outline=OUT, w=14):
    """core = (cx, cy, rx, ry, rot_deg). Outline pass first, then fill pass."""
    cx, cy, rx, ry, rot = core
    s = []
    s.append(f'<g fill="{outline}">')
    s.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx+w}" ry="{ry+w}" transform="rotate({rot} {cx} {cy})"/>')
    s += [f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r+w:.1f}"/>' for x, y, r in pts]
    s.append('</g>')
    s.append(f'<g fill="{fill}">')
    s.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" transform="rotate({rot} {cx} {cy})"/>')
    s += [f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}"/>' for x, y, r in pts]
    s.append('</g>')
    return "\n".join(s)

def poodle(w=14):
    """The mascot, drawn around the centre (512, 540) of a 1024 box."""
    g = []
    # Ears: long and fluffy. They hang beside the face, behind the head.
    for side, seed in ((-1, 3), (1, 4)):
        cx = 512 + side * 222
        pts = cluster(cx, 610, 82, 170, 16, 52, 0.12, seed, rot=side * -0.12)
        g.append(blob(pts, (cx, 610, 82, 170, side * -7), FUR_D, w=w))
        # A darker inner lock gives the ear depth.
        inner = cluster(cx + side * 8, 650, 44, 115, 12, 30, 0.15, seed + 20, rot=side * -0.12)
        g.append(f'<g fill="#C27842" opacity="0.55">' + "".join(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}"/>' for x, y, r in inner) + f'<ellipse cx="{cx + side * 8}" cy="650" rx="44" ry="115"/></g>')
    # Head: round and wide, with a soft top knot.
    head = cluster(512, 495, 215, 182, 24, 60, 0.1, 7)
    g.append(blob(head, (512, 495, 215, 182, 0), FUR, w=w))
    # Highlights on the top knot.
    knot = cluster(512, 365, 105, 45, 12, 34, 0.12, 30)
    g.append(f'<g fill="{FUR_L}" opacity="0.5">' + "".join(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}"/>' for x, y, r in knot) + '<ellipse cx="512" cy="365" rx="105" ry="45"/></g>')
    # Muzzle: wide, round and a little lighter, like a teddy bear.
    muz = cluster(512, 640, 132, 92, 16, 40, 0.08, 9)
    g.append(blob(muz, (512, 640, 132, 92, 0), FUR_L, outline="#E2995C", w=8))
    # Eyes.
    for side in (-1, 1):
        x = 512 + side * 94
        g.append(f'<ellipse cx="{x}" cy="532" rx="37" ry="41" fill="#2A160A"/>')
        g.append(f'<circle cx="{x+11}" cy="516" r="13" fill="#FFFFFF"/>')
        g.append(f'<circle cx="{x-10}" cy="546" r="5.5" fill="#FFFFFF" opacity="0.8"/>')
    # Nose.
    g.append('<path d="M458 596 Q512 572 566 596 Q564 638 512 654 Q460 638 458 596 Z" fill="#2A160A"/>')
    g.append('<ellipse cx="494" cy="598" rx="17" ry="8" fill="#FFFFFF" opacity="0.45"/>')
    # Mouth and tongue.
    g.append('<path d="M512 654 L512 676" stroke="#2A160A" stroke-width="9" stroke-linecap="round"/>')
    g.append('<path d="M480 704 Q480 752 512 752 Q544 752 544 704 Z" fill="#F07A8A" stroke="#2A160A" stroke-width="8" stroke-linejoin="round"/>')
    g.append('<path d="M512 708 L512 734" stroke="#C85468" stroke-width="5" stroke-linecap="round"/>')
    g.append('<path d="M450 682 Q482 714 512 676 Q542 714 574 682" fill="none" stroke="#2A160A" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>')
    # Cheeks.
    for side in (-1, 1):
        g.append(f'<ellipse cx="{512+side*158}" cy="618" rx="30" ry="18" fill="#F27E6B" opacity="0.35"/>')
    return "\n".join(g)

def svg(body, bg=None, size=1024):
    back = f'<rect width="1024" height="1024" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024">{back}{body}</svg>'
