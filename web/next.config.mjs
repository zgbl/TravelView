/** @type {import('next').NextConfig} */
const nextConfig = {
  // standalone: 打出来的产物可以直接在 OCI 的 Node 上跑，
  // 不绑定 Vercel —— 这是"代码能通用"的前提
  output: 'standalone',
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '**' },
    ],
  },
};
export default nextConfig;
