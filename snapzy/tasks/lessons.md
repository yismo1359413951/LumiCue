# Lessons

- 2026-06-25: 处理 Teleprompter 粘贴 bug 时，必须先验证真实渲染层输出，不能只看编辑框或中间态字符串。
- 2026-06-25: 对“去空格”类需求，不能只用 `CharacterSet.whitespaces`；要显式覆盖 `NBSP/窄空格/零宽/BOM` 这类用户肉眼看见为空格、但 API 不一定视为普通空白的 Unicode 字符。
