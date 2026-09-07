import { one } from './db';

/**
 * 谁可以发布。
 *
 * 现在是**公测期：所有注册用户都按付费用户对待**，不扣额度、不看订阅。
 * 等注册数到了 `FREE_BETA_LIMIT`（默认 100）自动结束，转为按额度收费。
 *
 * 为什么用"注册人数"当闸门，而不是日期:
 * 日期到了但只有 3 个用户，这时候收费只会把仅有的几个人吓走；
 * 人数到了说明东西有人要，那才是能开口要钱的时刻。
 *
 * 三个开关:
 *   FREE_BETA=auto  人数没到上限就免费（默认）
 *   FREE_BETA=on    强制免费，不看人数
 *   FREE_BETA=off   立刻开始收费
 */
export const freeBetaLimit = Number(process.env.FREE_BETA_LIMIT ?? 100);
const mode = (process.env.FREE_BETA ?? 'auto').toLowerCase();

export type BetaState = {
  free: boolean;      // 现在是不是免费期
  users: number;      // 已注册人数
  limit: number;
  remaining: number;  // 还差多少人结束免费
};

// 每次发布都数一遍全表没必要，但也不能缓存太久 —— 30 秒足够。
let cache: { at: number; users: number } | null = null;

export async function countUsers(): Promise<number> {
  if (cache && Date.now() - cache.at < 30_000) return cache.users;
  let users = 0;
  try {
    const row = await one<{ n: string }>(
      'select count(*)::text as n from users');
    users = Number(row?.n ?? 0);
  } catch {
    // 数不出来就当还在公测期 —— 宁可多给权限，也不要让页面挂掉
    users = 0;
  }
  cache = { at: Date.now(), users };
  return users;
}

export async function betaState(): Promise<BetaState> {
  const users = await countUsers();
  const free = mode === 'on' ? true
    : mode === 'off' ? false
    : users < freeBetaLimit;
  return {
    free,
    users,
    limit: freeBetaLimit,
    remaining: Math.max(0, freeBetaLimit - users),
  };
}

/**
 * 更新计费: **每 5 次更新收一次 0.5 篇**，不是超过 5 次之后次次收。
 *
 *   第 1-5 次   免费
 *   第 6 次     扣 0.5 篇，然后重新计
 *   第 7-10 次  免费
 *   第 11 次    扣 0.5 篇
 *   ...
 *
 * 更新是正当且高频的动作: 改错别字、换封面、删掉一张不该发的照片。
 * 次次收钱等于惩罚"把东西做好"，用户就会宁可留着一篇有瑕疵的。
 * 但它确实有成本（重传照片、重写文件），所以按批收一点点。
 */
export const FREE_UPDATES = 5;

/// 这是第几次更新，要不要收费
export function updateCharged(updateCount: number) {
  return updateCount >= FREE_UPDATES + 1 &&
    (updateCount - (FREE_UPDATES + 1)) % FREE_UPDATES === 0;
}

/// 下一次收费还差几次更新（0 = 这次就要收）
export function updatesUntilCharge(updateCount: number) {
  let n = updateCount + 1;
  while (!updateCharged(n)) n++;
  return n - updateCount - 1;
}

export type Entitlement = {
  allowed: boolean;
  reason: 'beta' | 'subscription' | 'credits' | 'need_payment';
  /** 这次发布要不要扣一个额度 */
  consumesCredit: boolean;
};

export function entitlementOf(
  user: {
    story_credits: number;
    subscription_status: string | null;
    subscription_until: string | Date | null;
  } | null,
  beta: BetaState,
): Entitlement {
  // 公测期一切从宽，**而且不扣额度** ——
  // 用户买过的额度要原封不动留到收费之后
  if (beta.free) return { allowed: true, reason: 'beta', consumesCredit: false };

  const subscribed = user?.subscription_status === 'active' &&
    (!user.subscription_until ||
      new Date(user.subscription_until) > new Date());
  if (subscribed) {
    return { allowed: true, reason: 'subscription', consumesCredit: false };
  }
  if ((user?.story_credits ?? 0) > 0) {
    return { allowed: true, reason: 'credits', consumesCredit: true };
  }
  return { allowed: false, reason: 'need_payment', consumesCredit: false };
}
