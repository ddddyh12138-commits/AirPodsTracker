# AirPodsTracker · 耳机时光

一个 iOS 17+ 原生 iPhone App 项目。已整合原开发方案与 UI 风格：四个标签页、深色双环、透明电量容器、记录时间轴、统计和分享卡。

**交付状态：源码、Xcode 工程及新 Logo 已齐全；27 项核心业务测试已在 GitHub macOS 构建机通过，完整 App 编译与 IPA 打包尚未完成。** 首次 App 编译发现模拟器架构不一致，配置已修正；再次构建被 GitHub 的账户付款/预算限制拒绝启动。详见 `docs/cloud-build-status.json`。尚未通过 iPhone 真机验证。

## 使用方式

首次建立耳机档案后，按 App 内向导在系统「快捷指令」设置两条个人自动化：

1. 所选耳机蓝牙连接 → 立即运行 → 「记录耳机连接」 → 固定选择该耳机档案。
2. 同一耳机蓝牙断开 → 立即运行 → 「记录耳机断开」 → 同一档案。

设置完成后，连接自动记开始、断开自动记结束并汇总时长。**正常日常使用不需要手填连接时间，也不需要逐条确认。** 只有系统触发失败、缺少端点或记录冲突时才补录/核对。动作记录的是执行时刻，系统调度可能带来延迟；它不等同硬件精确时间戳。

App 不能直接安装系统个人自动化。向导显示收到的两类动作时间，最后需实际连接/断开一次核对。手动运行快捷动作也会产生记录，因此“收到动作”本身不能证明触发器一定配置正确。

## 已包含的功能

- 总览：双环时长视图、最近事件、今日统计、待核对入口、分部件历史电量。
- 记录：自动配对、人工补录、编辑、拆分、排除/恢复、迟到事件引起的旧修正核对。
- 统计：7/30 天连接时长、每日图表、小时分布、可读明细表与观察条件。
- 充电盒：真实快照水位、充满/补电/开始/结束、当前与历史观察编辑、删除、安全撤销。
- 电量：手动记录、本地截图 OCR、部件映射与保存前确认；左右耳/盒可分别未知。
- 分享：1080×1350 PNG 观察报告，通过系统分享面板导出。
- 设置：外观、设备、自动化向导、默认关闭的记录核对通知、JSON 备份/恢复、CSV 导出。
- 系统动作：记录连接、记录断开、接收外部电量、确认盒子充满。
- 数据：本机 SwiftData、原始事件保留、事务保存、版本化备份、重复请求保护。

连接记录不表示全部佩戴或播放历史。没有结束证据的正常段显示“等待断开”，不累加进确认统计；超过核对阈值、孤立结束与冲突显示“待核对”。电量显示来源和读数时间，未知不填 0，旧截图不冒充实时电量。

## 在 Mac 上打开与运行

1. 解压后打开 `AirPodsTracker.xcodeproj`，选择 `AirPodsTracker` scheme。
2. 使用支持 iOS 17+ 的当前稳定 Xcode，等待本地 `TrackerCore` Swift Package 加载；项目无第三方运行依赖。
3. 模拟器可先检查界面。真机运行需在 Signing & Capabilities 选择自己的 Team，并将 `com.example.AirPodsTracker` 改成自己可用的 Bundle Identifier。
4. 连接 iPhone，运行 App，再按内置向导建立自动化。模拟器不能证明真实耳机蓝牙触发。

无需为了记录启用录音、蓝牙扫描或音频后台模式；项目未配置静音音频保活。截图入口使用 PhotosPicker，不请求整个相册读取。

## 检查与打包

在 macOS 项目根目录执行：

```bash
# 纯 Foundation 核心业务测试
swift test --package-path Packages/TrackerCore

# 核心测试 + iOS 模拟器集成测试；可传实际 simulator UDID
bash scripts/check-macos.sh

# 生成未签名 IPA，需要自己的签名才能安装
bash scripts/build-unsigned-ipa.sh
```

已附 `.github/workflows/ios.yml`，流程会测试、编译并上传未签名 IPA。项目已按授权上传到私有仓库 [ddddyh12138-commits/AirPodsTracker](https://github.com/ddddyh12138-commits/AirPodsTracker)。**已尝试 GitHub Actions，尚未生成或安装 IPA。** GitHub 提示账户付款失败或需要调整支出额度；保留私有构建需要账号所有者检查该限制，也可以自行在 Mac 运行上述脚本。

源码结构检查可运行 `python3 scripts/validate-source.py`。安装 `tree-sitter==0.26.0` 与 `tree-sitter-swift==0.7.4` 后还会做 Swift 语法解析。该脚本不检查 SDK API 类型或 SwiftUI 类型推断，不可用于宣称编译通过。

## 项目结构

```text
AirPodsTracker.xcodeproj/   Xcode 工程与共享 scheme
AirPodsTracker/            SwiftUI 页面、系统动作、本地持久化、OCR 与通知
Packages/TrackerCore/      可独立测试的 Foundation 模型、状态机、区间运算、事务与备份
AirPodsTrackerTests/       iOS SwiftData/Store 集成测试
scripts/                  macOS 检查、IPA 打包与源码结构检查
docs/                     合并规格、原稿、研究依据和交付验证记录
```

## 实现取舍与尚未验证能力

为让充电、修正与恢复可以一次原子保存，V1 用一个 SwiftData `TrackerDocument` 保存版本化 Codable `TrackerState`；领域模型仍独立，统计由纯函数计算。此实现比逐个持久化六个关联模型更简单，但大量历史数据时整份状态写入的成本需要实测。没有独立扩展或云同步，不涉及 App Group 并发。

UI 保留双环造型，V1 默认无官方续航刻度；未提供未经核实的型号参考表，不计算剩余电量或电池健康百分比。液体容器仅由确认快照控制。

AllMyBatteries 桥接、HealthKit、耳机运动信号、小组件、倾斜水波和云同步没有加入本版；它们在合并方案中列为条件扩展。电量 Intent 只接收调用方明确提供的数值，本身不会读取 AirPods 电量。

通知默认关闭，仅在开始后超过 12 小时仍可能缺少结束时提醒核对；收到断开后取消。锁屏、强制退出、首次解锁前、不同 iOS 与耳机型号下的自动化和数据访问仍需实测，记录模板见 `docs/device-validation.md`。

开发规格以 `docs/开发交付方案（含UI）.md` 为基础；本 README 与 `docs/implementation-status.md` 说明实际实现差异。原稿只作参考，不应重新引入原稿中的全局音频监听、静音保活、时长换算电量或级联删除历史。
