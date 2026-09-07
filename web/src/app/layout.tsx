import type { Metadata } from 'next';
import { getLocale, getPathname } from '@/lib/i18n.server';
import NavBar from '@/components/NavBar';
import './globals.css';
import 'maplibre-gl/dist/maplibre-gl.css';

export const metadata: Metadata = {
  title: 'TravelView — Turn your photos into a beautiful travel story',
  description:
    '从手机照片自动还原旅行路线，挑出最值得看的照片，生成一个可以分享的旅行故事页面。原图永远留在你自己的电脑上。',
  openGraph: {
    type: 'website',
    siteName: 'TravelView',
  },
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const locale = await getLocale();
  const path = await getPathname();

  /**
   * 哪些页面**不挂**全站导航:
   *   /        落地页自带一个透明的浮动头，再来一条会打架
   *   /s/...   公开的 Story 是一件作品。顶上压一条产品导航，
   *            会把作品变成"某个网站里的一页"。它的回链在页脚。
   */
  const bare = path === '/' || path.startsWith('/s/');

  return (
    <html lang={locale}>
      <body className="bg-ink font-sans text-paper antialiased">
        {!bare && <NavBar />}
        {children}
      </body>
    </html>
  );
}
