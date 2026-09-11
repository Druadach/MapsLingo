# 发布检查清单

## 发布内容

0.1.0 是首次公开发布的预发布版本。代码已在 iOS 15.4.1 收到一份使用成功的反馈；公开发布前应完成下列逐项验收，发布稳定版前必须完成。

建议以 `MapsLingo` 为仓库名（名称中不使用 iOS 前缀，避免商标误导；iOS 关键词放在仓库描述和 Topics 中）。使用 `dist/MapsLingo-0.1.0-source.zip` 中的干净源码目录创建仓库，不要把当前工作目录连同 SDK、工具链、历史 dylib 或个人崩溃日志整体上传。

GitHub 描述建议：`Apple Maps language picker for iOS 15+ — TrollFools-injectable dylib`。Topics 建议：`ios`、`trollfools`、`apple-maps`、`dylib`、`tweak`。

源码包包含当前 `src/`、构建/校验/打包脚本、中英文说明、变更记录和 GitHub Actions 配置。`dist/` 与本地历史文件被 Git 忽略；二进制应放在 GitHub Releases，而不是提交到 Git 历史。

1. 先决定许可证并加入 `LICENSE`。如选择 MIT，确认版权声明中的作者/年份，不使用示例占位作者。当前没有自动为你授予或选择许可证。
2. 必要时在 README 补充你的仓库链接、作者和联系方式；不要误称这是 Apple 官方工具。
3. 从仓库根目录运行 `bash build.sh`、`node scripts/verify.mjs`、`node scripts/package.mjs`。Windows 可在 WSL 构建、Windows Node.js 校验打包。
4. 在干净源码目录初始化 Git（已有仓库则跳过）、提交，并在确认远端地址与待推送内容后推送到你创建的 GitHub 仓库。构建和打包脚本不会自动建仓、提交、推送或发布。
5. 查看 Actions 的 Build 工作流，检查日志后下载产物。工作流只有读取仓库和上传工作流产物的权限，不会自动创建 Release。
6. 初次发布建议创建 `v0.1.0` 标签并勾选 **Set as a pre-release**，附上本页的验证范围。

## Release 附件

- `MapsLingo-0.1.0.dylib`：普通用户只注入此文件。
- `MapsLingoRestore-0.1.0.dylib`：恢复用途，必须先移除主库，不能同时注入。
- `MapsLingo-0.1.0-release.zip`：包含二进制、说明、构建记录与校验报告。
- `SHA256SUMS-0.1.0.txt`、`VERIFICATION-0.1.0.json`、`BUILD-INFO-0.1.0.txt`。

可以额外上传源码 ZIP；GitHub 的自动源码归档不能代替已编译的 dylib。

## 真机验收

发布稳定版前至少完成以下手动检查，并记录系统、机型、TrollFools 版本和注入目标：

- 从无注入状态安装后能打开地图，首次弹出选择面板，取消不会改变语言。
- 完全重启 Maps 后分别验证简体中文、英文及另一种实际列出的语言；记录界面与地图标签是否分别变化。
- 双指长按能重新进入面板，不破坏常用拖动、缩放、搜索、导航以及已启用的辅助功能。
- 跟随系统后重开地图，原系统语言本身始终不变。
- 独立恢复库可用；后来通过其他方式设定的不同语言不会被自动覆盖。
- 不需要二次注入即可多次切换；后台再前台不会重复弹面板或重复添加手势。

0.1.0 已收到 iOS 15.4.1 用户使用成功的反馈，但没有每项操作的详细测试记录，不应把这次反馈当成上述清单全部通过。静态分析与签名校验不是设备测试；自动生成报告中的 `onDeviceVerified: false` 仅表示校验脚本未进行设备测试，不否定文档记录的人工反馈。iPad、多窗口、VoiceOver 和其他 iOS 版本未验证时请明确标注。

## 隐私与源码发布范围

不要上传未经脱敏的 `.ips`、设备标识、完整 App 容器 UUID 路径、个人下载目录、SDK 或第三方工具链。打包脚本使用明确的源码文件清单，且拒绝符号链接。仓库代码不含遥测。

GitHub 公开后再附截图，请检查地图中的住址、收藏、位置和搜索记录是否需要遮挡。
