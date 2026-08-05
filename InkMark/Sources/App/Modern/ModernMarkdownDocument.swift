/**
 * 文件说明：墨记现代 Markdown 文档，使用 Swift + AppKit + WKWebView 组织编辑和预览。
 * 作者：Codex
 * 创建时间：2026-06-17
 */

import AppKit

/// ModernMarkdownDocument 是墨记新的默认文档类型。
/// 它用原生 NSSplitViewController（macOS 分栏控制器）组织编辑和预览，并提供工具栏切换交互。
@objc(ModernMarkdownDocument)
final class ModernMarkdownDocument: NSDocument, NSToolbarDelegate {
    /// WorkspaceMode 表示主窗口的三种经典工作方式。
    /// 明确模式比独立开关左右面板更容易理解，也避免用户组合出不可预期的空白布局。
    enum WorkspaceMode: Int {
        case writing
        case split
        case reading
    }

    private enum ToolbarItemIdentifier {
        static let openMarkdown = NSToolbarItem.Identifier("Moji.OpenMarkdown")
        static let formatting = NSToolbarItem.Identifier("Moji.Formatting")
        static let workspaceMode = NSToolbarItem.Identifier("Moji.WorkspaceMode")
    }

    private let renderer = ModernMarkdownRenderer()
    private let editorController = ModernEditorViewController()
    private let previewController = ModernPreviewViewController()
    private let splitViewController = NSSplitViewController()
    private let documentStatusLabel = NSTextField(labelWithString: "0 行 · 0 字符")
    private var markdownText = ""
    private var editorItem: NSSplitViewItem?
    private var previewItem: NSSplitViewItem?
    private var workspaceModeControl: NSSegmentedControl?
    private var pendingPreviewRender: DispatchWorkItem?
    private var lastSplitFraction: CGFloat = 0.5
    private(set) var workspaceMode: WorkspaceMode = .split

    override init() {
        super.init()
        editorController.onTextChange = { [weak self] text in
            self?.markdownText = text
            self?.updateDocumentStatus()
            self?.updateChangeCount(.changeDone)
            self?.schedulePreviewRender()
        }
        editorController.onScrollSourceLineChange = { [weak self] sourceLine in
            guard let self, self.workspaceMode == .split else { return }
            self.previewController.scrollToSourceLine(sourceLine)
        }
        previewController.onScrollSourceLineChange = { [weak self] sourceLine in
            guard let self, self.workspaceMode == .split else { return }
            self.editorController.scrollToSourceLine(sourceLine)
        }
    }

    override class var autosavesInPlace: Bool {
        return true
    }

    override var windowNibName: NSNib.Name? {
        // 新文档完全使用代码创建窗口，避免继续依赖旧 XIB（macOS 界面布局文件）。
        return nil
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        #if DEBUG
        window.title = "\(displayName ?? "未命名") · Debug"
        #else
        window.title = displayName
        #endif
        window.minSize = NSSize(width: 720, height: 520)
        // 编辑器采用稳定的系统窗口背景，避免透明材质与浅色/深色预览并排时产生割裂感。
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.contentViewController = makeRootViewController()
        window.toolbar = makeToolbar()

        let windowController = NSWindowController(window: window)
        addWindowController(windowController)
        editorController.setText(markdownText)
        renderPreview()
        updateDocumentStatus()
        applyWorkspaceMode(animated: false)
        editorController.focusEditor()
    }

    override func data(ofType typeName: String) throws -> Data {
        return markdownText.data(using: .utf8) ?? Data()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        markdownText = String(data: data, encoding: .utf8) ?? ""
    }

