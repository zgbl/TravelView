import 'dart:convert';
import 'dart:io';

/// 接用户自己的 AI。
///
/// **用户自己付费，所以不能把他绑死在某一家。**
/// 用 OpenAI 兼容的 chat/completions 协议 —— 这一套接口
/// OpenAI、DeepSeek、Kimi、通义、以及本地跑的 Ollama / LM Studio 都支持，
/// 换供应商只要改 baseUrl 和模型名。
///
/// **只发送文字**: 地名、时间、坐标、地标名。**照片一张都不发。**
class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;
}

class AiException implements Exception {
  final String message;
  final int? statusCode;
  const AiException(this.message, {this.statusCode});
  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

class AiClient {
  final AiConfig config;
  final Duration timeout;

  const AiClient(this.config, {this.timeout = const Duration(seconds: 60)});

  Future<String> complete(String prompt) async {
    if (!config.isConfigured) {
      throw const AiException('还没有配置 AI 服务');
    }
    final url = Uri.parse(
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions');

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.postUrl(url).timeout(timeout);
      req.headers.set('User-Agent', 'TravelView/0.1');
      req.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      if (config.apiKey.trim().isNotEmpty) {
        req.headers.set('Authorization', 'Bearer ${config.apiKey.trim()}');
      }
      req.write(jsonEncode({
        'model': config.model,
        'messages': [
          {
            'role': 'system',
            'content': '你在帮用户写旅行笔记。只使用用户给出的事实，'
                '绝不编造未提供的细节。'
          },
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.7,
      }));

      final resp = await req.close().timeout(timeout);
      final text = await resp.transform(utf8.decoder).join().timeout(timeout);
      if (resp.statusCode != 200) {
        throw AiException(_brief(text), statusCode: resp.statusCode);
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      final content = ((j['choices'] as List?)?.firstOrNull
          as Map?)?['message']?['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const AiException('返回内容为空');
      }
      return content.trim();
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException(_reason(e));
    } finally {
      client.close(force: true);
    }
  }

  static String _reason(Object e) {
    final s = e.toString();
    if (e is SocketException) return '连不上服务: $s';
    if (s.contains('TimeoutException')) return '请求超时';
    return s;
  }

  static String _brief(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 200 ? '${t.substring(0, 200)}...' : t;
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
