# test-output

- `fixtures/` — 从真机导出的**脱敏元数据**（仅 assetId / 时间戳 / 经纬度，无图片）。
  可以安全提交进 Git，供 Mac 上的纯 Dart 单测使用。
- `runs/` — 每次真机跑出来的完整产物（含压缩后的照片）。**已被 .gitignore 排除，永不入库。**

devsink 服务会自动往 `runs/<run-name>/` 里写文件：
    cd tools/devsink && python3 server.py
