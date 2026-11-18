# 熊猫麻将后台（Flutter）

原生 Flutter/Material UI 管理端，支持 Android 与 iOS。登录页默认记住后台账号和密码，日常只需输入 6 位 Google Authenticator 验证码。

## 功能

- 新旧后台一键切换
- 账号、密码本地记忆（可在登录页隐藏入口修改）
- 6 位验证码输入完成后自动登录
- 会员列表、搜索、备注、清分
- 开卡、禁用、恢复与待处理请求
- 详细撞号进度、日志、统计、会员池管理
- 牌池记录与详情
- 8 秒自动刷新及下拉刷新

## Android

本项目所在父目录含中文路径时，Android AOT 在 Windows 上可能发生路径乱码。运行脚本会自动复制到纯英文临时目录再构建：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-android.ps1
```

成品位于 `dist/熊猫麻将后台-Flutter-Android.apk`。

## iOS

必须在安装 Xcode 的 macOS 上执行：

```bash
chmod +x scripts/build-ios.sh
./scripts/build-ios.sh
```

未配置签名时脚本生成未签名归档；要安装到真机或发布，需在 Xcode 中配置 Apple Developer Team、证书和描述文件后移除 `--no-codesign`。

## 后端

应用内预置两个 HTTP 后台地址，并已为 Android/iOS 开启明文 HTTP 访问。修改地址请编辑 `lib/main.dart` 中的后台配置。
