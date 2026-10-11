# AirPodsTracker 开发交付方案（含完整 UI）

版本：1.0 · 编制日期：2026-10-11 · 适用场景：只用 iPhone，尽量自动记录。

> **给执行 Codex：**按第 9 节逐项实现并记录验证结果。若环境具备相关技能，可用 `superpowers:executing-plans` 或 `superpowers:subagent-driven-development` 执行；不依赖这些技能也应能完成。本文件已经合并原《完整开发方案》和《UI交互与视觉交付方案》，包含独立开工所需的产品、数据、UI、任务与验收规范。原文件中的旧 Prompt 不再作为实现依据。

**Goal：**做一个中文优先的 iPhone 本地工具，自动收集可获得的耳机连接记录，以很少的手动操作补全充电与电量信息，让用户看清记录、修正漏记、比较使用习惯。

**Architecture：**用户首次在快捷指令中设置两条个人自动化，之后连接自动记开始、断开自动记结束，正常记录无需手填或逐条确认。App Intents 保存事件，本地状态机生成连接区间；只有漏记或异常才提示补录。SwiftData 保存原始事件、用户修正、电量快照与充电观察，SwiftUI 提供四个页面。

**Tech Stack：**iOS 17+、Swift 5.9+、SwiftUI、SwiftData、Swift Charts、AppIntents、Vision 的 `VNRecognizeTextRequest`、PhotosPicker、UserNotifications。使用能构建 iOS 17 目标的当前稳定 Xcode；可选新 API 必须检查系统版本。

**Spec：**本文件第 1—8 节；第 9—11 节为实施与验收。研究依据见第 12 节。本文件是开发规格，尚不是可运行 App，也不代表已通过 iPhone 真机测试。

## 全局约束

- 使用设备仅要求 iPhone 与用户已有的 AirPods，不依赖 Mac、Android 或 Apple Watch 日常采集；**开发、原生编译和签名仍需要 macOS/Xcode**。
- 延续原方案四个 Tab：**总览 / 记录 / 统计 / 充电盒**。设置从总览右上角进入。
- 产品界面只说能证实的内容：连接记录不等于佩戴、播放或耗电；历史快照不等于实时电量。
- 本地优先，V1 不需要账号、服务器、云同步、订阅、广告或 AI 接口。不得默认上传截图、使用记录或健康数据。
- V1 的 App Intents 放在主 App target 中，使用同一个本地 SwiftData 存储；不为尚未实现的 Widget 或 Share Extension 先引入 App Group。
- 不播放静音音频保活，不为监听而激活 `.playAndRecord`，不默认添加 `audio` / `bluetooth-central` 后台模式。
- 不用蓝牙名称、MAC 地址或 SF Symbol 推断芯片、型号或真实佩戴状态；设备绑定由用户明确选择。
- SwiftData 不使用充电观察到连接记录的级联删除。生产环境存储失败必须报告，不可静默切换为空的内存数据库。
- 示例数据只存在于 Preview、测试或显式演示模式；首次正式启动无伪造记录和电量。
- 仅在用户选择功能时请求相关权限。拒绝可选权限后，核心记录与手动补录仍可使用。

## 优先审阅的五类风险

| 条件 | 预期行为 | 对应验证 |
|---|---|---|
| 锁屏、App 不在前台、系统挂起或强制退出 | 如实测试自动化是否到达；缺事件可见，不补造结束时间 | T2 真机矩阵、T3 缺端点测试 |
| 重复、乱序、两次连接之间缺少断开 | 原始记录保留；统计确定、无负时长、不把全部跨度算作使用 | T1/T3 状态机测试 |
| 跨午夜、夏令时、充电边界穿过连接区间 | 按日期与观察边界取交集，时长不重算、不丢失 | T3/T5 区间测试 |
| 电量未知、旧图、OCR 误配左右耳、数据源时间缺失 | 不填 0、不冒充实时；用户确认后才写入 | T4 快照测试与界面验收 |
| 修改/删除充电观察、迁移或写入失败 | 独立历史保留，错误可恢复，失败动作不回报成功 | T1/T5 持久化与删除测试 |

## 1. 原方案如何合并

### 1.1 保留原有主体，修正数据含义

| 原方案内容 | 合并决定 | 最终实现 |
|---|---|---|
| SwiftUI + SwiftData + Charts，iOS 17+ | 保留 | 原生轻量项目，按功能组织文件 |
| 四个标签页 | 保留 | 总览 / 记录 / 统计 / 充电盒 |
| 自动连接→断开记录 | 换采集主路径 | 快捷指令个人自动化 → App Intents；人工补录兜底 |
| AVAudioSession 全局监听、回来补算 | 删除错误前提 | 路由只可作局部诊断；没有结束证据就待确认 |
| `UsageSession` | 保留领域概念 | 从事件和修正推导的连接区间，不以 `end ?? Date()` 混入总量 |
| `FullCaseChargeCycle` | 改名并重定义 | `ChargeObservation`，中文“充电观察”，不声称电池完整循环次数 |
| `BatterySnapshot` | 保留并补字段 | 左/右/盒可空，来源、记录时间、读数时间与确认状态分开 |
| 深空背景、玻璃材质、高光描边 | 保留视觉方向 | 深色优先设计，跟随系统；实色信息卡保证可读性 |
| 双环能量仪 + 圆角大数字 | 保留双环外形 | 展示连接记录时长；播放续航仅作为显式参考，绝非剩余电量 |
| 悬浮状态药丸 | 保留 | 显示“已收到连接记录”等证据状态，不凭旧事件显示“实时已连接” |
| 透明充电盒与液体水位 | 保留 | 水位仅来自盒子电量快照；未知时为空轮廓，不用小时换算水位 |
| 长按充满、触感、结束后的分享卡 | 保留并简化 | 普通按钮也可操作；保存成功才反馈；分享由用户主动触发 |
| 声波时间轴 | 保留时间轴，改图形 | 真实时长条与电量采样点，不生成像真实音频的假波形 |
| 自动“通话/飞行/专注”标签 | 改为手动 | 用户可选标签，不能从时长推断活动 |
| 官方达成率 → 电池健康 | 删除 | 展示个人记录趋势、样本条件与缺测；不输出健康百分比 |
| 24 小时环形分布 | 保留为后续视图 | V1 先做清楚的分时条；P1 添加可访问的环形切换 |
| 长时间佩戴、熬夜奖励 | 删除激励 | 分享真实观察报告；不奖励熬夜或延长连续使用 |
| 60 分钟关怀提醒 | 改为自选提醒 | 默认关闭；文案是核对记录/休息提示，不能宣称已连续佩戴 |
| Widget、iCloud、Apple Watch | 调整顺序 | Widget P1；后两者不在本次范围 |

### 1.2 三种方案及选择

1. **纯前台记录：**实现容易，但离开 App 后容易缺记录，不满足“尽量自动”。
2. **个人自动化 + App Intents + 补录：本方案采用。**用户首次设置两条自动化，日常尽量无感；仍需真机验证系统状态差异。
3. **私有接口、协议逆向或持续保活：不作为主产品路线。**平台限制、稳定性和维护成本不能靠 UI 或普通侧载消除。

产品承诺使用“自动记录连接事件”，不用“全天无遗漏追踪佩戴”。两个自动化需要用户在系统快捷指令中创建；App 提供向导和自检，不能宣称一键安装个人自动化。

**用户不需要写代码，也不需要日常手填连接/断开时间。**首次只需按向导选耳机、选本 App 已提供的动作、确认立即运行。正常使用是“连接 → 自动开始；断开 → 自动结束并统计”。手动补录是异常兜底；电量/充电标记是另一类信息，不与自动连接记录混为一谈。

## 2. 范围、创新点与交付顺序

### 2.1 V1 必做

| 功能 | 用户价值 | 完成标准 |
|---|---|---|
| 自动化设置向导与接收自检 | 知道是否真的配好了 | 分别收到真实连接/断开动作后标记验证完成，并显示日期 |
| 连接事件记录与四页 UI | 日常无需手填时间 | 闭合区间自动入账；正常等待断开，异常才进入“待确认” |
| 待确认收件箱 | 快速修复漏记 | 可补结束、补开始、拆分、删除误记录；保留来源和修正标记 |
| 手动电量与截图 OCR | 没有公开电量 API 仍可使用 | 三个部件独立确认，识别失败不阻断手填 |
| 充电观察管理 | 看一次充电之后积累了哪些记录 | 开始、补电、结束、撤销；按区间聚合，不删除历史 |
| 清楚的来源与时间 | 避免旧电量误导 | 每个快照显示来源与读数/导入时间 |
| 本地统计与分享卡 | 记录有用且可展示 | 周/月图、待确认数量、观察报告图片、系统分享面板 |
| 自选本地提醒 | 降低漏记成本 | 默认关闭，可撤销，提醒文案不冒充已验证低电量 |
| 数据导出与基本恢复 | 不被工具锁住 | 版本化 JSON 导出/恢复，CSV 导出统计；失败不覆盖原数据 |

