import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tv_shared/tv_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/profile.dart';
import '../state/session.dart';
import '../state/workspace.dart';
import '../ui/theme.dart';

/// 个人中心。
///
/// 只放**用户真的需要做决定**的东西。手机 App 的设置页越长，
/// 用户越觉得这东西复杂 —— 该由 App 自己管好的事就别拿出来问。
class MePage extends StatefulWidget {
  final Session session;
  const MePage(this.session, {super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late final ProfileStore _profile =
      ProfileStore(widget.session.account.config);
  _Usage? _usage;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _profile.addListener(_onProfile);
    _profile.load();
    _measure();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = '${i.version} (${i.buildNumber})');
    });
  }

  @override
  void dispose() {
    _profile.removeListener(_onProfile);
    super.dispose();
  }

  void _onProfile() => setState(() {});

  Future<void> _measure() async {
    final w = Workspace.instance;
    final u = _Usage(
      exportBytes: await w.bytesOf('export'),
      bundleBytes: await w.bytesOf('bundle'),
      analysisBytes: await w.bytesOf('analysis'),
    );
    if (mounted) setState(() => _usage = u);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.session.settings;
    final u = _usage;

    return Scaffold(
      appBar: AppBar(title: Text(tr('个人中心'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(TV.pad, TV.gap, TV.pad, 30),
        children: [
          _IdentityCard(
            profile: _profile.profile,
            loading: _profile.loading,
            error: _profile.error,
            onEditName: _editName,
            onEditHandle: _editHandle,
            onSetProfilePublic: _setProfilePublic,
            onRetry: _profile.load,
            onOpenHome: (url) =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: TV.gap),

          _SectionTitle(tr('本机占用')),
          _Card(
            child: Column(
              children: [
                _StorageRow(
                  label: tr('待上传的缩小图'),
                  bytes: u?.exportBytes,
                  color: scheme.primary,
                ),
                const Divider(height: 18),
                _StorageRow(
                  label: tr('打包产物'),
                  bytes: u?.bundleBytes,
                  color: scheme.tertiary,
                ),
                const Divider(height: 18),
                _StorageRow(
                  label: tr('精选用的分析图'),
                  bytes: u?.analysisBytes,
                  color: scheme.secondary,
                ),
                const SizedBox(height: 14),
                Text(
                  tr('这些都是可以随时重新生成的临时文件，'
                      '删掉不会丢任何东西。照片原件一直在你的系统相册里。'),
                  style: TextStyle(
                      fontSize: 11.5, color: scheme.outline, height: 1.5),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Workspace.instance.clear();
                      await _measure();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(tr('清理完了'))));
                      }
                    },
                    icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                    label: Text(tr('全部清理')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TV.gap),

          _SectionTitle(tr('偏好')),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(tr('界面语言')),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'zh', label: Text('中文')),
                      ButtonSegment(value: 'en', label: Text('EN')),
                    ],
                    selected: {L10n.lang.value},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) async {
                      L10n.set(v.first);
                      s.uiLang = v.first;
                      await s.save();
                      if (mounted) setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: TV.gap),

          _SectionTitle(tr('关于')),
          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(tr('版本')),
                  trailing: Text(_version,
                      style: TextStyle(fontSize: 13, color: scheme.outline)),
                ),
                const Divider(height: 1),
                // 改密码留在网页：那边已经有完整的一套（当前密码校验、
                // 两次输入比对），手机上再做一份就是两处维护、两处会不一致
                _LinkTile(
                  icon: Icons.lock_outline,
                  label: tr('修改密码'),
                  url: '${s.siteUrl}/zh/account',
                ),
                const Divider(height: 1),
                _LinkTile(
                  icon: Icons.feedback_outlined,
                  label: tr('意见反馈'),
                  url: '${s.siteUrl}/zh/download',
                ),
                const Divider(height: 1),
                // **必须指向隐私政策本身，不能指向首页。**
                // 审核员会点进来，点开不是隐私政策就是一条拒审；
                // App Store Connect / Play Console 的元数据里也要填同一个地址。
                _LinkTile(
                  icon: Icons.privacy_tip_outlined,
                  label: tr('隐私政策'),
                  url: '${s.siteUrl}/zh/privacy',
                ),
                const Divider(height: 1),
                _LinkTile(
                  icon: Icons.description_outlined,
                  label: tr('服务条款'),
                  url: '${s.siteUrl}/zh/terms',
                ),
              ],
            ),
          ),
          const SizedBox(height: TV.gap),

          _Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.logout, color: scheme.error),
                  title: Text(tr('退出登录'),
                      style: TextStyle(color: scheme.error)),
                  onTap: _signOut,
                ),
                const Divider(height: 1),
                // **上架硬性要求。** Apple 审核指南 5.1.1(v) 和 Google Play
                // 都规定：能在 app 里注册账号，就必须能在 app 里发起删除账号。
                // 这是最常见的拒审理由之一，而且是"传上去等三天、被拒、
                // 再等三天"的那种。
                ListTile(
                  leading: Icon(Icons.person_remove_outlined,
                      color: scheme.error),
                  title: Text(tr('删除账号'),
                      style: TextStyle(color: scheme.error)),
                  subtitle: Text(tr('永久删除账号和所有已发布的回顾'),
                      style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                  onTap: _deleteAccount,
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            tr('照片原件一直在你手机里，只有你选中的那些会被缩小后上传。'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.outline, height: 1.6),
          ),
        ],
      ),
    );
  }

  /// 删除账号。
  ///
  /// 实际操作在网页上完成（那边已经有完整的一套：二次确认、连带清理
  /// 已发布的故事），**但入口必须在 app 里** —— 商店查的是"能不能在
  /// app 里发起"，不是"在哪儿执行"。
  ///
  /// 先弹一次说明再跳出去：一个直接把人踢到浏览器的菜单项，
  /// 用户不知道自己刚才点了什么。
  Future<void> _deleteAccount() async {
    final s = widget.session.settings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('删除账号')),
        content: Text(
          tr('账号、已发布的回顾、以及上传过的图片都会被永久删除，撤不回来。'
              '手机相册里的原件不受影响。\n\n'
              '接下来会打开网页完成这一步。'),
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('取消'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('继续')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await launchUrl(Uri.parse('${s.siteUrl}/zh/account'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _setProfilePublic(bool v) async {
    final err = await _profile.setProfilePublic(v);
    _toast(err ?? (v ? tr('主页已公开') : tr('主页已隐身')));
  }

  Future<void> _editName() async {
    final p = _profile.profile;
    final ctrl = TextEditingController(text: p?.name ?? '');
    final v = await _ask(
      title: tr('显示名'),
      hint: tr('别人在你的公开主页上看到的名字'),
      controller: ctrl,
    );
    if (v == null) return;
    final err = await _profile.setName(v);
    _toast(err ?? tr('改好了'));
  }

  /// 设公开主页地址。
  ///
  /// **不让用户从一个空框开始想。** 原来这里是一个空输入框加一句
  /// "小写字母、数字、下划线，3 到 20 位" —— 那是把数据库约束摊给用户看。
  /// 他要现想一个名字、猜哪些字符能用、还可能撞名被打回来，
  /// 而这一切发生在他只想赶紧把游记发出去的时候。
  ///
  /// 现在是：**我们按他的显示名先生成一个，他点「就用这个」就完了。**
  /// 想改的人永远能改，不想改的人一次点击走完。
  ///
  /// **地址和显示名是两件事，不能绑死。** 显示名随时可以改（改了页面上
  /// 就换个名字），地址一旦定下来就尽量别动 —— 那是别人转发到
  /// Facebook 上的链接，改一次，所有转发过的链接全死。
  /// 所以地址只在第一次由显示名推导，之后各走各的。
  Future<void> _editHandle() async {
    final p = _profile.profile;
    final site =
        widget.session.settings.siteUrl.replaceAll(RegExp(r'^https?://'), '');
    final current = p?.handle ?? '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _HandleSheet(
        site: site,
        current: current,
        suggestion: current.isNotEmpty
            ? current
            : HandleRules.suggest(
                name: p?.name, email: p?.email),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    final err = await _profile.setHandle(picked);
    _toast(err ?? tr('设好了'));
  }

  Future<String?> _ask({
    required String title,
    required String hint,
    required TextEditingController controller,
    String? helper,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              decoration: InputDecoration(hintText: hint),
            ),
            if (helper != null) ...[
              const SizedBox(height: 10),
              Text(helper,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: Theme.of(ctx).colorScheme.outline)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(tr('保存'))),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('退出登录？')),
        content: Text(tr('已经发布的回顾不受影响，链接照常能打开。')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('取消'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('退出'))),
        ],
      ),
    );
    if (ok == true) await widget.session.signOut();
  }
}

