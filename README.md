# LocalSend Enterprise (LSE) 企业版

企业换机文件传输工具，基于 LocalSend 二次开发，Flutter/Dart 实现。

## 功能特性

| 功能 | 说明 |
|------|------|
| ✅ 文件/文件夹传输 | 单文件直传，文件夹自动打包 zip |
| ✅ 跨平台 | Windows ↔ macOS |
| ✅ 6位数字口令 | 一次性使用，验证后即失效 |
| ✅ 断点续传 | 网络中断自动恢复（自动触发） |
| ✅ 传输日志 | JSON Lines 结构化日志，30天自动清理 |
| ✅ 完成通知 | 系统弹窗提醒 |
| ❌ iOS/Android | 不支持，仅 PC 端 |

---

## 下载安装包

### GitHub Actions 自动构建

代码推送到 GitHub 后，Actions 会自动构建双平台安装包：

1. 将整个 `lse_client` 目录推送到 GitHub 仓库
2. 进入 **Actions** 标签页
3. 点击 **Build macOS App** 或 **Build Windows EXE** → **Run workflow**
4. 构建完成后在对应的 workflow run 中下载 artifacts

产物：
- `lse-macos.zip` → macOS `.app` 安装包（解压后双击运行）
- `lse-windows.zip` → Windows `.exe` 便携版（解压后双击运行）

---

## 本地开发

### 前提条件

- **Flutter SDK 3.0+**：[安装指南](https://docs.flutter.dev/get-started/install)
- **OpenSSL**（首次启动自动生成证书用）：
  - macOS：预装，或 `brew install openssl`
  - Windows：[Win32 OpenSSL](https://slproweb.com/products/Win32OpenSSL.html)
- **网络互通**（同一局域网）

### macOS 额外依赖

```bash
# 安装 CocoaPods（需要完整 Xcode）
brew install cocoapods
```

### 开始开发

```bash
cd lse_client

# 拉取依赖
flutter pub get

# 运行（Debug）
flutter run

# 构建 macOS
flutter build macos --release

# 构建 Windows
flutter build windows --release
```

### 一键构建脚本

```bash
# macOS
bash scripts/build-macos.sh

# Windows（PowerShell）
.\scripts\build-windows.bat
```

---

## 目录结构

```
lse_client/
├── lib/
│   ├── main.dart                          # 入口
│   ├── core/
│   │   ├── constants/app_constants.dart   # 全局常量
│   │   └── theme/lse_theme.dart            # 主题样式
│   ├── features/
│   │   ├── send/presentation/send_page.dart    # 发送端页面
│   │   └── receive/presentation/receive_page.dart # 接收端页面
│   └── shared/
│       ├── models/                        # 数据模型
│       ├── services/                      # 核心服务
│       │   ├── code_service.dart          # 口令生成与验证
│       │   ├── archive_service.dart        # zip + SHA256 hash
│       │   ├── certificate_service.dart     # HTTPS 证书
│       │   ├── log_service.dart            # 结构化日志
│       │   ├── notification_service.dart    # 系统通知
│       │   ├── device_info_service.dart    # 设备信息
│       │   └── transfer_service.dart        # 传输服务（Server+Client）
│       └── widgets/lse_widgets.dart         # 公共组件
├── macos/                                 # macOS Xcode 项目
├── windows/                               # Windows Visual Studio 项目
├── scripts/
│   ├── build-macos.sh                     # macOS 一键构建
│   └── build-windows.bat                  # Windows 一键构建
├── .github/workflows/
│   ├── build-macos.yml                    # GitHub Actions: macOS
│   └── build-windows.yml                  # GitHub Actions: Windows
└── pubspec.yaml
```

---

## 技术架构

### 传输流程

```
发送方（Server）                          接收方（Client）
    │                                           │
    │  1. 选择文件/文件夹                          │
    │  2. 生成 6 位口令                            │
    │  3. 启动 HTTPS Server 监听                  │
    │                                             │
    │                   4. 输入口令 + 发送方 IP     │
    │                   POST /api/transfer/init   │
    │  5. 验证口令 ✓                              │
    │                   GET /api/transfer/{id}/info
    │  返回文件信息                                │
    │                   6. 选择保存位置             │
    │                   GET /api/transfer/{id}/chunk（分块拉取）
    │  7. 分块发送（每块 1MB）                      │
    │                   7. 写入文件（断点续传支持）    │
    │                   POST /api/transfer/{id}/complete
    │  8. 写日志 + 弹窗                            │
    │                   8. 自动解压（zip）+ 弹窗    │
```

### API 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/transfer/init` | 发起传输，口令验证 |
| GET | `/api/transfer/{id}/info` | 获取文件信息 |
| GET | `/api/transfer/{id}/chunk` | 分块拉取（Range header） |
| POST | `/api/transfer/{id}/complete` | 完成确认 |

### 日志位置

| 平台 | 路径 |
|------|------|
| Windows | `C:\Users\<用户名>\.lse\logs\` |
| macOS | `~/.lse/logs/` |

文件名格式：`lse-YYYY-MM-DD.log`，保留 30 天。

---

## 已知限制

- [ ] 局域网自动发现（mDNS）暂未实现，需要用户手动输入 IP
- [ ] iOS/Android 端不在本版本范围内

---

## License

MIT (继承 LocalSend)