### 2.2 值得增加的体验

- **配置完成有证据：**用“连接动作收到 / 断开动作收到 / 最近验证时间”替代一个不可靠的“自动化已开启”开关。长时间没收到事件只显示时间，不直接判定失效。
- **记录修正有上下文：**在一张卡中显示已知开始、未知结束和相邻记录；只给已知边界，不自动填一个看似精确的结束时刻。
- **充电只需一次轻操作：**快捷指令动作、App 内按钮使用同一保存逻辑；提前补电也能记录，用户不必为了统计把电耗尽。
- **双环与电量各司其职：**双环承载时长，盒子承载快照；视觉保留辨识度，语义清楚。
- **“资料不足”也有下一步：**无快照给“记录电量”，未设置给“设置自动记录”，缺端点给“核对记录”，不会只显示空仪表。
- **分享卡写事实：**如“观察期间已记录连接 12 小时 40 分，7 段记录，2 段待确认”，不输出“健康 92%”。

### 2.3 条件功能与暂缓项

| 优先级 | 功能 | 启用门槛与降级 |
|---|---|---|
| P1 | AllMyBatteries 电量桥接 | 真机确认动作输入输出、部件含义和时间；不满足则仍用手填/OCR |
| P1 | Widget、锁屏入口、截图 Share Extension | 核心 V1 通过后引入 App Group，完成既有数据库迁移和并发验证 |
| P1 | Core Motion 摘戴相关信号 | 仅支持机型/系统，独立标注采集覆盖；不能变成永久后台记录承诺 |
| P1 | 可选聆听健康模块 | 用户确实需要聆听暴露统计时才申请 HealthKit；与连接指标独立 |
| P1 | 24 小时圆盘、可比观察趋势 | 同一指标、条件与样本质量可比较；不输出容量健康诊断 |
| P2 | 倾斜水波、粒子、可选个性化外观 | 不妨碍可读性，不增加常驻采集，减少动态效果时全部停用 |
| 暂缓 | 续航预测、剩余可用时间 | 先验证能得到足够可比样本；V1 不用官方时长相减生成预测 |
| 不做 | Apple Watch、跨设备后台采集、云同步、位置轨迹 | 不符合当前“只用 iPhone”的最小范围 |

P1/P2 不是 V1 完成条件。不得为未验证的功能放一个看似可用的生产按钮，再用假值填充。

## 3. 采集方式与数据定义

### 3.1 主流程：两条个人自动化

1. 用户在 App 建立设备槽位，填写昵称，选择型号或“尚不确定”。生成内部 UUID；V1 界面只管理一个当前设备，但记录始终带设备 ID。
2. 向导指导用户在快捷指令建立“所选蓝牙设备连接时”自动化，选择“立即运行”，调用本 App 的“记录耳机连接”，指定设备槽位。
3. 建立对应“断开时”自动化，调用“记录耳机断开”，指定同一槽位。系统版本文案可能不同，实施时以实机为准。
4. 用户实际连接再断开一次。App 根据两条真实事件展示接收结果；点击 App 内测试按钮只验证存储，不得代替蓝牙触发自检。
5. 日常由动作保存小事件。App 重开时重新读取并生成视图，不需要持续计时服务。

App Intent 在执行开始时获取时间；它是**动作执行时刻**，不是硬件给出的精确连接时间。调度延迟无法事后凭空校正。UI 详情写“时间来自自动化执行”。不得把 `Date()` 标成蓝牙底层时间戳。

Intent 应尽量不打开 App、不显示额外确认，并在其安全策略允许下锁屏执行；具体 `authenticationPolicy` 与目标 SDK 逐项核实。文件保护可能使设备重启后首次解锁前不可写；失败要让快捷指令获知，不假报成功。不得为了成功率关闭数据库保护或申请不必要的敏感权限。

### 3.2 指标字典

| 指标 | 定义 | 不表示什么 |
|---|---|---|
| 已记录连接时长 | 已闭合、未被排除的连接区间在所选范围内取并集后的时长 | 佩戴、播放、真实耗电 |
| 连接段数 | 所选范围有正时长交集的有效连接段数量；跨日可在各日出现，总范围统计按 ID 去重 | 从盒子取出次数 |
| 等待断开 | 最近收到开始、尚无结束，且未达到异常规则 | 不是要求用户确认，也不能证明当前仍连接 |
| 待确认记录 | 孤立结束、被新开始打断的旧记录、超过核对阈值或重叠冲突 | 不等于所有尚未结束的记录 |
| 本段待确认跨度 | 最近未闭合开始至当前的墙钟跨度，仅详情可看 | 已确认使用时长，不计图表或环比例 |
| 充电观察时长 | 观察区间内有效连接区间的交集并集 | 电池容量、官方完整循环寿命 |
| 电量快照 | 某来源在某时记录/提供的部件电量 | 当前始终不变的实时读数 |
| 聆听记录（可选） | HealthKit 中有证据的耳机音频暴露区间，按来源筛选并求并集 | 所有听歌、静音佩戴、跨设备总使用 |

今日、7 天、30 天统计统一使用当前选定的本地时区和 `Calendar` 日边界；底层日期存 UTC，事件附采集时区标识用于核对。夏令时的“一天”不能写死为 86400 秒。改变展示时区会重分组，不改原始时间。

### 3.3 事件配对规则

以下 60 秒、12 小时均为**产品默认规则，不是 Apple 行为保证或医学阈值**；先设常量，不做一整套可配置规则引擎。

| 输入 | 处理 |
|---|---|
| 相同事件 UUID 重试 | Store 先查已存 ID；同规范化内容返回原结果，内容不同拒绝并保留原数据；不能声称系统只会调用一次 |
| 同设备、同种来源的连续相同类型事件，间隔 ≤60 秒，期间无反向事件 | 后一条作为疑似重复，不另开段；原始数据保留供核对 |
| start → end，end 晚于 start | 生成一个有效段，时间为动作执行边界；两者仍不证明实际佩戴 |
| start → start，间隔 >60 秒 | 前一段缺结束待确认；后一 start 进入等待断开，不用它充当旧段结束 |
| 没有 start 的 end | 孤立结束待确认，可补开始 |
| 最近 start 尚无 end，距现在 ≤12 小时 | 正常状态“等待断开记录”，无需用户确认；收到 end 后自动闭合入账 |
| 最近 start 超过 12 小时仍无 end | “结束时间待核对”；不把经过的全部时间累计成使用 |
| start/end 同时或 end 早于 start | 不生成负时长或隐含顺序；进入待确认 |
| App 重开，发现未闭合记录 | 按上述等待/异常规则展示，不填重开时间为 end，不声称当前已连接 |
| 闭合记录跨度超过 12 小时 | 自动列为待核对，用户确认或拆分后才计入；这是异常提示，不判断真实使用上限 |
| 人工补录与已有段重叠 | 保存前提示冲突；可编辑/拆分/排除，未解决的重叠段不入总量 |

排序按 `observedAt`；同一设备同一时刻出现不同类型且无法确定顺序时标记歧义，不靠 UUID 排序伪造先后。迟到写入会重算对应设备记录。V1 自动事件没有可验证的硬件时刻，不能解决“自动化本身晚执行且顺序倒置”，这类情况交给用户核对。

手动修正保留原始事件，并保存覆盖值与修改时间。开始/结束都明确的手动段可入统计，但来源显示“手动”或“已修正”。删除使用段默认写排除标记，8 秒内可撤销；不需要复杂审计系统。

`UsageSession.status` 固定为 `confirmed / awaitingEnd / needsReview / excluded`。等待中的段不进已确认总量，也不进“待确认 N 条”提醒数。`reduce` 接收明确的 `asOf` 参数判断阈值，避免业务函数内隐藏读取当前时间；前台展示每分钟重算即可，无须后台计时器。

待确认归属按已知端点：有开始以开始时刻归入日期/观察，只有结束以结束时刻归入；观察边界采用半开区间 `[start, end)`。不把未知跨度分摊到所有日期或观察。详情注明“按已知时间归类”；确实无法归属的更正冲突放全局待确认列表。

