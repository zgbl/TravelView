/**
 * 播放器的配乐。
 *
 * 就是一个循环播放的 <audio>，加上淡入淡出和转场压音。**没有花活** ——
 * 之前试过用 Web Audio 现场合成，结果不像音乐像电器嗡鸣，那条路作废了。
 *
 * 音量的三档:
 *   FULL  正常播放
 *   DUCK  转场时压低，让"车在动"这件事听得见（广播里叫 ducking）
 *   0     静音
 */
const FULL = 0.42;   // 配乐是垫底的。超过 0.5 就开始和画面抢注意力
const DUCK = 0.18;

export class Ambient {
  private el: HTMLAudioElement | null = null;
  private fadeTimer: number | null = null;
  private duckTimer: number | null = null;
  private target = FULL;

  constructor(private src: string) {}

  get running() {
    return !!this.el && !this.el.paused;
  }

  /**
   * **只能在用户手势里调用。** 浏览器不允许网页自己开始出声，这是对的:
   * 谁也不想打开一个链接就被音乐吓一跳。点"播放"那一下算手势，
   * 所以从那里调通常能过；过不了就静静地失败，由调用方显示开声按钮。
   */
  async start(): Promise<boolean> {
    if (!this.el) {
      const el = new Audio(this.src);
      el.loop = true;          // 行程长短不一，曲子必须能一直循环下去
      el.preload = 'auto';
      el.volume = 0;
      this.el = el;
    }
    try {
      await this.el.play();
    } catch {
      return false;            // 被浏览器拦下 —— 不是错误，交给调用方处理
    }
    this.fadeTo(FULL, 2000);
    return true;
  }

  /// 转场: 压低两秒再回来，给地图那一刻让出空间
  transit() {
    if (!this.el) return;
    if (this.duckTimer) window.clearTimeout(this.duckTimer);
    this.fadeTo(DUCK, 400);
    this.duckTimer = window.setTimeout(() => this.fadeTo(FULL, 1200), 1800);
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
    this.fadeTo(FULL, 800);
  }

  /// 淡出再停。**直接 pause 会有一声爆音**
  stop() {
    const el = this.el;
    if (!el) return;
    this.fadeTo(0, 700);
    window.setTimeout(() => {
      el.pause();
      el.src = '';           // 断开下载，别让它在后台继续拉流量
    }, 750);
    this.el = null;
    if (this.fadeTimer) window.clearInterval(this.fadeTimer);
    if (this.duckTimer) window.clearTimeout(this.duckTimer);
  }

  /**
   * 音量渐变。
   * **用定时器一步步逼近，不用 CSS/Web Audio 的 ramp** ——
   * HTMLAudioElement 的 volume 没有内建的渐变，而直接赋值听得出台阶。
   */
  private fadeTo(to: number, ms: number) {
    const el = this.el;
    if (!el) return;
    this.target = to;
    if (this.fadeTimer) window.clearInterval(this.fadeTimer);
    const step = 40;
    const from = el.volume;
    const n = Math.max(1, Math.round(ms / step));
    let k = 0;
    this.fadeTimer = window.setInterval(() => {
      k++;
      const v = from + (to - from) * (k / n);
      el.volume = Math.max(0, Math.min(1, v));
      if (k >= n) {
        if (this.fadeTimer) window.clearInterval(this.fadeTimer);
        this.fadeTimer = null;
      }
    }, step);
  }
}
