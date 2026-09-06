# 产品重定位方案 v1：从 TravelView 到 Photo Story

状态：提案，待确认名字后进入执行。

## 1. 重新定义问题

不是"我需要一个游记工具"，而是：

> 我手机里有 12,000 张照片。我几乎从来不看它们。

用户的真实心理链条：

1. **愧疚**：拍了那么多，等于没拍。照片=沉睡资产。
2. **无力**：整理成本太高。做相册要几小时，剪视频要专业技能。
3. **渴望**：其实很想再看一遍，也很想给别人看（家人、朋友、社交平台）。
4. **怀疑**：市面上的东西要么是"存储"（iCloud/Google Photos，只解决存，不解决看），要么是"手工创作工具"（剪映/Canva，要我自己干活）。

所以我们的定位缝隙非常清楚：

| 类别 | 代表 | 它解决什么 | 它不解决什么 |
|---|---|---|---|
| Photo Storage | iCloud / Google Photos | 不丢 | 不好看、不成故事 |
| Editor | 剪映 / Canva / Lightroom | 表达力 | 要你自己动手 |
| Travel Journal | Polarsteps / Journi | 旅行记录 | 只限旅行、需要边走边记 |
| **我们** | — | **自动把已经存在的照片变成一个值得重看和分享的故事** | 不做存储竞品，不做编辑器 |

一句话定位：

> **We turn the photos you already have into a story worth watching.**

主 Slogan（Hero）：**Turn your photos into a story.**
副 Slogan（情感钩子）：**Bring your forgotten photos back to life.**

关键：Travel 是 **展示场景**，不是 **产品类别**。落地页用旅行做 Demo，但语言必须是通用的（photos / trip / event / moment），导航和信息架构里不能出现 "Travel" 作为一级概念。

## 2. 名字

### 命名标准
1. 不含 travel / trip / map / journey——否则重蹈覆辙。
2. 能同时容纳：旅行、家庭、婚礼、演唱会、徒步、年度回顾。
3. 语义指向"故事 / 重看 / 时光 / 光"，不是"存储 / 相册 / 管理"。
4. 好念、好拼、两三个音节、能做动词或口号（"I made a ___"）。
5. 有 .com 或高质量替代（.app / .co），无明显商标冲突。

### 提案（按推荐度排序）

**A 组：语义清晰型（最好懂，最好做 SEO）**

| 名字 | 读感 | 为什么好 | 风险 |
|---|---|---|---|
| **Storyfold** | STOR-ee-fold | fold = 把成千上万张"折叠"成一个故事，正好是产品动作 | .com 已被占，需 storyfold.app |
| **Lumefold** | LOOM-fold | 光 + 折叠；独特、可注册可能性高 | 需要解释一次 |
| **Storyloom** | STOR-ee-loom | loom = 织机，把碎片织成整体；温暖、premium | 略文艺 |
| **Everscene** | EV-er-scene | 每个场景都留下；通用于任何事件 | 偏"影像"少"故事" |
| **Restory** | re-STOR-ee | 直接就是产品动作：把照片 re-story | 短，多半被占 |

**B 组：情感/电影感型（最贴 premium & cinematic 视觉方向）**

| 名字 | 读感 | 为什么好 |
|---|---|---|
| **Reelight** | REE-light | reel（影片卷）+ relight（重新点亮）双关，完美对应"让沉睡照片重新亮起来" |
| **Lumira** | loo-MEER-ah | 光 + mirar（看）；柔和、国际化、易发音 |
| **Aftergl** / **Afterglow** | — | 旅行结束后的余晖，正是我们的使用时刻（回来之后才用） |
| **Kinora** | ki-NOR-ah | 早期活动影像装置的名字，含"kin（亲人）"暗示；独特 |
| **Vesper** | VES-per | 黄昏；高级、安静、有电影感 |

**C 组：口号型（最直接，营销省力）**

| 名字 | 备注 |
|---|---|
| **Ten Thousand** / **10k** | "你手机里有一万张照片" 直接变成品牌 |
| **Unpile** | 把照片堆拆开——动词感强，非常互联网 |
| **Rewatch** | 一词说清价值：你终于会重看它们 |

### 我的推荐

1. **Reelight**（首选）——双关精准、cinematic、可动词化（"reelight your 2025"）、扩展性无限，且不指向任何单一场景。
2. **Lumefold**（次选）——独特、可注册概率高、"fold"直接对应"把上万张折成一个故事"这个核心动作。
3. **Storyloom**（稳妥）——最好懂，最不需要解释。

域名策略：优先 .com；拿不到就用品牌 + 后缀（getreelight.com / reelight.app），不要用连字符。分享链接域可以单独短一点（rlgt.link）。