**手动段不参与自动事件配对：**手动录入的一对事件携带同一 `manualSessionID`，先按显式 ID 生成段；仅 shortcut 来源参与上述自动序列规则，随后合并两类段做重叠检查。编辑/排除作用在配对后；排除的自动段端点仍视为已消费，不能被拿去配成其他段。拆分后的手动段与旧自动端点即使同刻，也不会触发自动流的顺序歧义。

**迟到事件不能悄悄覆盖人工决定：**更正保存其当时绑定的原始端点 ID。重算后只有端点集合仍匹配，才应用更正；如果新增事件导致端点组合或段 ID 改变，保留该更正，将涉及这些端点的新段设为“原记录发生变化，请核对”，暂不计入。核对页对比旧决定与新边界，用户选择重新应用或撤销更正后恢复统计。未受影响的段照常入账。

### 3.4 充电观察规则

- “盒子已充满”记录一个人工确认的 case=100 快照，并开始观察；左右耳为空，除非用户明确填写。不能顺便把左右耳写成 100。
- 起点可选“盒子已充满”或“从现在观察”；后者明确不是满电起点。不强迫补齐三项电量。
- 已有观察时再次开始，给“记录补电并开始新观察”确认页：旧观察结束原因为补电，新观察开始；不删除旧历史。
- “盒子没电了”只可写 case=0 的人工确认快照，并结束观察；左右耳余量仍可未知。界面不要鼓励为数据质量故意耗尽。
- “结束观察”可选择提前结束、补电、盒子没电、其他；结束原因与起止电量一并展示。
- 连接段跨观察边界时按时间交集归属两段观察，不拆改原始连接段；单个观察中的重叠时间只计一次。
- 样本标签用“起止齐全 / 存在待确认 / 有补电 / 电量条件不全”，不用没有校准依据的置信度百分比。
- V1 展示每次观察中记录了多久，不显示“平均充满可用 XX 小时”。P1 只有相同起止电量条件、无补电、无漏记、使用条件可比的样本才进入个人比较；仍叫“记录时长变化”。

### 3.5 电量数据的事实边界

部件读数允许 0—100 的整数或未知。真实 0 与未知不同，任何非法读数不能静默裁剪成合法电量。不同时间的左、右、盒不能拼成同一个无时间标签的“当前电量”。

优先级是**明确时间与来源的有效读数**，不是一律偏爱自动数据。设备和时间不匹配的截图先确认。历史快照始终叫“最近记录”，显示来源和时间；读数时间未知时写“读数时间未知 · 今日 18:20 导入”。导入发生在现在不代表测量发生在现在。

OCR 流程：PhotosPicker 单图选择 → 本地识别文字 → 建议值与截图对照 → 用户确认部件、时间 → 保存。不能确认部件的百分比只列为候选，不强塞进左耳/右耳/盒子。截图默认不长期保存，确认后的结构化数据足够；保存原图需用户另行选择。V1 不静默截屏或读取系统电池组件。

## 4. 本地模型与接口契约

### 4.1 最小数据结构

除 `UsageSession` 外，以下均为 SwiftData 持久化模型；枚举可以用原始字符串存储，读取时兼容未知值。ID 用 UUID，唯一字段使用 iOS 17 的 `@Attribute(.unique)`，不要误用只在更高版本可用的宏。注意 SwiftData 唯一冲突可能执行 upsert；唯一属性只是最后一道约束，不替代 Store 的查重与内容一致性检查。

| 类型 | 必需字段 | 职责 |
|---|---|---|
| `TrackedDevice` | id、displayName、modelKey?、createdAt、archivedAt? | 内部设备槽位；不依赖蓝牙 MAC |
| `ConnectionEvent` | id、deviceID、kind(start/end)、observedAt、savedAt、source(shortcut/manual)、manualSessionID?、timeZoneID | 原始边界；自动来源的 observedAt 是 Intent 执行时间；手动段显式配对 |
| `SessionCorrection` | id、sessionID、anchorEventIDs、deviceID、startOverride?、endOverride?、excluded、longSpanConfirmed、manualTag?、note?、updatedAt | id=sessionID，一份当前覆盖；anchorEventIDs 为编辑时绑定的端点集合 |
| `UsageSession`（值类型） | id、deviceID、start?、end?、startEventID?、endEventID?、source、status、issue?、manualTag? | 纯函数推导的展示与统计结果，不另持久化一套易漂移总时长 |
| `BatterySnapshot` | id、deviceID、leftLevel?、rightLevel?、caseLevel?、measuredAt?、importedAt、timeBasis、source、resolutionPercent?、userConfirmed | 一个来源的一次快照；部分部件可空 |
| `ChargeObservation` | id、deviceID、startAt、endAt?、startReason、endReason?、startSnapshotID?、endSnapshotID?、conditionsNote?、revision | 时间边界与条件；通过区间运算查询相关使用段；revision 用于安全撤销 |
| `ChargeActionReceipt` | id(requestID)、deviceID、observationID、requestInput、savedAt、status、undoState? | 充电动作去重回执；status 为 applied/undone/deleted；observationID 可是已撤销/删除对象的历史标识 |

`timeBasis` 值：`sourceTimestamp / userSpecified / importOnly`。`source` 电量值：`manual / screenshot / companion`。`resolutionPercent` 缺失表示不知精度，不默认当 1%。

`UsageSession.id`：自动段有开始时取 startEventID，只有结束时取 endEventID；手动段取 manualSessionID。人工补录先保存一对共享 manualSessionID 的 manual 事件，再走 reducer 的手动分支。一个更正保留当前值足够；V1 不实现完整多版本编辑历史。reducer 另返回无法匹配当前端点的更正列表，待确认页不能让这类更正消失。

拆分一个段时：先校验拆分结果；一次保存中排除旧段、创建两对手动事件；新段来源为手动修正。不得先删除旧段再尝试保存新段。修改观察只影响其聚合，不修改事件。

### 4.2 服务接口

以下为接口合同，类型定义与实现放在第 8 节对应文件。签名可为既有工程惯例调整，但必须统一调整调用与测试；不能各页面自己算出不同总量。

```swift
// 纯函数；EventValue/CorrectionValue 是 SwiftData 模型的不可变值副本。
func reduce(events: [EventValue], corrections: [CorrectionValue], asOf: Date) -> SessionReduction
func confirmedDuration(sessions: [UsageSession], in range: DateInterval) -> TimeInterval
func observationSummary(observation: ObservationValue, sessions: [UsageSession]) -> ObservationSummary

// Store 为进程内串行的持久化入口，传值，不跨 actor 传 ModelContext/@Model 实例。
func appendEvent(_ input: EventInput) async throws -> UUID
func saveDevice(_ input: DeviceInput) async throws -> UUID
func listDevices() async throws -> [DeviceValue]
func saveManualSession(_ input: ManualSessionInput) async throws -> UUID
func saveCorrection(_ input: CorrectionInput) async throws
func splitSession(_ input: SessionSplitInput) async throws -> [UUID]
func saveBatterySnapshot(_ input: BatteryInput) async throws -> UUID
func applyChargeAction(_ input: ChargeActionInput) async throws -> UUID
func updateObservation(_ input: ObservationEditInput) async throws
func deleteObservation(id: UUID) async throws
func undoChargeAction(requestID: UUID) async throws
func readSnapshot(deviceID: UUID) async throws -> TrackerSnapshot

// OCR 只给候选，不自动落库。
func recognizeBatteryCandidates(imageData: Data) async throws -> [BatteryCandidate]
```

`EventInput` 携带事件 UUID、设备 ID、类型、observedAt、来源、manualSessionID? 与时区；savedAt 由 Store 写入。Intent 必须在进入等待/存储前取得 observedAt。`TrackerSnapshot` 包含该设备的事件值、更正值、电量快照值和观察值；展示层通过纯函数生成结果。手动录入与快捷动作共用 Store 的校验。

`SessionReduction` 包含 `sessions: [UsageSession]` 与 `unresolvedCorrections: [CorrectionValue]`。`ObservationValue` 包含观察字段以及已解析的 `startSnapshot: BatteryValue?`、`endSnapshot: BatteryValue?`，摘要无需猜测快照完整度。`ObservationSummary` 至少提供 confirmedDuration、sessionCount、needsReviewCount、conditionLabels。

