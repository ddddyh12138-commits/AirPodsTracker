# AirPodsTracker — 高级感 UI/UX 交互与视觉设计交付规范

> **交付说明**：本方案旨在将传统的列表式工具应用升维为具备 **Apple 原生质感（HIG）**、**流体微动效**、**拟物触觉反馈** 与 **仪式感趣味性** 的高端效率工具。供设计师或 Codex 直接依循实现。

---

## 一、 设计语言体系（Design System）

### 1.1 核心设计理念
* **Neomorphism × Spatial Material (新拟态与空间材质)**：摒弃粗暴的纯扁平与沉重的伪拟物，采用 iOS 17/18 标志性的 `.ultraThinMaterial`（超薄毛玻璃）、0.5pt 细高光边缘描边与双层环境光散射阴影。
* **Glanceable Hierarchy (一瞥即知)**：用直观的「双环能量仪」和「声波水流」替代冰冷枯燥的数据表格，把复杂的数据折叠在优雅的视觉主干之下。
* **Tactile & Auditory Sync (触感与声学反馈)**：每次关键操作搭配 `CoreHaptics` 的高质感清脆震动，模拟 AirPods 充电盒合盖的磁吸触感。

### 1.2 颜色系统（Dark Mode 首选）

| 语义角色 | 颜色值 (Hex / Dynamic) | 视觉用途 |
| :--- | :--- | :--- |
| **Space Void (背景主色)** | `#0D0E12` ~ `#151821` (径向渐变) | 深邃夜空黑，沉浸且不压抑 |
| **Card Surface (卡片材质)** | `Color.white.opacity(0.06)` + UltraThin | 悬浮透光毛玻璃层 |
| **Apple Energy Green (满电能)**| `#30D158` → `#00F2FE` (流光渐变) | 充电盒与耳机高电量环 |
| **Amber Warning (低电能)** | `#FF9F0A` → `#FF453A` (落日渐变) | 电量 < 20% 或单次佩戴超时 |
| **Neon Cyan (活动音波)** | `#0A84FF` → `#5E5CE6` (电光紫蓝) | 实时佩戴中的脉冲光晕与声波纹理 |
| **Border Glow (高光描边)** | `LinearGradient(white 20% → transparent)` | 卡片边缘 0.5pt 晶体反光 |

### 1.3 字体排印规范 (Typography)
* **实时计时器/核心数字**：`SF Pro Rounded`，样式选用 `.monospacedDigit()`，字重 `Bold`，防止每秒数字跳动导致视觉抖动。
* **次级标签**：`SF Pro Text`，11pt，大写字母加微小字偶间距（tracking: 1.2pt），浅灰半透，呈现类似精密仪表的工程感。

---

## 二、 核心页面结构与趣味交互设计

### 2.1 仪表盘（Dashboard）——「能量流控舱」

#### ① 顶部：拟态灵动岛药丸 (Dynamic Island Floating Capsule)
* **未连接**：灰色呼吸微光药丸，文字显示 `AirPods 待命待机`。
* **连接瞬间**：
  * 药丸弹性展开（`spring(response: 0.45, dampingFraction: 0.65)`）。
  * 左右两枚 AirPods 图标向外“飞出”并定格，伴随清脆震动（Haptic: `.rigid`）。
  * 状态指示点变为绿色脉冲光斑，文字滚动变为 `AirPods Pro 2 已就绪`。

#### ② 视觉焦点：双环流体能量仪 (Dual Energy Gauge)
代替传统卡片，采用 Apple Watch 风格的嵌套高质感进度环：
* **外环（充电盒总续航池）**：
  * 最大刻度为官方标称（例如 30h），流体渐变填满。
  * 每当耳机取出使用，外环末端带有类似微粒子流动的光点。
* **内环（本次单次耳机续航）**：
  * 最大刻度为单次极限（如 6h），实时向前推进。
* **中心区域（计时核心）**：
  * 巨幅 `01:28:45` 数字，带有微弱的环境投影。
  * 底部显示一行趣味状态标语：“🎵 已陪伴你度过 2 张专辑的时长”。

