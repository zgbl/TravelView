import 'package:flutter/material.dart';
import 'package:tv_shared/tv_shared.dart';

import '../state/session.dart';
import 'login_page.dart';
import 'me_page.dart';
import 'my_stories_page.dart';
import 'new_trip_page.dart';

/// App 的骨架：**没登录只有登录页，登录了是三栏。**
///
/// 三栏对应三件事，多一栏都是负担：
///   我的回顾 —— 回来最常做的事：再看一眼、把链接再发给谁
///   新建     —— 从相册里认出旅行，做新的一篇
///   个人中心 —— 账号、语言、本机占用
///
/// 相册扫描只在「新建」里发生。打开 App 只想看看自己发过什么的人
/// （多数时候都是），不该为此等一遍几千张照片。
class AppShell extends StatefulWidget {
  final Session session;
  const AppShell(this.session, {super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    // 退出登录时把 tab 复位，否则下次登录进来停在"我的"上，很怪
    if (!widget.session.signedIn) _tab = 0;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.signedIn) {
      return LoginPage(widget.session);
    }

    return Scaffold(
      // IndexedStack：切走再切回来不要重扫相册、不要丢挑到一半的选择
      body: IndexedStack(
        index: _tab,
        children: [
          MyStoriesPage(widget.session),
          const NewTripPage(),
          MePage(widget.session),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.auto_stories_outlined),
              selectedIcon: const Icon(Icons.auto_stories),
              label: tr('我的回顾')),
          NavigationDestination(
              icon: const Icon(Icons.add_circle_outline),
              selectedIcon: const Icon(Icons.add_circle),
              label: tr('新建')),
          NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: tr('个人中心')),
        ],
      ),
    );
  }
}
