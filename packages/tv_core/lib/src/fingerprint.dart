import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// 内容寻址。照片的身份 = 它的字节，与文件名、路径、设备无关。
///
/// 全量哈希大文件慢，所以分两步:
///   1. quickFingerprint —— 文件大小 + 头尾各 64KB，筛掉绝大多数非重复
///   2. contentId        —— 快速指纹命中后才做全量哈希
class Fingerprint {
  static const int probeBytes = 64 * 1024;

  /// 内容 id: 全文件 SHA-256 的前 32 个 hex 字符（128 bit，碰撞概率可忽略）。
  static Future<String> contentId(File file) async {
    final sink = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    final digest = sink.events.single;
    sink.close();
    return digest.toString().substring(0, 32);
  }

  static String contentIdOfBytes(List<int> bytes) =>
      sha256.convert(bytes).toString().substring(0, 32);

  /// 快速指纹: 只读头尾各 64KB。同一个值不代表内容相同，
  /// 但不同的值一定内容不同 —— 用于在全量哈希前快速排除。
  static Future<String> quickFingerprint(File file) async {
    final len = await file.length();
    final raf = await file.open();
    try {
      final head = await _readAt(raf, 0, probeBytes, len);
      final tailStart = len > probeBytes ? len - probeBytes : 0;
      final tail = await _readAt(raf, tailStart, probeBytes, len);
      final digest = sha256.convert(<int>[...head, ...tail]);
      return '$len-${digest.toString().substring(0, 16)}';
    } finally {
      await raf.close();
    }
  }

  static Future<Uint8List> _readAt(
      RandomAccessFile raf, int offset, int count, int fileLength) async {
    if (fileLength == 0) return Uint8List(0);
    await raf.setPosition(offset);
    final n = count < fileLength - offset ? count : fileLength - offset;
    return raf.read(n);
  }
}
