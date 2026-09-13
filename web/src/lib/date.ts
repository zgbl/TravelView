/**
 * 从数据库取出来的时间，别直接当字符串用。
 *
 * **`pg` 会把 timestamptz / timestamp 返回成 JS 的 `Date` 对象**，而不是字符串。
 * 可代码里到处按字符串用（`.slice(0, 10)` 取日期），类型标注也写着 `string` ——
 * 这个不一致在 2026-09-13 把 `/admin` 整页打成 500：
 *
 *     TypeError: a.createdAt?.slice is not a function
 *     digest: '837459175'
 *
 * 同一个坑还有更阴的一层：`String(dateObject).slice(0, 10)` **不报错**，
 * 但显示出来的是 `"Sat Sep 13"` —— 页面上看着像日期，其实是垃圾。
 *
 * 所以：凡是"库里的时间要当字符串用"，一律过这里的函数。
 */

/** ISO 8601 字符串。Date 和字符串都能吃，空值给空串。 */
export function toIso(v: string | Date | null | undefined): string {
  if (!v) return '';
  return v instanceof Date ? v.toISOString() : String(v);
}

/** 形如 `2026-09-13` 的日期，给人看。 */
export function dayOf(v: string | Date | null | undefined): string {
  return toIso(v).slice(0, 10);
}
