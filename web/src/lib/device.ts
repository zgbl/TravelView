import { randomBytes } from 'crypto';

/**
 * 设备码登录（RFC 8628 那一套的简化版）。
 *
 * 桌面端显示一串短码，用户在网页上确认，App 轮询换回长期发布令牌。
 * **桌面端因此永远不接触用户密码** —— 以后接 Google / Apple 登录，
 * App 那一侧一行都不用改，因为它认的只是"网页上有人确认了这台机器"。
 *
 * 短码给人念和敲，所以去掉了 0/O/1/I/L 这些一眼看不清的字符，
 * 长度 8（分两段显示成 KDR8-Q2M7），配 15 分钟有效期足够抗猜测。
 */
const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export const DEVICE_CODE_TTL_MS = 15 * 60 * 1000;

export function newUserCode() {
  const bytes = randomBytes(8);
  let out = '';
  for (let i = 0; i < 8; i++) out += ALPHABET[bytes[i] % ALPHABET.length];
  return out;
}

export function newDeviceCode() {
  return `dc_${randomBytes(24).toString('hex')}`;
}

/** 显示用: KDR8-Q2M7。存库和比对一律用无横线的大写形式。 */
export function formatUserCode(code: string) {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

export function normalizeUserCode(input: string) {
  return input.toUpperCase().replace(/[^A-Z0-9]/g, '');
}
