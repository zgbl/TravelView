#!/usr/bin/env python3
"""从一枚源图生成全平台品牌资产。

源图: shared/logo/earth/travelview_earth.png (1254x1254, 白底圆角方形 app icon)。

生成两种形态，别混用:

  fullbleed  —— 把白底从四角"填"成图标自己的蓝，得到一张**不透明正方图**。
                iOS / Apple touch icon 用这种: 系统会自己套圆角遮罩，
                喂带透明或带白角的图，四个角就会露出白边。

  rounded    —— 保留源图自己的圆角轮廓，方框外全透明。
                浏览器 favicon、macOS/Windows 桌面图标、App 内品牌标用这种:
                这些地方不做遮罩，透明轮廓才对。

所有产物都由源图推出来，别手改生成物 —— 要改就改源图再跑一遍:
    python3 tools/brand/build_logo_assets.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "shared/logo/earth/travelview_earth.png"

# 源图上图标方块的紧贴边界（由 flood fill 量出来，见 README 中的说明）
ICON_BOX = (28, 28, 1228, 1228)
MASTER = 1200

# 判定"这是背景"的阈值: 离纯白多近算白。放太松会啃掉图标自己的浅蓝边。
BG_DEV = 45


def load_master() -> tuple[np.ndarray, np.ndarray]:
    """返回 (不透明的 fullbleed RGB master, 圆角形状 alpha master)。"""
    src = Image.open(SOURCE).convert("RGB")
    a = np.asarray(src.crop(ICON_BOX)).astype(np.int16)
    if a.shape[0] != a.shape[1]:
        raise SystemExit(f"裁出来的不是正方形: {a.shape}")

    dev = 255 - a.min(axis=2)  # 离纯白有多远
    bg_candidate = dev < BG_DEV

    # 只认**和画布边缘连通**的白 —— 否则地球上的雪、照片的白边框
    # 会被当成背景挖空，图标中间就出窟窿了。
    labels, _ = ndimage.label(bg_candidate)
    edge = np.concatenate([labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]])
    outside = np.isin(labels, np.unique(edge[edge > 0]))

    # 圆角外的白，用最近的非白像素补上 —— 四角本来就是一片平滑蓝，
    # 直接横向/纵向取边就足够，不会有缝。
    #
    # 补之前先把边界往外扩几像素: 源图圆角外挂着一圈很淡的辉光，
    # 只填"纯白"的话它会留下，做成不透明图标（iOS）四角就浮出一圈浅色描边。
    outside_fill = ndimage.binary_dilation(outside, iterations=8)
    idx = ndimage.distance_transform_edt(
        outside_fill, return_distances=False, return_indices=True
    )
    filled = a[idx[0], idx[1]]

    alpha = np.where(outside, 0, 255).astype(np.uint8)
    # 源图边缘本身是抗锯齿的，mask 也柔一点点，缩小时才不会出现硬锯齿
    alpha = np.asarray(
        Image.fromarray(alpha, "L").resize((MASTER, MASTER), Image.LANCZOS)
    )

    full = Image.fromarray(filled.astype(np.uint8), "RGB").resize(
        (MASTER, MASTER), Image.LANCZOS
    )
    return np.asarray(full), alpha


class Brand:
    def __init__(self) -> None:
        rgb, alpha = load_master()
        self.rgb = rgb
        self.alpha = alpha
        self._rounded: dict[int, Image.Image] = {}
        self._full: dict[int, Image.Image] = {}

    def fullbleed(self, size: int) -> Image.Image:
        if size not in self._full:
            self._full[size] = Image.fromarray(self.rgb, "RGB").resize(
                (size, size), Image.LANCZOS
            )
        return self._full[size]

    def rounded(self, size: int, pad: float = 0.0) -> Image.Image:
        """pad: 四周留白比例（macOS 图标习惯留一点，不然比邻居大一圈）。"""
        key = (size, round(pad, 3))
        if key in self._rounded:
            return self._rounded[key]
        inner = max(1, round(size * (1 - 2 * pad)))
        # RGB 用的也是"填过角"的那张: 透明区底下不是白，缩小时才不会泛白边
        art = Image.fromarray(self.rgb, "RGB").resize((inner, inner), Image.LANCZOS)
        art = art.convert("RGBA")
        art.putalpha(
            Image.fromarray(self.alpha, "L").resize((inner, inner), Image.LANCZOS)
        )
        if pad:
            canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            off = (size - inner) // 2
            canvas.paste(art, (off, off))
            art = canvas
        self._rounded[key] = art
        return art


def save(img: Image.Image, path: Path, *, opaque: bool = False, webp: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        img = img.convert("RGB")  # iOS 不接受带 alpha 的图标
    if webp:
        img.save(path, "WEBP", quality=webp, method=6)
    else:
        img.save(path, optimize=True)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]}  {path.stat().st_size // 1024}KB")


def quantized(img: Image.Image) -> Image.Image:
    """压到 256 色。

    照片就是这么一张，PNG 只能整张无损存，256 色能小四倍。
    只用在**显示尺寸很小**的地方（浏览器标签页图标）—— 那里的色带看不出来。
    放大会糊的场合（app 图标、桌面图标）不要用。
    """
    return img.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.FLOYDSTEINBERG)


def main() -> int:
    if not SOURCE.exists():
        raise SystemExit(f"找不到源图: {SOURCE}")
    b = Brand()

    print("web")
    # favicon: 一档三尺寸，浏览器自己挑
    b.rounded(48).save(
        ROOT / "web/src/app/favicon.ico",
        sizes=[(16, 16), (32, 32), (48, 48)],
    )
    print(f"  web/src/app/favicon.ico  16/32/48  "
          f"{(ROOT / 'web/src/app/favicon.ico').stat().st_size // 1024}KB")
    # 标签页图标。别用 512 —— Next 会把它塞进 <link rel=icon>，
    # 每次开页面都要下，192 够用且小得多
    save(quantized(b.rounded(192)), ROOT / "web/src/app/icon.png")
    # iOS"添加到主屏"用的那枚: 系统自己套圆角，所以喂不透明方图
    save(b.fullbleed(180), ROOT / "web/src/app/apple-icon.png", opaque=True)
    # 导航栏/页脚的品牌标。同一张图 PNG 105KB、WebP 17KB，
    # 而它每个页面都要取一次 —— 这一张值一个 webp。
    b.rounded(256).save(ROOT / "web/public/brand/logo.webp", "WEBP", quality=90, method=6)
    print(f"  web/public/brand/logo.webp  256x256  "
          f"{(ROOT / 'web/public/brand/logo.webp').stat().st_size // 1024}KB")

    print("mobile (tv_app)")
    for name, size in {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }.items():
        save(b.fullbleed(size), ROOT / f"apps/tv_app/ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}",
             opaque=True)

    # Android 传统图标不做遮罩，透明圆角轮廓才像图标而不是一块方块
    for density, size in {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }.items():
        save(b.rounded(size), ROOT / f"apps/tv_app/android/app/src/main/res/mipmap-{density}/ic_launcher.png")

    save(b.rounded(256), ROOT / "apps/tv_app/assets/logo.png")

    print("desktop (tv_desktop)")
    for name, size in {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }.items():
        save(b.rounded(size, pad=0.07),
             ROOT / f"apps/tv_desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset/{name}")

    save(b.rounded(256, pad=0.07), ROOT / "apps/tv_desktop/assets/logo.png")
    b.rounded(256, pad=0.04).save(
        ROOT / "apps/tv_desktop/windows/runner/resources/app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("  apps/tv_desktop/windows/runner/resources/app_icon.ico  16…256")

    return 0


if __name__ == "__main__":
    sys.exit(main())
