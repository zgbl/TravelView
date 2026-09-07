/**
 * 地图上那辆车。
 *
 * **俯视视角，会转头。** 之前用的是 🚗 emoji —— 它是侧视的，而且永远
 * 朝左，于是往东开的时候看着像在倒车。俯视的车压在地图上，
 * 加上按行进方向旋转，才是"车在路上跑"，而不是"一个图标在滑动"。
 *
 * 立体感来自三样东西，都不用 3D 引擎:
 *   - 车身左右两条渐变（一侧受光、一侧背光），车顶就有了弧度
 *   - 车底一圈偏移的阴影，把车"垫"起来离开路面
 *   - 前挡风玻璃的高光斜切一刀
 */

/// 俯视小车。朝向是**车头向上（北）**，旋转由 marker 的 rotation 负责
export function carSvg(size = 34) {
  const h = Math.round(size * 1.9);
  return `
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${h}"
     viewBox="0 0 40 76">
  <defs>
    <linearGradient id="tvBody" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0"    stop-color="#c2482a"/>
      <stop offset=".38"  stop-color="#ff7a4d"/>
      <stop offset=".62"  stop-color="#ff8f63"/>
      <stop offset="1"    stop-color="#a83c22"/>
    </linearGradient>
    <linearGradient id="tvGlass" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0"   stop-color="#dff1ff" stop-opacity=".95"/>
      <stop offset=".5"  stop-color="#7fa8c4" stop-opacity=".9"/>
      <stop offset="1"   stop-color="#2c4a5e" stop-opacity=".95"/>
    </linearGradient>
  </defs>

  <!-- 落在路面上的影子: 往右下偏一点，车就"浮"起来了 -->
  <ellipse cx="21.5" cy="39.5" rx="15.5" ry="33" fill="#000" opacity=".33"/>

  <!-- 车身 -->
  <rect x="4" y="4" width="32" height="68" rx="13" fill="url(#tvBody)"/>
  <!-- 车顶: 比车身窄，颜色略深，看着才有弧面 -->
  <rect x="9" y="20" width="22" height="34" rx="9" fill="#1d2529" opacity=".22"/>
  <!-- 前挡风 + 后窗 -->
  <path d="M10 26 Q20 20 30 26 L28 34 Q20 31 12 34 Z" fill="url(#tvGlass)"/>
  <path d="M12 52 Q20 49 28 52 L29 58 Q20 62 11 58 Z"
        fill="url(#tvGlass)" opacity=".8"/>
  <!-- 车头灯 -->
  <rect x="9"  y="6" width="7" height="4" rx="2" fill="#fff6d8"/>
  <rect x="24" y="6" width="7" height="4" rx="2" fill="#fff6d8"/>
  <!-- 尾灯 -->
  <rect x="9"  y="67" width="7" height="3" rx="1.5" fill="#ff3b2f"/>
  <rect x="24" y="67" width="7" height="3" rx="1.5" fill="#ff3b2f"/>
  <!-- 车身高光: 一条斜切的白，是立体感里最省力的一笔 -->
  <path d="M7 16 Q20 9 33 16 L33 21 Q20 14 7 21 Z" fill="#fff" opacity=".22"/>
  <!-- 描边: 地图底色深浅不一，没有描边的车在浅色路面上会糊掉 -->
  <rect x="4" y="4" width="32" height="68" rx="13"
        fill="none" stroke="#2a1108" stroke-opacity=".5" stroke-width="2"/>
</svg>`.trim();
}

/**
 * 两点之间的方位角（度，正北为 0，顺时针）。
 * 直接拿 marker 的 rotation 用。
 */
export function bearing(
  from: [number, number], to: [number, number],   // [lat, lon]
): number {
  const φ1 = (from[0] * Math.PI) / 180;
  const φ2 = (to[0] * Math.PI) / 180;
  const Δλ = ((to[1] - from[1]) * Math.PI) / 180;
  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x = Math.cos(φ1) * Math.sin(φ2) -
    Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/**
 * 转向要**平滑**，不能瞬移。
 *
 * 折线上相邻两点常常只差几米，逐点算出来的方位角会剧烈抖动 ——
 * 车看着像在原地哆嗦。所以每帧只朝目标角度转一部分。
 * 同时必须走最短的一边: 从 350° 到 10° 是向右转 20°，
 * 不是向左转 340°，否则每次过正北车都会整个转一圈。
 */
export function smoothTurn(current: number, target: number, rate = 0.25) {
  let d = ((target - current + 540) % 360) - 180;
  return (current + d * rate + 360) % 360;
}