## 3. 新落地页结构

原则：**Demo 优先，功能靠后。** 每一屏只回答一个问题。

| # | 区块 | 用户此刻的问题 | 内容 |
|---|---|---|---|
| 0 | Nav | 这是什么 | Logo / Stories / How it works / Pricing / Sign in / **[Get the app]** |
| 1 | **Hero** | 关我什么事 | 见下 |
| 2 | The Pile | 我是不是也这样 | 全屏铺满几千张缩略图缓慢滚动，逐渐变暗 → 一行字："You took 12,847 photos last year. You've looked at 40." |
| 3 | **The Magic**（核心） | 它怎么做到 | 一个连贯的滚动驱动动画：照片流 → 时间线聚类 → 地图落点 → Stops 生成 → 精选浮出 → 道路路线绘制 → 小车动画 → 定格成 Story 封面。**不切段落、不加标题，一镜到底。** |
| 4 | The Result | 结果长什么样 | 真实 Story 的嵌入式播放（可交互），下方一行："This took 4 minutes to make." |
| 5 | Three Steps | 我要干多少活 | Import → Review → Publish。强调"你只做第 2 步，30 秒" |
| 6 | Not just travel | 我不旅行也能用吗 | 五张卡片横滑：Road trip / Wedding / A year with the kids / Hiking / Concert。同一引擎，不同故事。 |
| 7 | Story Gallery | 别人做出来什么样 | 6–9 个真实公开 Story 缩略图，点开即看。这是最强的转化资产。 |
| 8 | Privacy | 我的照片安全吗 | "Your photos stay on your device. Only the ones you pick get published." 这是我们对 iCloud/Google 的差异化利刃。 |
| 9 | Pricing | 多少钱 | 极简三档，见 §6 |
| 10 | Final CTA | — | "You already took the photos. Let's make something out of them." |

### Hero 具体方案

- 背景：全屏静音自动播放的 Story 片段（地图 + 小车 + 照片切换），不是静态截图。
- H1：**Turn your photos into a story.**
- Sub：*Your phone has thousands of photos nobody ever looks at. Point us at them — we'll find the trips, the days, the places, and turn them into something beautiful you'll actually watch.*
- CTA1：Download for Mac（当前形态是桌面优先）
- CTA2：Watch a story →（直接跳 Gallery，不要"Learn more"）
- Hero 下方一行小字：Works with your existing photo library. Nothing uploads until you say so.

### 文案禁用词
travel journal、trip planner、photo manager、organize your library、AI-powered、dashboard。
### 文案主词
story、rediscover、relive、watch、the photos you already have、automatically。

## 4. Features 优先级（重排）

排序依据：**能否在 5 秒内制造"哇"。**

1. 自动识别一次事件（时间 + GPS 聚类）— 这是最不可替代的能力
2. 自动 Stops 与时间线
3. 真实道路路线 + 路线动画/小车 — 这是最"哇"的视觉资产，必须前置
4. 每个 Stop 的快速精选（用户唯一要做的事）
5. 一键发布为可分享的 Web Story
6. 隐私：本地处理，只有选中的才上传
7. （后续）Video / 社交尺寸导出
8. （后续）多人协作、家庭共享

明确不做：滤镜编辑、云存储订阅、行程规划、社交信息流。

## 5. 用户流程：App → Publish → Share

```
App（桌面/手机）
  选择照片来源 → 自动分析 → "We found 7 stories in your library"
  → 选一个 → 时间线 + 地图 + Stops 已生成
  → 逐 Stop 快速精选（保留/丢弃，30 秒）
  → 选主题（Cinematic / Warm / Minimal）
  → Publish
Web
  → 生成短链 + OG 封面
  → Share to Facebook / X / iMessage / QR
  → 访客无需注册即可观看
  → 访客页底部软 CTA："Made with ___. Make one from your photos."（这是我们的增长回路）
```

关键设计点：**发布出去的 Story 本身就是落地页。** 每个被分享的 Story 都要带一个不打扰但明确的品牌尾巴。

## 6. Pricing

原则：免费必须能做出一个完整的、能分享的 Story，否则病毒回路断掉。

| 档 | 价格 | 内容 |
|---|---|---|
| Free | $0 | 无限本地分析；1 个公开 Story（可随时替换）；带品牌尾巴 |
| Plus | $6/mo 或 $48/yr | 无限 Story、自定义域名尾巴、4K 视频导出、去品牌、密码保护 |
| Lifetime | $99 一次 | 早期用户专用，限量。对这类"情感资产"产品，买断转化率往往高于订阅 |

付费入口只出现在两处：Story 数量到上限时，和导出视频时。落地页只放一个极简价格表，不放对比长表。

## 7. Story Gallery

