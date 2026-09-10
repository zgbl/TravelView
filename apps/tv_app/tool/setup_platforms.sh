#!/usr/bin/env bash
# 生成 iOS / Android 工程壳子，并把相册权限声明补进去。
#
# 只需要跑一次。**这个脚本不碰 lib/** —— flutter create 在已有工程上
# 只补缺的平台目录，不会覆盖已经写好的代码。
#
#   cd apps/tv_app && bash tool/setup_platforms.sh
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=ios,android --org com.travelview .

# ---------- iOS ----------
PLIST=ios/Runner/Info.plist
add_plist() {   # add_plist <key> <说明文字>
  /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"
}
# 只读相册。**不要加 AddUsageDescription** —— App 不往相册里写东西，
# 多要一个权限只会让审核和用户都起疑。
add_plist NSPhotoLibraryUsageDescription \
  "TravelView 读取照片的拍摄时间和位置来生成旅行回顾。照片不会被上传或修改。"

# flutter create 用工程目录名当 App 名，桌面上会显示成 "Tv App"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName TravelView" "$PLIST" 2>/dev/null || true

# ---------- Android ----------
MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q READ_MEDIA_IMAGES "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
perms = '''    <!-- Android 13+ 用 READ_MEDIA_IMAGES；13 以下退回 READ_EXTERNAL_STORAGE。
         两条都要写，maxSdkVersion 让老权限在新系统上自动失效。 -->
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32" />
    <!-- Android 14 的"只选部分照片" -->
    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED" />
    <!-- **没有这一条，Android 10+ 读到的每张照片都不带 GPS。**
         系统从 MediaStore 返回的位置字段默认被抹掉，要单独申请这个权限
         才拿得到 EXIF 里的经纬度。没有位置就切不出行程，整个 App 是空的。
         它只给"读位置"，不给任何写相册的能力。 -->
    <uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
'''
s = s.replace('<application', perms + '\n    <application', 1)
# flutter create 用工程目录名当 App 名，桌面上会显示成 "tv_app"
s = s.replace('android:label="tv_app"', 'android:label="TravelView"')
open(p, 'w').write(s)
PY
fi

# photo_manager 要求 minSdk 21+、compileSdk 34+，新版 flutter create 默认就够，
# 这里只做一次检查，不去改用户的 gradle 配置。
grep -q "minSdk" android/app/build.gradle* 2>/dev/null && \
  echo "提醒: 确认 android/app/build.gradle 里 minSdk >= 21"

echo
echo "平台工程就绪。接着跑："
echo "  flutter pub get"
echo "  flutter devices"
echo "  flutter run -d <设备id>"
