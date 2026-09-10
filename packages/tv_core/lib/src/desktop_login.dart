import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 桌面端登录：邮箱 + 密码，换一个长期发布令牌。
///
/// **密码不落盘。** 它只在这一次请求里出现，App 保存的是换回来的令牌，
/// 令牌可以在网站账户页随时吊销。
class LoginException implements Exception {
  final String message;
  const LoginException(this.message);
  @override
  String toString() => message;
}

class DesktopLogin {
  final String siteUrl;
  final Duration timeout;

  const DesktopLogin(this.siteUrl,
      {this.timeout = const Duration(seconds: 30)});

  String get _base => siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Future<String> signIn(String email, String password,
      {String label = 'Desktop'}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .postUrl(Uri.parse('$_base/api/desktop/login'))
          .timeout(timeout);
      req.headers.set('User-Agent', 'TravelView/0.1');
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.write(jsonEncode({
        'email': email.trim(),
        'password': password,
        'label': label,
      }));
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join();

      if (res.statusCode == 200) {
        final token =
            (jsonDecode(body) as Map<String, dynamic>)['token'] as String?;
        if (token == null || token.isEmpty) {
          throw const LoginException('服务器没有返回令牌');
        }
        return token;
      }
      throw LoginException(_errorOf(body, res.statusCode));
    } on SocketException catch (e) {
      throw LoginException('连不上服务器: ${e.message}');
    } on TimeoutException {
      throw const LoginException('服务器没有响应（超时）');
    } finally {
      client.close(force: true);
    }
  }

  /// 注册一个新账号，**并直接换回令牌**。
  ///
  /// 注册完不让用户再把邮箱密码填一遍去登录 —— 他刚打完那两个框，
  /// 再来一遍纯粹是折磨。所以这里注册成功后立刻调 [signIn]。
  ///
  /// 密码规则跟着服务器走（目前至少 8 位），错误信息也直接用服务器返回的那句，
  /// 客户端不复制一份校验逻辑 —— 两边规则迟早会不一致。
  Future<String> signUp(String email, String password,
      {String? name, String label = 'Desktop'}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req =
          await client.postUrl(Uri.parse('$_base/api/signup')).timeout(timeout);
      req.headers.set('User-Agent', 'TravelView/0.1');
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.write(jsonEncode({
        'email': email.trim(),
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }));
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) {
        throw LoginException(_errorOf(body, res.statusCode));
      }
    } on SocketException catch (e) {
      throw LoginException('连不上服务器: ${e.message}');
    } on TimeoutException {
      throw const LoginException('服务器没有响应（超时）');
    } finally {
      client.close(force: true);
    }

    return signIn(email, password, label: label);
  }

  static String _errorOf(String body, int code) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final m = j['error'] ?? j['message'];
        if (m is String && m.isNotEmpty) return m;
      }
    } catch (_) {}
    final t = body.trim();
    // 服务器出错时返回的常常是一整页 HTML，原样显示没法看
    if (t.isEmpty || t.startsWith('<')) return '请求失败（HTTP $code）';
    return t.length > 200 ? '${t.substring(0, 200)}...' : t;
  }
}
