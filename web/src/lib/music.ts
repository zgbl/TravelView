/**
 * 配乐曲库。
 *
 * **数据里只存 id，不存文件名。** 换一首曲子、改个文件名、以后换供应商，
 * 都不该让已经发布出去的游记失效 —— 那些游记的 JSON 里躺着的是
 * 'road' 这样的 id，解析成哪个文件由这里说了算。
 *
 * 授权: 曲子作为游记的配乐播放，属于 Pixabay 许可里的
 * "adapt Content into new works"，合规。要守住的边界只有一条 ——
 * **不要让 mp3 变成一个可以单独下载的文件**: 页面上不放下载链接、
 * 不做曲库列表页。它只作为播放器的音轨存在。
 */
export type Track = {
  id: string;
  /// public/music/ 下的文件名（可以有空格，取 URL 时会编码）
  file: string;
  /// 显示给发布者看的名字
  title: string;
  /// 一句话说明它适合什么样的行程 —— 选曲时听不到，只能靠这句话判断
  mood: { zh: string; en: string };
  /// 片尾的署名。Pixabay 不强制，但这是好习惯，也是给用户的示范
  credit?: string;
};

export const TRACKS: Track[] = [
  {
    id: 'carefree',
    file: 'Carefree.mp3',
    title: 'Carefree',
    mood: { zh: '轻快 · 阳光下的公路', en: 'Bright · sunny road trip' },
    credit: 'Carefree — Kevin MacLeod',
  },
  {
    id: 'waterlily',
    file: 'Water Lily.mp3',
    title: 'Water Lily',
    mood: { zh: '安静 · 水边和清晨', en: 'Calm · water and early mornings' },
    credit: 'Water Lily',
  },
  {
    id: 'bittersweet',
    file: 'Bittersweet.mp3',
    title: 'Bittersweet',
    mood: { zh: '怀旧 · 回看很久以前的照片', en: 'Wistful · looking back' },
    credit: 'Bittersweet',
  },
  {
    id: 'duck',
    file: 'Fluffing a Duck.mp3',
    title: 'Fluffing a Duck',
    mood: { zh: '俏皮 · 家人和小孩', en: 'Playful · family and kids' },
    credit: 'Fluffing a Duck — Kevin MacLeod',
  },
];

export function trackById(id?: string | null): Track | null {
  if (!id) return null;
  return TRACKS.find((t) => t.id === id) ?? null;
}

/// 曲子的 URL。文件名里有空格，必须编码，否则 Safari 直接 404
export function trackUrl(t: Track) {
  if (/^https:\/\//i.test(t.file)) return t.file;   // 外部链接原样用
  return `/music/${encodeURIComponent(t.file)}`;
}

/**
 * 这篇游记选的曲子。没选 = null，播放器就完全不出现配乐控件。
 *
 * story.music 有两种写法:
 *   'carefree'            曲库里的 id —— 推荐，文件在我们自己这儿
 *   'https://…/x.mp3'     直接播别人服务器上的文件（hotlink）
 *
 * **第二种是给进阶用户的，我们不替它兜底。** 它法律上更干净
 * （文件不经我们的手），但对方随时可能防盗链、改地址、删文件，
 * 到那天这篇游记就永久没声音了，而发布者不会收到任何通知。
 */
export function storyTrack(story: unknown): Track | null {
  const m = (story as { music?: string })?.music?.trim();
  if (!m) return null;
  if (/^https:\/\//i.test(m)) {
    return {
      id: m,
      file: m,
      title: '自定义配乐',
      mood: { zh: '来自外部链接', en: 'External link' },
    };
  }
  // http:// 一律不收 —— 混合内容会被浏览器整页拦掉
  return trackById(m);
}
