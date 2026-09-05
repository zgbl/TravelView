import Link from 'next/link';
import AuthForm from '@/components/AuthForm';

export default function Login() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-6">
      <h1 className="mb-8 text-2xl font-semibold">登录 TravelView</h1>
      <AuthForm mode="login" />
      <p className="mt-6 text-sm text-muted">
        还没有账号？<Link href="/signup" className="text-accentBright">注册</Link>
      </p>
    </main>
  );
}