class _Usage {
  final int exportBytes, bundleBytes, analysisBytes;
  const _Usage({
    required this.exportBytes,
    required this.bundleBytes,
    required this.analysisBytes,
  });
}

class _StorageRow extends StatelessWidget {
  final String label;
  final int? bytes;
  final Color color;
  const _StorageRow(
      {required this.label, required this.bytes, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text(
          bytes == null ? '…' : fmtBytes(bytes!),
          style: TextStyle(fontSize: 13, color: scheme.outline),
        ),
      ],
    );
  }
}

String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;
  const _LinkTile(
      {required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.open_in_new, size: 16),
        onTap: () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      );
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(TV.rCard),
          boxShadow: TV.shadow(context),
        ),
        child: Padding(padding: padding, child: child),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.outline)),
      );
}

/// 「我是谁」那张卡。
///
/// 头像圈里是名字首字母 —— 不做真头像上传：服务器没有存头像的地方，
/// 做一个只能存在本机的头像，换台手机就没了，比没有更让人困惑。
/// 首字母 + 主色底在所有正经产品里都是合格的兜底。
class _IdentityCard extends StatelessWidget {
  final Profile? profile;
  final bool loading;
  final String? error;
  final VoidCallback onEditName;
  final VoidCallback onEditHandle;
  final void Function(bool) onSetProfilePublic;
  final VoidCallback onRetry;
  final void Function(String url) onOpenHome;

