/** @type {import('next').NextConfig} */
const nextConfig = {
  // standalone: 打出来的产物可以直接在 OCI 的 Node 上跑，
  // 不绑定 Vercel —— 这是"代码能通用"的前提
  output: 'standalone',
  experimental: {
    // 站点同时挂在多个域名下（yourtravelview.com 和老的 travelview.blackrice.top），
    // 而 standalone server 默认**忽略** Host / X-Forwarded-Host，一律按
    // HOSTNAME:PORT（也就是 0.0.0.0:3001）拼绝对地址 —— 后果是登录回调和
    // 跳转会把浏览器甩到 https://0.0.0.0:3001/... 上去。
    // 打开它，Next 才按反代传来的 host 头推导地址，两个域名各自登录各自生效。
    trustHostHeader: true,
  },
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '**' },
    ],
  },
};
export default nextConfig;
