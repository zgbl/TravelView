import StoryRenderer from '@/components/StoryRenderer';
import { demoStory } from '@/lib/demo-story';
import { getLocale } from '@/lib/i18n.server';

export const metadata = { title: 'TravelView — 示例' };

/**
 * 完整的示例游记。
 *
 * **和真实的 Story 页长得一模一样**（没有导航条、可以全屏播放），
 * 因为它要回答的问题就是"我发出去的东西长什么样"。
 * 落地页里那个装在窗口框里的是同一份数据，只是被限制了高度。
 */
export default async function Demo() {
  const L = await getLocale();
  return <StoryRenderer story={demoStory} locale={L} />;
}
