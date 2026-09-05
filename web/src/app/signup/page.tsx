import Link from 'next/link';
import AuthForm from '@/components/AuthForm';

export default function Signup() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-6">
      <h1 className="mb-3 text-2xl font-semibold">创建账号</h1>
      <p className="mb-8 max-w-sm text-center text-sm text-muted">
        注册只是为了发布和管理你的旅行故事。
        照片的识别、挑选、路线还原全都在你自己的电脑上完成。
      </p>
      <AuthForm mode="signup" />
      <p className="mt-6 text-sm text-muted">
        已经有账号？<Link href="/login" className="text-accentBright">登录</Link>
      </p>
    </main>
  );
}
