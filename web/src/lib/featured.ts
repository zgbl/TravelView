import { one } from './db';
import { demoStory } from './demo-story';
import type { Story } from './story';

/**
 * 落地页上展示的那一篇。
 *
 * **用一篇真发布过的游记，而不是内置的假数据。**
 * 内置的示例是芝加哥周末两日，路线短、地图上几乎看不出形状；
 * 而这个产品最有说服力的画面是一条横穿几个州的长路线 ——
 * 落地页展示的东西不该比产品实际能做到的差。
 *
 * 换哪一篇由环境变量 `FEATURED_STORY_SLUG` 决定，改了不用改代码。
 * 找不到（没配、被删了、设成私密了）就回落到内置示例 ——
 * **落地页绝不能因为一篇游记不见了就打不开。**
 */
/**
 * 落地页上展示的那一篇 —— **写死一个能用的默认值**。
 *
 * Route 66 接西部国家公园那一趟: 横穿几个州的长路线，
 * 地图上一眼就能看出形状。内置的芝加哥示例只有两天、几英里，
 * 在地图上几乎是一个点 —— **落地页展示的东西不该比产品实际能做到的差**。
 *
 * 环境变量 FEATURED_STORY_SLUG 可以覆盖它，但**不配也能用**:
 * 一个要靠运维加一行配置才能正常显示的落地页，就是坏的。
 */
const DEFAULT_SLUG = '57976379bd';

export type Featured = { story: Story; prefix: string | null; real: boolean };

export async function featuredStory(): Promise<Featured> {
  const slug = (process.env.FEATURED_STORY_SLUG ?? '').trim() || DEFAULT_SLUG;
  if (slug) {
    try {
      const row = await one<{
        slug: string; media_prefix: string | null; manifest: Story;
      }>(
        `select slug, media_prefix, manifest
           from stories
          where slug = $1 and visibility <> 'private'
            and published_at is not null`,
        [slug],
      );
      if (row?.manifest) {
        return {
          story: row.manifest,
          prefix: row.media_prefix ?? `s/${row.slug}`,
          real: true,
        };
      }
    } catch {
      // 数据库连不上时落地页仍然要能打开
    }
  }
  return { story: demoStory, prefix: null, real: false };
}

/// 展示用的链接: 真故事指向它自己，回落时指向内置示例页
export function featuredHref(f: Featured) {
  return f.real ? `/s/${f.story.slug}` : '/demo';
}
