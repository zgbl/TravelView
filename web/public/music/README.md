# TravelView 测试用背景音乐

> 这些文件**仅作功能测试占位**，正式上线前请替换成你确认过授权/签好约的正式曲库。

## 曲目与授权（全部可商用，需署名）

所有曲目作者 **Kevin MacLeod**，来自 incompetech.com，采用 **CC-BY 4.0** 许可：
商用免费，但**必须在你的产品里保留署名**。

| 文件 | 用途/氛围 | 来源 |
|---|---|---|
| Water Lily.mp3 | 舒缓/轻氛围，适合风景 | https://incompetech.com/music/royalty-free/mp3-royaltyfree/Water%20Lily.mp3 |
| Carefree.mp3 | 轻快，适合旅途 | https://incompetech.com/music/royalty-free/mp3-royaltyfree/Carefree.mp3 |
| Bittersweet.mp3 | 偏抒情 | https://incompetech.com/music/royalty-free/mp3-royaltyfree/Bittersweet.mp3 |
| Fluffing a Duck.mp3 | 活泼短曲 | https://incompetech.com/music/royalty-free/mp3-royaltyfree/Fluffing%20a%20Duck.mp3 |

**署名写法示例（可放"关于/设置"页或每篇页脚）：**
> Music: "Water Lily" / "Carefree" / "Bittersweet" / "Fluffing a Duck" by Kevin MacLeod (incompetech.com), Licensed under Creative Commons: By Attribution 4.0 http://creativecommons.org/licenses/by/4.0/

## 其它可商用的可靠来源（备选/以后换）
- **FreePD.com** —— Public Domain/CC0，商用无需署名（最省心）
- **Pixabay Music / Unminus / YouTube 音频库** —— 免费商用，通常无需署名（看各自条款）
- **Musopen** —— 公版古典乐
- 谨慎：Free Music Archive / ccMixter 授权不一，很多是 **NC 禁商用**，用前逐个核对

## 怎么被网站用到
本目录在 `web/public/` 下，Next.js 会把 `public/` 原样发到站点根：
所以文件对外地址是 `https://travelview.blackrice.top/music/<文件名>.mp3`（本地开发 `http://localhost:3000/music/<文件名>.mp3`）。
功能开发时可在此直接用；正式版建议走 `/media/` 或对象存储并做压缩/时长控制。
