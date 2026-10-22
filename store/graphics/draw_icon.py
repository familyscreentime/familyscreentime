"""Draws the Family Screen Time icon: a Time Timer-style dial (red sector on
a white face) on a deep blue background."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont

BLUE = (31, 42, 68)
RED = (220, 40, 40)
WHITE = (255, 255, 255)
INK = (60, 70, 95)
S = 2048  # work size

def dial(size, scale=0.62, fraction=0.36):
    """Transparent image with the dial centred, diameter = scale * size."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = size * scale / 2
    c = size / 2
    d.ellipse([c - r, c - r, c + r, c + r], fill=WHITE)
    # Minute ticks.
    for i in range(12):
        a = math.radians(i * 30 - 90)
        r1 = r * (0.86 if i % 3 else 0.80)
        r2 = r * 0.93
        w = max(2, int(size * (0.012 if i % 3 == 0 else 0.007)))
        d.line([c + r1 * math.cos(a), c + r1 * math.sin(a),
                c + r2 * math.cos(a), c + r2 * math.sin(a)], fill=INK, width=w)
    # Red sector: time left, counting down towards 12 o'clock.
    rs = r * 0.76
    d.pieslice([c - rs, c - rs, c + rs, c + rs], -90 - 360 * fraction, -90, fill=RED)
    hub = r * 0.09
    d.ellipse([c - hub, c - hub, c + hub, c + hub], fill=INK)
    return img

def rounded(size, radius):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius, fill=255)
    return m

def legacy_icon(px):
    """Square icon with rounded corners, for launchers without adaptive icons."""
    bg = Image.new('RGBA', (S, S), BLUE + (255,))
    bg.alpha_composite(dial(S, 0.70))
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(bg, (0, 0), rounded(S, int(S * 0.22)))
    return out.resize((px, px), Image.LANCZOS)

def play_icon(px=512):
    """Full-bleed square: Google Play rounds the corners itself."""
    bg = Image.new('RGBA', (S, S), BLUE + (255,))
    bg.alpha_composite(dial(S, 0.70))
    return bg.resize((px, px), Image.LANCZOS)

def adaptive_foreground(px):
    """108 dp layer; the dial stays well within the 66 dp safe zone."""
    return dial(S, 0.50).resize((px, px), Image.LANCZOS)

def feature_graphic(path):
    w, h = 1024, 500
    img = Image.new('RGBA', (w * 2, h * 2), BLUE + (255,))
    d = dial(h * 2, 0.70, 0.36)
    img.alpha_composite(d, (int(w * 2 * 0.03), 0))
    draw = ImageDraw.Draw(img)
    font = None
    for f in ['/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
              '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf']:
        if os.path.exists(f):
            font = ImageFont.truetype(f, 128)
            small = ImageFont.truetype(f.replace('-Bold', ''), 60) if os.path.exists(f.replace('-Bold', '')) else ImageFont.truetype(f, 60)
            break
    x = int(w * 2 * 0.50)
    draw.text((x, 300), 'Family', font=font, fill=WHITE)
    draw.text((x, 440), 'Screen Time', font=font, fill=WHITE)
    draw.text((x, 640), 'familyscreentime.org', font=small, fill=(200, 210, 230))
    img.convert('RGB').resize((w, h), Image.LANCZOS).save(path)

res = sys.argv[1]
store = sys.argv[2]
for name, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    legacy_icon(px).save(f'{res}/mipmap-{name}/ic_launcher.png')
    adaptive_foreground(int(px * 108 / 48)).save(f'{res}/mipmap-{name}/ic_launcher_foreground.png')
os.makedirs(f'{res}/mipmap-anydpi-v26', exist_ok=True)
open(f'{res}/mipmap-anydpi-v26/ic_launcher.xml', 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
open(f'{res}/values/colors.xml', 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#1F2A44</color>
</resources>
''')
play_icon().save(f'{store}/icon-512.png')
feature_graphic(f'{store}/feature-graphic-1024x500.png')
print('ok')