`BatteryCandidate` 包含识别文字、候选整数、部件建议（可空）和图片中的文字框；识别置信度只供候选排序，不能当作电量准确率展示。`EventValue` 等 Value 类型逐字段映射对应存储模型，不携带 ModelContext。原始事件查重比较设备、类型、observedAt、来源、manualSessionID 与时区；不比较 Store 新生成的 savedAt。

`ManualSessionInput` 包含 id（manualSessionID）、deviceID、start、end、tag?、note?；`CorrectionInput` 对应更正字段；`BatteryInput` 对应快照字段；`ChargeActionInput` 包含 requestID、deviceID、action、occurredAt、可选部件读数。action 枚举固定为 `startFull / startNow / topUpAndRestart / end`；end 必带结束原因。开始观察/结束旧观察/写相关快照/写回执作为一次保存操作，失败回滚整个操作。充电动作重复 requestID 先比较回执 requestInput；内容不同拒绝，相同且 applied 才返回既有 observationID。已 undone/deleted 的请求返回“原操作已撤销/删除”，不重新执行。同一次 UI 提交重试复用 requestID；不同用户操作各用新 ID。

`DeviceInput` 对应设备可编辑字段；`SessionSplitInput` 包含旧 sessionID、当前端点 ID 和两个不重叠的 `ManualSessionInput`，Store 一次保存排除旧段与两个新段。`ObservationEditInput` 包含 id、预期 revision 与新边界/原因/备注；更新时校验时间顺序以及同设备观察不重叠。手动段重复提交同 manualSessionID 时复用既有结果，内容冲突则拒绝，不再追加两条新事件。

充电撤销只支持本设备最新一次、尚未撤销且相关观察 revision 未改变的动作；回执的 `undoState` 保存操作前观察值、新建观察 ID、新建快照 ID、操作后 revision。撤销在一次保存中恢复旧观察、移除本次新建观察及本次新建快照、标记回执 undone 并清空 undoState；不碰任何连接事件。后续已发生充电操作或观察编辑时不自动回滚，提示使用观察编辑。删除观察将以它为结果的回执标记 deleted 并清空 undoState，保留去重标识防止旧请求重试重建；使用历史和独立快照保留。

### 4.3 App Intents

| 类型名 / 中文动作 | 参数 | 行为 |
|---|---|---|
| `RecordConnectionIntent` / 记录耳机连接 | `TrackedDeviceEntity` | 写 start，成功后返回简短结果 |
| `RecordDisconnectionIntent` / 记录耳机断开 | 同上 | 写 end，不能自行补 start |
| `RecordBatteryIntent` / 记录耳机电量 | 设备、左?、右?、盒?、读数时间? | 至少一项合法值；缺时刻标明时间未知/导入时间 |
| `MarkCaseChargedIntent` / 记录盒子充满 | 设备、允许结束旧观察并重开（默认 false） | 无旧观察则开始；有旧观察且用户未预设同意时返回明确提示，让用户在 App 记录补电；同意后原子关闭旧观察并重开 |

提供 `AppShortcutsProvider` 暴露动作。连接/断开动作 `openAppWhenRun = false`，动作只做校验、小量数据库写入并返回，不带 OCR、UI 或长任务。锁屏参数均应由用户事先固定，避免执行时再弹参数选择。可选快捷动作不代替个人自动化触发器的设置。

V1 不另建 App Intents Extension；主 App target 可处理其动作。Store 缓存同一 ModelContainer，使用独立 actor/ModelActor 串行写入；不要把 MainActor 标注误当成跨进程锁。App 激活、动作写入后和页面手动刷新时读取最新数据。后续若添加独立扩展，必须重新验证跨进程存储，不直接复用“单进程已测”的结论。

### 4.4 失败、迁移与导出

- 保存成功才更新成功提示、触觉与自检标记。数据库不可用时保留错误上下文，用户看到“本次记录未保存，请解锁后重试”；不在后台无限重试。
- SwiftData 使用版本化 Schema；已有工程先识别是否有真实数据，再编写迁移，不能删库重建。
- JSON 导出包含 schemaVersion、exportedAt、设备、原始事件、更正、快照、观察和充电动作回执；恢复先完整解析/校验，再按 ID 合并，一次失败不部分覆盖。同 ID 同内容跳过；同 ID 不同内容默认保留当前本机版本并在预览列出冲突数量，不凭文件日期覆盖人工修正。正常记录引用的设备/端点/观察必须存在于最终合并集合；回执状态为 undone/deleted 时，其 observationID 是历史标识，允许对应观察已不存在。其他缺失引用拒绝导入并解释。恢复后重新计算派生统计；不依靠备份恢复过期的撤销 UI。
- CSV 导出为派生记录，包含来源、状态、时间、时区与时长；未知留空，不补 0。导出通过系统分享面板，生产 UI 不展示内部路径。
- 删除观察只删除观察和其关联引用；快照与使用历史保留。删除设备须明确解释历史影响；V1 首选归档设备，避免引入批量删除流程。

## 5. UI 视觉规范

### 5.1 设计方向

继承原方案“深空、薄玻璃、双环、透明盒子、圆角数字”的辨识度。整体安静、信息明确；青蓝用于连接时长，绿青用于电量快照，橙色用于待确认与低电量读数。不能把光晕动画当作设备实时在线的证据。

默认跟随系统外观，设置可选深色/浅色。设计验收以深色为主，同时检查浅色与辅助功能。标题和数字精致，来源说明保持足够字号，不沿用原稿的 11pt 半透明标签。

### 5.2 Design Tokens

| Token | 深色 | 浅色 | 用途 |
|---|---|---|---|
| `background` | #0D1219 | #F4F6FA | 主背景，顶部可有轻微径向渐变 |
| `surface` | #17212D | #FFFFFF | 信息卡片主体 |
| `textPrimary` | #F3F6FA | #152236 | 标题、主要数字 |
| `textSecondary` | #AAB7C7 | #526176 | 解释与来源 |
| `textMuted` | #92A1B5 | #64748B | 次级信息，仍需可读 |
| `accentText` | #79AEFF | #185FC8 | 可点击文字与选中项 |
| `primaryFill` | #185FC8 | #185FC8 | 主按钮背景，白色文字 |
| `warningText` | #FFC573 | #925100 | 待确认、过期或低电量说明 |
| `destructiveText` | #FFB4AB | #B3261E | 删除动作，配文字 |
| `durationRing` | #0A84FF → #5E5CE6 | 同色，另配文本 | 时长图形，不直接承载小字 |
| `batteryFill` | #30D158 → #00B8C4 | 同色，另配文本 | 电量容器填充 |
| `hairline` | 白 16% | 黑 10% | 装饰边缘；不能单独作为控件边界 |

- 页面左右边距 20pt；卡片内边距 20pt；卡片间距 16pt；内部组间距 12pt，标签间距 8pt。
- 卡片圆角 24pt；小卡 16pt；按钮 14pt；主按钮高度至少 50pt；所有操作目标至少 44×44pt。
- 页面标题约 28pt semibold；主数字 40pt rounded bold，使用 `.monospacedDigit()`；二级标题 20pt；正文 16pt；说明 13pt。采用可缩放系统字体，不锁死 Dynamic Type。
- 固定信息卡使用实色 surface；Hero、顶部胶囊与弹层可叠薄材质，边缘 0.5pt 高光。开启“降低透明度”自动改实色，文字放在稳定背景上。
- 白字 + #185FC8 按钮对比度约 5.98:1；文字颜色按上述实色背景设计。半透明叠加后的最终效果需另验，不把 token 对比度当全页无障碍通过。
- 图标优先系统 SF Symbols：house.fill、clock.arrow.circlepath、chart.bar.fill、battery.100.bolt。耳机图标在目标系统验证可用性，未知型号用通用耳机轮廓。

### 5.3 双环：保留造型，不伪装电量

**默认无官方参考时：**两道轨道作为无刻度图形，中央显示上次完整连接段时长；下方直接列“今日已记录连接”和“本次观察已记录连接”。首次无记录显示“等待第一段记录”，不显示 00:00:00 正在运行。

**用户已确认型号，且型号续航参考有 Apple 来源与测试条件时：**允许开启“播放参考刻度”。外环=当前观察中的已确认连接时长 / 总播放参考；内环=最近一个完整连接段时长 / 单次播放参考。必须同时显示分子名称、参考值，并常驻说明：**“连接记录与播放参考口径不同；圆环不是电量。”**不展示达成率百分比、不显示剩余小时、不由环色判断健康。比例最多画到 100%，数值仍显示真实时长，超出标“超过参考刻度”。