#### ③ 快捷交互手势
* **双指轻捏（Pinch）中心表盘**：在「简约极客模式」（纯大字体时钟）与「详细能量视图」之间丝滑切换。
* **长按计时表盘**：触发触感反馈并弹出快捷微调菜单（“补录电量”、“手动结束本次”）。

---

### 2.2 充电盒管理（The Battery Vault）——「储能胶囊」

#### ① 趣味拟物：液态储能舱动画 (Liquid Battery Vessel)
* 页面中央是一个立体的 **透明 AirPods 充电盒拟态轮廓容器**。
* 内部呈现真实**液态水面晃动效果**（利用 SwiftUI `Canvas` 或 `TimelineView` + 正弦波函数）：
  * 水位高度 = 当前周期已用电量 / 官方标称 30 小时。
  * 手机轻微倾斜时，利用 CoreMotion（陀螺仪）让能量液体产生物理倾斜与波纹晃动（极致交互彩蛋！）。
  * 剩余容量低于 15% 时，液体颜色由清澈翠绿平滑渐变为警戒落日红。

#### ② 仪式感按钮：“满电充能”与“耗尽归零”
* **「🔋 盒子已充满」按钮**：
  * **按压特效**：长按 0.8 秒触发“蓄力充能”动画，环形进度条蓄满后，屏幕中央爆发展开一道柔和的绿色粒子光圈。
  * **触觉模拟**：`CoreHaptics` 连续输出由弱渐强的连续震动，并在松手时给予一个坚实的 `.heavy` 敲击，模拟“推上电源闸”的仪式感。
* **「🪫 盒子已没电」按钮**：
  * 点击后，液体像漏斗般平滑旋涡沉底流干，随后自动弹出一张优雅精美的 **「本充放周期战绩报告单」**。

---

### 2.3 使用记录（Timeline）——「声波足迹」

#### ① 视觉设计：音乐声波时间轴 (Audio Waveform Ribbon)
* 不再使用死板的白色 UITableView 列表，而是一条贯穿屏幕的垂直光纤导轨。
* **每条记录卡片**：
  * 左侧：按使用时长动态生成的**声波高度柱形图**（使用 45 分钟呈现短波浪，使用 3 小时呈现起伏丰富的高动态波浪）。
  * 右侧：起止时间戳、设备芯片标识（如 H2 Chip 标志）。
  * 卡片右上角带有轻量情绪便签（可根据时长自动打标：`快速通话`、`专注沉浸`、`长途飞行`）。

#### ② 交互动效
* **向左滑动**：露出带有触感阶梯的隐藏操作（红亮色删除、蓝色补记）。
* **轻点展开**：卡片以弹簧物理效果原地撑开，展示该时段消耗电量走势估算图。

---

### 2.4 数据洞察（Insights & Trends）——「声学体检」

#### ① 官方续航达成率标尺 (Real-world vs Claimed)
* **仪表板对比指针**：
  * 直观展示你的 AirPods 是“远超预期（104%）”还是“略微老化（81%）”。
  * 动态生成健康建议卡片：“在开启降噪模式下，你的 AirPods 表现极其坚挺，已达到新机水准的 92%。”

#### ② 热力作息分布盘 (24h Activity Radial Matrix)
* 24小时环形极坐标热力图，颜色深浅直观暴露用户在哪个时段最离不开耳机（例如上午 9 点通勤、晚上 11 点睡前白噪音）。

---

## 三、 微动效与触觉反馈规范 (Haptics & Motion)

### 3.1 弹簧物理参数标准
在 SwiftUI 中全量统一定义动画曲线，杜绝机械线性运动：

```swift
extension Animation {
    // 界面主元素弹出、卡片开合
    static let spatialSpring = Animation.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0)
    // 按钮按下反弹
    static let buttonTapSpring = Animation.spring(response: 0.25, dampingFraction: 0.55, blendDuration: 0)
    // 液体与指针微摆
    static let fluidBreathe = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
}
```

