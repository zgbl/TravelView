import 'package:flutter_test/flutter_test.dart';
import 'package:tv_app/state/story_draft.dart';
import 'package:tv_shared/tv_shared.dart';

/// 配乐的规则是**发布链路上的闸门**，不是界面上的装饰:
/// 收错一种后缀，导出时那个文件会被 StoryExporter 静默跳过（用户配了音乐却是哑的）；
/// 声明没重置，一句"我拥有使用权"会被无限期沿用下去。
/// 这些都在纯 Dart 里，不碰手机也不碰相册，正好拿来当护栏。
void main() {
  StoryDraft draft() => StoryDraft(defaultTitle: '2024.5.1');

  test('收音频后缀，别的挡在外面', () {
    final d = draft();
    expect(d.addMusic('/tmp/a.mp3'), isTrue);
    expect(d.addMusic('/tmp/b.m4a'), isTrue);
    expect(d.addMusic('/tmp/c.ogg'), isTrue);
    // 到上限了
    expect(d.addMusic('/tmp/d.wav'), isFalse);
    expect(d.music.length, StoryDraft.maxTracks);

    final e = draft();
    expect(e.addMusic('/tmp/movie.mp4'), isFalse);
    expect(e.addMusic('/tmp/photo.jpg'), isFalse);
    expect(e.addMusic('   '), isFalse);
    expect(e.music, isEmpty);
  });

  test('后缀大小写不影响', () {
    final d = draft();
    expect(d.addMusic('/tmp/Song.MP3'), isTrue);
  });

  test('https 外链收，http 不收', () {
    final d = draft();
    expect(d.addMusic('https://example.com/a.mp3'), isTrue);
    // http 会被浏览器整页拦掉，而且导出时会被当成一个不存在的本地文件
    // 静默跳过 —— 收进来等于给用户埋一个"发布出去是哑的"的坑
    expect(d.addMusic('http://example.com/b.mp3'), isFalse);
    expect(d.addMusic('file:///Users/me/a.mp3'), isFalse);
    expect(d.addMusic('ftp://example.com/c.mp3'), isFalse);
  });

  test('同一首不重复加', () {
    final d = draft();
    expect(d.addMusic('https://example.com/a.mp3'), isTrue);
    expect(d.addMusic('https://example.com/a.mp3'), isFalse);
    expect(d.music.length, 1);
  });

  test('每次加曲子，版权声明都要重新来', () {
    final d = draft();
    d.addMusic('https://example.com/a.mp3');
    d.setMusicRights(true);
    expect(d.musicRightsOk, isTrue);

    d.addMusic('https://example.com/b.mp3');
    expect(d.musicRightsOk, isFalse, reason: '新曲子没被声明过');
  });

  test('没声明就不发布配乐', () {
    final d = draft();
    d.addMusic('https://example.com/a.mp3');
    expect(d.musicForPublish, isEmpty);

    d.setMusicRights(true);
    expect(d.musicForPublish.length, 1);

    d.setMusicRights(false);
    expect(d.musicForPublish, isEmpty);
  });

  test('曲子全删掉之后，声明不能还亮着', () {
    final d = draft();
    d.addMusic('https://example.com/a.mp3');
    d.setMusicRights(true);
    d.removeMusic('https://example.com/a.mp3');
    expect(d.music, isEmpty);
    expect(d.musicRightsOk, isFalse);
  });

  test('没有曲子时，声明只能是假', () {
    final d = draft();
    d.setMusicRights(true);
    expect(d.musicRightsOk, isFalse);
  });

  test('显示名: 本地取文件名，外链取域名', () {
    expect(StoryDraft.trackLabel('/Users/me/Music/夜曲.mp3'), '夜曲.mp3');
    expect(StoryDraft.trackLabel('https://cdn.example.com/song.mp3'),
        'cdn.example.com');
  });

  _i18nGuard();
}

/// 英文界面上不该冒出中文。**用中文原文当 key 的代价就在这里** ——
/// 改中文原文时忘了改 key，英文界面会安静地回落到中文。
/// 这一组只盯着配乐这条路：它是发布链路的闸门，用户看不懂就敢乱勾。
void _i18nGuard() {
  group('配乐文案的英文都在', () {
    setUp(() => L10n.set('en'));
    tearDown(() => L10n.set('zh'));

    const keys = [
      '配乐',
      '没有配乐',
      '{0} 首 · 已声明',
      '{0} 首 · 未声明',
      '配乐 · {0} 首：{1}',
      '配乐（最多 {0} 首，轮流播放）',
      '曲子由你自己上传，我们不提供曲库，上传的人就是版权责任的承担人。',
      '选一个音频文件…',
      '再加一首',
      '用外部链接',
      '去掉这一首',
      '用一个外部链接作为配乐',
      '用这个',
      '必须是 https 的音频文件直链（.mp3 / .m4a / .ogg），\n不是播放页面的网址',
      '只能用 https 开头的链接 —— http 会被浏览器整页拦掉',
      '这些音乐我拥有使用权，或它们允许商用/公开分享，由此产生的版权责任由我承担。',
      '没有勾选声明，发布时不会带上配乐。',
      '本地文件会随游记一起上传，删掉这篇游记时一并删除；外部链接的文件不在我们这儿，对方一旦失效就没声音了。',
      '只在全屏播放时出声，默认静音，读者点一下才播。',
      '配乐的版权由你负责',
      '我确认，加进去',
      '这段音频会跟着游记一起传到网上，任何人都能听到、也能下载。请确认你拥有它的使用权，或者它允许商用/公开分享 —— 由此产生的版权责任由你承担。',
      '这个链接会直接放给读者听，我们不为它的内容和存活兜底。请确认你拥有它的使用权，或者它允许商用/公开分享 —— 由此产生的版权责任由你承担。',
      '音乐存在对方服务器上，我们不复制也不保存。好处是版权关系清楚；代价是对方一旦防盗链、改地址或删文件，这篇游记就永久没有声音了，而且你不会收到任何通知。',
      '这个文件 {0}MB，超过了服务器 10MB 的单文件上限。配乐几 MB 就够 —— 读者要下完才有声音。',
      '这个文件读不到了，换一个试试',
      '只收 {0} 这几种格式，换个文件试试',
      '这首已经在里面了',
    ];

    for (final k in keys) {
      test(k, () => expect(tr(k), isNot(k), reason: 'l10n_en.dart 里没有这一条'));
    }
  });
}
