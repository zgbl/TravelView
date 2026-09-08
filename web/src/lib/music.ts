/**
 * 配乐。
 *
 * **曲子由用户自己上传，我们不提供曲库。**
 * 内置曲库有两个走不通的地方: 选择永远太少（一个人的旅行配不上四首曲子里的任何一首），
 * 而且我们成了内容的提供方，版权责任落在我们身上。
 * 改成用户上传之后，上传者才是内容的来源 —— 发布时要他明确声明拥有使用权。
 *
 * story.music 的两种写法:
 *   'audio/xxx.mp3'    随这篇游记一起上传的文件，和照片放在同一个前缀下
 *   'https://…/x.mp3'  外部直链，文件不在我们这儿（我们也不为它的存活兜底）
 */
import { mediaUrl } from './story';

export type Track = {
  /// 直接能喂给 <audio> 的地址
  url: string;
  /// 是不是外部链接 —— 外链随时可能失效，播放器可以据此少报错
  external: boolean;
};

/**
 * 这篇游记的配乐，**最多三首，轮流播放**。
 *
 * @param prefix 媒体前缀（stories.media_prefix），和照片用的是同一个，
 *   所以上传的曲子天然跟着故事走、删故事时一起删掉。
 *
 * story.music 兼容两种写法:
 *   'audio/a.mp3'                 老数据: 一首
 *   ['audio/a.mp3', 'https://…']  新数据: 一到三首
 */
export function storyTracks(story: unknown, prefix?: string | null): Track[] {
  const raw = (story as { music?: unknown })?.music;
  const list = Array.isArray(raw) ? raw : (raw ? [raw] : []);
  const out: Track[] = [];
  for (const item of list) {
    if (typeof item !== 'string') continue;
    const m = item.trim();
    if (!m) continue;
    if (/^https:\/\//i.test(m)) { out.push({ url: m, external: true }); continue; }
    // http:// 一律不收 —— 混合内容会被浏览器整页拦掉
    if (/^https?:/i.test(m)) continue;
    if (!/^audio\/[A-Za-z0-9._-]{1,80}\.(mp3|m4a|aac|ogg|wav)$/i.test(m)) continue;
    // 和照片走同一个取址函数 —— 媒体根路径只有一处定义，不会各写各的
    out.push({ url: mediaUrl(m, prefix), external: false });
    if (out.length >= 3) break;
  }
  return out;
}
