import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tv_core/tv_core.dart';

/// 我是谁。
///
/// **App 必须知道这件事。** 之前手机端只揣着一个发布令牌，
/// 从来没问过服务器这个令牌是谁的 —— 用户打开个人中心，看不到自己的
/// 邮箱、昵称、主页地址，连自己登的是哪个账号都不知道。
/// 同一台手机上换过账号的人（自己的、家人的、测试的）根本分不清。
class Profile {
  final String email;
  final String? name;
  final String? handle;
  final String? homeUrl;
  final int credits;
  final bool subscribed;

  /// 公开主页是"谁都能浏览"，还是"只有拿到链接的人才看得到"。
  ///
  /// **默认公开。** 这个产品的意义就是把东西分享出去，
  /// 默认藏起来等于默认关掉了自己的功能。想藏的人自己去关。
  final bool profilePublic;

  const Profile({
    required this.email,
    this.name,
    this.handle,
    this.homeUrl,
    this.credits = 0,
    this.subscribed = false,
    this.profilePublic = true,
  });

  /// 界面上叫他什么。**永远有一个能认出人的名字** ——
  /// 昵称没设就用邮箱的用户名部分，不要显示空白。
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// 头像圈里那个字。
  ///
  /// 用 substring 而不是 characters —— 中文名和 emoji 昵称都是单个码位，
  /// 这里取一个字符就够，不值得为它多引一个包。
  String get initial {
    final n = displayName;
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        email: j['email'] as String? ?? '',
        name: j['name'] as String?,
        handle: j['handle'] as String?,
        homeUrl: j['homeUrl'] as String?,
        credits: (j['credits'] as num?)?.toInt() ?? 0,
        subscribed: j['subscribed'] == true,
        profilePublic: j['profilePublic'] != false,
      );
}

class ProfileStore extends ChangeNotifier {
  ProfileStore(this.config);

  final PublishConfig config;

  Profile? profile;
  String? error;
  bool loading = false;

  String get _base => config.siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final body = await _send('GET', '/api/me', null);
      profile = Profile.fromJson(jsonDecode(body) as Map<String, dynamic>);
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String?> setName(String name) => _patch({'name': name});

  /// 公开主页地址。服务器的规则：小写字母数字下划线、3-20 位、
  /// 撞名或保留字返回 TAKEN。**规则不在客户端复制一份** ——
  /// 两边迟早会不一致，报错直接用服务器那句。
  Future<String?> setHandle(String handle) => _patch({'handle': handle});

  /// 主页要不要被公开浏览。关掉之后 /u/<handle> 对别人是 404，
  /// **但每一篇已发布的回顾自己的链接照样能打开** —— 那是两件事。
  Future<String?> setProfilePublic(bool v) =>
      _patch({'profilePublic': v});

  Future<String?> _patch(Map<String, Object?> body) async {
    try {
      await _send('PATCH', '/api/me', body);
      await load();
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<String> _send(
      String method, String path, Map<String, Object?>? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.openUrl(method, Uri.parse('$_base$path'));
      req.headers.set('Authorization', 'Bearer ${config.token.trim()}');
      if (body != null) {
        req.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) throw _friendly(text, res.statusCode);
      return text;
    } on SocketException catch (e) {
      throw '连不上服务器: ${e.message}';
    } finally {
      client.close(force: true);
    }
  }

  /// 服务器用的是错误码，界面要说人话。
  static String _friendly(String body, int code) {
    String raw = '';
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) raw = j['error'] as String;
    } catch (_) {}
    return switch (raw) {
      'TAKEN' => '这个地址已经被人用了',
      'BAD_HANDLE' => '只能用小写字母、数字和下划线，3 到 20 位',
      '' => '出错了（HTTP $code）',
      _ => raw,
    };
  }
}
