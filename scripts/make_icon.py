#!/usr/bin/env python3
"""生成 1024×1024 AppIcon：深蓝渐变 + 洗衣机轮廓 + 胖乖字样。"""
import os
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
OUT_DIR = os.path.join('Sources', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')


def pick_font(size):
    for path in (
        r'C:\Windows\Fonts\msyhbd.ttc',
        r'C:\Windows\Fonts\msyh.ttc',
        r'C:\Windows\Fonts\simhei.ttf',
        '/System/Library/Fonts/PingFang.ttc',
    ):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def vertical_gradient(top, bottom):
    img = Image.new('RGB', (SIZE, SIZE), top)
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (SIZE, y)], fill=color)
    return img


def main():
    img = vertical_gradient((58, 126, 246), (18, 44, 118)).convert('RGBA')
    draw = ImageDraw.Draw(img)

    # 洗衣机机身
    body = [SIZE * 0.235, SIZE * 0.165, SIZE * 0.765, SIZE * 0.755]
    draw.rounded_rectangle(body, radius=int(SIZE * 0.075),
                           outline=(255, 255, 255, 235), width=int(SIZE * 0.032))

    # 顶部控制条
    draw.line([(SIZE * 0.235, SIZE * 0.335), (SIZE * 0.765, SIZE * 0.335)],
              fill=(255, 255, 255, 235), width=int(SIZE * 0.026))
    knob = SIZE * 0.032
    draw.ellipse([SIZE * 0.70 - knob, SIZE * 0.25 - knob, SIZE * 0.70 + knob, SIZE * 0.25 + knob],
                 fill=(255, 255, 255, 235))

    # 滚筒
    cx, cy, r = SIZE * 0.5, SIZE * 0.552, SIZE * 0.155
    draw.ellipse([cx - r, cy - r, cx + r, cy + r],
                 outline=(255, 255, 255, 245), width=int(SIZE * 0.030))

    # 滚筒里的水波（两段弧）
    wave_r = r * 0.66
    draw.arc([cx - wave_r, cy - wave_r + r * 0.10, cx + wave_r, cy + wave_r + r * 0.10],
             start=20, end=160, fill=(255, 255, 255, 200), width=int(SIZE * 0.024))
    wave_r2 = r * 0.42
    draw.arc([cx - wave_r2, cy - wave_r2 + r * 0.22, cx + wave_r2, cy + wave_r2 + r * 0.22],
             start=25, end=155, fill=(255, 255, 255, 160), width=int(SIZE * 0.020))

    # 字样
    font = pick_font(int(SIZE * 0.115))
    label = '胖乖'
    box = draw.textbbox((0, 0), label, font=font)
    draw.text(((SIZE - (box[2] - box[0])) / 2 - box[0], SIZE * 0.80 - box[1]),
              label, font=font, fill=(255, 255, 255))

    os.makedirs(OUT_DIR, exist_ok=True)
    png_path = os.path.join(OUT_DIR, 'icon-1024.png')
    img.convert('RGB').save(png_path)
    print('wrote', png_path)

    contents = '''{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
'''
    with open(os.path.join(OUT_DIR, 'Contents.json'), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(contents)
    print('wrote Contents.json')


if __name__ == '__main__':
    main()