    func loadMarkdownFile(at url: URL) throws {
        // 直接读取 Markdown 文件，绕开 NSDocumentController 对“Markdown”类型名的内部映射问题。
        let data = try Data(contentsOf: url)
        markdownText = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .unicode)
            ?? ""
        fileURL = url
        // 保留原始文档类型，避免打开 `.md` 后自动保存时被系统改名为 `.txt`。
        fileType = url.pathExtension.lowercased() == "txt"
            ? "public.plain-text"
            : "net.daringfireball.markdown"
    }

    func presentLoadedDocument() {
        // 手动打开文件时 NSDocumentController 不一定会自动创建窗口；这里强制创建并显示。
        if windowControllers.isEmpty {
            makeWindowControllers()
        }
        showWindows()
        windowControllers.forEach { controller in
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func makeRootViewController() -> NSViewController {
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin

        let editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = 360
        editorItem.canCollapse = true

        let previewItem = NSSplitViewItem(viewController: previewController)
        previewItem.minimumThickness = 360
        previewItem.canCollapse = true

        self.editorItem = editorItem
        self.previewItem = previewItem
        splitViewController.addSplitViewItem(editorItem)
        splitViewController.addSplitViewItem(previewItem)

        let rootController = NSViewController()
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        rootController.view = rootView
        rootController.addChild(splitViewController)
        rootView.addSubview(splitViewController.view)
        splitViewController.view.translatesAutoresizingMaskIntoConstraints = false

        let statusBar = makeStatusBar()
        rootView.addSubview(statusBar)
        NSLayoutConstraint.activate([
            splitViewController.view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            splitViewController.view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            splitViewController.view.topAnchor.constraint(equalTo: rootView.topAnchor),
            splitViewController.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28)
        ])
        return rootController
    }

    /// 创建底部状态栏，用于持续显示文档类型和文本统计。
    /// 状态栏保持克制，不占用工具栏空间，也不会干扰写作区域。
    private func makeStatusBar() -> NSView {
        let statusBar = NSView()
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        statusBar.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let formatLabel = NSTextField(labelWithString: "Markdown")
        formatLabel.font = .systemFont(ofSize: 11, weight: .medium)
        formatLabel.textColor = .secondaryLabelColor
        formatLabel.translatesAutoresizingMaskIntoConstraints = false

        documentStatusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        documentStatusLabel.textColor = .secondaryLabelColor
        documentStatusLabel.alignment = .right
        documentStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBar.addSubview(separator)
        statusBar.addSubview(formatLabel)
        statusBar.addSubview(documentStatusLabel)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: statusBar.topAnchor),
            formatLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            formatLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            documentStatusLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            documentStatusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
        return statusBar
    }

    /// 更新行数和字符数，帮助用户快速判断文档规模。
    private func updateDocumentStatus() {
        let lineCount = markdownText.isEmpty ? 0 : markdownText.components(separatedBy: .newlines).count
        documentStatusLabel.stringValue = "\(lineCount) 行 · \(markdownText.count) 字符"
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "Moji.DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    private func renderPreview() {
        // 每次渲染前读取最新偏好设置，保证菜单切换主题和插件后能立即生效。
        renderer.style = MojiPreferences.shared.markdownStyle
        renderer.options = MojiPreferences.shared.renderOptions
        let pluginScripts = MojiPluginManager.shared.loadPluginScripts()
        let html = renderer.renderHTML(from: markdownText)
        // 已保存文档以自身目录解析相对资源；未命名文档回退到应用资源目录。
        let previewBaseURL = fileURL?.deletingLastPathComponent() ?? Bundle.main.resourceURL
        previewController.load(html: html, baseURL: previewBaseURL, pluginScripts: pluginScripts)
    }

    /// 合并短时间内连续发生的输入事件，避免每个按键都让 WKWebView（网页预览控件）重载整页。
    /// 80 毫秒延迟几乎不会影响实时感，但能明显降低长文档连续输入时的卡顿和闪烁。
    private func schedulePreviewRender() {
        pendingPreviewRender?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.renderPreview()
        }
        pendingPreviewRender = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    func refreshPreviewFromPreferences() {
        // 设置变化需要立即可见，因此取消尚未执行的输入防抖任务并直接刷新。
        pendingPreviewRender?.cancel()
        editorController.applyPreferences()
        renderPreview()
    }

    /// 导出当前 Markdown 为独立 HTML（网页文件）。
    /// 导出的文件包含当前预览主题，双击即可用浏览器阅读。
    func exportHTML() {
        let panel = NSSavePanel()
        panel.title = "导出 HTML"
        panel.prompt = "导出"
        panel.allowedFileTypes = ["html"]
        panel.nameFieldStringValue = "\(displayName ?? "未命名").html"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        renderer.style = MojiPreferences.shared.markdownStyle
        renderer.options = MojiPreferences.shared.renderOptions
        let html = renderer.renderHTML(from: markdownText)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// 当前编辑区是否可见，供顶部“查看”菜单显示勾选状态。
    var isEditorVisible: Bool {
        return editorItem?.isCollapsed == false
    }

    /// 当前预览区是否可见，供顶部“查看”菜单显示勾选状态。
    var isPreviewVisible: Bool {
        return previewItem?.isCollapsed == false
    }

    /// 切换编辑区显示状态。
    /// 至少保留编辑区或预览区中的一个，避免窗口变成空白。
    func toggleEditorVisibility() {
        setWorkspaceMode(isPreviewVisible ? .reading : .split)
    }

    /// 切换预览区显示状态。
    /// 至少保留编辑区或预览区中的一个，避免窗口变成空白。
    func togglePreviewVisibility() {
        setWorkspaceMode(isEditorVisible ? .writing : .split)
    }

    /// 切换主窗口工作模式，并让工具栏分段控件同步反映当前状态。
    /// 写作和阅读模式只隐藏非目标区域，重新回到分栏时会恢复原有分隔位置。
    func setWorkspaceMode(_ mode: WorkspaceMode) {
        if workspaceMode == .split, splitViewController.splitView.bounds.width > 0 {
            // NSSplitView 在较低系统版本没有公开的分隔位置读取方法，左侧子视图宽度就是当前分隔位置。
            let dividerPosition = splitViewController.splitView.subviews.first?.frame.maxX
                ?? splitViewController.splitView.bounds.width / 2
            lastSplitFraction = min(max(dividerPosition / splitViewController.splitView.bounds.width, 0.3), 0.7)
        }
        workspaceMode = mode
        applyWorkspaceMode(animated: true)
    }

    func insertBold() {
        editorController.wrapSelection(prefix: "**", suffix: "**", placeholder: "粗体文本")
    }

    func insertItalic() {
        editorController.wrapSelection(prefix: "*", suffix: "*", placeholder: "斜体文本")
    }

    func insertInlineCode() {
        editorController.wrapSelection(prefix: "`", suffix: "`", placeholder: "code")
    }

    func insertLink() {
        editorController.wrapSelection(prefix: "[", suffix: "](https://example.com)", placeholder: "链接文字")
    }

    func insertImage() {
        editorController.insertBlock("![图片说明](image.png)\n", selectedPlaceholder: "image.png")
    }

    /// 插入附件资源卡片模板。
    /// 使用纯文本键值对保存信息，其他 Markdown 编辑器即使不识别卡片也能读懂文件地址。
    func insertAttachment() {
        editorController.insertBlock(
            "```attachment\ntitle: 需求说明.pdf\nurl: ./需求说明.pdf\ndescription: 附件说明\n```\n\n",
            selectedPlaceholder: "./需求说明.pdf"
        )
    }

    /// 插入视频模板，支持文档相对路径或 HTTPS 地址。
    func insertVideo() {
        editorController.insertBlock(
            "```video\ntitle: 演示视频\nurl: ./demo.mp4\n```\n\n",
            selectedPlaceholder: "./demo.mp4"
        )
    }

    func insertHeading() {
        editorController.insertBlock("## 标题\n\n", selectedPlaceholder: "标题")
    }

    func insertBlockquote() {
        editorController.insertBlock("> 引用内容\n\n", selectedPlaceholder: "引用内容")
    }

    /// 插入 GitHub Alerts（GitHub 提示块）兼容语法。
    func insertAlert() {
        editorController.insertBlock("> [!NOTE]\n> 这里填写需要强调的内容。\n\n", selectedPlaceholder: "这里填写需要强调的内容。")
    }

    /// 插入响应式双栏容器；窄窗口预览会自动纵向排列。
    func insertContentColumns() {
        editorController.insertBlock(
            "::: columns\n::: column\n## 左栏\n\n左侧内容\n\n::: column\n## 右栏\n\n右侧内容\n:::\n\n",
            selectedPlaceholder: "左侧内容"
        )
    }

    /// 插入可展开与收起的折叠内容容器。
    func insertDetails() {
        editorController.insertBlock(
            "::: details 详细内容\n这里填写折叠内容。\n:::\n\n",
            selectedPlaceholder: "这里填写折叠内容。"
        )
    }

    func insertCodeBlock() {
        editorController.insertBlock("```swift\n代码内容\n```\n\n", selectedPlaceholder: "代码内容")
    }

    /// 插入 Mermaid 流程图模板，使用本地运行库渲染。
    func insertMermaidDiagram() {
        editorController.insertBlock(
            "```mermaid\nflowchart LR\n  A[开始] --> B[完成]\n```\n\n",
            selectedPlaceholder: "A[开始] --> B[完成]"
        )
    }

    /// 插入 PlantUML 模板；图表由应用内置运行时在本机生成，不上传源码。
    func insertPlantUMLDiagram() {
        editorController.insertBlock(
            "```plantuml\n@startuml\nAlice -> Bob: Hello\n@enduml\n```\n\n",
            selectedPlaceholder: "Alice -> Bob: Hello"
        )
    }

    /// 插入块级 LaTeX（数学排版语言）公式。
    func insertMathFormula() {
        editorController.insertBlock("```math\nE = mc^2\n```\n\n", selectedPlaceholder: "E = mc^2")
    }

    /// 插入通用技术资产链接卡片，不依赖企业内部接口。
    func insertTechnicalAsset() {
        editorController.insertBlock(
            "```asset\ntitle: 接口评审\nurl: https://example.com/asset\ndescription: 技术资产说明\n```\n\n",
            selectedPlaceholder: "https://example.com/asset"
        )
    }

    /// 插入 ZERO 文件链接卡片；开源版本保留链接能力，不读取内部系统数据。
    func insertZeroFile() {
        editorController.insertBlock(
            "```zero\ntitle: 产品原型\nurl: https://example.com/zero\ndescription: ZERO 原型或设计稿\n```\n\n",
            selectedPlaceholder: "https://example.com/zero"
        )
    }

    func insertTaskList() {
        editorController.insertBlock("- [ ] 待办事项\n- [x] 已完成事项\n\n", selectedPlaceholder: "待办事项")
    }

    func insertUnorderedList() {
        editorController.insertBlock("- 列表项目\n- 列表项目\n\n", selectedPlaceholder: "列表项目")
    }

    func insertOrderedList() {
        editorController.insertBlock("1. 列表项目\n2. 列表项目\n\n", selectedPlaceholder: "列表项目")
    }

    func insertHorizontalRule() {
        editorController.insertBlock("---\n\n")
    }

    func insertTable() {
        editorController.insertBlock("| 名称 | 说明 | 状态 |\n| --- | --- | ---: |\n| 墨记 | Markdown 预览 | 100% |\n\n", selectedPlaceholder: "名称")
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [ToolbarItemIdentifier.openMarkdown, .space, ToolbarItemIdentifier.formatting, .flexibleSpace, ToolbarItemIdentifier.workspaceMode]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [ToolbarItemIdentifier.openMarkdown, .space, ToolbarItemIdentifier.formatting, .flexibleSpace, ToolbarItemIdentifier.workspaceMode]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemIdentifier.openMarkdown:
            return makeToolbarItem(identifier: itemIdentifier, title: "打开", symbolName: "folder", action: #selector(openMarkdownFromToolbar))
        case ToolbarItemIdentifier.formatting:
            return makeFormattingToolbarItem(identifier: itemIdentifier)
        case ToolbarItemIdentifier.workspaceMode:
            return makeWorkspaceModeToolbarItem(identifier: itemIdentifier)
        default:
            return nil
        }
    }

    private func makeToolbarItem(identifier: NSToolbarItem.Identifier, title: String, symbolName: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = title
        item.paletteLabel = title
        item.toolTip = title
        item.target = self
        item.action = action
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        }
        return item
    }

    /// 创建高频格式工具组，使用瞬时分段按钮减少标题栏中的零散图标和视觉噪音。
    private func makeFormattingToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let control = NSSegmentedControl(labels: ["", "", "", ""], trackingMode: .momentary, target: self, action: #selector(applyFormattingFromToolbar(_:)))
        control.segmentStyle = .rounded
        control.frame = NSRect(x: 0, y: 0, width: 132, height: 28)
        let symbols = ["bold", "italic", "curlybraces", "link"]
        let toolTips = ["粗体", "斜体", "行内代码", "链接"]
        for index in 0..<symbols.count {
            control.setImage(NSImage(systemSymbolName: symbols[index], accessibilityDescription: toolTips[index]), forSegment: index)
            control.setToolTip(toolTips[index], forSegment: index)
            control.setWidth(32, forSegment: index)
        }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "格式"
        item.paletteLabel = "常用格式"
        item.view = control
        return item
    }

    /// 创建“写作 / 分栏 / 阅读”模式选择器。
    /// 三段式控件沿用成熟 Markdown 工具的明确模式模型，避免两个独立显示开关互相冲突。
    private func makeWorkspaceModeToolbarItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let control = NSSegmentedControl(labels: ["", "", ""], trackingMode: .selectOne, target: self, action: #selector(changeWorkspaceMode(_:)))
        control.segmentStyle = .rounded
        control.frame = NSRect(x: 0, y: 0, width: 108, height: 28)
        let symbols = ["square.and.pencil", "rectangle.split.2x1", "doc.text"]
        let toolTips = ["写作模式", "分栏模式", "阅读模式"]
        for index in 0..<symbols.count {
            control.setImage(NSImage(systemSymbolName: symbols[index], accessibilityDescription: toolTips[index]), forSegment: index)
            control.setToolTip(toolTips[index], forSegment: index)
            control.setWidth(35, forSegment: index)
        }
        control.selectedSegment = workspaceMode.rawValue
        workspaceModeControl = control

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "视图模式"
        item.paletteLabel = "视图模式"
        item.view = control
        return item
    }

    @objc private func openMarkdownFromToolbar() {
        // 工具栏按钮直接调用 AppDelegate，避免响应链转发失败导致“点击没有反应”。
        (NSApp.delegate as? MojiAppDelegate)?.openMarkdownDocument(self)
    }

    @objc private func applyFormattingFromToolbar(_ sender: NSSegmentedControl) {
        // 格式按钮始终把焦点带回编辑器，阅读模式下使用格式操作会自动切回写作模式。
        if workspaceMode == .reading {
            setWorkspaceMode(.writing)
        }
        switch sender.selectedSegment {
        case 0: insertBold()
        case 1: insertItalic()
        case 2: insertInlineCode()
        case 3: insertLink()
        default: break
        }
        editorController.focusEditor()
    }

    @objc private func changeWorkspaceMode(_ sender: NSSegmentedControl) {
        guard let mode = WorkspaceMode(rawValue: sender.selectedSegment) else { return }
        setWorkspaceMode(mode)
    }

    /// 应用当前工作模式。
    /// 动画只用于用户主动切换；窗口初次创建时立即布局，避免首屏出现面板闪动。
    private func applyWorkspaceMode(animated: Bool) {
        guard let editorItem, let previewItem else { return }
        let changes = {
            editorItem.isCollapsed = self.workspaceMode == .reading
            previewItem.isCollapsed = self.workspaceMode == .writing
        }
        if animated {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.18
                    editorItem.animator().isCollapsed = self.workspaceMode == .reading
                    previewItem.animator().isCollapsed = self.workspaceMode == .writing
                },
                completionHandler: { [weak self] in
                    self?.restoreSplitPositionIfNeeded()
                }
            )
        } else {
            changes()
            restoreSplitPositionIfNeeded()
        }
        workspaceModeControl?.selectedSegment = workspaceMode.rawValue
        if workspaceMode != .reading {
            editorController.focusEditor()
        }
    }

    /// 回到分栏模式时恢复用户上一次的左右比例。
    /// 保存比例而不是固定像素，窗口缩放后也能维持相同的阅读关系。
    private func restoreSplitPositionIfNeeded() {
        guard workspaceMode == .split else { return }
        let splitView = splitViewController.splitView
        guard splitView.bounds.width > 0 else { return }
        splitView.setPosition(splitView.bounds.width * lastSplitFraction, ofDividerAt: 0)
    }
}
