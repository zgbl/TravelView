# 桌面端双语 —— 施工说明

框架已经搭好并跑通（`story_page.dart` 是做完的样板）。剩下的是**机械活**：
把还没接入的中文字面量包上 `tr()`，并在 `l10n_en.dart` 里补英文。

## 机制

按**中文原文当 key**，不发明 key 名。

```dart
Text(tr('发布'))                              // 简单文案
Text(trf('已选 {0} / {1} 张', [a, b]))         // 带变量
```

为什么这么设计：

- 四百多条文案不用起名字，也不会出现 `label_23` 这种没人看得懂的 key
- **漏翻自动回落成中文**，不会把 `MISSING_KEY_42` 显示给用户
- 中文那一份永远不用维护

代价：改中文原文会让对应英文失效 —— 用下面的脚本能立刻查出来。

相关文件：

| 文件 | 作用 |
|---|---|
| `lib/state/l10n.dart` | `tr()` / `trf()` / `L10n.lang` |
| `lib/state/l10n_en.dart` | 中文 → English 的表，**要补的就是这里** |
| `lib/widgets/lang_switch.dart` | 顶栏的 中文 / EN 开关 |
| `tool/i18n_scan.dart` | 查还没包 `tr()` 的 |
| `tool/i18n_missing.dart` | 查包了 `tr()` 但没有英文的 |

语言存在 `AppSettings.uiLang`，整棵树挂在 `main.dart` 的
`ValueListenableBuilder` 上 —— 切换语言时**所有** Text 一起重建。

## 怎么做

```bash
cd apps/tv_desktop
dart run tool/i18n_scan.dart            # 看还剩多少、都在哪
dart run tool/i18n_scan.dart --todo     # 直接生成可贴进 l10n_en.dart 的骨架
```

按文件逐个处理，每个文件做完跑一次 `flutter analyze`。

### 三条必须守住的规则

**1. `const` 和 `tr()` 不能共存。**
`tr()` 是运行时函数调用，编译期常量里不能有它。

```dart
const Text('发布')            // 改成 →
Text(tr('发布'))

segments: const [ ... ]       // 里面只要出现 tr()，就把这个 const 去掉
```
这是最容易出的编译错，`story_page.dart` 里就有三处 `const [`。

**2. 带插值的必须改成 `trf()`。**

```dart
'已选 ${a} / ${b} 张'                        // 错: 插值在运行时就拼好了，
                                             //     查表永远命中不了
trf('已选 {0} / {1} 张', [a, b])              // 对
```

**3. 这些**不要**动：

- `lib/export/web_template.dart` —— 那是**导出网页的内容**，
  它的双语由网页自己的 locale 决定，跟桌面界面语言无关
- 源码注释里的中文（注释本来就该是中文）
- 日志、异常信息里给开发者看的中文
- 用户自己输入的内容、草稿名、地名

## 翻译的分寸

这个产品的中文文案是**有态度**的（"胡说八道"式的直白、破折号解释、
加粗强调关键半句）。英文要保持同样的语气，**不要翻译成客服腔**：

| 中文 | ✅ | ❌ |
|---|---|---|
| 原图一张都不会离开这台电脑 | No original ever leaves this computer | Your privacy is important to us |
| 传到一半断了，再点一次就接着传 | The upload stopped partway. Press Resume to carry on. | An error occurred during the upload process |
| 删除不返还额度 | Deleting does not refund the credit | Credits are non-refundable upon deletion |

具体要求：

- 短标签用**祈使句或名词**，不要 "Please"、"Click here to"
- 破折号 `——` 在英文里用 ` — `（前后带空格）
- 数字单位跟着英文习惯（`3 张` → `3`，量词在英文里通常省掉）
- 已有的 `l10n_en.dart` 开头那几十条是定调的样本，照着写

## 验收

```bash
dart run tool/i18n_scan.dart      # 应当输出"还没接入: 0 条"
dart run tool/i18n_missing.dart   # 应当输出"没有漏翻的"
flutter analyze                   # 干净
```

然后手动切到 EN 走一遍：主界面 → 挑照片 → 呈现设置 → 发布对话框 →
照片大图 → 手机导入。**重点看按钮会不会被英文撑破**——
中文两个字的按钮，英文常常要四五个词。
