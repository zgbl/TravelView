/** @type {import('next').NextConfig} */
const nextConfig = {
  // standalone: 打出来的产物可以直接在 OCI 的 Node 上跑，
  // 不绑定 Vercel —— 这是"代码能通用"的前提
  output: 'standalone',
  // ⚠ 别在这里写 experimental.trustHostHeader。
  //
  // 站点挂在多个域名下（yourtravelview.com + 老的 travelview.blackrice.top）时，
  // standalone server 会忽略 Host / X-Forwarded-Host，按 HOSTNAME:PORT 拼绝对地址，
  // 导致登录跳转指向 https://0.0.0.0:3001/...。
  // 但 Next 15.5 **不再允许**从 next.config 设置这个键（构建会报
  // "Unrecognized key(s) in object: 'trustHostHeader' at experimental"，值被丢弃）；
  // 手工在构建产物里改成 true 又会让中间件的语言跳转也变成 0.0.0.0:3001（更糟）。
  // 所以这里保持默认，改为在服务器上用 AUTH_URL 钉住正式域名（见 web/deploy/setup-server.sh）。
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '**' },
    ],
  },
};
export default nextConfig;
