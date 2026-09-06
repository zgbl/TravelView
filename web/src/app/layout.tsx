import type { Metadata } from 'next';
import { getLocale } from '@/lib/i18n';
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
  return (
    <html lang={locale}>
      <body className="bg-ink font-sans text-paper antialiased">{children}</body>
    </html>
  );
}
