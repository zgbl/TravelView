/**
 * 播放器的配乐。一到三首，放完一首接下一首。
 *
 * 三条原则，都是"背景音乐"这四个字的直接推论:
 *   **音量要低。** 它是垫在画面底下的，不是节目本身。
 *   **要缓缓进来。** 画面先站住，音乐再浮上来 —— 一上来就响，
 *     像误点了别的东西。
 *   **放完就结束。** 游记看完了还在循环，是在赶人。
 */
/// 默认音量。**刻意压得很低** —— 背景音乐盖过画面就是喧宾夺主
const DEFAULT_VOL = 0.18;
const MAX_VOL = 0.6;

export class Ambient {
  private el: HTMLAudioElement | null = null;
  private fadeTimer: number | null = null;
  /// 现在放到第几首
  private at = 0;
  /// 音量（用户可调），0..MAX_VOL
  private vol = DEFAULT_VOL;
  /// 收尾中: 当前这首放完就停，不再接下一首
  private finishing = false;

  constructor(private srcs: string[]) {
    try {
      const v = parseFloat(localStorage.getItem('tv.player.vol') ?? '');
      if (Number.isFinite(v) && v >= 0 && v <= MAX_VOL) this.vol = v;
    } catch { /* 无痕模式会抛，用默认值 */ }
  }

  get running() { return !!this.el && !this.el.paused; }
  get volume() { return this.vol; }

  /**
   * **只能在用户手势里调用。** 浏览器不允许网页自己开始出声，这是对的:
   * 谁也不想打开一个链接就被音乐吓一跳。点"播放"那一下算手势。
   *
   * @param delayMs 等一会儿再出声。**默认让画面先走两秒** ——
   *   标题还没出来音乐就响了，观众会先去找声音是哪儿来的。
   */
  async start(delayMs = 0): Promise<boolean> {
    if (!this.el) {
      const el = new Audio(this.srcs[0]);
      // **不用 loop**: 单曲循环会把"就这一首"暴露得很明显。
      // 放完切下一首；只有一首时才等于循环
      el.loop = false;
      el.preload = 'auto';
      el.volume = 0;
      el.addEventListener('ended', () => this.next());
      // 某一首挂了（文件坏了、外链失效）不该让配乐整个停掉，跳过它
      el.addEventListener('error', () => {
        if (this.srcs.length > 1 && !this.finishing) this.next();
      });
      this.el = el;
    }
    try {
      await this.el.play();
    } catch {
      return false;            // 被浏览器拦下 —— 不是错误，交给调用方处理
    }
    // 起头这一段要长: 音乐是"浮上来"的，不是"切进来"的
    if (delayMs > 0) {
      window.setTimeout(() => this.fadeTo(this.vol, 4000), delayMs);
    } else {
      this.fadeTo(this.vol, 2500);
    }
    return true;
  }

  /// 换下一首。收尾状态下不再续 —— 游记已经放完了
  private next() {
    const el = this.el;
    if (!el) return;
    if (this.finishing) { this.stop(); return; }
    this.at = (this.at + 1) % this.srcs.length;
    el.src = this.srcs[this.at];
    void el.play().catch(() => {});
  }

  /**
   * 行程放完了: **让当前这首自然放完，然后停住，不再从头开始。**
   * 硬切会把最后那一刻切碎；而无限循环下去是在赶人。
   */
  finish() { this.finishing = true; }

  /// 用户调音量。记住选择 —— 嫌吵的人不该每篇都调一次
  setVolume(v: number) {
    this.vol = Math.max(0, Math.min(MAX_VOL, v));
    try { localStorage.setItem('tv.player.vol', String(this.vol)); }
    catch { /* 无痕 */ }
    if (this.el) this.fadeTo(this.vol, 200);
  }

  /// 暂停画面时音乐也该停 —— 画面停了声音还在飘，很怪
  pause() {
    if (!this.el) return;
    this.fadeTo(0, 500);
    window.setTimeout(() => this.el?.pause(), 520);
  }

  async resume() {
    if (!this.el) return;
    try { await this.el.play(); } catch { return; }
    this.fadeTo(this.vol, 1200);
  }

  /// 淡出再停。**直接 pause 会有一声爆音**
  stop() {
    const el = this.el;
    if (!el) return;
    this.fadeTo(0, 900);
    window.setTimeout(() => {
      el.pause();
      el.src = '';           // 断开下载，别让它在后台继续拉流量
    }, 950);
    this.el = null;
    if (this.fadeTimer) window.clearInterval(this.fadeTimer);
  }

  /**
   * 音量渐变。
   * **用定时器一步步逼近** —— HTMLAudioElement 的 volume 没有内建渐变，
   * 直接赋值听得出台阶。
   */
  private fadeTo(to: number, ms: number) {
    const el = this.el;
    if (!el) return;
    if (this.fadeTimer) window.clearInterval(this.fadeTimer);
    const step = 40;
    const from = el.volume;
    const n = Math.max(1, Math.round(ms / step));
    let k = 0;
    this.fadeTimer = window.setInterval(() => {
      k++;
      el.volume = Math.max(0, Math.min(1, from + (to - from) * (k / n)));
      if (k >= n) {
        if (this.fadeTimer) window.clearInterval(this.fadeTimer);
        this.fadeTimer = null;
      }
    }, step);
  }
}

export { DEFAULT_VOL, MAX_VOL };
