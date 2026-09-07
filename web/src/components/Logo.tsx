/**
 * 品牌标记: **一张钉在某个地方的照片**。
 *
 * 三个元素都来自产品本身 —— 照片、地点、风景。
 * 用 SVG 而不是位图，是因为它要出现在导航栏、页脚、空状态里，
 * 尺寸从 16 到 96 都要清楚；位图在这些地方不是糊就是发虚。
 */
export default function Logo({
  size = 28,
  boxed = false,
}: {
  size?: number;
  /// 带深色圆角底（用于浅色背景 / 需要"图标感"的地方）
  boxed?: boolean;
}) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" aria-hidden="true">
      {boxed && <rect width="100" height="100" rx="22" fill="#0f1113" />}
      {/* 照片卡 + 底部收成尖 = 地点标记 */}
      <path
        d="M42 60h16L50 86z"
        fill="#faf8f5"
      />
      <rect x="20" y="18" width="60" height="48" rx="9" fill="#faf8f5" />
      <rect x="25" y="23" width="50" height="38" rx="5" fill="#deece8" />
      {/* 照片内容: 两座山 + 一轮日头，抽象但一眼是风景 */}
      <circle cx="67" cy="29" r="5" fill="#ff8a5b" />
      <path d="M26 58 44 34 58 58z" fill="#1f6f63" />
      <path d="M48 58 63 40 76 58z" fill="#4fbfa8" />
      <rect x="25" y="52" width="50" height="9" rx="3" fill="#1f6f63" />
    </svg>
  );
}
