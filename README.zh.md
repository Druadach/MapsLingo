# MapsLingo

[English](README.md)

为 iOS 15+ 的 Apple 地图（Apple Maps）提供独立的语言选择面板。脱离系统全局语言控制，轻松切换地图界面语言。
💡 兼容性：iOS 15.4.1 真机实测通过。如果您的系统遇到问题，请参考 [3. 崩溃日志提交（Crash Logs）](#crash-logs) 反馈。

基于 TrollFools 注入 dylib 实现，无需替换任何 Objective-C 方法，无遥测、无网络请求，不读取或记录任何位置、路线及个人隐私数据。

<img width="300" alt="20260911-210409" src="https://github.com/user-attachments/assets/2e6a2b40-88b1-4bad-874f-d59bae68ac3e" />

---

## 🌟 核心功能

- **独立语言切换**：动态读取 Apple 地图自带的本地化资源，提供 iOS 原生语言切换。
- **便捷手势唤出**：首次启动自动显示；后续使用只需在地图任意位置**双指按住不放 1.2 秒**即可再次唤出。
- **一键跟随/恢复**：
  - **Follow System（跟随系统）**：取消独立语言设置，恢复跟随 iOS 系统全局语言。
  - **Restore Original（恢复原设置）**：一键还原首次修改前的初始状态（安全备份保存在 `MapsLingo.SafeBackup.v1`）。
- **纯净安全**：不修改系统地区、定位、地图供应商或导航数据，不依赖任何外部服务器。

---

## 📦 Release 附件说明

| 文件名 | 类型 / 用途 | 适用人群 |
| :--- | :--- | :--- |
| **`MapsLingo-0.1.0.dylib`** | **主插件库** | 普通用户（正常使用只需注入此文件） |
| **`MapsLingoRestore-0.1.0.dylib`** | **应急恢复库** | 面板打不开时的恢复工具（不可与主库同时注入） |
| `MapsLingo-0.1.0-release.zip` | 完整发布包 | 包含二进制文件、使用说明、构建日志与校验报告 |
| `SHA256SUMS-0.1.0.txt` | 哈希校验文件 | 用于校验文件完整性与安全性 |
| `VERIFICATION-0.1.0.json` / `BUILD-INFO-0.1.0.txt` | 构建与签名报告 | 供高级用户及安全审计参考 |

---

## 🚀 安装与使用指南

### 步骤 1：准备与注入
1. 在多任务界面将 **Apple 地图** 卡片向上划掉，彻底退出地图。
2. 打开 **TrollFools**，进入 **Advanced Settings**（高级设置）：
   - 开启 **Prefer Main Executable**（优先主程序）。
   - 其余选项保持默认（开启 `Lexicographic`、开启 `Compatibility Fallback`、开启 `Use Weak Reference`）。
3. 选择注入 **`MapsLingo-0.1.0.dylib`**。

### 步骤 2：选择语言并生效
1. 打开 Apple 地图，等待语言选择面板自动弹出（若未弹出，在地图界面**双指长按 1.2 秒**）。
2. 选择希望使用的语言并点击 **确认**（选定后面板勾选代表“已保存偏好”，此时界面不会立即更新）。
3. **关键步骤（使设置生效）**：进入 iOS 多任务界面，**将 Apple 地图卡片向上划掉彻底退出，然后重新打开地图**。
   > ⚠️ **注意**：仅仅返回桌面并非彻底退出。语言偏好需在下一次 App 冷启动时才会加载生效。

---

## 🔄 恢复与卸载

> ⚠️ **特别提示**：仅仅在 TrollFools 中移除 dylib **不会**自动撤销已经保存的语言偏好。

### 方案 A：恢复跟随系统语言（推荐）
1. 双指长按打开地图内面板，选择 **Follow System（跟随系统）** 并确认。
2. 彻底杀掉地图后台并重新打开。
3. （可选）在 TrollFools 中移除 `MapsLingo-0.1.0.dylib`。

### 方案 B：恢复首次修改前的原始设置
1. 双指长按打开地图内面板，选择 **Restore Original（恢复原设置）** 并确认。
2. 彻底杀掉地图后台。
3. 在 TrollFools 中移除主插件库，重新打开地图。

### 方案 C：应急恢复（面板无法唤出时）
1. 在 TrollFools 中**移除主库** `MapsLingo-0.1.0.dylib`。
2. 单独注入应急恢复库 **`MapsLingoRestore-0.1.0.dylib`**。
3. 打开地图，等待 3~5 秒。
4. 杀掉地图后台，在 TrollFools 中**移除恢复库**，再次重新打开地图。

---

## ⚠️ 技术限制与排错指南

### 1. 语言生效范围说明
* **界面 vs 地名 vs 语音**：iOS 应用界面语言、地图 POI 地名以及 Siri 导航语音属于不同的数据链路。本插件仅切换 App UI 界面语言，**不会也不可能强制修改 Apple 地图服务器返回的矢量地名或语音引擎**。

### 2. 注入失败 / 面板不弹出排查
* **启动提示**：首次弹出提示关闭后不会每次启动重复弹出，请使用**双指长按 1.2 秒**手动唤出。部分辅助功能或手势插件可能存在手势冲突。
* **目标进程确认**：检查 TrollFools 注入日志，确认包含 `Best matched Mach-O is .../Maps.app/Maps` 才代表正确注入了主程序。
* **平台二进制报错**：若日志出现 `mapping process is a platform binary, but mapped file is not`，说明存在加载或签名异常。请先在 TrollFools 中点击 **Eject All** 并确认原版地图可正常启动。切勿删除 Apple 系统框架或盲目叠加注入。

<a id="crash-logs"></a>

### 3. 崩溃日志提交（Crash Logs）
若遇到闪退，排错日志路径为：`设置` → `隐私与安全性` → `分析与改进` → `分析数据`，搜索以 `Maps-` 开头、后缀为 `.ips` 的文件（如 `Maps-202X-XX-XX.ips`）。
> 💡 **提交反馈提示**：在公开 Issue 提交日志前，请务必隐去个人标识与设备敏感信息，保留异常类型（Exception）、调用栈（Call Stack）、硬件架构及插件 UUID。

---

## 🛠️ 本地构建 (Local Build)

### 环境依赖
- **macOS**：需要完整 Xcode（包含 iPhoneOS SDK）以及 Node.js 22+（SDK 与编译工具链不随本仓库分发）。
- **Linux / WSL**：支持交叉编译。

### 构建命令

#### macOS + Xcode 环境：
```bash
bash build.sh
node scripts/verify.mjs
node scripts/package.mjs
```

#### Linux / WSL 交叉编译：
```bash
TOOLCHAIN_BIN=/path/to/iphone/bin \
SDKROOT=/path/to/iPhoneOS.sdk \
bash build.sh
node scripts/verify.mjs
node scripts/package.mjs
```
> **提示**：若未配置环境变量，Linux 构建会自动使用本地 `.build-tools/toolchain-modern/linux/iphone/bin` 与 `.build-tools/sdk/iPhoneOS15.6.sdk`。Windows 用户可在 WSL 中编译，再回到 Windows 环境运行 Node.js 校验与打包脚本。

默认输出兼容 arm64 + 现代 arm64e ABI 的通用 dylib（运行时创建字符串，符合 PAC 指针认证规范）。所有产物均保存在 `dist/` 目录下。

---

## 📄 声明与许可

- 本项目基于 **MIT 许可证** 开源。
- 本项目为独立开源插件，与 Apple Inc. 或 TrollFools 开发团队无任何隶属关系。
