# TrackerCore

独立 Foundation Swift Package，供 iOS App 与 App Intents 共用。最低部署版本 iOS 17 / macOS 14，Swift tools 5.9；核心不导入 SwiftUI、SwiftData 或 AppIntents。

在安装 Swift 的 macOS 或 Linux 中执行：

```sh
cd Packages/TrackerCore
swift test
```

当前交付环境为 Windows，执行 `swift test` 返回 `swift` 命令不存在。测试已编写，尚未运行；不能将此包视为已经编译或已经通过测试。

## 核心约定

- `SessionReducer.reduce(events:corrections:asOf:)` 显式使用传入时间，保留未闭合、歧义、孤立端点和迟到事件导致的更正冲突。自动流与按 `manualSessionID` 配对的手动流分开处理。
- `IntervalMath.confirmedDuration` 仅累计 confirmed 段，并先裁剪再求区间并集。`dailyDurations` 使用传入 Calendar 的日边界，支持 23/25 小时的夏令时日期。
- `TrackerEngine` 写操作在副本上执行，校验成功才赋值。App 包装层仍须负责数据库事务、串行访问及持久化失败回滚。
- `charge` 的 `requestID` 必须在同次提交重试时复用。已撤销/删除的回执保留；相同 ID 的不同内容会报错。`fullOnRestart` 只有用户明确确认补电至满电时传 true。
- `undoCharge` 按回执数组的追加顺序识别本设备最新操作，同时核对所有相关观察的 revision。撤销不修改连接事件。
- `merge` 按 ID 保留本机冲突版本，完整校验合并结果，清除旧撤销缓冲；删除/撤销创建的本机回执阻止旧备份重新带回相应观察。调用 `mergeConflictCount` 可在恢复前展示冲突数量。
- `.end` 需要非空结束原因。原因明确为“盒子没电”或“盒子没电了”时只写盒子 0%，左右耳保持未知；普通补电不会自动填满电。

测试覆盖重复/乱序/同刻事件、12 小时阈值、人工修正锚点、手动与自动流隔离、重叠排除、夏令时、区间裁剪、幂等冲突、缺省电量、充电原子性、revision 撤销、防重建回执、拆分、恢复缺失引用、观察边界与 CSV 文本转义。真实存储、系统自动化、锁屏和 OCR 的验证由 App 集成及 iPhone 真机测试承担。
