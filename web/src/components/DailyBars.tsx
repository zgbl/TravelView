/**
 * 一条序列的日柱状图。
 *
 * 刻意**不做双轴** —— 注册数和浏览量量级差着两个数量级，
 * 硬画在一张图上只会让人读错。两张小图各自一条序列，反而一眼看得懂。
 * 一条序列不需要图例（标题已经说了是什么），只直接标出峰值。
 */
export default function DailyBars({
  data,
  label,
  color = '#4fbfa8',
}: {
  data: { day: string; n: number }[];
  label: string;
  color?: string;
}) {
  const max = Math.max(1, ...data.map((d) => d.n));
  const total = data.reduce((a, d) => a + d.n, 0);
  const W = 100;
  const gap = 0.35;
  const bw = data.length ? (W - gap * (data.length - 1)) / data.length : W;

  return (
    <figure className="m-0">
      <figcaption className="flex items-baseline justify-between">
        <span className="text-sm text-muted">{label}</span>
        <span className="text-sm">
          <strong className="text-lg">{total}</strong>
          <span className="ml-1 text-muted">近 {data.length} 天</span>
        </span>
      </figcaption>

      <svg
        viewBox={`0 0 ${W} 34`}
        preserveAspectRatio="none"
        role="img"
        aria-label={`${label}，近 ${data.length} 天共 ${total}`}
        className="mt-3 h-28 w-full"
      >
        {/* 基线，退到背景里 */}
        <line x1="0" y1="32" x2={W} y2="32"
          stroke="currentColor" strokeWidth="0.2" className="text-white/15" />
        {data.map((d, i) => {
          const h = (d.n / max) * 28;
          return (
            <rect
              key={d.day}
              x={i * (bw + gap)}
              y={32 - h}
              width={bw}
              height={Math.max(d.n > 0 ? 0.6 : 0, h)}
              rx="0.4"
              fill={color}
              opacity={d.n > 0 ? 0.95 : 0.18}
            >
              <title>{`${d.day}  ${d.n}`}</title>
            </rect>
          );
        })}
      </svg>

      <div className="flex justify-between text-[11px] text-muted">
        <span>{data[0]?.day.slice(5)}</span>
        <span>峰值 {max}</span>
        <span>{data[data.length - 1]?.day.slice(5)}</span>
      </div>
    </figure>
  );
}