  const _IdentityCard({
    required this.profile,
    required this.loading,
    required this.error,
    required this.onEditName,
    required this.onEditHandle,
    required this.onSetProfilePublic,
    required this.onRetry,
    required this.onOpenHome,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = profile;

    if (p == null) {
      return _Card(
        child: Row(
          children: [
            if (loading)
              const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.person_off_outlined, color: scheme.outline),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                loading ? tr('正在读取账号…') : (error ?? tr('读不到账号信息')),
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ),
            if (!loading)
              TextButton(onPressed: onRetry, child: Text(tr('重试'))),
          ],
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary,
                      scheme.primary.withValues(alpha: 0.62),
                    ],
                  ),
                ),
                child: Text(
                  p.initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: onEditName,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.edit_outlined,
                                size: 15, color: scheme.outline),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(p.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12.5, color: scheme.outline)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // 公开主页。没设过就是一句引导，而不是一个点开 404 的链接
          InkWell(
            onTap: onEditHandle,
            borderRadius: BorderRadius.circular(TV.rControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.public, size: 18, color: scheme.outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: p.handle == null
                        ? Text(tr('还没设置公开主页地址'),
                            style: TextStyle(
                                fontSize: 13.5, color: scheme.outline))
                        : Text('@${p.handle}',
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ),
                  Text(p.handle == null ? tr('去设置') : tr('修改'),
                      style: TextStyle(fontSize: 12.5, color: scheme.primary)),
                ],
              ),
            ),
          ),

          if (p.homeUrl != null) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => onOpenHome(p.homeUrl!),
              borderRadius: BorderRadius.circular(TV.rControl),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18, color: scheme.outline),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.homeUrl!.replaceAll(RegExp(r'^https?://'), ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // **可见性紧贴着主页地址放。** 它说的就是"这个地址别人能不能
          // 随便逛"这一件事，放到下面的"偏好"里，用户不会把两者联系起来。
          if (p.handle != null) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              value: p.profilePublic,
              onChanged: onSetProfilePublic,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                p.profilePublic ? tr('主页可以被公开浏览') : tr('主页隐身'),
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                // **关掉之后到底还能不能分享，必须说清楚。**
                // 用户最怕的是"我一关，之前发出去的链接是不是全废了"——
                // 没有这句话，想保护隐私的人反而不敢关。
                p.profilePublic
                    ? tr('别人打开你的主页能看到你全部公开的回顾。')
                    : tr('别人打不开你的主页。已经分享出去的每一篇回顾，'
                        '拿到链接的人照样能看。'),
                style: TextStyle(
                    fontSize: 11.5, height: 1.45, color: scheme.outline),
              ),
            ),
          ],

          const SizedBox(height: 12),
          // 额度：发布前才发现不够是最糟的时机，摆在这儿让人心里有数
          Row(
            children: [
              _Stat(
                label: tr('可发布额度'),
                value: p.subscribed ? tr('订阅中 · 不限') : '${p.credits}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TV.rControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: scheme.outline)),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary)),
        ],
      ),
    );
  }
}

