import 'package:flutter_test/flutter_test.dart';
import 'package:tv_desktop/state/library_controller.dart';
import 'package:tv_shared/tv_shared.dart';

/// 配乐的规矩本身住在 tv_shared 的 [MusicRules] 里（手机端用的是同一份），
/// 这个文件守的是**桌面端有没有真的转手过去**，以及那条最容易出错的白名单。
///
/// 为什么值得为几行判断写测试: 收错一种东西不会当场报错 ——
/// 界面上一模一样，直到导出时才被 StoryExporter 静默跳过，
/// 用户拿到的是一篇哑掉的游记，而没有人会告诉他为什么。
void main() {
  group('配乐白名单', () {
    test('收这几种音频后缀', () {
      for (final ext in ['mp3', 'm4a', 'aac', 'ogg', 'wav']) {
        expect(LibraryController.acceptsTrack('/Users/me/Music/track.$ext'),
            isTrue, reason: ext);
      }
      // 大小写不影响
      expect(LibraryController.acceptsTrack('/Users/me/Music/Track.MP3'), isTrue);
    });

    test('别的文件挡在外面', () {
      expect(LibraryController.acceptsTrack('/Users/me/movie.mp4'), isFalse);
      expect(LibraryController.acceptsTrack('/Users/me/photo.jpg'), isFalse);
      expect(LibraryController.acceptsTrack('   '), isFalse);
    });

    test('https 外链收，http 和别的协议一律不收', () {
      expect(LibraryController.acceptsTrack('https://example.com/a.mp3'), isTrue);
      // http 会被浏览器整页拦掉，而且导出时会被当成一个不存在的本地文件
      // 静默跳过 —— 收进来等于给用户埋一个"发出去是哑的"的坑
      expect(LibraryController.acceptsTrack('http://example.com/a.mp3'), isFalse);
      expect(LibraryController.acceptsTrack('file:///Users/me/a.mp3'), isFalse);
      expect(LibraryController.acceptsTrack('ftp://example.com/a.mp3'), isFalse);
    });

    test('显示名: 本地取文件名，外链取域名', () {
      expect(LibraryController.trackLabel('/Users/me/Music/夜曲.mp3'), '夜曲.mp3');
      expect(LibraryController.trackLabel('https://cdn.example.com/song.mp3'),
          'cdn.example.com');
    });

    test('分得清本地文件和外链', () {
      expect(LibraryController.isLocalTrack('/Users/me/a.mp3'), isTrue);
      expect(LibraryController.isLocalTrack('https://x.com/a.mp3'), isFalse);
    });
  });

  group('和手机端是同一份规矩', () {
    test('上限和格式表不是各写各的', () {
      expect(LibraryController.maxTracks, MusicRules.maxTracks);
      expect(LibraryController.audioExts, MusicRules.audioExts);
    });
  });
}
