# LX Music Flutter Mobile

一个基于 Flutter 开发的跨平台音乐播放器，支持 Android 和 iOS。

## 功能特性

### 核心功能
- ✅ 音乐搜索（酷我/酷狗/咪咕）
- ✅ 音频播放（播放/暂停/上下首）
- ✅ 播放模式（顺序/随机/单曲循环）
- ✅ 歌单管理（创建/编辑/删除）
- ✅ 歌词显示（LRC/QRC 格式）
- ✅ 后台播放
- ✅ 锁屏/通知栏控制

### 扩展功能
- ✅ 下载管理
- ✅ 缓存管理（LRU 策略）
- ✅ 自定义源
- ✅ 数据同步
- ✅ 多语言支持

### 界面特性
- ✅ 深色主题
- ✅ 底部导航栏
- ✅ 迷你播放器
- ✅ 全屏播放器
- ✅ 歌词滚动同步

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.24+ |
| 状态管理 | Riverpod 2.x |
| 路由 | go_router 14.x |
| 音频播放 | just_audio |
| 后台播放 | audio_service |
| 网络请求 | dio |
| JS 引擎 | flutter_js |
| 本地存储 | shared_preferences |

## 项目结构

```
lx_music_flutter/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── audio/           # 音频服务
│   │   ├── network/         # 网络请求
│   │   ├── theme/           # 主题配置
│   │   └── widgets/         # 通用组件
│   ├── features/
│   │   ├── player/          # 播放器模块
│   │   ├── search/          # 搜索模块
│   │   ├── playlist/        # 歌单模块
│   │   ├── download/        # 下载模块
│   │   ├── lyric/           # 歌词模块
│   │   ├── custom_source/   # 自定义源
│   │   ├── sync/            # 同步模块
│   │   └── settings/        # 设置模块
│   └── router/              # 路由配置
├── android/
├── ios/
└── pubspec.yaml
```

## 开发环境

### 安装依赖

```bash
# 设置国内镜像（可选）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# 获取依赖
flutter pub get
```

### 运行应用

```bash
# macOS
flutter run -d macos

# iOS 模拟器
flutter run -d ios

# Android 模拟器
flutter run -d android
```

### 构建发布版

```bash
# macOS
flutter build macos --release

# iOS
flutter build ios --release

# Android APK
flutter build apk --release
```

## 主要模块

### 1. 音乐源模块

支持三大音乐平台：
- 酷我音乐
- 酷狗音乐
- 咪咕音乐

### 2. 播放器模块

- 播放/暂停/上下首
- 进度条拖拽
- 播放模式切换
- 后台播放支持
- 锁屏/通知栏控制

### 3. 歌单模块

- 创建/编辑/删除歌单
- 添加/移除歌曲
- 手动拖拽排序
- 自动排序（按名称/歌手/时长）

### 4. 歌词模块

- LRC 格式解析
- QRC 逐字歌词
- 歌词滚动同步
- 点击跳转

### 5. 下载模块

- 单曲/批量下载
- 并发控制
- 进度显示
- LRU 缓存清理

### 6. 自定义源模块

- 添加/编辑/删除自定义源
- 导入/导出源配置
- JavaScript 脚本执行

## 设计参考

UI 设计基于 Stitch 生成的设计稿：
- 深色主题（#0D0D0D）
- 紫色强调色（#6366F1）
- 圆角卡片设计
- 底部导航栏

## 待优化

- [ ] 音频库迁移到 media_kit
- [ ] 更多音乐源支持
- [ ] 歌词翻译显示
- [ ] 均衡器功能
- [ ] Android Auto / CarPlay 支持

## 许可证

本项目基于 Apache License 2.0 开源。