**最近连接事件正在等待断开时：**内环变虚线无刻度，中央写“等待断开记录”，下方显示“开始已自动记录 · 18:10”；不要求用户操作。超过异常阈值或被下一次连接打断的旧段才显示“结束时间待核对”。跨度只在展开详情中展示，不做持续增长的能量进度。外环只包含已确认段。

无当前充电观察时，外环仅作轨道，不借上次观察冒充当前观察。参考型号不明时不默认 30h；不得复制原稿型号表作为未经核查的常量。参考刻度是可关闭的对照，不是核心使用门槛。

### 5.4 充电盒容器

- 使用原创简洁盒子轮廓与半透明内层；以 SwiftUI Shape/Canvas 绘制即可，不引入 3D 引擎或外部付费资产。
- 只有存在 caseLevel 的已确认快照时填充水位，旁边写“盒子 42% · 最近记录”，同时显示时间与来源。42% 为布局示例，不是默认值。
- 旧快照仍可显示，但明确写“历史读数”；时间未知显示未知。容器不能因时间流逝自行下降。
- 无 caseLevel：轮廓 + “尚无盒子电量”，按钮“记录电量”。左/右读数单独放下面，未知用“—”。
- 静态液面为 V1 默认。保存新快照时短暂平滑过渡；粒子、手机倾斜与持续水波属于 P2，默认不启用。
- <20% 的真实快照可用橙色，标签写“最近记录低于 20%”，不能据此声明当前电量告警。

### 5.5 动效、触觉与可访问性

| 场景 | 行为 |
|---|---|
| 切换卡片详情 | 0.2—0.3 秒淡入/高度过渡；可用原稿 spring(0.42, 0.72) |
| 手动保存成功 | 一次 success 触觉；后台动作不震动、不播放声音 |
| “盒子已充满” | 普通点击打开确认页；可选长按 0.8 秒快捷确认，首次解释且提供等价按钮 |
| 删除或撤销 | 普通点击与滑动操作均可；删除后 8 秒撤销条，详情仍可恢复排除状态 |
| 前台收到新记录 | 状态胶囊轻微过渡，随后静止；不持续脉冲暗示在线 |
| 减少动态效果 | 移除粒子、波浪、缩放、旋转与循环呼吸，保留必要的即时状态变化 |

Pinch 和长按可以作为高级捷径，但每个功能必须有可见按钮。大字体时双栏改竖排、主环缩小或转为数字摘要，不裁剪重要文字。VoiceOver 能读出每个数据的名称、值、来源、时间和未知原因。颜色、环形或水位不能成为唯一信息载体。

## 6. 四个页面与完整交互

以下线框展示布局关系，数值均为**设计样例**；生产首次启动不得预置这些记录。

### 6.1 总览 `DashboardView`

```text
总览                                      设置
我的 AirPods                 最近收到断开 · 18:42
┌────────────────────────────────────────────┐
│              双环时长视图                  │
│           上次已记录连接 48 分钟           │
│   今日已记录 2小时18分    本次观察 5小时18分 │
│   [查看详情]                 [简洁视图]    │
└────────────────────────────────────────────┘
[今日连接 3 段]             [待确认 1 条 →]
最近电量                 左 70%  右 —  盒 42%
截图确认 · 18:20 读数                   记录电量
当前充电观察     昨日 21:10 开始       查看 →
[补录连接记录]                     [记录充电]
           总览 / 记录 / 统计 / 充电盒
```

阅读顺序：记录状态 → 核心时长 → 待确认 → 最近电量 → 快捷操作。总览不堆满所有图表。

- 未配置：顶部横条“完成两步设置，开始自动记录”，主按钮“设置自动记录”；允许先手动体验。
- 最近已收 start 无 end：胶囊“18:10 开始已自动记录”，环中心“等待断开记录”，无需确认；只有异常时出现“核对这段记录”。不显示未经当前验证的绿色“正在佩戴”。
- 设置完成仅表示曾验证成功，详情保留最近验证时间与最近两类事件时间。
- 点击最近电量进入快照详情；三项来自不同快照时每项有各自时间，不能压成单一时间行。
- 简洁/详细切换用可见按钮；可以附加原稿 Pinch，不隐藏入口。

### 6.2 记录 `SessionHistoryView`

```text
记录                                      ＋
[全部] [待确认 1]             设备：我的 AirPods
今天                 已记录连接 2小时18分
│ 18:10 — 18:42     32分钟      自动化
│ 15:30 — ？        结束待确认  [补结束]
│ 09:00 — 10:46     1小时46分   手动修正
昨天                                      …
```

保留原稿纵向导轨。行内图形为按真实时长缩放的条段，不生成音乐波形。时长条只用于比较，与可读时间并存。

点击一行展开：原始事件、动作执行时间、来源、用户修正、手动标签、电量快照点。没有快照时不画耗电曲线；两个离散快照可显示两点，任何连接线均标为视觉连接，不当作连续采样。

滑动提供“编辑/排除”；更多菜单提供同样入口。编辑面板显示已知边界和相邻记录，结束时间未填时保存按钮说明需要输入，不自动取打开面板的当前时间。用户主动点击“结束时间设为现在”才写现在并标人工修正。

手动标签仅“通勤 / 工作 / 运动 / 其他”等用户选择，不从时长、时间段或耳机型号自动推断。

### 6.3 统计 `StatisticsView`

```text
统计                         [7天] [30天]
统计口径：已记录连接               了解 →
本期 12小时40分       18 段       待确认 2 条
┌──────── 每日已记录连接柱状图 ────────┐
│ 按日期的真实数据；无记录留空并解释     │
└─────────────────────────────────────┘
分时分布                            查看表格
充电观察对比                [全部] [条件齐全]
10/08—10/10     8小时20分    有补电
10/05—10/08    10小时12分    存在待确认
```

- 主图用 Swift Charts；点选日期查看时长、段数、待确认数量。无数据写“该日没有可计入的连接记录”，不能推论当天没使用。
- 平均每日 = 所选日期范围总时长 / 日期数，包括无记录日期，并明确“按整个所选期间平均”；不偷换成仅活跃日均值。
- 最长单段只取已确认闭合段；被排除与异常未确认段不参与。
- V1 分时分布用 24 小时条形/网格，按实际区间交集计算。P1 再添加原稿圆形分布盘；两者都提供表格替代。
- 观察对比默认展示事实和条件，不输出“略微老化”“新机水准”“健康 92%”。
- 官方播放续航只能出现在单独的参考说明中，写型号、功能状态、Apple 来源和检索日期；不能混作图表健康基线。

### 6.4 充电盒 `CaseChargeCycleView`

```text
充电盒
┌──────────── 透明盒子容器 ────────────┐
│               盒子 42%              │
│           最近记录 · 18:20           │
│         截图确认       [记录电量]     │
└─────────────────────────────────────┘
左耳 70%                         右耳 —
当前观察       10/10 21:10 至今
已记录连接 5小时18分     7 段     待确认 1 条
[盒子已充满]   [记录补电]   [结束观察]
历史观察列表                         查看 →
```

首次为空容器，主按钮“开始一次观察”。开始表单只需时间与原因；电量、降噪/使用条件备注可选。结束表单显示结束原因、未确认记录提醒、起止电量完整度；允许带缺测结束，只是不进入可比样本。

结束成功后以 sheet 展示观察摘要：期间、已记录连接、段数、待确认数、补电/缺测标签、来源说明。按钮“生成分享卡”由用户主动点；不自动保存相册或发送社交平台。

分享卡保留原稿磨砂深色、精致排版与仪式感：1080×1350 的 4:5 图片，标题“我的耳机记录”，使用 SF 圆角大数字与真实时长条背景。包含观察时间、统计口径、待确认数；设备昵称和具体时间可隐藏。系统分享前预览，不能出现示例数据或对健康的结论。

### 6.5 设置与引导

- 首次引导三屏以内：说明“记录连接”；建立设备；设置两条自动化与真实自检。底部始终允许“稍后设置”。
- 设置项：设备、自动记录设置、自检历史、电量来源、外观与动效、提醒、数据导出/恢复、隐私说明。
- 型号可选未知；没有准确型号也能正常记录。不要要求用户填序列号或 MAC。
- 启用提醒时再申请通知权限。通知拒绝后界面仍可设置规则，但需清楚显示“系统通知未开启”。
- V1 的 OCR 使用 PhotosPicker，不申请整个相册读取；生成分享图先走分享面板。
- 健康、动作与健身、蓝牙等权限只在对应功能确实实现且用户打开时申请，不在首屏打包请求。

