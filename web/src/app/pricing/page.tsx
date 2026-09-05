import Link from 'next/link';
import CheckoutButtons from '@/components/CheckoutButtons';

/**
 * 定价页刻意只有两档。
 * 第一版要验证的是"有没有人愿意为发布付钱"，不是"哪种套餐卖得好"。
 */
export default function Pricing() {
  return (
    <main className="mx-auto max-w-4xl px-6 py-24">
      <Link href="/" className="text-sm text-muted">&larr; 返回</Link>
      <h1 className="mt-6 text-4xl font-semibold tracking-tight">价格</h1>
      <p className="mt-3 max-w-xl text-muted">
        App 免费使用：导入照片、还原路线、自动精选、本地预览，都不需要付费，
        也不需要注册。<strong className="text-paper">只有发布成公开链接时才收费。</strong>
      </p>

      <div className="mt-12 grid gap-6 md:grid-cols-2">
        <div className="rounded-2xl border border-white/12 p-8">
          <h2 className="text-xl font-semibold">发布一篇</h2>
          <p className="mt-2 text-sm text-muted">
            一次付费，一个永久有效的公开链接。
          </p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>永久公开地址，可随时更新内容</li>
            <li>社交平台分享预览图</li>
            <li>随时可以删除</li>
          </ul>
        </div>
        <div className="rounded-2xl border border-accentBright/40 bg-accentBright/5 p-8">
          <h2 className="text-xl font-semibold">一年不限篇数</h2>
          <p className="mt-2 text-sm text-muted">
            经常旅行的话更划算。
          </p>
          <ul className="mt-6 space-y-2 text-sm text-muted">
            <li>一年内发布任意多篇</li>
            <li>同样永久有效</li>
          </ul>
        </div>
      </div>

      <CheckoutButtons />

      <p className="mt-10 text-xs text-muted">
        无论哪一档，原图都不会上传。服务器上只有你挑中的那些照片的压缩版本。
      </p>
    </main>
  );
}
