import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 跨启动保存的工作状态。
///
/// 存在系统的应用支持目录里，不依赖任何插件。
/// 只存"上次做到哪里"，不存任何照片数据 ——
/// 照片和标签的真相始终在照片库的 sidecar 里。
/// 官方站点。开发时可以用 --dart-define=TV_SITE=http://localhost:3000 覆盖。
const kDefaultSiteUrl = String.fromEnvironment(
  'TV_SITE',
  defaultValue: 'https://travelview.blackrice.top',
);

/// 早期版本把 travelview.app 写进了配置文件，那个域名根本不存在，
/// 用户升级后会看到"Failed host lookup"。这里悄悄迁移掉。
const _deadSiteUrls = {
  'https://travelview.app',
  'http://travelview.app',
  '',
};

class AppSettings {
  String? lastLibraryPath;
  DateTime? rangeStart;
  DateTime? rangeEnd;
  int view;
  String pickAlbum;
  String clusterPreset;
  String? currentProject;

  /// 路径规划设置。默认用 openrouteservice（注册即有免费额度）；
  /// 自托管 OSRM 的填 osrmBaseUrl。两者都基于 OpenStreetMap，
  /// 结果允许永久保存 —— 这是能把路线写进分享页的前提。
  String routeProvider; // 'ors' | 'osrm' | 'direct'
  String orsApiKey;
  String osrmBaseUrl;
  String routeMode; // 'driving' | 'walking' | 'direct'

  /// 用户自己的 AI 服务。**费用由用户自己承担**，所以不绑定任何一家:
  /// 用 OpenAI 兼容协议，OpenAI / DeepSeek / Kimi / 本地 Ollama 都能接。
  /// key 只存在这台机器上，不会上传到任何地方。
  String aiBaseUrl;
  String aiApiKey;
  String aiModel;
  String aiLanguage;
  String aiTone;

  /// 发布到网站。
  ///
  /// **这不该是一个让用户填的字段。** 用户当然是发布到我们的网站上，
  /// 问他"你要发到哪个网站"只会让人困惑。保留这个字段只是为了
  /// 自建服务器和本地开发（改配置文件即可），界面上不再出现。
  String siteUrl;
  String publishToken;

  /// 界面语言: 'zh' 中文 / 'en' English。
  /// **不跟随系统**: 很多人系统是英文但更愿意用中文界面，反过来也一样。
  /// 第一次启动按系统语言猜一个，之后完全由用户说了算。
  String uiLang;

  AppSettings({
    this.lastLibraryPath,
    this.rangeStart,
    this.rangeEnd,
    this.view = 0,
    this.pickAlbum = '精选',
    this.clusterPreset = 'road',
    this.currentProject,
    this.routeProvider = 'ors',
    this.orsApiKey = '',
    this.osrmBaseUrl = 'http://localhost:5000',
    this.routeMode = 'driving',
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiApiKey = '',
    this.aiModel = 'gpt-4o-mini',
    this.aiLanguage = '中文',
    this.aiTone = '简洁克制',
    this.siteUrl = kDefaultSiteUrl,
    this.publishToken = '',
    this.uiLang = '',
  });

  /// 配置目录。手机上没有"应用支持目录"这个概念可以靠环境变量猜 ——
  /// iOS / Android 的沙盒路径要问系统要（path_provider），所以留一个注入点：
  /// 手机端在 `main()` 里 `AppSettings.configDir = await getApplicationSupportDirectory()`
  /// 就够了，共享代码一行都不用改。桌面端不设，走下面按平台拼的默认值。
  static Directory? configDir;

  static Directory get _dir {
    final injected = configDir;
    if (injected != null) return injected;
    final env = Platform.environment;
    if (Platform.isMacOS) {
      final home = env['HOME'] ?? '.';
      return Directory(p.join(home, 'Library', 'Application Support', 'TravelView'));
    }
    if (Platform.isWindows) {
      final appData = env['APPDATA'] ?? env['USERPROFILE'] ?? '.';
      return Directory(p.join(appData, 'TravelView'));
    }
    return Directory(p.join(env['HOME'] ?? '.', '.travelview'));
  }

  static File get _file => File(p.join(_dir.path, 'settings.json'));

  /// 配置文件里存的站点。历史遗留的死域名一律换成当前默认值。
  static String _siteOf(String? stored) {
    final v = (stored ?? '').trim();
    return _deadSiteUrls.contains(v) ? kDefaultSiteUrl : v;
  }

  static Future<AppSettings> load() async {
    try {
      final f = _file;
      if (!await f.exists()) return AppSettings();
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return AppSettings(
        lastLibraryPath: j['lastLibraryPath'] as String?,
        rangeStart: _parse(j['rangeStart']),
        rangeEnd: _parse(j['rangeEnd']),
        view: (j['view'] as num?)?.toInt() ?? 0,
        pickAlbum: j['pickAlbum'] as String? ?? '精选',
        clusterPreset: j['clusterPreset'] as String? ?? 'road',
        currentProject: j['currentProject'] as String?,
        routeProvider: j['routeProvider'] as String? ?? 'ors',
        orsApiKey: j['orsApiKey'] as String? ?? '',
        osrmBaseUrl: j['osrmBaseUrl'] as String? ?? 'http://localhost:5000',
        routeMode: j['routeMode'] as String? ?? 'driving',
        aiBaseUrl: j['aiBaseUrl'] as String? ?? 'https://api.openai.com/v1',
        aiApiKey: j['aiApiKey'] as String? ?? '',
        aiModel: j['aiModel'] as String? ?? 'gpt-4o-mini',
        aiLanguage: j['aiLanguage'] as String? ?? '中文',
        aiTone: j['aiTone'] as String? ?? '简洁克制',
        siteUrl: _siteOf(j['siteUrl'] as String?),
        publishToken: j['publishToken'] as String? ?? '',
        uiLang: j['uiLang'] as String? ?? '',
      );
    } catch (_) {
      // 配置坏了不该让 App 打不开
      return AppSettings();
    }
  }

  Future<void> save() async {
    try {
      await _dir.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'lastLibraryPath': lastLibraryPath,
        'rangeStart': rangeStart?.toIso8601String(),
        'rangeEnd': rangeEnd?.toIso8601String(),
        'view': view,
        'pickAlbum': pickAlbum,
        'clusterPreset': clusterPreset,
        'currentProject': currentProject,
        'routeProvider': routeProvider,
        'orsApiKey': orsApiKey,
        'osrmBaseUrl': osrmBaseUrl,
        'routeMode': routeMode,
        'aiBaseUrl': aiBaseUrl,
        'aiApiKey': aiApiKey,
        'aiModel': aiModel,
        'aiLanguage': aiLanguage,
        'aiTone': aiTone,
        'siteUrl': siteUrl,
        'publishToken': publishToken,
        'uiLang': uiLang,
      }));
      await tmp.rename(_file.path);
    } catch (_) {
      // 存不下就算了，不影响使用
    }
  }

  static DateTime? _parse(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;
}
