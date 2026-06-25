# Lessons

- 2026-06-25: 处理 Teleprompter 粘贴 bug 时，必须先验证真实渲染层输出，不能只看编辑框或中间态字符串。
- 2026-06-25: 用户让读 Shotlit 项目并评估能否实现时，先确认她要的是整体项目/功能可行性评估，不能直接跳到“下一步 UI 重做”。
- 2026-06-25: 对“去空格”类需求，不能只用 `CharacterSet.whitespaces`；要显式覆盖 `NBSP/窄空格/零宽/BOM` 这类用户肉眼看见为空格、但 API 不一定视为普通空白的 Unicode 字符。
- 2026-06-25: 用户说“还有空格”时，不能默认是残留空白字符；对提词器这种大字效果，还要同时检查字距和最终视觉观感。
- 2026-06-25: 提词器遇到“一个字挨着一个字”的强需求时，优先改成逐字测量、逐字分行，别先在系统自动包行上做小修小补。

## 2026-06-25 LumiCue(接手Codex) 空格bug+打包 大复盘
- 🔴【最大教训】"反复修不好的bug"先查**用户跑的是不是最新版**：用户反复说"还有空格",我NSLog铁证渲染面/编辑框/所有路径空格字符早删净了。真因不是代码,是**验证路径≠用户真实操作路径**+怀疑旧实例。每次验证前`pkill -9 -f Snapzy`杀光,且确认系统无其他.app(mdfind/find)。
- 🔴 中文"字没挨着/有空格"投诉,真因常是**字距/markdown**不是空格字符:① 先用NSLog打scalar码验证字符层(U+0020/U+3000等有没有) ② markdown删空格也"不挨"是因为**换行符+符号(#|-*)删不掉**,逐字稿(纯句子)才是真实效果 ③ 视觉字距是CATextLayer字面留白,任何中文都有。别一上来改代码,先定性。
- 🔴 隐形窗口sharingType=.none截图拍不到:用`NSLog`打渲染内容,或`linesView.cacheDisplay(in:to:rep)`导出PNG(绕过屏幕捕获隐形)给用户肉眼判断。
- 🔴 编译铁律:perl注释摄像头(CameraBubbleWindow)+chmod 444锁文件防还原器,编译后git checkout还原;否则开摄像头/编译被破坏。entitlements在 snapzy/Snapzy/Snapzy.entitlements。
- 🔴 打包.app成品流程:cp Debug产物→改Info.plist(plutil/PlistBuddy改CFBundleName+CFBundleDisplayName,删CFBundleIconName加CFBundleIconFile)→换AppIcon.icns(iconutil从iconset)→codesign --force --deep --sign -(用绝对路径entitlements)→xattr -cr→首次右键打开绕Gatekeeper。
- 🔴 需求发散时当顾问帮收敛(列剩余+建议先出能用成品),但别引导用户跳过她明确要的功能。

## 2026-06-26 用户纠正:绝不自动打开提词器app
- 🔴 用户在工作时,我每次打包后自动 `open` 启动提词器=弹窗打扰她工作。**以后改完只 commit+文字告诉她,要验证她自己点。绝不自动 open/启动 LumiCue。** 验证用导出PNG/NSLog/读文件,不启动GUI。
