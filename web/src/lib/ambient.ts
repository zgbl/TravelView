/**
 * 播放时的配乐。**在浏览器里现场合成，不放任何音频文件。**
 *
 * 为什么不用现成的音乐:
 *   1. **版权。** 这些页面是要被分享出去的，用一首没授权的曲子，
 *      风险落在用户和我们头上。找免费授权的曲子也要逐首核实条款，
 *      而"我们以为它是免费的"不是抗辩理由。
 *   2. **体积。** 一首三分钟的 mp3 是 3-5MB，比整篇游记的照片还大。
 *   3. **长度。** 曲子是定长的，游记不是。7 张照片的和 160 张的，
 *      要么循环得很明显，要么中途没了。合成出来的音乐可以一直长下去。
 *
 * 音乐本身刻意简单: 五声音阶（怎么弹都不会难听）、无节拍的持续音，
 * 加上换站时的一声轻响。它的作用是**托住画面**，不是抢戏 ——
 * 一段旅行回顾的配乐一旦有了旋律记忆点，第二遍看就会烦。
 */
export class Ambient {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private voices: OscillatorNode[] = [];
  private timer: number | null = null;

  /// 五声音阶（D 大调），随便挑两个音叠在一起都不会撞
  private static readonly SCALE = [
    146.83, 164.81, 185.00, 220.00, 246.94,   // D3 E3 F#3 A3 B3
    293.66, 329.63, 369.99, 440.00, 493.88,   // D4 E4 F#4 A4 B4
  ];

  get running() {
    return this.ctx !== null && this.ctx.state === 'running';
  }

  /**
   * **只能在用户手势里调用**（点了播放按钮）——
   * 浏览器不允许网页自己开始出声，这是对的:
   * 谁也不想打开一个链接就被音乐吓一跳。
   */
  async start() {
    if (this.ctx) {
      await this.ctx.resume();
      return;
    }
    const Ctor = window.AudioContext ??
      (window as unknown as { webkitAudioContext: typeof AudioContext })
        .webkitAudioContext;
    if (!Ctor) return;
    const ctx = new Ctor();
    this.ctx = ctx;

    const master = ctx.createGain();
    master.gain.value = 0;
    master.connect(ctx.destination);
    this.master = master;

    // 低通 + 缓慢摆动的截止频率: 让持续音"呼吸"，不至于像电器嗡鸣
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 700;
    filter.Q.value = 0.6;
    filter.connect(master);

    const lfo = ctx.createOscillator();
    const lfoGain = ctx.createGain();
    lfo.frequency.value = 0.05;        // 20 秒一个来回，慢到察觉不到
    lfoGain.gain.value = 260;
    lfo.connect(lfoGain).connect(filter.frequency);
    lfo.start();
    this.voices.push(lfo);

    // 三个略微失谐的持续音叠成一个"垫子"。
    // 完全同频听起来是死的，差几音分才有厚度
    [146.83, 220.00, 293.66].forEach((f, i) => {
      const o = ctx.createOscillator();
      o.type = i === 0 ? 'sine' : 'triangle';
      o.frequency.value = f;
      o.detune.value = (i - 1) * 6;
      const g = ctx.createGain();
      g.gain.value = i === 0 ? 0.16 : 0.07;
      o.connect(g).connect(filter);
      o.start();
      this.voices.push(o);
    });

    // 每 6-11 秒落一个音，位置随机 —— 有规律的间隔听着像倒计时
    const drop = () => {
      this.note(Ambient.SCALE[
        4 + Math.floor(Math.random() * (Ambient.SCALE.length - 4))]);
      this.timer = window.setTimeout(drop, 6000 + Math.random() * 5000);
    };
    this.timer = window.setTimeout(drop, 2500);

    this.fade(0.5, 3.5);
  }

  /// 一声轻响。换站时也调它，让转场"听得见"
  note(freq = 440, gain = 0.12) {
    const ctx = this.ctx;
    if (!ctx || !this.master) return;
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = 'sine';
    o.frequency.value = freq;
    // 慢起慢落，像远处的钟；直接开关会"啪"一声
    g.gain.setValueAtTime(0, ctx.currentTime);
    g.gain.linearRampToValueAtTime(gain, ctx.currentTime + 0.6);
    g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 5);
    o.connect(g).connect(this.master);
    o.start();
    o.stop(ctx.currentTime + 5.2);
  }

  /// 转场: 音色亮一点、落两个音，画面在动，声音也该动
  transit() {
    this.note(Ambient.SCALE[5], 0.1);
    window.setTimeout(() => this.note(Ambient.SCALE[8], 0.08), 700);
  }

  private fade(to: number, seconds: number) {
    const ctx = this.ctx;
    if (!ctx || !this.master) return;
    this.master.gain.cancelScheduledValues(ctx.currentTime);
    this.master.gain.setValueAtTime(this.master.gain.value, ctx.currentTime);
    this.master.gain.linearRampToValueAtTime(to, ctx.currentTime + seconds);
  }

  /// 淡出再停。硬停会有一声爆音
  async stop() {
    if (!this.ctx) return;
    this.fade(0, 1.2);
    if (this.timer) window.clearTimeout(this.timer);
    this.timer = null;
    const ctx = this.ctx;
    await new Promise((r) => setTimeout(r, 1300));
    this.voices.forEach((v) => {
      try { v.stop(); } catch { /* 已经停了 */ }
    });
    this.voices = [];
    this.master = null;
    this.ctx = null;
    await ctx.close().catch(() => {});
  }
}