### 6.6 必须具备的页面状态

| 状态 | 展示文案/内容 | 可执行入口 |
|---|---|---|
| 尚未设置自动化 | “完成两步设置，开始自动记录” | 设置 / 稍后 |
| 自检仅收到连接 | “连接动作已收到，尚未收到断开动作” | 查看断开设置 |
| 首次零记录 | “等待第一段记录” | 自动化向导 / 手动补录 |
| 最近收到开始、正常等待结束 | “开始已自动记录，等待断开” | 查看详情；无需确认 |
| 缺结束且触发异常规则 | “结束时间待核对” + 已知开始时刻 | 核对记录 |
| 孤立结束 | “缺少开始时间” | 补开始 / 排除 |
| 所有电量未知 | 三项“—”，空盒子轮廓 | 记录电量 |
| 历史快照/未知读数时间 | 明示时间或“读数时间未知” | 记录新电量 |
| OCR 歧义或失败 | 原图与候选值，未确认部件保持空 | 修改 / 手动填写 / 取消 |
| 观察中含漏记或补电 | 条件标签与待确认数量 | 核对 / 仍结束观察 |
| 保存失败 | “本次记录未保存” + 可理解原因 | 重试 / 返回 |
| 可选来源没有数据 | “尚未获得可用数据” | 查看设置 / 手动记录 |
| 图表没有可计入记录 | 空坐标/简洁空态，解释统计口径 | 查看记录 |

## 7. 可选能力的独立验证合同

这些是研究结论转化出的扩展门槛，不可当作已经实现的 API。

### 7.1 AllMyBatteries 桥接

其开发者官网展示连接 AirPods 后刷新耳机与盒子电量；GitHub 也有依赖该 App 的电量提醒快捷指令。这说明它值得测试，**没有证明第三方能获得稳定的左右耳/盒子完整结构**。

实施者须在用户接受安装该第三方 App 后核对：实际动作名、返回类型、支持部件、读数时间、缓存语义、锁屏行为、系统版本与免费/付费限制。保存脱敏输出样例与版本，不猜测 API。若只返回耳机整体值，不能复制到左右耳；V1 模型不支持整体值时保留在桥接诊断结果，不写错误部件。

通过后由用户的快捷指令将确认可解释的值传入 `RecordBatteryIntent`；来源为 companion。无法得到读数时间则标未知，不能因为自动调用就标“实时”。外部 App 卸载、动作出错、付费条件变化时，核心工具仍能用。

### 7.2 Core Motion

`CMHeadphoneMotionManager` 可对受支持设备提供运动数据；部分摘戴相关 API 与系统版本有关，实施前核对 availability。它提供的观察覆盖与蓝牙自动化不同，作为独立信号保存，不用运动采样空白推断摘下。

不为了此功能引入静音播放，不把一个耳机提供的运动数据当作只有单耳佩戴。V1 主数据模型不预先加入整套姿态或健康推断，验证后另写小型迁移。

### 7.3 HealthKit

只在用户选择“聆听健康”时加入，并说明目的。耳机音频暴露样本可以提供有记录的区间，但可能延迟、重叠、没有唯一设备信息，不能充当全面的佩戴历史。

使用锚定查询保存进度、按 HealthKit UUID 去重并处理删除；区间求并集，不直接累加所有 sample 时长。需要时解析 quantity series，不能把粗粒度容器的完整跨度一律当连续播放。来源无法确定属于所选耳机时进入独立来源筛选，不偷偷合并。读取不到数据不能区分没有样本与没有读取权限；锁屏数据库不可读时延后重试，不清空既有数据。

### 7.4 Widget 与 Share Extension

先确保真实签名配置支持 App Group；不要硬编码他人的 Team ID 或 group identifier。把既有 SwiftData 数据安全迁移至共享容器，App、Widget、Share Extension 读取同一 schema，验证不同进程写入、刷新与冲突。没有能力配置时保留 V1 主 App，不以清库作为降级。

Widget 展示“最近记录”“今日已记录连接”“待确认”，附刷新时间；系统不保证精确每秒刷新。锁屏入口可以打开记录页或执行预设明确动作。Live Activity 不作为永久后台执行/蓝牙扫描的解决方案。

### 7.5 通知的边界

V1 自选提醒默认关闭。用户选择记录核对/休息提醒后，可以在收到 start 时安排本地通知，在 end 时尽快撤销；即使撤销因系统延迟未及时发生，也不会写错记录。文案如“有一段连接记录尚未结束，方便时核对一下，也可以休息片刻”，而非“你已连续佩戴 60 分钟”。

不得根据“已用时长超过官方续航 85%”发低电量警报。真正低电量提醒须有明确时间的有效电量来源并注明记录时间，默认不重复通知同一快照。

## 8. 目标文件结构与职责

以下为新项目建议路径；如果已有代码，先匹配既有结构，只调整相关文件，不整体重构。路径均相对于待开发仓库。

```text
AirPodsTracker/
  App/
    AirPodsTrackerApp.swift          # 入口、容器、前后台刷新
    ContentView.swift                # 四 Tab 与设置入口
  Core/
    Models.swift                     # 6 个 SwiftData 模型、版本 Schema
    DomainValues.swift               # 输入值、快照值、UsageSession、状态枚举
    TrackerStore.swift               # 串行持久化与事务边界
    SessionReducer.swift             # 事件配对与更正，纯函数
    IntervalMath.swift               # 并集、交集、日/小时拆分
    ObservationSummary.swift         # 充电观察聚合
  Intents/
    TrackingIntents.swift             # 4 个动作
    TrackedDeviceEntity.swift         # 设备参数查询与展示
    TrackerShortcuts.swift            # AppShortcutsProvider
  Features/
    Setup/AutomationSetupView.swift   # 设置步骤、真实接收自检
    Dashboard/DashboardView.swift
    History/SessionHistoryView.swift
    History/SessionEditor.swift
    Statistics/StatisticsView.swift
    Charging/CaseChargeCycleView.swift
    Charging/ObservationEditor.swift
    Battery/BatteryInputSheet.swift
    Battery/BatteryOCRService.swift
    Battery/BatteryImportView.swift
    Settings/SettingsView.swift
    Sharing/ObservationShareCard.swift
  UI/
    DesignTokens.swift
    DualDurationRing.swift
    BatteryVessel.swift
    RecordStatusCapsule.swift
    EmptyStateView.swift
  Services/
    NotificationService.swift
    ExportService.swift
  Resources/
    Assets.xcassets                  # 语义颜色、图标资源
    Localizable.xcstrings            # 中文首发文案
    ModelReferences.json            # 可为空；有来源/条件的型号参考
AirPodsTrackerTests/
  SessionReducerTests.swift
  IntervalMathTests.swift
  TrackerStoreTests.swift
  BatteryInputTests.swift
  ObservationTests.swift
  ExportTests.swift
docs/
  implementation-status.md
  device-validation.md
```

不用为每个按钮建 ViewModel。逻辑保留在纯函数与 Store，视图只管理展示/表单状态；复杂度增长再拆文件。`ModelReferences.json` 每条包括型号 key、单次/总播放参考、适用条件、sourceURL、verifiedAt；空表是合法情况。

## 9. 分步实施计划

每个任务输出可审阅结果。修改业务规则先写有意义的失败测试，再实现并运行；颜色、文案和简单布局不写镜像测试，用 Preview/模拟器检查。若既有仓库有测试约定沿用它。不得把“模拟器通过”登记为“锁屏真机通过”。

**先交付 T1—T3 的可用里程碑：**真实自动化 → 保存 → 自动配对 → 简单记录页。先证明正常使用无需手填时间，再继续完成 OCR 与精细 UI。完整 V1 是 T1—T7，不要求等视觉全部完成才验证采集。

### T1：建立本地可信数据底座

**文件：**App 入口、`Core/Models.swift`、`DomainValues.swift`、`TrackerStore.swift`；测试 `TrackerStoreTests.swift`。

**输入/输出：**定义第 4 节全部基础类型和 Store 接口；后续任务只使用这些值与方法。

- [ ] 检查现有工程、最低系统、签名与已有数据；若新仓库则建立 iOS App 和 unit test target，写运行说明。
- [ ] 写测试 `testRepeatedEventIDCreatesOneEvent`、`testConflictingEventIDDoesNotOverwriteOriginal`、`testManualSessionSaveIsAtomic`、`testInvalidDeviceRejectsWrite`：同 ID 同内容只留一个；同 ID 不同内容拒绝且原字段不变；非法手动输入不留半段；未知设备不写入。
- [ ] 实现主 App 的版本化 SwiftData 容器与串行 Store；`readSnapshot` 返回不可变值。运行上述测试。
- [ ] 测试重开容器仍能读出已存记录，以及真实失败被上抛而不是返回成功；生产无内存数据库兜底。
- [ ] 建立四 Tab 空页面、中文文案和设计 token；不预置真实库示例数据。

