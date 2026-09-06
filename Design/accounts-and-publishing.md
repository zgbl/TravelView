---
title: 账号、主页与再次发布
---

# 账号、主页与再次发布

本文覆盖三件事：桌面端怎么登录、用户的公开主页、发布后怎么原地修改。
网站侧已经实现，桌面端待改（见文末契约）。

## 1. 桌面端登录：设备码

不让桌面端碰用户密码。流程和 OAuth 设备流一致：

```
App                          网站                         用户
 |  POST /api/device/code      |                            |
 |---------------------------->|                            |
 |  { userCode: "KDR8-Q2M7",   |                            |
 |    deviceCode, verifyUrl,   |                            |
 |    interval: 3 }            |                            |
 |                             |     打开 /link，敲入 KDR8-Q2M7
 |                             |<---------------------------|
 |                             | POST /api/device/approve   |
 |                             | 生成 publish token 并绑定    |
 |  POST /api/device/token     |                            |
 |  { deviceCode }  每 3 秒     |                            |
 |---------------------------->|                            |
 |  428 authorization_pending  |                            |
 |  ...                        |                            |
 |  200 { token: "tv_..." }    |                            |
```

- 短码 8 位，字母表去掉了 `0 O 1 I L`，15 分钟有效，只能兑换一次。
- 令牌**只在轮询成功时返回一次**，取走后 `device_codes` 那一行立即删除。
- 确认动作只能发生在带会话的网页上，桌面端不参与授权决策。
- 老的"网页生成令牌 → 复制粘贴"仍然可用，不删。

## 2. 公开主页 `/u/<handle>`

- `users.handle`：3-20 位小写字母/数字/下划线，唯一索引建在 `lower(handle)` 上，
  保留字（admin、api、account…）挡掉。用户在账户页自己设。
- **不用 UUID 做地址。** UUID 又长又丑，而且把内部主键钉死在分享链接里，
  以后再想换标识就换不掉了。
- 主页只列 `visibility = 'public'` 的故事。`unlisted` 拿到链接才能看，
  不出现在任何列表里——这是"仅凭链接访问"这个承诺的一部分。
- `profile_public = false` 时，本人还能看到自己的主页，别人一律 404。
  显示"这个人隐藏了主页"等于泄露了这个 handle 有人在用。
- 主页自带分享条（Facebook / 二维码给微信 / 复制链接），底部一行
  "Made with TravelView" 回链——每一个被分享出去的主页都是一个入口。

## 3. 发布后原地更新

`POST /api/publish` 的请求体多了一个可选字段 `storyId`：

- **不传** → 新建一篇，扣一次额度，生成新的 slug 和新的媒体前缀。
- **传了且这篇属于你** → 原地更新：slug 不变、公开链接不变、**不再扣额度**，
  这一次没再出现的旧图会被删掉（否则改一次图就在磁盘上留一份垃圾）。
- **传了但找不到**（用户删了那篇、或换了账号）→ 当作新建，而不是报错。
  他手上的照片已经导出好了，把人卡在这里没有任何好处。

返回体多了 `updated: true|false`，桌面端据此决定提示语。

## 4. 图片的存放

文件系统，不入库。数据库里只有 manifest（JSON）和路径。

```
新   u/<user uuid>/<年>/<月>/<slug>/photos/*.webp
                                   /thumbs/*.webp
老   s/<slug>/photos/*.webp
```

- 按用户和年月分目录：单个用户几万张图时目录还翻得动，也方便按用户整体迁移。
- **前缀记在 `stories.media_prefix` 里，不靠代码算。** 算法会变，
  已经落盘的路径不会跟着变；老数据回落到 `s/<slug>`，一张图都不用搬。
- manifest 里存的始终是相对路径 `photos/x.webp`，
  这样同一份 manifest 在本地预览、导出包、服务器上都成立。
- 上传口有三道闸：票据 HMAC 签名 + 路径形状白名单（防目录穿越）
  + RIFF/WEBP 魔数校验。原图上传不进来。

## 5. 桌面端要改什么（契约）

| 改动 | 说明 |
|---|---|
| 新增「连接账号」 | 调 `POST /api/device/code`，显示 `userCode` 和 `verifyUrl`，按 `interval` 轮询 `POST /api/device/token`；拿到 token 存进 `AppSettings.publishToken` |
| 记住 storyId | 发布成功后把返回的 `storyId` 写进那次行程的本地记录 |
| 再次发布带上 storyId | 用户对同一趟行程再次点发布时，请求体带 `storyId`，提示语按 `updated` 区分「已更新」/「已发布」 |
| 上传路径 | 不变。`uploads[]` 里的 `url` 直接 PUT，前缀由服务端决定，App 不需要知道 |
| 压缩 | 不变。已经是 1600px WebP + 剥 EXIF |

## 6. 数据库

`db/migrations/008_profiles.sql`：`users.handle/bio/profile_public`、
`device_codes` 表、`stories.media_prefix`（并把老数据回填成 `s/<slug>`）。
可重复执行。
