import Link from 'next/link';
import StoryRenderer from '@/components/StoryRenderer';
import { demoStory } from '@/lib/demo-story';

/**
 * 落地页。
 *
 * 首屏直接就是一个**真实可滚动的 Story** —— 照片、实际道路路线、地图、小车。
 * 不用截图、不用视频、不用一堆功能列表: 产品本身就是最好的说明。
 * 访客滚一屏就明白这个东西是什么，比任何文案都快。
 */
export default function Home() {
  return (
    <main>
      <header className="fixed inset-x-0 top-0 z-50 flex items-center justify-between
        bg-gradient-to-b from-black/70 to-transparent px-6 py-4">
        <div className="text-sm font-semibold tracking-wide">TravelView</div>
        <nav className="flex items-center gap-5 text-sm">
          <Link href="/pricing" className="text-white/80 hover:text-white">
            价格
          </Link>
          <Link href="/login" className="text-white/80 hover:text-white">
            登录
          </Link>
          <Link
            href="/signup"
            className="rounded-full bg-accentBright px-4 py-1.5 font-medium text-ink"
          >
            开始使用
          </Link>
        </nav>
      </header>

      <StoryRenderer story={demoStory} compact />

      <section className="border-t border-white/10 px-[6vw] py-24 text-center">
        <h2 className="mx-auto max-w-3xl text-[clamp(28px,4.5vw,48px)]
          font-semibold leading-tight tracking-tight">
          Turn your photos into a beautiful travel story.
        </h2>
        <p className="mx-auto mt-5 max-w-2xl text-muted">
          你刚刚滚过的这一页，是从一次真实旅行的照片自动生成的 ——
          路线来自照片里的 GPS，照片是自动挑出来的，你只需要确认。
        </p>

        <div className="mx-auto mt-16 grid max-w-5xl gap-10 text-left md:grid-cols-3">
          <Feature
            title="路线自己就在照片里"
            body="每张照片都带着 GPS 和时间。我们把它们还原成一条真实的驾车路线，而不是把两个点连起来。"
          />
          <Feature
            title="帮你从 91 张里挑出 8 张"
            body="连拍、同一个街景、同一个自拍，自动折叠。你只需要确认，或者改。"
          />
          <Feature
            title="原图永远不上传"
            body="所有解析都在你自己的电脑上完成。只有你点了发布，并且只有你挑中的那些照片的压缩版本，才会离开这台机器。"
          />
        </div>

        <div className="mt-16 flex flex-wrap items-center justify-center gap-4">
          <Link
            href="/signup"
            className="rounded-full bg-accentBright px-7 py-3 font-medium text-ink"
          >
            创建账号
          </Link>
          <Link
            href="/pricing"
            className="rounded-full border border-white/20 px-7 py-3"
          >
            看看价格
          </Link>
        </div>
      </section>

      <footer className="border-t border-white/10 px-6 py-10 text-center text-xs text-muted">
        TravelView &middot; 地图数据 &copy; OpenStreetMap 贡献者
      </footer>
    </main>
  );
}

function Feature({ title, body }: { title: string; body: string }) {
  return (
    <div>
      <h3 className="mb-2 text-lg font-semibold">{title}</h3>
      <p className="text-sm leading-relaxed text-muted">{body}</p>
    </div>
  );
}
