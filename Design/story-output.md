---
# 中文 PDF 字体 —— 必须写在文件里：VS Code 的 Pandoc 扩展只注入 Helvetica，不读外部配置文件。
CJKmainfont: "PingFang SC"
CJKoptions: "BoldFont=PingFang SC Semibold"
header-includes: |
  ```{=latex}
  \setCJKsansfont{PingFang SC}
  \setCJKmonofont{PingFang SC}
  \xeCJKDeclareCharClass{CJK}{"2010 -> "2027, "2190 -> "21FF, "2460 -> "24FF,
                              "2500 -> "257F, "25A0 -> "25FF, "2600 -> "27BF}
  ```
---

# 输出架构：Story 是唯一数据源

---

## 1. 一份数据，多种渲染

**不要分别开发网页、视频、社交图。** 先把 Story 定死，再挂多个 Renderer：

```
照片库 -> 行程识别 -> Stops -> 精选
                                 |
                                 v
                            STORY (JSON manifest)
                          /       |        \
                    Web Story   Video    Social Pack
                    (第一优先)   (复用)    (9:16)
```

Story 已实现于 `tv_core/lib/src/story.dart`，纯数据、纯函数、有完整测试。
它不碰磁盘、不联网 —— 图片转码和上传由调用方负责，它只负责结构。

### Web Story 的结构

```
Hero -> Day -> Stop -> Photos -> Road Route -> 小车动画 -> Summary
```

路线随滚动推进，小车沿实际道路行驶，走过的路线逐渐画出来。
Video 之后复用同一份 Story，不重新组织数据。

---

## 2. Route：完整 geometry，压缩存储

**保存完整的道路 geometry，不是只存拐点。** 抽稀只用于控制体积上限，
不是"只留拐点"那种简化 —— 城市里的弯道信息丢了，路线就假了。

| 层 | 格式 | 理由 |
|---|---|---|
| 服务端 / manifest | **Encoded Polyline6** | 比 GeoJSON 数字数组小四到五倍，测试里验证过 |
| 渲染时 | 解码成坐标 / GeoJSON | MapLibre 直接吃 |
| 导出给用户 | GPX | 互通格式，数据能带着走 |

precision 6（约 0.1 米）是 OSRM 的默认值，城市里不会出现折线抖动。
`PolylineCodec` 与 `StoryRoute.decodeGeometry()` 已实现。

每条路线记录 `source` / `provider` / `mode` / `distance`：

- `source`: `photoGps`（照片轨迹还原）/ `inferred`（推算）/ `actual`（真实轨迹）
- 页面上如实标注，**不能写"这是你走过的路"**

### 供应商策略

**照片 GPS 是真实数据；只有照片之间缺失的部分才需要路径规划。**

长期用**自托管 OSRM**。openrouteservice 只作为起步期的便利选项，
不作为永久数据源依赖 —— 托管服务会变、额度会限、条款会改。
Google Routes 可以做成可插拔 provider 用于对比，
但**它返回的 geometry 不能永久保存当作自己的数据**。

关键在于：**路线随时可以从 OSM 数据重新算出来**，
所以即使某个 provider 消失，Story 也不会烂 —— 大不了重算一次。

---

## 3. 数据与隐私：Server 只存派生版本

### 铁律

**原图永远不上传。** GPS/EXIF 解析、缩放、剥离 EXIF 全部在本地完成。
用户只有在点「发布」时，才上传他**最终选中**的照片，
而且只上传 **Web 派生版本**。

### Server 上有什么

| 内容 | 体积 | 说明 |
|---|---|---|
| Story manifest / metadata / route | **几十 KB** | 测试里一个两站的 Story 不到 4KB |
| thumbnails | 少量 | 列表和占位 |
| Web 照片（WebP，1200-1600px） | 每张约 100-300KB | |
| **原图** | **不存** | 一个字节都没有 |

**目标：一次普通旅行的 Server footprint 控制在 10-20MB**，
而不是几百 MB 的原图。40 张照片乘以 250KB 约合 10MB，正好。

这个数字直接决定商业模型能不能成立 —— 它比"技术上能不能存"重要得多。

### 存储选型

| 用途 | 选型 |
|---|---|
| metadata | Postgres |
| 图片 / CDN | Cloudflare R2（**零出网费**，对图片型产品是决定性的） |
| 视频 | **第一版本地生成 MP4**，不让 Server 存大文件 |

---

## 4. Social

### Facebook

优先分享 **Story URL**，靠 Open Graph 生成漂亮预览。
`og:image` 必须是 JPEG/PNG（抓取器不吃 WebP），
而且必须服务端直出标签（爬虫不执行 JavaScript）。

### 小红书

**不要依赖自动发布 API。** 生成 **9:16 Social Pack**：
封面、路线图、精选照片、标题与文案。用户保存到相册后自行发布。

这比对接 API 更稳：不受平台政策变化影响，也不需要用户交出账号。

### 视频

支持 16:9 和 9:16，复用同一个 Story Renderer。
第一版本地生成，不占服务器。

---

## 5. 实施顺序

| 步 | 内容 | 状态 |
|---|---|---|
| 1 | Story 数据模型 + manifest 序列化 | **已完成**（`story.dart`，14 个测试） |
| 2 | Polyline6 编解码 | **已完成**（`polyline_codec.dart`） |
| 3 | 本地导出管线：WebP 派生图 + 剥 EXIF + 写 manifest | 下一步 |
| 4 | Web Story Renderer（Template A + 滚动驱动 + 小车） | |
| 5 | 发布到 R2 + Postgres，拿到分享链接 | |
| 6 | Social Pack 9:16 | |
| 7 | 视频（本地生成，16:9 / 9:16） | |

第 3 步是把"桌面端已经算好的一切"变成"可以传出去的东西"的那一步，
做完就能在本地打开一个完整的 Story 网页 —— 还不用管服务器。
