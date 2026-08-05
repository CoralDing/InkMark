/**
 * 文件说明：墨记设置窗口，使用更接近 macOS 系统设置的原生列表和表单布局。
 * 作者：Codex
 * 创建时间：2026-06-18
 */

import AppKit

/// MojiSettingsSidebarRowView 负责绘制设置侧栏的轻量选中态。
/// 系统默认整行高饱和蓝色会压过页面内容，因此改用带圆角的半透明强调色，同时保留原生键盘选择行为。
private final class MojiSettingsSidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let selectionRect = bounds.insetBy(dx: 4, dy: 2)
        let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.16 : 0.1).setFill()
        selectionPath.fill()
    }
}

/// MojiSettingsDocumentView 为设置右侧滚动区域提供从上到下的坐标系。
/// NSView 默认从左下角计算坐标，短页面放进 NSScrollView 后容易贴近底部；翻转后内容会稳定从顶部开始排列。
private final class MojiSettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// MojiPreferencesWindowController 使用 AppKit（macOS 原生 UI 框架）构建设置窗口。
/// 这一版尽量减少自定义视觉：左侧用 NSTableView（原生表格列表），右侧用规则表单，优先保证对齐和稳定。
final class MojiPreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = MojiPreferencesWindowController()

    /// SettingsSection 表示设置页分类。
    /// 右侧内容根据当前分类重建，避免多个页面控件互相影响布局。
    private enum SettingsSection: Int, CaseIterable {
        case general
        case preview
        case editor
        case plugins
        case about

        var title: String {
            switch self {
            case .general: return "通用"
            case .preview: return "预览"
            case .editor: return "编辑"
            case .plugins: return "插件"
            case .about: return "关于"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .preview: return "doc.richtext"
            case .editor: return "keyboard"
            case .plugins: return "puzzlepiece.extension"
            case .about: return "info.circle"
            }
        }

        /// 页面副标题只说明当前分类的目标，避免标题下方出现冗长的功能教学。
        var subtitle: String {
            switch self {
            case .general: return "文档、启动与常用操作"
            case .preview: return "阅读样式与 Markdown 展示"
            case .editor: return "写作外观与编辑辅助"
            case .plugins: return "管理内置增强与本地脚本"
            case .about: return "专注、清晰的 Markdown 工具"
            }
        }
    }

    private enum Layout {
        static let windowSize = NSSize(width: 800, height: 600)
        static let minimumWindowWidth: CGFloat = 760
        static let sidebarWidth: CGFloat = 196
        static let contentWidth: CGFloat = 520
        static let textColumnWidth: CGFloat = 320
        static let rowHeight: CGFloat = 58
    }

    private let tableView = NSTableView()
    private let contentStack = NSStackView()
    private let contentScrollView = NSScrollView()
    private let stylePopUp = NSPopUpButton()
    private let previewWidthPopUp = NSPopUpButton()
    private let editorFontSizePopUp = NSPopUpButton()
    private let autoLinkSwitch = NSSwitch()
    private let createUntitledSwitch = NSSwitch()
    private let pluginsSwitch = NSSwitch()
    private let pluginPathLabel = NSTextField(labelWithString: MojiPluginManager.shared.pluginDirectory.path)
    private var selectedSection: SettingsSection = .general

    private init() {
        let contentController = NSViewController()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Layout.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        // 设置窗口只允许横向调整，固定内容区高度可避免不同分类之间产生窗口跳动。
        window.contentMinSize = NSSize(width: Layout.minimumWindowWidth, height: Layout.windowSize.height)
        window.contentMaxSize = NSSize(width: .greatestFiniteMagnitude, height: Layout.windowSize.height)
        window.contentViewController = contentController
        contentController.preferredContentSize = Layout.windowSize
        window.setContentSize(Layout.windowSize)
        // 自动保存只沿用窗口位置和宽度；旧版本保存过的其他高度会在恢复后统一校正为 600。
        let restoredSavedFrame = window.setFrameAutosaveName("Moji.PreferencesWindow")
        let restoredContentWidth = max(window.contentLayoutRect.width, Layout.minimumWindowWidth)
        window.setContentSize(NSSize(width: restoredContentWidth, height: Layout.windowSize.height))
        if !restoredSavedFrame {
            window.center()
        }
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureControls()
        buildInterface(in: contentController)
        reloadFromPreferences()
        selectSection(.general)
    }

    required init?(coder: NSCoder) {
        fatalError("MojiPreferencesWindowController 不支持从 Storyboard（可视化界面文件）创建。")
    }

    /// 显示设置窗口并刷新设置状态。
    func show() {
        reloadFromPreferences()
        selectSection(selectedSection)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 初始化右侧复用控件。
    /// 复用控件能保证切换页面后开关和下拉框仍然保持真实偏好状态。
    private func configureControls() {
        ModernMarkdownStyle.allCases.forEach { style in
            stylePopUp.addItem(withTitle: style.displayName)
            stylePopUp.lastItem?.representedObject = style.rawValue
        }
        stylePopUp.target = self
        stylePopUp.action = #selector(changeStyle(_:))
        stylePopUp.controlSize = .regular
        stylePopUp.translatesAutoresizingMaskIntoConstraints = false
        stylePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true

        [("紧凑", 720), ("标准", 900), ("宽屏", 1100)].forEach { title, width in
            previewWidthPopUp.addItem(withTitle: title)
            previewWidthPopUp.lastItem?.representedObject = width
        }
        previewWidthPopUp.target = self
        previewWidthPopUp.action = #selector(changePreviewWidth(_:))
        previewWidthPopUp.controlSize = .regular
        previewWidthPopUp.translatesAutoresizingMaskIntoConstraints = false
        previewWidthPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true

        [13, 14, 15, 16, 18, 20].forEach { size in
            editorFontSizePopUp.addItem(withTitle: "\(size) pt")
            editorFontSizePopUp.lastItem?.representedObject = Double(size)
        }
        editorFontSizePopUp.target = self
        editorFontSizePopUp.action = #selector(changeEditorFontSize(_:))
        editorFontSizePopUp.controlSize = .regular
        editorFontSizePopUp.translatesAutoresizingMaskIntoConstraints = false
        editorFontSizePopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

        autoLinkSwitch.target = self
        autoLinkSwitch.action = #selector(toggleAutoLink(_:))
        autoLinkSwitch.translatesAutoresizingMaskIntoConstraints = false

        createUntitledSwitch.target = self
        createUntitledSwitch.action = #selector(toggleCreateUntitled(_:))
        createUntitledSwitch.translatesAutoresizingMaskIntoConstraints = false

        pluginsSwitch.target = self
        pluginsSwitch.action = #selector(togglePlugins(_:))
        pluginsSwitch.translatesAutoresizingMaskIntoConstraints = false

        pluginPathLabel.font = .systemFont(ofSize: 12)
        pluginPathLabel.textColor = .secondaryLabelColor
        pluginPathLabel.lineBreakMode = .byTruncatingMiddle
        pluginPathLabel.alignment = .left
        pluginPathLabel.maximumNumberOfLines = 1
        pluginPathLabel.toolTip = MojiPluginManager.shared.pluginDirectory.path
    }

    /// 创建窗口骨架。
    /// 左侧使用 NSTableView 原生列表，右侧使用 NSGridView 表单，尽量让系统自己处理基础对齐。
    private func buildInterface(in controller: NSViewController) {
        let rootView = NSVisualEffectView(frame: NSRect(origin: .zero, size: Layout.windowSize))
        rootView.material = .underWindowBackground
        rootView.blendingMode = .behindWindow
        rootView.state = .active

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .width
        sidebarStack.spacing = 18
        sidebarStack.edgeInsets = NSEdgeInsets(top: 22, left: 10, bottom: 14, right: 10)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false

        sidebarStack.addArrangedSubview(makeSidebarHeader())
        sidebarStack.addArrangedSubview(makeSidebarList())
        sidebar.addSubview(sidebarStack)

        let contentBackground = NSVisualEffectView()
        contentBackground.material = .contentBackground
        contentBackground.blendingMode = .withinWindow
        contentBackground.state = .active
        contentBackground.translatesAutoresizingMaskIntoConstraints = false

        contentScrollView.drawsBackground = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = MojiSettingsDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .gravityAreas
        contentStack.spacing = 18
        contentStack.edgeInsets = NSEdgeInsets(top: 30, left: 0, bottom: 32, right: 0)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        // 短页面必须保持内容自身高度，否则堆叠视图会被窗口高度拉伸并把控件放到垂直中间。
        contentStack.setHuggingPriority(.required, for: .vertical)
        contentStack.setContentCompressionResistancePriority(.required, for: .vertical)
        documentView.addSubview(contentStack)
        contentScrollView.documentView = documentView

        rootView.addSubview(sidebar)
        rootView.addSubview(contentBackground)
        contentBackground.addSubview(contentScrollView)
        controller.view = rootView

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: rootView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth),

            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarStack.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor),

            contentBackground.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentBackground.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentBackground.topAnchor.constraint(equalTo: rootView.topAnchor),
            contentBackground.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            contentScrollView.leadingAnchor.constraint(equalTo: contentBackground.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: contentBackground.trailingAnchor),
            contentScrollView.topAnchor.constraint(equalTo: contentBackground.topAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: contentBackground.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor),
            documentView.leadingAnchor.constraint(equalTo: contentScrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: contentScrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: contentScrollView.contentView.topAnchor),
            // 文档至少铺满可视区域；内容较长时再由内容栈自然撑高，保证滚动范围准确。
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: contentScrollView.contentView.heightAnchor),

            contentStack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
            contentStack.widthAnchor.constraint(equalToConstant: Layout.contentWidth),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor)
        ])

        // 低优先级等式让长页面的文档高度跟随内容，同时不会把短页面内容强行拉到窗口高度。
        let contentBottomConstraint = contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        contentBottomConstraint.priority = .defaultHigh
        contentBottomConstraint.isActive = true
    }

    private func makeSidebarHeader() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "墨记")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        let subtitle = NSTextField(labelWithString: "设置")
        subtitle.font = .systemFont(ofSize: 11.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(subtitle)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2)
        ])
        return container
    }

    private func makeSidebarList() -> NSView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        column.width = Layout.sidebarWidth - 24
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 38
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 206)
        ])
        return scrollView
    }

    /// 从偏好设置读取最新值。
    private func reloadFromPreferences() {
        stylePopUp.selectItem(withTitle: MojiPreferences.shared.markdownStyle.displayName)
        if let widthItem = previewWidthPopUp.itemArray.first(where: {
            ($0.representedObject as? Int) == MojiPreferences.shared.previewContentWidth
        }) {
            previewWidthPopUp.select(widthItem)
        }
        if let fontItem = editorFontSizePopUp.itemArray.first(where: {
            ($0.representedObject as? Double) == MojiPreferences.shared.editorFontSize
        }) {
            editorFontSizePopUp.select(fontItem)
        }
        autoLinkSwitch.state = MojiPreferences.shared.autoLinkBareURLs ? .on : .off
        createUntitledSwitch.state = MojiPreferences.shared.createUntitledAtLaunch ? .on : .off
        pluginsSwitch.state = MojiPreferences.shared.pluginsEnabled ? .on : .off
        pluginPathLabel.stringValue = MojiPluginManager.shared.pluginDirectory.path
        pluginPathLabel.toolTip = MojiPluginManager.shared.pluginDirectory.path
    }

    private func selectSection(_ section: SettingsSection) {
        selectedSection = section
        tableView.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        // 所有设置项都放进顶部重力区域；窗口较高时，多余空间只保留在底部，不拉伸任何卡片。
        let pageViews = [makeTitle(section.title, subtitle: section.subtitle)] + makeSections(for: section)
        contentStack.setViews(pageViews, in: .top)
        // 页面高度和滚动范围会在本轮布局结束后更新，延后一轮才能可靠回到新的顶部。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.contentScrollView.contentView.scroll(to: .zero)
            self.contentScrollView.reflectScrolledClipView(self.contentScrollView.contentView)
        }
    }

    private func makeSections(for section: SettingsSection) -> [NSView] {
        switch section {
        case .general:
            return [
                makeFormSection(title: "文件", rows: [
                    makeRow(label: "打开文件", detail: "支持 Markdown 与文本文件", control: makeButton("打开…", action: #selector(openMarkdownDocument(_:)))),
                    makeRow(label: "新建空白文档", detail: "启动时没有其他文档则自动创建", control: createUntitledSwitch)
                ]),
                makeFormSection(title: "快捷键", rows: [
                    makeRow(label: "新建文档", detail: "创建空白 Markdown 文档", value: "⌘N"),
                    makeRow(label: "打开文件", detail: "选择本地文档", value: "⌘O"),
                    makeRow(label: "设置", detail: "打开设置窗口", value: "⌘,")
                ])
            ]
        case .preview:
            return [
                makeFormSection(title: "显示", rows: [
                    makeRow(label: "预览风格", detail: "控制预览区样式", control: stylePopUp),
                    makeRow(label: "内容宽度", detail: "调整文档阅读行宽", control: previewWidthPopUp),
                    makeRow(label: "自动链接", detail: "识别纯文本网址", control: autoLinkSwitch)
                ]),
                makeFormSection(title: "能力", rows: [
                    makeRow(label: "表格", detail: "GitHub 风格表格", value: "支持"),
                    makeRow(label: "任务列表", detail: "- [ ] 与 - [x]", value: "支持"),
                    makeRow(label: "代码块", detail: "保留语言标记", value: "支持")
                ])
            ]
        case .editor:
            return [
                makeFormSection(title: "写作", rows: [
                    makeRow(label: "编辑字号", detail: "调整 Markdown 源码字号", control: editorFontSizePopUp),
                    makeRow(label: "基础样式", detail: "标题、粗体、斜体、代码", value: "插入菜单"),
                    makeRow(label: "内容块", detail: "链接、图片、引用、表格", value: "插入菜单"),
                    makeRow(label: "查找拼写", detail: "系统原生编辑能力", value: "编辑菜单")
                ]),
                makeFormSection(title: "帮助", rows: [
                    makeRow(label: "语法速查", detail: "查看 Markdown 示例", control: makeButton("查看", action: #selector(showMarkdownCheatsheet(_:))))
                ])
            ]
        case .plugins:
            return makePluginSections()
        case .about:
            return [
                makeAboutOverview(),
                makeFormSection(title: "应用信息", rows: [
                    makeRow(label: "技术架构", detail: "Swift、AppKit 与 WebKit", value: "macOS 原生"),
                    makeRow(label: "开源许可", detail: "允许使用、修改和分发", value: "MIT License"),
                    makeRow(label: "数据存储", detail: "文档和设置均保留在本机", value: "本地优先")
                ])
            ]
        }
    }

    /// 创建完整的插件设置区域。
    /// 核心格式能力单独说明，可选内置增强和用户脚本仍可按需启停。
    private func makePluginSections() -> [NSView] {
        let descriptors = MojiPluginManager.shared.availablePlugins()
        let builtInPlugins = descriptors.filter { $0.source == .builtIn }
        let userPlugins = descriptors.filter { $0.source == .user }

        let managementSection = makeFormSection(title: "管理", rows: [
            makeRow(label: "启用可选插件", detail: "控制目录、代码复制和用户脚本", control: pluginsSwitch),
            makeRow(label: "用户插件", detail: "添加、打开目录或重新扫描", control: makePluginActionControls()),
            makeRow(label: "当前路径", detail: "插件目录完整路径", control: pluginPathLabel)
        ])

        let corePreviewSection = makeFormSection(title: "核心预览", rows: [
            makeRow(label: "Mermaid", detail: "在本机将 mermaid 代码块渲染为图表", value: "始终启用"),
            makeRow(label: "PlantUML", detail: "使用内置 Java 运行时在本机生成 SVG", value: "始终启用"),
            makeRow(label: "数学公式", detail: "使用本地 KaTeX 渲染 LaTeX 公式", value: "始终启用")
        ])

        let builtInSection = makeFormSection(
            title: "内置插件",
            rows: builtInPlugins.map(makePluginRow)
        )

        let userRows: [NSView]
        if userPlugins.isEmpty {
            userRows = [
                makeRow(
                    label: "尚未安装用户插件",
                    detail: "添加 .js 文件后可在这里单独启停",
                    control: makeButton("添加…", action: #selector(addPluginFiles(_:)))
                )
            ]
        } else {
            userRows = userPlugins.map(makePluginRow)
        }

        return [
            managementSection,
            corePreviewSection,
            builtInSection,
            makeFormSection(title: "用户插件（\(userPlugins.count)）", rows: userRows),
            makeFormSection(title: "安全", rows: [
                makeRow(label: "脚本权限", detail: "可修改当前预览，但不能调用墨记原生接口", value: "预览页内")
            ])
        ]
    }

    /// 创建单个插件设置行。
    private func makePluginRow(_ descriptor: MojiPluginDescriptor) -> NSView {
        return makeRow(
            label: descriptor.displayName,
            detail: descriptor.detail,
            control: makePluginControl(descriptor)
        )
    }

    /// 创建插件行右侧控制区。
    /// 用户插件额外提供“在访达中显示”按钮，内置插件只需要开关。
    private func makePluginControl(_ descriptor: MojiPluginDescriptor) -> NSView {
        let toggle = NSSwitch()
        toggle.identifier = NSUserInterfaceItemIdentifier(descriptor.identifier)
        toggle.state = descriptor.isEnabled ? .on : .off
        toggle.isEnabled = MojiPreferences.shared.pluginsEnabled
        toggle.target = self
        toggle.action = #selector(toggleIndividualPlugin(_:))

        var controls: [NSView] = []
        if descriptor.source == .user {
            let revealButton = makeIconButton(
                symbolName: "magnifyingglass",
                toolTip: "在访达中显示",
                action: #selector(revealPluginFile(_:))
            )
            revealButton.identifier = NSUserInterfaceItemIdentifier(descriptor.identifier)
            controls.append(revealButton)
        }
        controls.append(toggle)

        let stack = NSStackView(views: controls)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    /// 创建用户插件管理操作，使用图标承载刷新和文件夹等熟悉动作。
    private func makePluginActionControls() -> NSView {
        let addButton = makeButton("添加…", action: #selector(addPluginFiles(_:)))
        let folderButton = makeIconButton(
            symbolName: "folder",
            toolTip: "打开插件目录",
            action: #selector(openPluginDirectory(_:))
        )
        let refreshButton = makeIconButton(
            symbolName: "arrow.clockwise",
            toolTip: "重新扫描插件",
            action: #selector(rescanPlugins(_:))
        )
        let stack = NSStackView(views: [addButton, folderButton, refreshButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    /// 创建关于页的品牌概览。
    /// 这里不再重复普通表单内容，而是用应用图标、名称和一句定位建立清晰的视觉中心。
    private func makeAboutOverview() -> NSView {
        let container = NSVisualEffectView()
        container.material = .contentBackground
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.34).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "墨记")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let version = NSTextField(labelWithString: appVersionText())
        version.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        version.textColor = .secondaryLabelColor
        version.translatesAutoresizingMaskIntoConstraints = false

        let summary = NSTextField(labelWithString: "专注于 Markdown 写作、阅读与本地扩展。")
        summary.font = .systemFont(ofSize: 12.5)
        summary.textColor = .secondaryLabelColor
        summary.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(version)
        container.addSubview(summary)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Layout.contentWidth),
            container.heightAnchor.constraint(equalToConstant: 116),
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 18),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 25),
            version.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 9),
            version.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            summary.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            summary.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8)
        ])
        return container
    }

    /// 读取应用版本并生成稳定的展示文本；开发构建缺少版本字段时提供明确回退值。
    private func appVersionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "版本 \(version)（\(build)）"
    }

    /// 创建页面标题和副标题，让每个分类拥有一致的信息层级。
    private func makeTitle(_ title: String, subtitle: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Layout.contentWidth),
            container.heightAnchor.constraint(equalToConstant: 52),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4)
        ])
        return container
    }

    private func makeFormSection(title: String, rows: [NSView]) -> NSView {
        // 分组使用显式容器约束，避免 NSStackView 根据固有尺寸把标题和卡片压到右侧。
        // 页面标题、分组标题和卡片由此共享同一条左边线，视觉上更接近 macOS 系统设置。
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = NSStackView()
        rowStack.orientation = .vertical
        rowStack.alignment = .width
        rowStack.distribution = .fill
        rowStack.spacing = 0
        rows.enumerated().forEach { index, row in
            rowStack.addArrangedSubview(row)
            if index < rows.count - 1 {
                rowStack.addArrangedSubview(makeSeparator())
            }
        }

        let background = NSVisualEffectView()
        background.material = .contentBackground
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.cornerCurve = .continuous
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.34).cgColor
        background.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(rowStack)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: background.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])

        container.addSubview(titleLabel)
        container.addSubview(background)
        // 每行和分隔线都有固定高度，显式计算卡片高度可防止短分组被窗口剩余空间拉长。
        let rowContentHeight = CGFloat(rows.count) * Layout.rowHeight
        let separatorHeight = CGFloat(max(0, rows.count - 1))
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Layout.contentWidth),

            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),

            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            background.heightAnchor.constraint(equalToConstant: rowContentHeight + separatorHeight),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeRow(label: String, detail: String, value: String) -> NSView {
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 13)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle
        return makeRow(label: label, detail: detail, control: valueLabel)
    }

    private func makeRow(label: String, detail: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let controlContainer = NSView()
        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.addSubview(control)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(textStack)
        row.addSubview(controlContainer)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: Layout.rowHeight),

            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            textStack.widthAnchor.constraint(equalToConstant: Layout.textColumnWidth),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            controlContainer.leadingAnchor.constraint(equalTo: textStack.trailingAnchor, constant: 18),
            controlContainer.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            controlContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            controlContainer.heightAnchor.constraint(equalTo: row.heightAnchor),

            control.leadingAnchor.constraint(greaterThanOrEqualTo: controlContainer.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: controlContainer.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: controlContainer.centerYAnchor)
        ])
        return row
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    /// 创建紧凑图标按钮，并提供工具提示说明不熟悉的图标动作。
    private func makeIconButton(symbolName: String, toolTip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 26)
        ])
        return button
    }

    private func makeSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        // 分隔线从文字区域起始处绘制，避免整行切割造成过强的表格感。
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 1),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            separator.topAnchor.constraint(equalTo: container.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
        return container
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return SettingsSection.allCases.count
    }

    /// 返回自定义侧栏行视图，仅改变选中态绘制，不影响 NSTableView 的键盘导航和辅助功能。
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return MojiSettingsSidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard SettingsSection.allCases.indices.contains(row) else { return nil }
        let section = SettingsSection.allCases[row]
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("sectionCell")

        let imageView = NSImageView(image: NSImage(systemSymbolName: section.icon, accessibilityDescription: section.title) ?? NSImage())
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: section.title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(imageView)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard SettingsSection.allCases.indices.contains(row) else { return }
        let section = SettingsSection.allCases[row]
        guard section != selectedSection else { return }
        selectSection(section)
    }

    @objc private func changeStyle(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let style = ModernMarkdownStyle(rawValue: rawValue) else { return }
        MojiPreferences.shared.markdownStyle = style
        refreshOpenDocuments()
    }

    /// 修改预览内容宽度并立即刷新所有文档。
    @objc private func changePreviewWidth(_ sender: NSPopUpButton) {
        guard let width = sender.selectedItem?.representedObject as? Int else { return }
        MojiPreferences.shared.previewContentWidth = width
        refreshOpenDocuments()
    }

    /// 修改编辑器字号并立即应用到所有已打开文档。
    @objc private func changeEditorFontSize(_ sender: NSPopUpButton) {
        guard let size = sender.selectedItem?.representedObject as? Double else { return }
        MojiPreferences.shared.editorFontSize = size
        refreshOpenDocuments()
    }

    @objc private func toggleAutoLink(_ sender: NSSwitch) {
        MojiPreferences.shared.autoLinkBareURLs = sender.state == .on
        refreshOpenDocuments()
    }

    /// 控制应用在没有恢复文档时是否创建空白窗口；设置会在下次启动时生效。
    @objc private func toggleCreateUntitled(_ sender: NSSwitch) {
        MojiPreferences.shared.createUntitledAtLaunch = sender.state == .on
    }

    @objc private func togglePlugins(_ sender: NSSwitch) {
        MojiPreferences.shared.pluginsEnabled = sender.state == .on
        refreshOpenDocuments()
        // 总开关变化后重建本页，让可选插件开关同步进入可用或禁用状态。
        selectSection(.plugins)
    }

    @objc private func openMarkdownDocument(_ sender: Any?) {
        NSApp.delegate.flatMap { $0 as? MojiAppDelegate }?.openMarkdownDocument(sender)
    }

    @objc private func openPluginDirectory(_ sender: Any?) {
        MojiPluginManager.shared.ensurePluginDirectoryExists()
        NSWorkspace.shared.open(MojiPluginManager.shared.pluginDirectory)
    }

    /// 添加用户插件文件，并在完成后刷新插件列表和所有预览。
    @objc private func addPluginFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "添加预览插件"
        panel.message = "选择可信的 JavaScript（脚本语言）文件。插件会在本地预览页面中运行。"
        panel.prompt = "添加"
        panel.allowedFileTypes = ["js"]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }

        do {
            try MojiPluginManager.shared.installPluginFiles(from: panel.urls)
            reloadPluginSectionAndPreviews()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// 重新读取插件目录，用于用户在访达中手动增删脚本后的即时同步。
    @objc private func rescanPlugins(_ sender: Any?) {
        reloadPluginSectionAndPreviews()
    }

    /// 切换单个插件，不影响其他插件和总开关。
    @objc private func toggleIndividualPlugin(_ sender: NSSwitch) {
        guard let identifier = sender.identifier?.rawValue else { return }
        MojiPluginManager.shared.setPlugin(identifier: identifier, isEnabled: sender.state == .on)
        refreshOpenDocuments()
    }

    /// 在访达中定位指定用户插件，方便查看、编辑或移除脚本文件。
    @objc private func revealPluginFile(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue,
              let fileURL = MojiPluginManager.shared.availablePlugins().first(where: {
                  $0.identifier == identifier
              })?.fileURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// 重建插件设置页并立即刷新已打开文档。
    private func reloadPluginSectionAndPreviews() {
        reloadFromPreferences()
        selectSection(.plugins)
        refreshOpenDocuments()
    }

    @objc private func showMarkdownCheatsheet(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Markdown 语法速查"
        alert.informativeText = "# 一级标题\n## 二级标题\n**粗体**  *斜体*  `代码`\n[链接](https://example.com)\n- [ ] 任务\n| 列 A | 列 B |\n| --- | --- |"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func refreshOpenDocuments() {
        NSDocumentController.shared.documents
            .compactMap { $0 as? ModernMarkdownDocument }
            .forEach { $0.refreshPreviewFromPreferences() }
    }
}
