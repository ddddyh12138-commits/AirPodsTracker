# 交付与验证记录

日期：2026-10-11。本地交付环境：Windows / PowerShell；已使用 GitHub macOS 构建机进行第一轮编译测试。

| 层级 | 结果 | 实际证据与限制 |
|---|---|---|
| 项目源码 | 已写入 | 四页 UI、动作、存储、OCR、通知、备份恢复、分享与业务核心 |
| Swift 语法 | 已通过解析 | tree-sitter Swift 语法解析；不等于 Swift 编译或 API 类型检查 |
| 工程结构 | 已检查 | 所有 App Swift 文件与集成测试均有 Xcode 源文件引用，scheme 指向有效 target |
| 资源结构 | 已检查 | Info.plist、隐私声明、资源 JSON、AppIcon 引用可解析 |
| 核心业务测试 | 已通过 | macOS 上 27 项 XCTest，0 失败；首轮运行 38142253954 |
| Store 集成测试 | 未执行完成 | 首轮 App 编译失败，未进入测试执行 |
| iOS 编译 | 已尝试，未通过 | 首轮模拟器架构不一致；已修正 Debug 的 ONLY_ACTIVE_ARCH。重跑遭 GitHub 账户限制拒绝启动，修正尚未验证 |
| 模拟器 UI | 未验证 | 未完成 App 编译；未以生成图代替实际渲染证据 |
| iPhone 安装 | 未执行 | 未使用用户 Team/签名材料，未生成已签名包 |
| 自动化、OCR、通知真机行为 | 待验证 | 需按 device-validation.md 实际操作 |
| GitHub Actions | 已运行，当前受限 | 已创建私有仓库并推送；最新运行 38142462652 未能启动 job |
| Logo | 已生成并接入 | imagegen 原图、1024 RGB AppIcon 已接入资源清单；尚未完成原生资源编译 |
| IPA | 尚未生成 | 不能将源代码压缩包作为 IPA；仍需要真实设备目标编译产物 |

## 已修正的审查问题

- 自动/手动端点独立配对，拆分不改写原始事件。
- 迟到端点不使旧修正消失；核对页可撤销旧修正，编辑新段会更新锚点。
- Store 保存成功才发布新状态；失败保留原库与界面数据。
- 充电撤销按操作追加顺序与 revision 校验；观察提供编辑入口。
- 充电删除/撤销保留回执；旧请求不会重建已删除观察。
- 已撤销的充满/空盒快照有持久删除标识，旧备份恢复不会让电量复活。

## 与计划的实现差异

- 保留 SwiftData，但使用一个版本化文档，领域数组以 Codable 存储，以简化跨功能原子性。
- 四页 UI 已实现；未核实型号参考时双环为无刻度时长视图，不放入假定 30 小时常量。
- 分享/导出由用户主动发起；没有 P1/P2 可选能力的占位按钮。
- 排除记录可从“已排除”恢复；删除观察先明确确认。没有实现删除观察后的 8 秒恢复提示。

下一步解除 GitHub 构建限制，或在 Mac 运行 `bash scripts/check-macos.sh`；完成编译测试后运行 IPA 打包脚本，再进行真机矩阵。账户限制提示原文为 “The job was not started because recent account payments have failed or your spending limit needs to be increased.” 该提示没有区分两种原因，不能据此断定用户欠费。