### 3.2 触觉设计矩阵 (CoreHaptics)
* **AirPods 自动吸附连接**：`UIImpactFeedbackGenerator(style: .medium).impactOccurred()`
* **长按充能完成**：`UINotificationFeedbackGenerator().notificationOccurred(.success)`
* **滑动删除卡片到达临界点**：`UISelectionFeedbackGenerator().selectionChanged()`

---

## 四、 趣味性与仪式感彩蛋设计（Delight Features）

1. **里程碑徽章系统 (AirPods Odyssey Badges)**：
   * 🏆 **「马拉松战士」**：单次连续佩戴超过 4 小时未断开。
   * 🔋 **「核能电池盒」**：单个充电盒周期累计续航突破 28 小时。
   * 🌙 **「深宵夜行者」**：在凌晨 2:00 ~ 5:00 持续连接工作。
   * 点击徽章可翻转查看 3D 金币光泽与达成日期。

2. **听力关怀保护色 (Adaptive Health Tint)**：
   * 当连续佩戴时长超过 **60 分钟**，界面实时计时器的呼吸光圈会从柔和的冷蓝色，非常缓慢、无声无息地渐变为温润的暖橙色。
   * 不会弹出粗暴打扰用户的弹窗，而是通过视觉温度提醒用户：“该摘下耳机，让耳朵透透气了”。

3. **一键生成精美拍立得分享卡 (Shareable Polaroid Card)**：
   * 在结束一个充电盒周期时，支持渲染生成一张长图卡片：
     * 极简磨砂黑底色
     * 优雅的金色衬线体排版
     * 标注：“充电盒总续航：26h 40m · 陪伴了 9 次聆听时光”
     * 带有极具质感的波形背景，方便一键保存至相册或发小红书/朋友圈。

---

## 五、 给 Codex 的 UI 升级落地 Prompt

> **直接将以下 Prompt 追加发送给 Codex，指引其编写高质感 UI 代码：**

```markdown
请按照以下高标准视觉与交互规范，对 AirPodsTracker 的全部 SwiftUI 界面进行重构升级：

1. 视觉质感升级：
   - 全局采用深色太空黑背景（Color(hex: "0E1015") 到深灰蓝径向微渐变）。
   - 所有卡片容器改用 Material 材质：.background(.ultraThinMaterial)，配合 0.5pt 的半透明白微光描边（.stroke(LinearGradient(colors: [.white.opacity(0.3), .clear]), lineWidth: 0.5)）与柔和多层阴影。
   - 核心数字显示全部采用 .font(.system(.largeTitle, design: .rounded, weight: .bold))，并强制添加 .monospacedDigit()。

2. 仪表盘 (DashboardView) 重构：
   - 顶部设计拟态药丸胶囊状态条：连接状态带有动态绿色脉冲呼吸环（使用 repeatForever 动画）。
   - 中央核心采用双层圆环进度仪表（Outer Ring 为充电盒总消耗进度，Inner Ring 为单次耳机时长），包裹大字号实时翻牌计时器。
   - 融入精致的触觉反馈：使用 UIImpactFeedbackGenerator 在状态变更与交互时提供清脆震动。

3. 充电盒管理 (CaseChargeCycleView) 重构：
   - 将枯燥的数据面板改为拟物化的「储能水舱」卡片：已用时长与官方 30 小时标称形成波浪视觉对比。
   - 「盒子已充满」操作改为长按 0.8 秒确认按钮，附带充能环形动画与完成后的成功触觉震动。
   - 历史周期列表改用悬浮卡片流，直观展示官方达成率百分比标签。

4. 细节与耐看度：
   - 优化色彩体系，使用高饱和度的 Apple 能量绿 (#30D158)、电光青蓝 (#0A84FF) 与警示橙黄。
   - 所有列表行 (SessionRow) 左侧增加根据时长动态渲染的迷你拟态声波柱条。
   - 界面文字使用自然、优雅的高品质中文。
```
