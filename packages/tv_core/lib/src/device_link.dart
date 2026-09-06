import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 设备码登录。桌面端**永远不接触用户密码**。
///
/// 流程（和 OAuth 设备流一致，见 Design/accounts-and-publishing.md）:
///   1. POST /api/device/code   拿到给人看的短码 + 给机器用的 deviceCode
///   2. 用户在网页 /link 上敲入短码确认
///   3. 轮询 POST /api/device/token，确认后换回长期发布令牌
///
/// 为什么不做成"在 App 里填邮箱密码": 那样 App 就成了一个存密码的地方，
/// 而且以后接 Google / Apple 登录时整条路要推倒重来。
/// 设备码这条路，App 那侧认的只是"网页上有人确认了这台机器"，登录方式怎么变都不用改。
class DeviceLinkStart {
  /// 给用户看和敲的短码，形如 KDR8-Q2M7
  final String userCode;

  /// 给机器轮询用的长串，**不要显示给用户**
  final String deviceCode;

  /// 让用户打开的网址
  final String verifyUrl;

  /// 短码多久过期（秒）
  final int expiresIn;

  /// 建议的轮询间隔（秒）
  final int interval;

  const DeviceLinkStart({
    required this.userCode,
    required this.deviceCode,
    required this.verifyUrl,
    required this.expiresIn,
    required this.interval,
  });
}

class DeviceLinkException implements Exception {
  final String message;
  const DeviceLinkException(this.message);
  @override
  String toString() => message;
}

/// 短码过期了，得回到第一步重新生成一个
class DeviceLinkExpired extends DeviceLinkException {
  const DeviceLinkExpired() : super('这串码已经过期，重新生成一个');
}

class DeviceLinker {
  final String siteUrl;
  final Duration timeout;

  const DeviceLinker(this.siteUrl,
      {this.timeout = const Duration(seconds: 30)});

  String get _base => siteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// 第一步：申请一对码。这一步不需要任何身份。
  Future<DeviceLinkStart> start({String label = 'Desktop'}) async {
    final j = await _post('/api/device/code', {'label': label});
    return DeviceLinkStart(
      userCode: j['userCode'] as String,
      deviceCode: j['deviceCode'] as String,
      verifyUrl: j['verifyUrl'] as String? ?? '$_base/link',
      expiresIn: (j['expiresIn'] as num?)?.toInt() ?? 900,
      interval: (j['interval'] as num?)?.toInt() ?? 3,
    );
  }

  /// 第三步：轮询直到用户在网页上确认，返回长期发布令牌。
  ///
  /// [onTick] 每轮回调一次剩余秒数，UI 可以显示倒计时。
  /// 调用方可以用 [cancelled] 让用户随时中断（比如关掉对话框）。
  Future<String> awaitToken(
    DeviceLinkStart start, {
    void Function(int secondsLeft)? onTick,
    bool Function()? cancelled,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: start.expiresIn));
    final gap = Duration(seconds: start.interval.clamp(2, 10));

    while (DateTime.now().isBefore(deadline)) {
      if (cancelled?.call() ?? false) {
        throw const DeviceLinkException('已取消');
      }
      final token = await _poll(start.deviceCode);
      if (token != null) return token;
      onTick?.call(deadline.difference(DateTime.now()).inSeconds);
      await Future<void>.delayed(gap);
    }
    throw const DeviceLinkExpired();
  }

  /// 返回 null 表示"还没人确认，继续等"
  Future<String?> _poll(String deviceCode) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client
          .postUrl(Uri.parse('$_base/api/device/token'))
          .timeout(timeout);
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.write(jsonEncode({'deviceCode': deviceCode}));
      final res = await req.close().timeout(timeout);
      final body = await utf8.decoder.bind(res).join();

      if (res.statusCode == 200) {
        return (jsonDecode(body) as Map<String, dynamic>)['token'] as String?;
      }
      final err = _errorOf(body);
      if (err == 'authorization_pending') return null;
      if (err == 'expired_token') throw const DeviceLinkExpired();
      throw DeviceLinkException(err);
    } on SocketException catch (e) {
      // 网络抖一下不该让整个连接流程失败 —— 当成"继续等"，下一轮再试
      if (e.osError?.errorCode == 0) rethrow;
      return null;
    } on TimeoutException {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req =
          await client.postUrl(Uri.parse('$_base$path')).timeout(timeout);
      req.headers.set('User-Agent', 'TravelView/0.1');
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.write(jsonEncode(body));
      final res = await req.close().timeout(timeout);
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode >= 400) {
        throw DeviceLinkException(_errorOf(text));
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw DeviceLinkException('连不上服务器: ${e.message}');
    } on TimeoutException {
      throw const DeviceLinkException('服务器没有响应（超时）');
    } finally {
      client.close(force: true);
    }
  }

  static String _errorOf(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final m = j['error'] ?? j['message'];
        if (m is String && m.isNotEmpty) return m;
      }
    } catch (_) {}
    return body.trim().isEmpty ? '未知错误' : body.trim();
  }
}
