# 发布接口（桌面端 -> 服务器）

## 认证

用户在网站 `/account` 生成 **publish token**，粘贴进桌面端设置。
**App 里不存用户密码**，也不用做 OAuth 设备流。

```
Authorization: Bearer tv_xxxxxxxx
```

## 一次发布分两步

### 第一步：创建 Story，换取上传地址

```
POST /api/publish
Content-Type: application/json

{
  "manifest": { ...story.json 的完整内容... },
  "files": [
    { "path": "photos/abc123.webp", "contentType": "image/webp" },
    { "path": "thumbs/abc123.webp", "contentType": "image/webp" }
  ],
  "visibility": "public"
}
```

服务器会：校验令牌 -> 检查发布额度 -> 扣一次额度 -> 建 story ->
返回一批**预签名上传地址**。

```json
{
  "slug": "9f3a2b7c1d",
  "publicUrl": "https://travelview.app/s/9f3a2b7c1d",
  "mediaBase": "https://media.travelview.app/s/9f3a2b7c1d",
  "uploads": [
    { "path": "photos/abc123.webp", "url": "https://...预签名..." }
  ]
}
```

额度不够时返回 **402** 和 `{"error":"NEED_PAYMENT"}`，
桌面端据此引导用户去网页付款。

### 第二步：图片直传 R2

对每个 `uploads[i].url` 发 `PUT`，body 就是文件字节，
`Content-Type` 与申请时一致。

**图片不经过我们的服务器**，直传对象存储。

## 铁律

- **原图永远不上传。** 只传 `views/by-trip/<slug>/` 里已经剥掉 EXIF 的 WebP。
- 服务器会检查 manifest 里有没有原图后缀（`.heic` / `.dng` / `.jpg` 等），
  发现就直接拒绝 —— 这是防止桌面端出 bug 把原图路径写进去。
- manifest 里的图片路径是**相对路径**（`photos/xxx.webp`），
  由服务器拼上 `mediaBase`。这样以后换 CDN 域名不用改任何已发布的数据。

## 更新已发布的 Story

同一个 slug 重新发布时（后续版本会支持）走 `PUT /api/publish/<slug>`，
只上传变化的图片。**公开链接始终不变** —— 这是"网页是产品本身，
不是导出结果"的具体体现。
