# say2me

[English](README.md) | 中文

本地语音听写工具：双击 Control 开始听写，再按一次结束（或超时自动结束），识别文本自动粘贴到光标处。基于 SenseVoice-Small 模型与 sherpa-onnx 推理，全程离线，音频不出本机。

## 特性

- 触发方式可自定义：双击 Control / Option / Command，或录制任意组合键
- 默认自动结束 30 秒，可在设置中调整
- 自动检测语言（中、粤、英、日、韩），可锁定单一语言
- 识别结果自动粘贴到当前光标位置（或仅复制到剪贴板）
- 菜单栏常驻，无 Dock 图标

## 系统要求

- macOS 13 及以上，Apple Silicon
- Xcode Command Line Tools（仅构建时需要）

## 使用 Release 包（推荐）

1. 从 [Releases](https://github.com/AaronyfDesign/say2me/releases) 下载 `say2me-vX.Y.Z-macos-arm64.zip`，解压直接运行。语音推理引擎已内置在 app 里。
2. 若被 Gatekeeper 拦截：`xattr -cr say2me.app` 后再打开。
3. 首次启动后点菜单栏图标，选择「语音模型：未下载（点击下载）」，会自动把 SenseVoice 模型（约 230MB）下载到 `~/Library/Application Support/say2me/model/`。
4. 手动方式：从 [模型 release](https://github.com/AaronyfDesign/say2me/releases/tag/model-sensevoice-v1) 下载 `say2me-sensevoice-model.zip`，解压到 `~/Library/Application Support/say2me/model/`（里面应有 `model.int8.onnx` 和 `tokens.txt`）。

## 快速开始

```bash
# 1. 下载 sherpa-onnx 二进制（一次即可）
mkdir -p vendor
curl -sL -o /tmp/sherpa.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/v2.0.1/sherpa-onnx-v2.0.1-osx-arm64-shared.tar.bz2
tar xjf /tmp/sherpa.tar.bz2 -C vendor

# 2. 下载 SenseVoice-Small int8 模型（约 230MB）
mkdir -p models/sense-voice
curl -sL -o models/sense-voice/model.int8.onnx \
  https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx
curl -sL -o models/sense-voice/tokens.txt \
  https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt

# 3. 构建
./build.sh

# 4. 运行
open build/say2me.app
```

## 首次运行权限

应用需要两项权限，均在系统提示时授予：

1. 辅助功能（Accessibility）——用于监听双击修饰键、模拟 Cmd+V 粘贴。
   系统设置 → 隐私与安全性 → 辅助功能，把 say2me 打开。
   若列表里出现的是「未知」，先退出应用、用下面的方式重新打开一次再勾选。
2. 麦克风——首次听写时系统会弹窗询问。

授予辅助功能后建议退出并重新打开应用，事件监听才会生效。

## 使用

1. 双击 Control（默认）开始听写，听到提示音，光标旁会浮现「听写中…」提示胶囊
2. 对着麦克风说话
3. 单击一次同一触发键结束（结束提示音）；或超过设定秒数自动结束
4. 稍候约半秒，文本自动粘贴到当前光标位置

双击开始、单击结束：只统计「孤立按压」，打字、组合键、滚轮不会误触。开始后 0.3 秒内的触发键活动不会被当成结束指令（防止双击尾部误停）。

设置面板（菜单栏图标 → 设置…）可改触发键、语言、数字规整、插入方式，并提供「录 3 秒并识别」测试按钮。

## 目录结构

```
Sources/          Swift 源码（无 Xcode 工程，swiftc 直接编译）
  main.swift            菜单栏入口
  HotkeyCenter.swift    双击修饰键检测 + 自定义热键
  AudioRecorder.swift   麦克风采集 + WAV 写入
  Recognizer.swift      调用 sherpa-onnx CLI 识别
  DictationController.swift   状态机
  TextInserter.swift    剪贴板交换 + 模拟粘贴
  SettingsView.swift    设置窗口（SwiftUI）
tests/smoke.swift       无 GUI 端到端冒烟测试（解码→WAV→识别）
build.sh                构建脚本
```

## 冒烟测试

```bash
bash tests/smoke.sh
```

用系统 `say` 合成中英文语音，经完整识别管线验证，不依赖麦克风与 GUI。

## 已知限制

- 识别为非流式：说完一段后一次性出结果，无逐字上屏
- 无热词/自定义词表能力
- 粘贴模式下会短暂占用剪贴板（约 1.5 秒后恢复原内容，若目标应用已读取或用户有操作则不恢复）
- 提示胶囊位置取焦点输入框光标的 AX 坐标，取不到时跟随鼠标；个别自绘输入框可能定位不到
- 起止提示音使用系统音效（开始 Tink / 结束 Pop），可在设置中关闭
