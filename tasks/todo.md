# 靓相 Shotlit · 任务清单

> 产品定位：**让你出镜好看的录屏软件** —— Screen Studio 级自动美化录屏 + 直播级实时美颜露脸 + 异形露脸框 + 隐形提词器，四合一。
> 中文名：靓相　英文名：Shotlit　基座：Snapzy（BSD-3，可商用二开，macOS 原生 Swift）

---

## 💡 需求收件箱（一条不漏 · 🔴一期地基 🟡二期 ⚪三四期）

### 🔴 一期 · 地基 + 核心（两天 MVP 目标）
- [ ] 基座 Snapzy 跑通（需先装完整 Xcode）
- [ ] 录屏**真高清**：Retina 原生分辨率 + 高码率 + H.265/ProRes（治"Mac 录屏糊"）
- [ ] 摄像头**露脸 bubble**（先圆形/方形）
- [ ] 基础实时美颜：磨皮 + 美白 + 滤镜（Metal，先做出"脸真变好看"）
- [ ] **隐形提词器**：浮窗给主播看、录屏排除（命根子已验证基座支持）、放镜头附近、可调字号/滚动速度、导入 txt/粘贴稿
- [ ] 全 UI "先英文后中文"文案规范（如 `Smooth Skin 磨皮`）
- [ ] 支持 **iPhone 当高清摄像头**（连续互通相机，救 Mac 前置糊）

### 🟡 二期 · 美型 + 正脸
- [ ] 异形露脸框：心形 / 星形 / 多边形 / 自定义遮罩
- [ ] **自动构图 Auto-Framing**：人脸自动居中 + 水平拉正（放角落也端正）
- [ ] **眼神矫正 Eye Contact**：AI 把眼神/脸朝向掰成看镜头（旗舰卖点）
- [ ] 瘦脸 / 大眼 / V脸（基于 Vision 人脸关键点形变）

### ⚪ 三四期 · 氛围 + 体验 + 商业化
- [ ] 贴纸 / 虚拟背景·背景模糊 / 美妆
- [ ] 竖屏录制 + 平台安全区参考线（抖音/小红书/视频号）
- [ ] 免装虚拟声卡原生内录 + 系统声/麦分轨
- [ ] 中文 ASR + LLM 语义断句字幕
- [ ] 自动 Auto-Zoom / 光标轨迹平滑 / 背景壁纸一键美化
- [ ] 微信/支付宝直付、国内服务器/CDN、微信可打开的分享链接
- [ ] 画质增强/锐化（糊→变清晰）

---

## 🚧 当前阶段：环境搭建

### 已完成（带铁证）
- [x] 8 个开源仓库 + 两轮痛点调研（见 docs/调研与方案.md）
- [x] 定名：靓相 / Shotlit
- [x] clone Snapzy 基座到 `snapzy/`（592 文件）
- [x] 验证提词器命根子：基座 ScreenCaptureKit 已支持 `excludingWindows/excludingApplications`（ScreenCaptureManager.swift:2047-2049）
- [x] 确认摄像头需新建（基座仅麦克风音频）

### 🔴 阻塞中（关键路径）
- [ ] **装 Xcode 16.4**（⚠️ 不能用 App Store！它只给最新 Xcode 26.4，要 macOS 26.2，本机 15.7.7 装不了）
  - 正确方式：developer.apple.com/download/all 用免费 Apple ID 登录 → 下 Xcode 16.4 的 .xip（~8G）→ 解压拖进"应用程序"
  - 版本依据（已查证）：本机 macOS 15.7.7 最高可装 Xcode 26.3（要 15.6+）；Snapzy 只要 macOS 13+/Swift 5，故 Xcode 16.4（要 15.3+）足够且更省磁盘
- [x] 磁盘清理：已删 swift-6.3.2.pkg + WeChat.dmg + 部分缓存，48G→56G（保留 ms-playwright 爬虫浏览器）