/// 选公开主页地址。
///
/// **主角是那一行完整的地址，不是输入框。** 用户要判断的是
/// "yourtravelview.com/u/lixiaoming 这个地址我满不满意"，
/// 不是"我该在这个框里填什么"。所以地址整行大字摆在最上面，
/// 输入框默认根本不出现 —— 想自己改的人点一下才展开。
class _HandleSheet extends StatefulWidget {
  final String site;
  final String current;
  final String suggestion;
  const _HandleSheet({
    required this.site,
    required this.current,
    required this.suggestion,
  });

  @override
  State<_HandleSheet> createState() => _HandleSheetState();
}

class _HandleSheetState extends State<_HandleSheet> {
  late String _handle = widget.suggestion;
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.suggestion);
  bool _editing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => HandleRules.isValid(_handle);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 已经有地址的人进来是"改"，措辞和风险提示都不一样
    final changing = widget.current.isNotEmpty;

    return Padding(
      // 输入法弹出来时把内容顶上去，别盖住按钮
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('你的公开主页'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                tr('别人从这个地址能看到你公开的全部回顾。'),
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: scheme.outline),
              ),
              const SizedBox(height: 16),

              // 地址整行大字 —— 这是用户真正要判断的东西
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(TV.rControl),
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 15, color: scheme.outline),
                    children: [
                      TextSpan(text: '${widget.site}/u/'),
                      TextSpan(
                        text: _handle.isEmpty ? '…' : _handle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _valid ? scheme.onSurface : scheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_editing) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  onChanged: (v) =>
                      setState(() => _handle = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '${widget.site}/u/',
                    prefixStyle:
                        TextStyle(fontSize: 13, color: scheme.outline),
                    errorText: _handle.isEmpty || _valid
                        ? null
                        : tr('只能用小写字母、数字、下划线，3 到 20 位'),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (!_editing)
                    TextButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(tr('自己改一个')),
                    ),
                  TextButton.icon(
                    onPressed: () {
                      final next = HandleRules.vary(widget.suggestion);
                      setState(() {
                        _handle = next;
                        _ctrl.text = next;
                      });
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(tr('换一个')),
                  ),
                ],
              ),

              if (changing) ...[
                const SizedBox(height: 6),
                // **改地址是有代价的，必须说。** 这个产品的产出就是一条
                // 转发出去的链接；改了地址，之前分享到 Facebook、微信上的
                // 那些链接会全部失效，而且没有任何人会来通知他。
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 15, color: scheme.error),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      tr('改了之后，之前分享出去的主页链接就打不开了。'
                          '已经发布的每一篇回顾自己的链接不受影响。'),
                      style: TextStyle(
                          fontSize: 11.5, height: 1.5, color: scheme.error),
                    ),
                  ),
                ]),
              ],

              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _valid
                      ? () => Navigator.of(context).pop(_handle)
                      : null,
                  child: Text(changing ? tr('改成这个') : tr('就用这个')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
