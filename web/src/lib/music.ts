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
 * @param prefix 这篇游记的媒体前缀（stories.media_prefix），
 *               和照片用的是同一个，所以上传的曲子天然跟着故事走、
 *               删故事时一起删掉。
 */
export function storyTrack(story: unknown, prefix?: string | null): Track | null {
  const m = (story as { music?: string })?.music?.trim();
  if (!m) return null;
  if (/^https:\/\//i.test(m)) return { url: m, external: true };
  // http:// 一律不收 —— 混合内容会被浏览器整页拦掉
  if (/^https?:/i.test(m)) return null;
  if (!/^audio\/[A-Za-z0-9._-]{1,80}\.(mp3|m4a|aac|ogg|wav)$/i.test(m)) return null;
  // 和照片走同一个取址函数 —— 媒体根路径只有一处定义，不会各写各的
  return { url: mediaUrl(m, prefix), external: false };
}