### ✅ 基座已编译+运行通过（2026-06-23，界面验证·截图为证）
- Xcode 26.3 (build 17C529) 已装，xcode-select 已指向；旧的 16.4 已被替换
- 🔴 正确编译命令（在 snapzy/ 目录，否则满盘 MainActor 隔离错）：
  `xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug -derivedDataPath /tmp/snapzy-build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
- 产物：`/tmp/snapzy-build/Build/Products/Debug/Snapzy Debug.app`
- 运行验证：`open` 后中文欢迎窗口正常弹出（菜单栏 app），进程在跑
- 教训：Snapzy CreatedOnToolsVersion=26.2，必须 Xcode 26.x(Swift 6.2，因 SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor)；16.4 死路（试了 8 次编译/降级/minimal/借toolchain 全失败）

### 下一步：开始一期功能开发（每步先描述方法→批准→写码→编译跑→截图验证）
1. ✅ 露脸摄像头 bubble（圆形浮窗 + 实时摄像头画面，界面验证 2026-06-23）— 文件:Features/Camera/CameraCaptureService.swift + CameraBubbleWindow.swift + SnapzyApp.swift挂载
   ⚠️ 运行要点:未签名app摄像头被TCC拒绝(黑屏),必须 `codesign --force --deep --sign - "<app>"` 做ad-hoc签名后才弹权限/出画面
   还需:集成进录制(addExceptedWindow让它录进去)、可调大小/位置记忆、关闭按钮
1b. ✅ 异形露脸框（8 形状:圆/方/圆角/椭圆/心❤️/星/六边/三角 + 单击循环切换 + 拖动，界面验证 2026-06-23）
    文件:Features/Camera/BubbleShape.swift + CameraBubbleWindow.swift(CAShapeLayer 遮罩)
    坑:CALayer 坐标 Y 朝上，自定义 path 按"底 fy=0、顶 fy=1"画(否则心形上下颠倒像屁股)
    还需:长方形(非正方形尺寸)、明确的形状选择 UI(不只单击循环)

2. ✅ 基础美颜(2026-06-23,界面验证) — Metal 双边滤波磨皮(保边不糊)+美白, 文件 Beauty.metal+MetalBeautyRenderer.swift
3. ✅ 滤镜 — 9个3D LUT(CIColorCube:电影/日系/奶油肌/胶片等), BeautyFilterType.swift
4. ✅ 人脸跟随 — Vision检测+缩小到40%完整居中+防抖+模糊背景填充(消黑边), FaceTracker.swift
5. ✅ 水平镜像(像照镜子,消左右反别扭)
6. ✅ 单击弹选项菜单(形状/滤镜/美颜强度), CameraBubbleWindow
7. ⚠️ 瘦脸 — 整体液化基础版done(已修背景变形:液化限人脸椭圆区), 但**非美图秀秀级分部位**
   🔴 路线已定(用户2026-06-23):**手搓认真开发分部位精细美颜** — 用 Apple Vision 76点人脸关键点, 逐部位(瘦下巴/瘦颧骨/瘦鼻/大眼/美妆)独立液化。数周工程,先吃透Vision FaceLandmarks 76点。诚实:难追美图秀秀多年调优的商业级。
   备选(用户暂不选):接PixelFree/Banuba商业SDK(花钱,现成商业级)。
🔴 BUG(明天先修) 提词器调框大小后文字被切/没在框内正常显示 — setBoxSize 只改了 window/scrollView 尺寸,没重新布局 textView。修:setBoxSize 里同步更新 textView.frame + textContainer + 重新布局,确保文字在新框内完整可读。根因=我只验默认大小没验调节后状态。

🆕 提词器右上角控制条(用户 2026-06-23 建议,比右键直观): 像浏览器窗口那样——右上角放 小/中/大 三档大小按钮 + 关闭✕(碍事一键关掉) + 暂停/播放按钮。替代/补充右键菜单。用户原话"一直在滚不知道怎么关"=关闭✕和可见的暂停是刚需。

## 💡 收件箱(2026-06-24 第二天补充)
- 🔴 BUG: bubble里"脸中间被一条透明的边隔开"=前景(缩小画面)+模糊背景合成的边穿过脸。修:做人像分割(VNGeneratePersonSegmentationRequest)抠人物+背景虚化,而非整画面缩小;或前景边缘羽化过渡。

- 🔴 滤镜根治:下载真专业 .cube LUT(FilterGrade 8个/Lutify 10个/Skin奶油肤色)替代程序生成的劣质LUT(雾蒙蒙)。资源:filtergrade.com、lutify.me/free-luts、fixthephoto。实现:CIColorCube 加载 .cube。**目标=美颜相机/美图秀秀那种通透好看,不发灰发雾**。
- 🔴 所有设置按钮中英文一起放(先英后中,如"Small 小"),控制条+菜单都要
- 🟡 字体两套选择:界面按钮(小中大)快速 + 右键 Word 式字号数值列表(12/16/20/24/30/36/44/52)细致
- 🔴 点边框/控制条后 app 别退/功能别误退(只 ✕ 关提词器)
- 🟡 提词器字号细致档(配合上面)

## 💡 收件箱(2026-06-23 收工补充, 参考美颜相机/美图秀秀)
- 🔴 美颜/瘦脸改 **0-100 滑块**调节(像手机,直观),替代现在的强/中/弱档
- 🔴 **分左右脸**独立调节(Vision 左右脸关键点分别 liquify)
- 🔴 **美颜提亮/打光**(补光美颜:提亮+柔光+磨皮联动,参考美颜相机的"自然光/影棚光")
- 🔴 **更多好看滤镜**(扩充 LUT:奶茶/初恋/冷白皮/胶片/港风等,参考美图秀秀)
- 🔴 **长视频导出失败**对策:流式导出(边处理边写文件、不全压内存)+ 硬件编码(VideoToolbox)+ 分段/断点续 + 导出前查磁盘空间
- 🟡 **英文自动字幕**(ASR 英文 + 竖屏安全区适配)

8. 🆕 虚拟摄像头(CoreMediaIO Camera Extension) — 让美颜能被任何直播/会议/录课软件选为"摄像头源"(OBS/抖音直播伴侣/视频号/腾讯会议/Zoom)。用户2026-06-23问"能直播用吗"时提出。💡超值通用功能:做了美颜不限自家录屏,通吃所有软件。macOS原生支持,技术可行。
3. 隐形提词器（浮窗 + 不加 exceptedWindow = 录不进去）
4. 全程"先英文后中文"文案

---

## ⚠️ 诚实风险说明
- "两天做完整个产品"= 不可能（数月工程）。两天目标 = 一个**能亲手录、能露脸、有基础美颜、高清**的可跑原型。
- 最大风险：Xcode 未装 + 磁盘紧。这是当前唯一阻塞，已请用户处理。