**验收：**可保存/重读事件，错误路径可见；界面空态可打开。已有用户数据的项目必须附迁移测试。

### T2：跑通个人自动化与自检

**文件：**`Intents/`、`Features/Setup/AutomationSetupView.swift`、App 激活刷新。

**输入/输出：**使用 `appendEvent` 与 `readSnapshot`；产出真实 start/end 事件和双步骤自检状态。

- [ ] 实现设备 Entity、连接/断开 Intent 和 AppShortcutsProvider，时间在 Intent 入口取得。
- [ ] 确认动作可在快捷指令中搜索；预填设备参数，不强制打开 App。
- [ ] 实现三屏以内向导；“真实蓝牙自检”与“手动测试保存”结果分开。
- [ ] 在真机用两条个人自动化各触发一次，记录 iOS、机型、AirPods 型号/固件、动作时间与入库结果。
- [ ] 验证前台、后台、锁屏、强制退出、重启后未首次解锁、低电量模式；逐项登记成功/失败/未测，不猜系统行为。

**验收：**至少有一台真实 iPhone 的正常连接/断开自动化闭环证据；否则本任务标“待真机验证”，继续完成可验证的 UI 和纯逻辑，不声称自动采集已交付。

### T3：连接状态机、补录与统计

**文件：**`SessionReducer.swift`、`IntervalMath.swift`、History、Statistics；测试 `SessionReducerTests.swift`、`IntervalMathTests.swift`。

**输入/输出：**实现 `reduce` 与 `confirmedDuration`；为所有页面提供同一 `SessionReduction`、`UsageSession` 和总量。

- [ ] 写并通过下表用例，禁止各视图另写 `(end ?? Date()) - start` 累加逻辑。
- [ ] 实现第 3.3 节配对、重复识别、长跨度核对、修正与排除；未闭合不计入总量。
- [ ] 实现编辑、手动补录、冲突提示、拆分和撤销；所有保存共用 Store。
- [ ] 完成记录时间轴、待确认筛选、7/30 天统计与来源详情。

| 测试名 | 精确断言 |
|---|---|
| `testClosedSession` | 09:00 start → 10:00 end = 3600 秒 |
| `testOpenSessionIsNotConfirmed` | 仅 09:00 start，总量始终 = 0；asOf 10:00 为 awaitingEnd、不增加待确认计数，asOf 22:00 为 needsReview |
| `testDuplicateStart` | 09:00 start、09:00:20 start、10:00 end = 1 段、3600 秒 |
| `testMissingEndBetweenStarts` | 09:00 start、11:00 start、12:00 end：旧段待确认；只计 3600 秒 |
| `testOrphanEndAndAmbiguousTie` | 孤立 end 和同一时刻的 start/end 均不生成正时长有效段 |
| `testLongSpanNeedsConfirmation` | 13 小时闭合段核对前计 0，人工确认后计 46800 秒 |
| `testCrossMidnight` | 本地 23:30→次日 00:30，两日各 1800 秒 |
| `testDSTDayBoundary` | 使用有夏令时时区真实转换日，Calendar 日边界正确，区间总秒数守恒 |
| `testOverlapConflict` | 手填重叠段须解决冲突后才入账；并集计算不能把重叠分钟加两次 |
| `testCorrectionSurvivesRelaunch` | 补结束后重读仍保留修正；原始事件未被覆盖 |
| `testManualPairsDoNotRewireAutomaticEvents` | 自动 09:00→10:00 被拆分成两个人工段，自动端点不参与人工配对，排除旧段后总量仍为 3600 秒 |
| `testLateEventPreservesCorrectionForReview` | 先收到孤立 end 并补 start，后写入更早的真实 start；旧更正仍可见，相关新段待核对且不重复计时 |
| `testLateEventDoesNotUndoExclusion` | 已排除段遇到改变端点组合的迟到事件，不能自动恢复为有效时长 |
| `testUnknownBoundaryBelongsToKnownEndpoint` | 观察 10:00→12:00 内的 11:00 孤立 end 计待确认 1 条；不扩散到相邻观察 |

**验收：**测试通过；总览、记录、统计相同范围结果一致；待确认记录有明确可操作入口。

### T4：真实电量快照与 OCR

**文件：**Battery 功能、`BatteryVessel.swift`、`TrackingIntents.swift` 电量动作；测试 `BatteryInputTests.swift`。

**输入/输出：**实现 `recognizeBatteryCandidates`；确认表单通过 `saveBatterySnapshot` 写入。

- [ ] 写测试：nil 与 0 不同；-1/101 拒绝；全部为空拒绝；缺读数时间保留未知；导入时间不覆盖源时间。
- [ ] 完成手动表单与“最近记录”三部件展示；不同快照时间分别显示。
- [ ] 用 iOS 17 支持的 `VNRecognizeTextRequest` 做本地 OCR；候选带识别文字/位置供对照，不硬编码系统截图布局。
- [ ] 识别结果先进入确认页；百分比不明归属、多设备、乱码、无百分比都可转手动输入。
- [ ] 用脱敏真实截图验证已知布局；再检查旧截图与读数时间未知状态。模拟器样例不代替真机截图兼容证明。
- [ ] 实现电量 Intent 参数校验；只接收到可解释数据时写入，不预写 AllMyBatteries 假接口。

**验收：**可从选图到确认保存完成一次闭环，失败可手填；盒子水位仅由确认读数控制。

### T5：充电观察与四页视觉整合

**文件：**`ObservationSummary.swift`、Charging、Dashboard、UI 组件；测试 `ObservationTests.swift`。

**输入/输出：**实现 `applyChargeAction` 与 `observationSummary`；消费 T3/T4 的可信数据。

- [ ] 写测试 `testSessionCrossingObservationBoundary`：09:00→11:00 会话，观察 10:00→12:00 仅计 3600 秒。
- [ ] 写测试 `testChargeActionAtomicAndIdempotent`：同 requestID 不重复开观察；新观察失败时旧观察不被提前结束；`testDeleteObservationKeepsHistory`：删除后使用记录数量不变；`testChargeUndoChecksRevision`：最新未变更动作可撤销，观察已被编辑时拒绝回滚。
- [ ] 实现开始/补电/结束/撤销及样本条件标签；盒子 100 或 0 不改变左右耳未知值。
- [ ] 完成双环、胶囊、液体盒子、今日摘要和四页布局；无参考时无刻度，不默认 30h。
- [ ] 接入可见按钮、长按捷径、保存触觉与减少动态效果，检查第 6.6 节全部状态。

**验收：**UI 保留原稿视觉主题，四页数据一致；修改观察不改变原始连接历史。

### T6：分享、导出与自选提醒

**文件：**`ObservationShareCard.swift`、`ExportService.swift`、`NotificationService.swift`、Settings；测试 `ExportTests.swift`。

**输入/输出：**以 T5 摘要生成分享图片；以 Store 快照生成版本化 JSON/CSV，不另算指标。

- [ ] 实现分享卡和系统分享面板，检查长昵称、长时长、隐藏隐私字段与待确认文案。
- [ ] 写 `testExportImportRoundTrip`：导出/恢复后事件、修正、快照、观察数量及 UUID 一致，包含已撤销/删除动作的回执也可恢复，重试旧 requestID 不重建；`testInvalidImportDoesNotChangeStore`：错误 schema 或非法时间不改变原库。
- [ ] 实现数据恢复预览与确认：显示设备和记录数、合并原则；未识别高版本格式拒绝恢复并保留文件。
- [ ] 实现默认关闭的提醒开关；启用才请求通知。start 安排/end 撤销，以设备/段 ID 标识防重复。
- [ ] 验证通知拒绝、已安排后及时断开、旧快照不重复提醒；不做“85% 官方时长”低电量推测。

**验收：**分享预览内容正确；导出可恢复；通知不是核心功能的前置门槛。

### T7：交付验证与条件扩展登记

**文件：**`docs/implementation-status.md`、`docs/device-validation.md`，必要的小范围修正。

