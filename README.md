# 取色鸭 · 相机版（Duck Camera Picker）

以取色鸭桌面端 UI 为原型（黄鸭图标、大黄渐变按钮、暖色深浅主题、中文颜色命名），
用 Flutter 重写的**相机实时取色**应用：把手机对准任何物体，中央准星实时识别颜色，
点「确认取色」即保存到历史并复制色值。

## 功能

- **底部 Liquid Glass 标签栏**：磨砂圆角矩形，左边取色历史、中间相机取色按钮、右边我的
- **相机实时取色**：全屏预览 + 中央取色点，约 8fps 实时刷新当前颜色
- **取色卡片**：顶部圆角矩形，左边圆形色块，右边上面中文颜色名、下面色值
- **中文颜色命名**：算法直接移植自桌面端（`color_name`），两端命名一致
- **色值格式**：HEX / RGB / HSL / CMYK 显示开关（我的页可切换）
- **取色后复制**：HEX（不含 #）/ HEX（含 #）/ RGB / HSL / CMYK
- **取色历史**：独立标签页，最近 50 条持久化保存；点按复制，一键清空
- **我的**：应用图标、取色设置（显示格式 / 取色后复制 / 软件外观）、关于
- **外观**：跟随系统 / 浅色 / 深色（深色为桌面端 v2.0.19 同款暖色降饱和）
- **沉浸式状态栏**：内容延伸进系统栏，全透明
- **应用图标**：小鸭启动图标（Android 传统 + 自适应图标，iOS 全尺寸）
- **闪光灯**：取色页右上角可开关补光灯

## 运行

```bash
flutter pub get
flutter run
```

## 平台配置（已完成）

- iOS：`ios/Runner/Info.plist` 已添加 `NSCameraUsageDescription`（取色鸭需要使用相机进行实时取色）
- Android：`android/app/src/main/AndroidManifest.xml` 已添加 `CAMERA` 权限 + `android.hardware.camera` feature

相机权限由 `camera` 插件在运行时申请，拒绝后页面会显示重试入口。

## 验证状态（2026-09-24，Linux CI 环境）

- `flutter analyze`：无问题
- `flutter test`：10/10 通过（HEX/RGB/HSL/CMYK、中文命名、序列化）
- Android APK 未编译：本机无 Android SDK / Java，需在开发机上 `flutter build apk`

## 实现说明

- 取色点固定为**画面中心**：避开预览旋转 / 前后摄镜像的坐标映射坑，
  中心点在任何方向下都是稳定的。交互上移动手机对准颜色即可
  （桌面端的放大镜跟随鼠标，移动端的对等物就是准星取色）。
- Android 相机帧为 YUV420，iOS 为 BGRA8888，`lib/camera/frame_sampler.dart`
  中双路处理，中心 5×5 平均降噪。
- 应用锁定竖屏（`main.dart`），保证预览与采样坐标一致。

## 应用图标

`assets/icon.png` 即取色鸭黄鸭图标（1020×1020）。生成各平台启动图标：

```bash
flutter pub add dev:flutter_launcher_icons
# 按 flutter_launcher_icons 文档配置后
dart run flutter_launcher_icons
```

## 已知限制

- 实时取色依赖相机帧流，中低端机连续取色时会有轻微发热
- 未做点击画面任意位置取色（见上：中心准星方案更稳）
