import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'layout.dart';
import 'route.dart';

/// 一站的文字。
///
/// `source` 记录它是谁写的: `user` / `ai` / `aiEdited`。
/// 这不是洁癖 —— 用户需要知道哪些是自己写的、哪些是 AI 起草后改过的，
/// 将来重新生成时也不能覆盖掉手写的内容。
class StopNote {
  final String title;
  final String note;
  final String source;
  final DateTime updatedAt;

  /// 英文版的标题和正文。
  ///
  /// **发布出去的网页是中英双语的**，读者按 /zh /en 看到不同的版本；
  /// 文字只有一种语言，等于英文读者看到的是中文正文。
  /// 事实型文案（FactCaption）两种语言都能直接生成，所以默认两份都存。
  /// 用户手写/AI 写的内容没有对应译文时，英文页回落到原文。
  final String titleEn;
  final String noteEn;

  const StopNote({
    this.title = '',
    this.note = '',
    this.source = 'user',
    this.titleEn = '',
    this.noteEn = '',
    required this.updatedAt,
  });

  bool get isEmpty => title.trim().isEmpty && note.trim().isEmpty;

  StopNote copyWith({
    String? title,
    String? note,
    String? source,
    String? titleEn,
    String? noteEn,
  }) =>
      StopNote(
        title: title ?? this.title,
        note: note ?? this.note,
        source: source ?? this.source,
        titleEn: titleEn ?? this.titleEn,
        noteEn: noteEn ?? this.noteEn,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'note': note,
        'source': source,
        if (titleEn.isNotEmpty) 'titleEn': titleEn,
        if (noteEn.isNotEmpty) 'noteEn': noteEn,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StopNote.fromJson(Map<String, dynamic> j) => StopNote(
        title: j['title'] as String? ?? '',
        note: j['note'] as String? ?? '',
        source: j['source'] as String? ?? 'user',
        titleEn: j['titleEn'] as String? ?? '',
        noteEn: j['noteEn'] as String? ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 站点文字的存储。
///
/// **按"这一站最早那张照片的 id"作为键。**
/// 站是聚类算出来的，换个半径就会重新分 —— seq 不稳定，坐标也会漂。
/// 而"最早那张照片"是一个具体存在的东西，重新聚类后依然指向同一个时刻和地点，
/// 所以写好的文字不会因为调了一下聚类参数就全部对不上。
///
/// 存在照片库里（`catalog/notes.json`），跟着库走。
class NoteStore {
  final Directory libraryRoot;
  final Map<String, StopNote> _notes = {};

  NoteStore(this.libraryRoot);

  File get file => File(
      p.join(libraryRoot.path, LibraryLayout.catalogDir, 'notes.json'));

  static String keyFor(Stop stop) =>
      stop.photoIds.isEmpty ? 'stop-${stop.seq}' : stop.photoIds.first;

  Future<void> load() async {
    _notes.clear();
    if (!await file.exists()) return;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      j.forEach((k, v) {
        _notes[k] = StopNote.fromJson(Map<String, dynamic>.from(v as Map));
      });
    } catch (_) {
      // 坏了就当空的，不该因为一个附属文件让整个库打不开
    }
  }

  StopNote? get(Stop stop) => _notes[keyFor(stop)];

  Future<void> put(Stop stop, StopNote note) async {
    _notes[keyFor(stop)] = note;
    await save();
  }

  Future<void> remove(Stop stop) async {
    _notes.remove(keyFor(stop));
    await save();
  }

  int get length => _notes.length;

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ')
        .convert(_notes.map((k, v) => MapEntry(k, v.toJson()))));
    await tmp.rename(file.path);
  }
}
