import { redirect } from 'next/navigation';
import { requireUser } from '@/lib/auth';
import { getLocale } from '@/lib/i18n.server';
import { t } from '@/lib/i18n';
import LinkDeviceForm from '@/components/LinkDeviceForm';

export const dynamic = 'force-dynamic';

/**
 * 桌面端连接页。App 显示一串码，用户在这里敲进去。
 *
 * 为什么值得单独做一页: 原来的流程是"去 /account 生成令牌 -> 复制 ->
 * 切回 App 粘贴"，三步里每一步都能出错（复制少一个字符、粘到错的框、
 * 令牌漏在剪贴板里）。敲 8 个字符只有一步，而且**令牌从头到尾没经过用户的手**。
 */
export default async function LinkDevice() {
  const user = await requireUser();
  if (!user) redirect('/login?next=/link');
  const L = await getLocale();

  return (
    <main className="mx-auto max-w-md px-6 py-24">
      <h1 className="text-3xl font-semibold tracking-tight">
        {t(L, 'link.title')}
      </h1>
      <p className="mt-3 text-sm text-muted">{t(L, 'link.intro')}</p>

      <LinkDeviceForm
        labels={{
          placeholder: t(L, 'link.placeholder'),
          submit: t(L, 'link.submit'),
          busy: t(L, 'link.busy'),
          done: t(L, 'link.done'),
        }}
      />

      <p className="mt-8 text-xs text-muted">{t(L, 'link.note')}</p>
    </main>
  );
}
