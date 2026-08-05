<!--
文件说明：墨记开源贡献指南，统一问题报告、代码风格和提交前检查。
作者：Codex
创建时间：2026-07-29
-->

# 贡献指南

感谢参与墨记。开始较大改动前，建议先创建 Issue（问题议题）说明目标和交互方案，避免重复实现或方向冲突。

## 开发原则

- 保持 macOS 原生体验，优先使用 AppKit 和系统控件。
- 用户可见文案默认使用简体中文，表达简短、明确。
- 不引入仅用于装饰的依赖；新增第三方代码必须说明必要性和许可证。
- 新增类、方法、关键流程和边界条件需要中文注释。
- 插件只能增强预览 DOM（网页文档结构），不能新增未经说明的原生权限或网络通道。
- 修改界面后需要检查默认窗口、最小窗口、空文档和长文档状态。

## 开发流程

1. 从主分支创建功能分支。
2. 使用 `./dev.sh` 构建并运行应用。
3. 保持改动范围清晰，不混入无关格式化或生成文件。
4. 完成下方检查后提交 Pull Request（合并请求）。

## 提交前检查

```bash
plutil -lint InkMark/InkMark-Info.plist InkMark.xcodeproj/project.pbxproj

xcrun swiftc \
  InkMark/Sources/Core/Markdown/ModernMarkdownRenderer.swift \
  Tests/RendererSmokeTests/main.swift \
  -o /tmp/moji-renderer-tests
/tmp/moji-renderer-tests

xcodebuild \
  -project InkMark.xcodeproj \
  -scheme InkMark \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

同时手动确认：

- 新建、打开、编辑、保存 Markdown 文档正常。
- 表格、任务列表、代码块和相对图片正常展示。
- 设置窗口各分类在默认尺寸和最小尺寸下没有错位或截断。
- 插件总开关和单插件开关可以立即刷新所有文档。
- 没有新增控制台调试输出、临时文件或用户本地路径。

## 提交信息

建议使用 Conventional Commits（约定式提交），例如：

```text
feat(plugins): add plugin metadata validation
fix(preview): preserve anchors after refresh
docs: clarify local build steps
```