- [ ] 运行与本次改动相关的单元测试和 iOS build；只在新失败/更改后扩大复测。
- [ ] 检查至少小屏与大屏 iPhone、深浅色、最大辅助字号、VoiceOver、减少动态效果、降低透明度、横竖屏布局退化。
- [ ] 真机执行第 10 节场景并保存证据：平台版本、步骤、实际结果、日志/截图，不收集隐私截图进 Git。
- [ ] 若具备条件，仅做 AllMyBatteries 能力验证，写清输出结构与门槛是否通过；未经验证不启用桥接。
- [ ] 更新状态表：已实现、已通过静态/单测/模拟器、已通过真机、未测/受限分别列出。

**验收：**交付源码、可复现构建说明、验证记录与已知限制。没有签名材料不伪造已安装 IPA；若用户另行要求安装包，再按真实签名环境交付。

## 10. 验证方法与发布门槛

### 10.1 macOS 命令模板

先发现真实项目与可用模拟器，再把模板的名称替换为实际值。不要复制一个不存在的模拟器 UDID，也不要在 Windows 上声称运行过 Xcode。

```bash
xcodebuild -list -project AirPodsTracker.xcodeproj
xcodebuild -showdestinations -scheme AirPodsTracker -project AirPodsTracker.xcodeproj
xcodebuild test -project AirPodsTracker.xcodeproj -scheme AirPodsTracker \
  -destination 'platform=iOS Simulator,id=<实际可用的模拟器UDID>'
xcodebuild build -project AirPodsTracker.xcodeproj -scheme AirPodsTracker \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

如果已有工程用 workspace，改用它的实际 workspace 与 scheme。测试通过的依据是退出码与测试结果，不是仅生成日志文件。无签名 generic build 只证明编译，不证明真机安装或 App Intents 后台行为。

### 10.2 真机验证矩阵

| 场景 | 必须观察的结果 |
|---|---|
| 正常连接/断开，主 App 前台与后台各一次 | 两事件到达、时刻来源正确、一段闭合，不打断音乐 |
| 锁屏后连接/断开 | 动作是否到达、是否要求解锁；失败能辨认 |
| 强制退出主 App | 实测系统是否执行动作，不能预先承诺 |
| 重启且未首次解锁 | 不假报成功；首次解锁后正常重试不产生重复 |
| 低电量模式、离线 | 本地功能可用；记录受系统影响则说明 |
| 只到一个事件/人为重复执行 | 待确认或去重，不连续夸大时长 |
| 自动切换到其他设备 | 不把其他设备的使用时间自动算入本机证据 |
| 关自动入耳检测、单耳、空盒/盒子远离手机 | 不把“连接”“运动数据”“盒子可读”混成一个状态 |
| 来电/播放器暂停/切换音频输出 | 不为了记录抢占音频，不假造佩戴/播放结论 |
| 用户修改时钟/时区 | 无负时长；歧义可修正，按选定时区重分组 |
| OCR 旧图、多设备、左右混淆 | 提示确认，不直接存成新实时快照 |
| 删除观察、重复充满、提前补电 | 历史保留；重复请求无双观察 |

上线最低要求：T1/T3/T4/T5/T6 的业务测试通过；四页主要状态无阻塞；真实 iPhone 的基本自动化闭环通过；其余系统场景实测结果在设置说明中有准确表述。若没有真机，只能交付“待真机验证版本”。不为了达到“全部绿色”修改统计定义。

## 11. 给执行 Codex 的完成清单

- [ ] 原稿四页、双环、状态胶囊、透明盒子、时间轴、触觉、分享卡均有对应实现或明确的分期记录。
- [ ] 总量只来自有效闭合段，未结束与异常不混入。
- [ ] 自动化向导完整，真实自检与手动测试分开。
- [ ] 未使用私有 API、静音保活、无意义后台权限或默认录放音会话。
- [ ] 不把历史电量显示为实时，不用时长转换电量/健康。
- [ ] 不默认 30h，不自动猜测型号、活动或佩戴状态。
- [ ] 修改充电观察不会删除使用历史。
- [ ] OCR 有用户确认，所有失败都有手动路径。
- [ ] 关键逻辑测试、UI 状态、真机自动化三层结果分别记录。
- [ ] 无用户账号、签名密钥或私密截图进入仓库。

## 12. 核查依据与开源借鉴

下列资料在 2026-10-11 调研。官方文档说明平台能力；开源项目说明可借鉴的实现，不证明 iOS 能直接继承其他平台能力。执行开发时，应复核会影响实现的 SDK availability 和第三方动作版本。

| 来源 | 本方案采用的结论 | 使用方式 |
|---|---|---|
| [Apple：处理音频路由变化](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes) | 路由事件有 previousRoute；不能把当前路由检查当全局摘戴日志 | 修正原稿断开检测与语义 |
| [Apple DTS：iOS 后台执行](https://developer.apple.com/forums/thread/685525) | 系统挂起不能用普通计时器恢复未知事件 | 不做无限后台监听承诺 |
| [Apple：playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord) | 是录放音会话配置 | 不为追踪占用音频 |
| [Apple：iOS 17 更新说明](https://support.apple.com/111098)；[Mgears 的 iPhone 自动化说明](https://www.manual-en.m-gears.com/autohotspot-iphone) | 立即运行与蓝牙断开自动化有系统/实机资料依据；泛化文档可能不完整 | 以实际系统 UI 与真机自检验收 |
| [Apple：AppIntent authenticationPolicy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)；[WWDC23 App Shortcuts](https://developer.apple.com/videos/play/wwdc2023/10179/) | 动作执行和锁屏策略有约束 | 不把无 UI 等同永远执行成功 |
| [Apple：耳机运动数据](https://developer.apple.com/documentation/coremotion/getting-motion-activity-data-from-headphones) | 支持的设备/系统可提供相关信号 | 独立、条件扩展 |
| [Apple：headphoneAudioExposure](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/headphoneaudioexposure?language=objc)；[Anchored Query](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery)；[HealthKit 隐私](https://developer.apple.com/documentation/healthkit/protecting-user-privacy) | 暴露样本、增量/删除、读取隐私边界 | 可选聆听模块，不能替代完整使用史 |
| [Apple：VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) | 本地 OCR 有 iOS 17 可用路线 | 用户选图、确认后保存 |
| [AllMyBatteries 开发者官网](https://allmybatteries.jylljy.com/)；[App Store](https://apps.apple.com/us/app/allmybatteries/id1621263412) | 值得验证的 iPhone 电量来源，包含应用内购买 | 不假定数据结构、价格或永久免费 |
| [jamesjingyi/ios-shortcuts](https://github.com/jamesjingyi/ios-shortcuts#-batteries) | 公开说明包含依赖 AllMyBatteries 的电量提醒 | 仅说明桥接线索，尚未验证动作内部输出 |
| [AirPodsPro-Motion-Sampler](https://github.com/tukuyo/AirPodsPro-Motion-Sampler)（MIT） | 耳机运动采样演示 | 借鉴能力探测，不承诺后台佩戴追踪 |
| [AirPosture](https://github.com/allenv0/AirPosture)（MIT） | 耳机运动工程实例；其音频后台策略不能照搬 | 借鉴 provider 分离，不复制静音保活 |
| [CAPod](https://github.com/d4rken-org/capod)（GPL-3.0） | Android 的未知值、缓存与电量分辨率值得参考 | 只借鉴模型理念；不直接复制进闭源工程 |
| [AirBattery](https://github.com/lihaoyun6/AirBattery)（AGPL-3.0） | macOS 能力依赖桌面接口 | 不宣称 Swift 代码能直接移植 iPhone |
| [BTLEmap](https://github.com/seemoo-lab/BTLEmap)（Apache-2.0）；[Apple DTS：Live Activity 与 BLE 限制](https://developer.apple.com/forums/thread/815189) | 平台广播过滤/锁屏限制仍需考虑 | 普通侧载或 Live Activity 不是通用绕过方案 |
| [Apple：SwiftData ModelConfiguration](https://developer.apple.com/documentation/swiftdata/modelconfiguration)；[App Groups 配置](https://developer.apple.com/documentation/xcode/configuring-app-groups) | 本地存储与扩展共享是不同配置层面 | V1 主 App 存储，P1 扩展前再迁移验证 |
| [Apple WWDC23：Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/) | 唯一属性冲突可能执行 upsert | 原始事件先比较 ID 与内容，不靠 unique 属性实现不可变去重 |

开源项目许可证应以选用版本的 LICENSE 为准；当前计划不打包或复制这些项目代码。型号续航值必须另查对应 Apple 产品技术规格，记录条件后才能进入 `ModelReferences.json`。
