import nodemailer, { type Transporter } from 'nodemailer';

/**
 * 发信。现在只发一种信：重置密码。
 *
 * **用 SMTP，不用第三方发信 API。** 一个自己能搬走的邮箱（Zoho）加一行
 * SMTP 配置，就不会哪天因为某家服务改价、封号、要求域名验证而发不出信；
 * 将来量大了再换 SES/Resend，也只用改这一个文件。
 *
 * 配置全部走环境变量（见 deploy/setup-server.sh 里的模板）：
 *
 *   SMTP_HOST=smtp.zoho.com     欧洲区账号是 smtp.zoho.eu
 *   SMTP_PORT=465               465=SSL（默认），587=STARTTLS
 *   SMTP_USER=travelview@zoho.com
 *   SMTP_PASS=<Zoho 生成的应用专用密码，不是登录密码>
 *   MAIL_FROM="TravelView <travelview@zoho.com>"
 *
 * **发信人必须就是那个 SMTP 账号**（或它的别名），否则 Zoho 直接拒收 ——
 * 这是伪造发件人的通用防线，不是配置错误。
 */
const host = process.env.SMTP_HOST ?? 'smtp.zoho.com';
const port = Number(process.env.SMTP_PORT ?? 465);
const user = process.env.SMTP_USER ?? '';
const pass = process.env.SMTP_PASS ?? '';

export const mailFrom =
  process.env.MAIL_FROM ?? (user ? `TravelView <${user}>` : '');

/** 没配 SMTP 时**不要静默假装发出去了** —— 调用方据此如实告诉用户。 */
export const mailConfigured = Boolean(user && pass);

let cached: Transporter | null = null;

function transport(): Transporter {
  if (cached) return cached;
  cached = nodemailer.createTransport({
    host,
    port,
    // 465 是隐式 SSL；587 要先明文再 STARTTLS，secure 必须是 false
    secure: port === 465,
    auth: { user, pass },
  });
  return cached;
}

export async function sendMail(opts: {
  to: string;
  subject: string;
  text: string;
  html?: string;
}) {
  if (!mailConfigured) {
    throw new Error('SMTP 没有配置（SMTP_USER / SMTP_PASS）');
  }
  await transport().sendMail({ from: mailFrom, ...opts });
}

/**
 * 重置密码的信。
 *
 * 纯文本和 HTML 都给：很多邮件客户端（和企业网关）只读纯文本那一份，
 * 只发 HTML 的信在它们那里就是一封空信。
 */
export function resetMail(link: string, locale: 'zh' | 'en') {
  const zh = locale === 'zh';
  const subject = zh ? 'TravelView 重置密码' : 'Reset your TravelView password';

  const text = zh
    ? `点下面的链接设置新密码（1 小时内有效，只能用一次）：\n\n${link}\n\n`
      + '如果不是你本人要求的，忽略这封信就行，你的密码不会有任何变化。\n'
    : `Open this link to set a new password. It expires in 1 hour and works `
      + `once:\n\n${link}\n\n`
      + `If you did not ask for this, just ignore this email — your password `
      + `stays as it is.\n`;

  const html = `
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
  max-width:520px;margin:0 auto;padding:32px 24px;color:#16181a">
  <div style="font-size:18px;font-weight:600;margin-bottom:24px">TravelView</div>
  <p style="font-size:15px;line-height:1.7;margin:0 0 24px">
    ${zh ? '点下面的按钮设置一个新密码。' : 'Use the button below to set a new password.'}
  </p>
  <a href="${link}" style="display:inline-block;background:#1f6f63;color:#fff;
    text-decoration:none;font-size:15px;font-weight:600;padding:12px 28px;
    border-radius:999px">
    ${zh ? '设置新密码' : 'Set a new password'}
  </a>
  <p style="font-size:13px;line-height:1.7;color:#6b7280;margin:24px 0 0">
    ${zh ? '这个链接 1 小时内有效，而且只能用一次。'
         : 'The link expires in 1 hour and works once.'}
    <br>
    ${zh ? '如果不是你本人要求的，忽略这封信即可，密码不会有任何变化。'
         : 'If you did not ask for this, ignore this email — nothing changes.'}
  </p>
  <p style="font-size:12px;color:#9ca3af;margin-top:24px;word-break:break-all">
    ${link}
  </p>
</div>`.trim();

  return { subject, text, html };
}
