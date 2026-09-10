'use client';

import { signOut } from 'next-auth/react';
import { t, type Locale } from '@/lib/i18n';

export default function SignOutButton({
  locale = 'zh', className = '',
}: { locale?: Locale; className?: string }) {
  return (
    <button
      onClick={() => signOut({ callbackUrl: `/${locale}` })}
      className={className}
    >
      {t(locale, 'nav.signout')}
    </button>
  );
}
