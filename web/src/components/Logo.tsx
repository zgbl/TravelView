/**
 * 品牌标记: **地球 + 目的地照片钉 + 航线** —— 一枚就把产品说完了。
 *
 * 用位图不用 SVG: 这枚标是画出来的（球面、六张照片、光），
 * 照着描成矢量只会得到一个"像它"的东西，不是它。
 *
 * 源图在 shared/logo/earth/，各处尺寸统一由 tools/brand/build_logo_assets.py
 * 生成。这里取的是**透明圆角**那一版 —— 导航栏压在深色底上，
 * 带白角的方图会在角上留着四块白。
 *
 * ⚠ 换 logo 别从这张图下手，改源图再跑那个脚本。
 */
export default function Logo({ size = 28 }: { size?: number }) {
  return (
    <img
      src="/brand/logo.webp"
      alt=""
      width={size}
      height={size}
      aria-hidden="true"
      draggable={false}
      // 行内图片会沿基线多出一条缝，flex 里还可能被压扁
      className="shrink-0 select-none align-middle"
    />
  );
}