- 独立路由 `/stories`，是网站第二重要的页面。
- 每个 Story 卡片：封面 + 标题 + "9,300 miles · 12 stops · 84 photos"。
- 至少放 5 个非旅行样例（婚礼/年度回顾/徒步/演唱会/孩子的一年），否则用户仍会以为这是旅行工具。
- 首批样例由我们自己做，用真实照片，质量决定一切。

## 8. 信息架构

```
/                Landing
/stories         Story Gallery（公开精选）
/s/[slug]        单个 Story（分享目标页）
/how-it-works    可选，深度说明 + 隐私
/pricing
/download
/login /signup /account /admin
```
去掉一切"功能列表页""博客占位""关于我们"，现阶段是噪音。

## 9. 从 Travel 扩展到其他 Photo Stories 的路线

引擎其实是通用的：**时间聚类 + 地理聚类 + 精选 + 模板渲染**。差别只在渲染模板与叙事骨架。

- 阶段 1（现在）：Travel 模板（地图为主角，路线动画）。
- 阶段 2：Event 模板（婚礼/生日/演唱会）——单地点，时间线为主角，地图退为一个小徽章。需要新增"按小时聚类"。
- 阶段 3：Year in Review 模板——跨年度，地图为世界视图，节奏由月份驱动。
- 阶段 4：People 模板（孩子的一年、和某人的所有照片）——需要人脸聚类，端侧完成。

工程上要做的准备：把 Story 数据模型里的 "trip / stop" 抽象成 **"story / chapter"**，地图只是 chapter 的一种可选装饰而非必需。这一步应该在改代码时就做，否则以后要动数据契约。

## 10. 代码与架构层面的重构清单（待名字确认后执行）

1. **命名去 travel 化**：包名 `tv_core` / `tv_app` / `tv_desktop` 可保留缩写但文档语义改为 story；面向用户的字符串全部替换。
2. **数据模型泛化**：`Trip → Story`，`Stop → Chapter`，`route` 变为 chapter 级可选字段。
3. **模板层抽离**：渲染器按 `story.template` 分发（travel / event / year），先只实现 travel 但把接口留出来。
4. **web/ 重写**：landing 按 §3 重做；新增 `/stories` gallery；`/s/[slug]` 页尾加增长回路 CTA。
5. **视觉系统**：深色为底、大图、少 UI、衬线标题 + 无衬线正文、动效以缓慢推移为主。远离 SaaS dashboard 观感。
6. **文档同步**：README、Design/architecture.md、user-manual.md 同步改名与新定位。

## 附：YC 口味的命名修正

YC 反复讲的择名原则很朴素，和"好听"不完全一致：

1. **短**：一到两个音节最好，最多三个。
2. **电话里说一次别人就能拼对**——不要造词造得太怪（Lumefold、Kinora 在这条上扣分）。
3. **能拿到 .com**——YC 明确说过为了 .com 花几千美金是值得的，用 .ai / .io 会显得像玩具。
4. **不要把自己锁死在一个场景**（这正是 TravelView 的问题，改对了）。
5. **别太描述性**（PhotoStoryAI 这种一看就是功能，不像公司）。
6. **一句话能说清你是干嘛的比名字本身重要得多**——名字不需要解释产品。

按这套标准，把上面的提案重排：

| 名字 | 音节 | 拼写难度 | 场景锁定 | YC 适配度 |
|---|---|---|---|---|
| **Rewatch** | 2 | 零 | 无 | ★★★★★ 一词即定位，投资人 30 秒懂 |
| **Reelight** | 2 | 低 | 无 | ★★★★☆ 双关好，但会被听成 "relight" |
| **Storyloom** | 3 | 低 | 无 | ★★★★☆ 好懂、温暖 |
| **Vesper** | 2 | 零 | 无 | ★★★★☆ 像公司，但不提示产品 |
| **Lumira** | 3 | 中 | 无 | ★★★☆☆ |
| **Storyfold** | 3 | 低 | 无 | ★★★☆☆ |
| **Lumefold / Kinora** | 3 | 高 | 无 | ★★☆☆☆ 造词太重 |
| **Ten Thousand / Unpile** | — | — | 无 | ★★☆☆☆ 聪明但难长大 |

**修正后的推荐顺序：**

1. **Rewatch** — 最符合 YC 口味。名字本身就是产品的成功指标（用户重看了自己的照片）；pitch 第一句可以是 "People take 10,000 photos a year and rewatch none of them. We fix that."。.com 大概率要花钱买，值得。
2. **Reelight** — 有品牌感又不空洞，.com 更可能拿得到。
3. **Storyloom** — 安全牌，最容易注册，最不容易记错。

不推荐再考虑：任何含 photo/travel/album/AI 的组合词。
