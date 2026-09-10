import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../state/photo_source.dart';

/// 相册缩略图。
///
/// **不落盘缓存。** 系统相册自己就有缩略图缓存，App 再存一份只是在
/// 用户的手机上浪费空间。内存里的 [_memo] 只是为了滚动时不反复解码。
class AssetThumb extends StatefulWidget {
  final String assetId;
  final int size;
  final BoxFit fit;

  const AssetThumb(this.assetId,
      {super.key, this.size = 256, this.fit = BoxFit.cover});

  @override
  State<AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<AssetThumb> {
  static final _memo = <String, Uint8List>{};
  Uint8List? _data;

  String get _key => '${widget.assetId}@${widget.size}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AssetThumb old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId || old.size != widget.size) _load();
  }

  Future<void> _load() async {
    final hit = _memo[_key];
    if (hit != null) {
      setState(() => _data = hit);
      return;
    }
    final a = PhotoSource.instance.asset(widget.assetId);
    if (a == null) return;
    final bytes =
        await a.thumbnailDataWithSize(ThumbnailSize.square(widget.size));
    if (bytes == null || !mounted) return;
    // 缓存不设上限，滚过几千张之后会吃掉几百 MB。超了整个清掉 ——
    // 比实现一套 LRU 简单得多，用户感觉不到差别。
    if (_memo.length > 400) _memo.clear();
    _memo[_key] = bytes;
    setState(() => _data = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest);
    }
    return Image.memory(d, fit: widget.fit, gaplessPlayback: true);
  }
}
