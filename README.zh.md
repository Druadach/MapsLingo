# MapsLingo

[English](README.md)

给 iOS 15+ 的 Apple 地图增加独立的语言选择面板。系统保持英文，地图可使用简体中文、繁体中文、英文等**当前地图 App 自带的语言**。

以一个 dylib 通过 TrollFools 注入，不需要单独的设置 App，也不依赖 Substrate / ElleKit。

> **当前状态：0.1.0 预发布。** 已收到一位 iOS 15.4.1 用户使用成功的反馈；每种语言、手势、恢复操作和其他设备尚未逐项验证，一次成功反馈不代表完整兼容性认证。最低系统版本标记为 iOS 15.0，不等于所有 iOS 15+ 设备都已验证。

## 设计说明

早期原型在 iOS 15.4.1 的 arm64e 设备上发生过启动崩溃：系统会认证静态注册的 Objective-C 自定义类的父类指针，失败发生在任何面板代码执行之前。本版改用系统原生控制器，在主队列通过 Objective-C runtime 注册独立的回调类，不携带需要启动注册的自定义类、分类或协议元数据，不修改现有方法，不关闭 PAC；偏好保存和恢复逻辑不变。构建检查新增了静态类元数据回归检测，避免只检查编译与文件签名而漏过该缺陷。

注入 0.1.0 前先移除其他所有注入。不需要清空地图数据或反复更改 TrollFools 策略；[发布检查清单](PUBLISHING.md) 中的逐项验收仍然必要。

## 功能

- 首次启动自动显示原生语言列表；以后在地图内**双指按住不动 1.2 秒**重新打开。
- 自动读取 Maps 的本地化资源，显示语言自称、英文名称和语言代码，不虚构支持列表。
- “Follow System / 跟随系统”移除地图的独立语言设置，不改变系统语言。
- “Restore Original / 恢复原设置”恢复首次修改前的备份，保存在 `MapsLingo.SafeBackup.v1`。
- 不替换任何 Objective-C 方法，不修改地区、定位、地图供应商或导航数据。
- 无遥测、无网络请求，不读取或记录位置、搜索、路线、联系人。

## 注入与使用

1. 完全退出地图，在 TrollFools 移除所有已有注入，确认原版地图可以打开。**不要叠加注入。**
2. Maps → Advanced Settings：打开 **Prefer Main Executable**。其余选项先保持默认：Lexicographic、Compatibility Fallback 开启、Use Weak Reference 开启。
3. 只注入 **`MapsLingo-0.1.0.dylib`**，不要同时注入恢复库。
4. 打开地图，等待语言面板出现。选择语言，再点确认；第一次展示面板不会自动更改语言。
5. **在多任务界面把地图卡片向上划掉，再重新打开。** 返回桌面不是彻底退出。语言偏好在下一次启动生效，不会即时翻译已经打开的界面。

面板中的勾选表示**已保存的偏好**，不是当前界面已完成切换。关闭面板后，双指长按可再次修改；无需重新注入。

手势允许与地图手势同时识别、不取消触摸，但不同设备或辅助功能配置仍可能有冲突，需实测。首次提示关闭后不会每次启动重复弹出。

## 恢复与卸载

**仅移除 dylib 不会撤销已经保存的语言。**

- 想跟随当前系统语言：面板选择 Follow System，彻底关闭并重开地图。
- 想恢复首次修改前的设置：选择 Restore Original，再彻底关闭地图、移除主库并重开。
- 面板无法使用时：先移除主库，单独注入 `MapsLingoRestore-0.1.0.dylib`，打开地图等待几秒，再关闭、移除恢复库并重开。

恢复只处理本插件的语言备份，不清空地图数据。如果语言后来被其他方式改成不同值，恢复操作会保留该值并清理旧备份。

首次展示记录会保留在地图自己的偏好域中，因此重新注入后可能不会自动弹出面板；仍可通过双指长按打开。

## 限制与排错

- 界面、地图地名、POI、导航语音不是同一条语言链路。设置成功不代表全部都会切换；本插件不强制修改服务器或系统守护进程行为。
- TrollFools 的 Prefer Main Executable 只是优先选主程序，受保护时仍可能回退。注入日志的 `Best matched Mach-O is .../Maps.app/Maps` 才能确认目标。
- 如果日志写着 `mapping process is a platform binary, but mapped file is not`，先 Eject All 并确认原版可启动。这是加载/签名问题，不要删除 Apple 的框架或继续叠加注入。
- 不再使用静态 `CFSTR` / Objective-C 字符串常量，避免此前 arm64e 的 CFString 指针认证故障；运行时创建字符串，不关闭 PAC 或签名检查。
- 如果面板不出现，先试双指长按并确认没有旧版残留；再提供 TrollFools 注入日志。Weak Reference 可能允许地图在插件实际未加载时正常启动，不能只凭“不闪退”判断加载成功。
- 闪退日志位于 Settings → Privacy → Analytics & Improvements → Analytics Data，文件通常为 `Maps-….ips`。公开提交前遮盖设备标识和个人信息，保留异常、调用栈、架构和插件 UUID。

## 本地构建

### macOS + Xcode

需要完整 Xcode 的 iPhoneOS SDK，以及 Node.js 22 或更新版本。SDK 和工具链**不随本仓库分发**。

```bash
bash build.sh
node scripts/verify.mjs
node scripts/package.mjs
```

### Linux / WSL 交叉编译

```bash
TOOLCHAIN_BIN=/path/to/iphone/bin \
SDKROOT=/path/to/iPhoneOS.sdk \
bash build.sh
node scripts/verify.mjs
node scripts/package.mjs
```

没有配置环境变量时，Linux 构建可使用本地 `.build-tools/toolchain-modern/linux/iphone/bin` 和 `.build-tools/sdk/iPhoneOS15.6.sdk`。Windows 用户可在 WSL 编译，然后回到项目目录，在 Windows 的 Node.js 中运行校验和打包命令。

默认输出 arm64 + 现代 arm64e ABI 的通用 dylib。校验脚本检查最低系统版本、依赖、UUID、静态 CFString/类注册元数据回归和每页 ad-hoc 签名；这些检查不能替代真机测试。

输出都在 `dist/`：主库、恢复库、构建记录、校验报告、SHA-256 清单、安装包和**不含工具链/SDK/旧版文件/崩溃日志**的源码 ZIP。

## GitHub 发布

见 [发布检查清单](PUBLISHING.md) 和 [变更记录](CHANGELOG.md)。GitHub Actions 配置会在 macOS 构建并上传工作流产物，不会自动创建公开 Release。

当前未替你选择许可证。公开作为开源项目发布前，请确定并加入适合的 `LICENSE`；打包脚本会自动收录它。本项目与 Apple、TrollFools 无隶属关系。
