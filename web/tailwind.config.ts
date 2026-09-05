import type { Config } from 'tailwindcss';

export default {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        ink: '#0f1113',
        paper: '#faf8f5',
        accent: '#2e6f6a',
        accentBright: '#4fbfa8',
        muted: '#8a9196',
      },
      fontFamily: {
        sans: ['-apple-system', 'BlinkMacSystemFont', 'PingFang SC',
               'Helvetica Neue', 'sans-serif'],
      },
    },
  },
  plugins: [],
} satisfies Config;
