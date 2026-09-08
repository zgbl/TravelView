# 打出可以直接安装的 Windows 包。
#
#   powershell -ExecutionPolicy Bypass -File tool\build_windows.ps1
#
# 产物在 dist\ 下: 一个 zip（解压即用）和一个 msix（需要证书才能装，见下）。
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$AppName = 'TravelView'
$Version = (Select-String -Path pubspec.yaml -Pattern '^version:').Line `
    -replace 'version:\s*', '' -replace '\+.*', ''
$Version = $Version.Trim()

Write-Host "==> 清一遍" -ForegroundColor Cyan
flutter clean
flutter pub get

Write-Host "==> 编译 release" -ForegroundColor Cyan
flutter build windows --release

$Rel = "build\windows\x64\runner\Release"
if (-not (Test-Path "$Rel\$AppName.exe")) {
    throw "没找到 $Rel\$AppName.exe —— 检查 windows\CMakeLists.txt 里的 BINARY_NAME"
}

New-Item -ItemType Directory -Force -Path dist | Out-Null
$Zip = "dist\$AppName-$Version-windows.zip"
Remove-Item $Zip -ErrorAction SilentlyContinue

# **整个 Release 目录都要打进去，不能只拿 exe。**
# Flutter 的 Windows 产物是 exe + flutter_windows.dll + data\ 目录，
# 少一样就是启动即闪退，而且不给任何提示
Write-Host "==> 打 zip" -ForegroundColor Cyan
Compress-Archive -Path "$Rel\*" -DestinationPath $Zip

Write-Host ""
Write-Host "完成: $Zip" -ForegroundColor Green
Write-Host "自己安装: 解压到任意目录，双击 $AppName.exe。"
Write-Host "第一次运行 SmartScreen 会拦一下（没有代码签名证书）——"
Write-Host "  点「更多信息」→「仍要运行」。"
Write-Host ""
Write-Host "想要 .msix 安装包（能进开始菜单、能自动更新）:" -ForegroundColor Yellow
Write-Host "  dart run msix:create"
Write-Host "  但自签名的 msix 必须先把证书装进「受信任的根证书颁发机构」才装得上，"
Write-Host "  自己测试用 zip 更省事。"
