/**
 * 文件说明：墨记现代应用代理，替代旧 MainMenu.xib 和 Objective-C 启动控制器。
 * 作者：Codex
 * 创建时间：2026-06-17
 */

import AppKit

/// MojiAppDelegate 是墨记新的应用生命周期入口。
/// 它用代码创建菜单，避免继续依赖旧 XIB（macOS 界面布局文件）和旧 Objective-C 控制器。
final class MojiAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // macOS 菜单栏需要尽早安装；放在 willFinish 能避免窗口先创建后菜单栏仍为空的问题。
        installMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        reinstallMainMenuAfterLaunch()
        NSApp.activate(ignoringOtherApps: true)

        // 首次启动没有窗口时，主动创建一个新 Markdown 文档，避免用户看到空应用。
        if NSDocumentController.shared.documents.isEmpty,
           MojiPreferences.shared.createUntitledAtLaunch {
            NSDocumentController.shared.newDocument(nil)
        }
        installMainMenu()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 如果用户从旧包切换回来，或系统在启动期间重置了菜单，这里兜底恢复一次完整菜单。
        installMainMenu()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return MojiPreferences.shared.createUntitledAtLaunch
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        // 支持从 Finder（访达）双击、拖拽文件到 Dock 图标等系统级打开方式。
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        openMarkdownFiles(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu(title: "墨记")
        appendTopLevelMenu(makeApplicationMenuItem(), to: mainMenu)
        appendTopLevelMenu(makeFileMenuItem(), to: mainMenu)
        appendTopLevelMenu(makeEditMenuItem(), to: mainMenu)
        appendTopLevelMenu(makeInsertMenuItem(), to: mainMenu)
        appendTopLevelMenu(makeViewMenuItem(), to: mainMenu)
        appendTopLevelMenu(makeWindowMenuItem(), to: mainMenu)
        appendTopLevelMenu(makeHelpMenuItem(), to: mainMenu)
        return mainMenu
    }

    private func appendTopLevelMenu(_ item: NSMenuItem, to menu: NSMenu) {
        // AppKit 对纯代码创建的顶层菜单有时需要先 addItem 再 setSubmenu，避免只显示应用菜单。
        let submenu = item.submenu
        item.submenu = nil
        menu.addItem(item)
        if let submenu {
            menu.setSubmenu(submenu, for: item)
        }
    }

    func installMainMenu() {
        let menu = makeMainMenu()
        NSApp.mainMenu = menu
        // 显式声明窗口和服务菜单，让系统菜单栏知道哪些子菜单承担系统级职责。
        if let windowMenu = menu.item(withTitle: "窗口")?.submenu {
            NSApp.windowsMenu = windowMenu
        }
        if let servicesMenu = menu.item(withTitle: "墨记")?.submenu?.item(withTitle: "服务")?.submenu {
            NSApp.servicesMenu = servicesMenu
        }
    }

    private func reinstallMainMenuAfterLaunch() {
        // 某些 AppKit 启动流程会在 didFinish 后再安装一份默认最小菜单，导致只剩“墨记”。
        // 下一轮主线程再强制安装一次，确保“文件/编辑/格式/视图/窗口/帮助”进入系统菜单栏。
        DispatchQueue.main.async { [weak self] in
            self?.installMainMenu()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.installMainMenu()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.installMainMenu()
        }
    }

    private func makeApplicationMenuItem() -> NSMenuItem {
        let item = makeTopLevelMenuItem(title: "墨记")
        let menu = NSMenu(title: "墨记")
        menu.addItem(NSMenuItem(title: "关于墨记", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "设置…", action: #selector(showPreferences(_:)), keyEquivalent: ","))
        menu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "隐藏墨记", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOtherItem = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        // macOS 标准快捷键是 ⌥⌘H；显式增加 Option（可选键）可避免与“隐藏墨记”的 ⌘H 冲突。
        hideOtherItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOtherItem)
        menu.addItem(NSMenuItem(title: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出墨记", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = menu
        return item
    }

    private func makeFileMenuItem() -> NSMenuItem {
        let item = makeTopLevelMenuItem(title: "文件")
        let menu = NSMenu(title: "文件")
        menu.addItem(NSMenuItem(title: "新建文档", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n"))
        menu.addItem(makeMenuItem(title: "打开…", action: #selector(openMarkdownDocument(_:)), keyEquivalent: "o"))
        let recentItem = NSMenuItem(title: "最近打开", action: nil, keyEquivalent: "")
        recentItem.submenu = makeRecentDocumentsMenu()
        menu.addItem(recentItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "保存", action: #selector(NSDocument.save(_:)), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "另存为…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S"))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "导出 HTML…", action: #selector(exportHTML(_:)), keyEquivalent: "E"))
        menu.addItem(NSMenuItem(title: "恢复到已保存版本…", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: ""))
        item.submenu = menu
        return item
    }

    private func makeEditMenuItem() -> NSMenuItem {
        let item = makeTopLevelMenuItem(title: "编辑")
        let menu = NSMenu(title: "编辑")
        menu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        menu.addItem(.separator())
        menu.addItem(makeFindMenuItem(title: "查找…", action: .showFindInterface, keyEquivalent: "f"))
        menu.addItem(makeFindMenuItem(title: "查找下一个", action: .nextMatch, keyEquivalent: "g"))
        menu.addItem(makeFindMenuItem(title: "查找上一个", action: .previousMatch, keyEquivalent: "G"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "检查拼写", action: #selector(NSTextView.checkSpelling(_:)), keyEquivalent: ";"))
        item.submenu = menu
        return item
    }

    private func makeInsertMenuItem() -> NSMenuItem {
        let item = makeTopLevelMenuItem(title: "插入")
        let menu = NSMenu(title: "插入")
        // 按内容用途分组，避免功能增加后形成难以扫描的长菜单。
        menu.addItem(makeInsertSubmenu(title: "文本与列表", items: [
            makeMenuItem(title: "标题", action: #selector(insertHeading(_:)), keyEquivalent: "1"),
            makeMenuItem(title: "粗体", action: #selector(insertBold(_:)), keyEquivalent: "b"),
            makeMenuItem(title: "斜体", action: #selector(insertItalic(_:)), keyEquivalent: "i"),
            makeMenuItem(title: "行内代码", action: #selector(insertInlineCode(_:)), keyEquivalent: "`"),
            makeMenuItem(title: "任务列表", action: #selector(insertTaskList(_:)), keyEquivalent: ""),
            makeMenuItem(title: "无序列表", action: #selector(insertUnorderedList(_:)), keyEquivalent: ""),
            makeMenuItem(title: "有序列表", action: #selector(insertOrderedList(_:)), keyEquivalent: "")
        ]))
        menu.addItem(makeInsertSubmenu(title: "基础", items: [
            makeMenuItem(title: "链接", action: #selector(insertLink(_:)), keyEquivalent: "l"),
            makeMenuItem(title: "图片", action: #selector(insertImage(_:)), keyEquivalent: ""),
            makeMenuItem(title: "表格", action: #selector(insertTable(_:)), keyEquivalent: "t"),
            makeMenuItem(title: "附件", action: #selector(insertAttachment(_:)), keyEquivalent: ""),
            makeMenuItem(title: "视频", action: #selector(insertVideo(_:)), keyEquivalent: "")
        ]))
        menu.addItem(makeInsertSubmenu(title: "布局和样式", items: [
            makeMenuItem(title: "高亮提示块", action: #selector(insertAlert(_:)), keyEquivalent: ""),
            makeMenuItem(title: "内容分栏", action: #selector(insertContentColumns(_:)), keyEquivalent: ""),
            makeMenuItem(title: "引用", action: #selector(insertBlockquote(_:)), keyEquivalent: ">"),
            makeMenuItem(title: "分隔线", action: #selector(insertHorizontalRule(_:)), keyEquivalent: ""),
            makeMenuItem(title: "折叠块", action: #selector(insertDetails(_:)), keyEquivalent: "")
        ]))

        let textDiagramItem = makeInsertSubmenu(title: "文本绘图", items: [
            makeMenuItem(title: "Mermaid", action: #selector(insertMermaidDiagram(_:)), keyEquivalent: ""),
            makeMenuItem(title: "PlantUML", action: #selector(insertPlantUMLDiagram(_:)), keyEquivalent: "")
        ])
        menu.addItem(makeInsertSubmenu(title: "研发", items: [
            makeMenuItem(title: "代码块", action: #selector(insertCodeBlock(_:)), keyEquivalent: ""),
            textDiagramItem,
            makeMenuItem(title: "流程图", action: #selector(insertMermaidDiagram(_:)), keyEquivalent: ""),
            makeMenuItem(title: "UML", action: #selector(insertPlantUMLDiagram(_:)), keyEquivalent: ""),
            makeMenuItem(title: "数学公式", action: #selector(insertMathFormula(_:)), keyEquivalent: ""),
            makeMenuItem(title: "技术资产", action: #selector(insertTechnicalAsset(_:)), keyEquivalent: ""),
            makeMenuItem(title: "ZERO 文件", action: #selector(insertZeroFile(_:)), keyEquivalent: "")
        ]))
        item.submenu = menu
        return item
    }

    /// 创建“插入”菜单的二级分组，所有项目仍沿用统一的目标和可用状态校验。
    private func makeInsertSubmenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        parent.submenu = submenu
        return parent
    }

    private func makeViewMenuItem() -> NSMenuItem {
        let item = makeTopLevelMenuItem(title: "查看")
        let menu = NSMenu(title: "查看")
        // 经典三模式比左右区域独立开关更容易理解，也与主窗口工具栏保持一致。
        let workspaceModes: [(String, ModernMarkdownDocument.WorkspaceMode, String)] = [
            ("写作模式", .writing, "1"),
            ("分栏模式", .split, "2"),
            ("阅读模式", .reading, "3")
        ]
        workspaceModes.forEach { title, mode, keyEquivalent in
            let modeItem = makeMenuItem(
                title: title,
                action: #selector(selectWorkspaceMode(_:)),
                keyEquivalent: keyEquivalent,
                representedObject: mode.rawValue
            )
            modeItem.keyEquivalentModifierMask = [.command, .control]
            modeItem.state = currentDocument()?.workspaceMode == mode ? .on : .off
            menu.addItem(modeItem)
        }
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "重新载入预览", action: #selector(reloadPreview(_:)), keyEquivalent: "r"))
        menu.addItem(.separator())
        // 常用主题保留在菜单中快速切换，详细说明和插件管理仍放在设置窗口。
        let previewStyleItem = NSMenuItem(title: "预览主题", action: nil, keyEquivalent: "")
        let previewStyleMenu = NSMenu(title: "预览主题")
        ModernMarkdownStyle.allCases.forEach { style in
            previewStyleMenu.addItem(makeStyleMenuItem(for: style))
        }
        previewStyleItem.submenu = previewStyleMenu
        menu.addItem(previewStyleItem)

        let previewOptionsItem = NSMenuItem(title: "阅读选项", action: nil, keyEquivalent: "")
        let previewOptionsMenu = NSMenu(title: "阅读选项")
        previewOptionsMenu.addItem(makeMenuItem(title: "自动识别网址", action: #selector(toggleAutoLink(_:)), keyEquivalent: ""))
        previewOptionsMenu.addItem(makeMenuItem(title: "启用可选插件", action: #selector(togglePlugins(_:)), keyEquivalent: ""))
        previewOptionsMenu.addItem(.separator())
        previewOptionsMenu.addItem(makeMenuItem(title: "打开插件目录", action: #selector(openPluginDirectory(_:)), keyEquivalent: ""))
        previewOptionsItem.submenu = previewOptionsMenu
        menu.addItem(previewOptionsItem)
        item.submenu = menu
        return item
    }

    private func makeMenuItem(title: String, action: Selector, keyEquivalent: String, representedObject: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        // 自定义菜单项必须明确 target，否则 macOS 响应链找不到 AppDelegate 时会显示为不可用或点击无反应。
        item.target = self
        item.representedObject = representedObject
        if let rawValue = representedObject as? String, rawValue == MojiPreferences.shared.markdownStyle.rawValue {
            item.state = .on
        }
        if action == #selector(togglePlugins(_:)) {
            item.state = MojiPreferences.shared.pluginsEnabled ? .on : .off
        }
        if action == #selector(toggleAutoLink(_:)) {
            item.state = MojiPreferences.shared.autoLinkBareURLs ? .on : .off
        }
        return item
    }

    private func makeFindMenuItem(title: String, action: NSTextFinder.Action, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: keyEquivalent)
        item.tag = action.rawValue
        return item
    }

    private func makeRecentDocumentsMenu() -> NSMenu {
        let menu = NSMenu(title: "打开最近使用")
        let recentURLs = NSDocumentController.shared.recentDocumentURLs
        guard !recentURLs.isEmpty else {
            let emptyItem = NSMenuItem(title: "无最近文档", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return menu
        }
        recentURLs.forEach { url in
            let item = makeMenuItem(title: url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "", representedObject: url)
            item.toolTip = url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "清除菜单", action: #selector(clearRecentDocuments(_:)), keyEquivalent: ""))
        return menu
    }

    private func makeTopLevelMenuItem(title: String) -> NSMenuItem {
        // 顶层菜单项必须有标题；空标题在部分 macOS 版本上会导致菜单栏点击没有反应。
        return NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func makeStyleMenuItem(for style: ModernMarkdownStyle) -> NSMenuItem {
        let item = makeMenuItem(title: style.displayName, action: #selector(changeMarkdownStyle(_:)), keyEquivalent: "", representedObject: style.rawValue)
        item.state = MojiPreferences.shared.markdownStyle == style ? .on : .off
        return item
    }

    private func makeWindowMenuItem() -> NSMenuItem {
        let item = makeTopLevelMenuItem(title: "窗口")
        let menu = NSMenu(title: "窗口")
        menu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "全部置于前面", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = menu
        item.submenu = menu
        return item
    }

    private func makeHelpMenuItem() -> NSMenuItem {
        let item = makeTopLevelMenuItem(title: "帮助")
        let menu = NSMenu(title: "帮助")
        menu.addItem(makeMenuItem(title: "墨记帮助", action: #selector(showHelp(_:)), keyEquivalent: "?"))
        menu.addItem(makeMenuItem(title: "Markdown 语法速查", action: #selector(showMarkdownCheatsheet(_:)), keyEquivalent: ""))
        item.submenu = menu
        return item
    }

    @objc private func changeMarkdownStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let style = ModernMarkdownStyle(rawValue: rawValue) else {
            return
        }
        MojiPreferences.shared.markdownStyle = style
        refreshOpenDocuments()
        NSApp.mainMenu = makeMainMenu()
    }

    @objc func openMarkdownDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "打开 Markdown 文件"
        panel.message = "选择 .md、.markdown、.mdown、.mkd 或 .txt 文件。"
        panel.prompt = "打开"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["md", "markdown", "mdown", "mkd", "txt"]
        // 使用同步 runModal（模态运行）而不是 begin 回调，避免菜单或工具栏点击后面板被当前窗口状态吞掉。
        guard panel.runModal() == .OK else { return }
        openMarkdownFiles(panel.urls)
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openMarkdownFiles([url])
    }

    @objc private func clearRecentDocuments(_ sender: NSMenuItem) {
        NSDocumentController.shared.clearRecentDocuments(nil)
        NSApp.mainMenu = makeMainMenu()
    }

    func openMarkdownFiles(_ urls: [URL]) {
        urls.forEach { url in
            do {
                // 直接创建墨记文档并读取文件，避免系统提示“打不开格式为 Markdown 的文件”。
                let document = ModernMarkdownDocument()
                try document.loadMarkdownFile(at: url)
                NSDocumentController.shared.addDocument(document)
                document.presentLoadedDocument()
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func togglePlugins(_ sender: NSMenuItem) {
        MojiPreferences.shared.pluginsEnabled.toggle()
        refreshOpenDocuments()
        NSApp.mainMenu = makeMainMenu()
    }

    @objc private func toggleAutoLink(_ sender: NSMenuItem) {
        MojiPreferences.shared.autoLinkBareURLs.toggle()
        refreshOpenDocuments()
        NSApp.mainMenu = makeMainMenu()
    }

    @objc private func openPluginDirectory(_ sender: NSMenuItem) {
        MojiPluginManager.shared.ensurePluginDirectoryExists()
        NSWorkspace.shared.open(MojiPluginManager.shared.pluginDirectory)
    }

    @objc private func reloadPreview(_ sender: NSMenuItem) {
        refreshOpenDocuments()
    }

    /// 导出当前文档为可独立打开的 HTML（网页文件）。
    @objc private func exportHTML(_ sender: NSMenuItem) {
        currentDocument()?.exportHTML()
    }

    /// 从系统菜单切换当前文档的工作模式，并同步刷新菜单勾选状态。
    @objc private func selectWorkspaceMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let mode = ModernMarkdownDocument.WorkspaceMode(rawValue: rawValue) else {
            return
        }
        currentDocument()?.setWorkspaceMode(mode)
        NSApp.mainMenu = makeMainMenu()
    }

    @objc private func showPreferences(_ sender: NSMenuItem) {
        // 统一使用原生设置窗口承载主题、插件和预览增强选项，避免功能散落在多个菜单里。
        MojiPreferencesWindowController.shared.show()
    }

    @objc private func showHelp(_ sender: NSMenuItem) {
        showInformationalAlert(
            title: "墨记帮助",
            message: "墨记是一个轻量 Markdown 编辑和预览工具。你可以通过“文件 → 打开…”打开文档，通过“插入”菜单快速添加标题、链接、表格等 Markdown 片段，并在“墨记 → 设置… → 插件”中管理预览扩展。"
        )
    }

    @objc private func showMarkdownCheatsheet(_ sender: NSMenuItem) {
        showInformationalAlert(
            title: "Markdown 语法速查",
            message: "# 一级标题\n## 二级标题\n**粗体**  *斜体*  `代码`\n[链接](https://example.com)\n- [ ] 任务\n| 列 A | 列 B |\n| --- | --- |\n\n扩展内容可通过“插入 → 布局和样式”或“插入 → 研发”快速添加。"
        )
    }

    @objc private func insertBold(_ sender: NSMenuItem) { currentDocument()?.insertBold() }
    @objc private func insertItalic(_ sender: NSMenuItem) { currentDocument()?.insertItalic() }
    @objc private func insertInlineCode(_ sender: NSMenuItem) { currentDocument()?.insertInlineCode() }
    @objc private func insertLink(_ sender: NSMenuItem) { currentDocument()?.insertLink() }
    @objc private func insertImage(_ sender: NSMenuItem) { currentDocument()?.insertImage() }
    @objc private func insertAttachment(_ sender: NSMenuItem) { currentDocument()?.insertAttachment() }
    @objc private func insertVideo(_ sender: NSMenuItem) { currentDocument()?.insertVideo() }
    @objc private func insertHeading(_ sender: NSMenuItem) { currentDocument()?.insertHeading() }
    @objc private func insertBlockquote(_ sender: NSMenuItem) { currentDocument()?.insertBlockquote() }
    @objc private func insertAlert(_ sender: NSMenuItem) { currentDocument()?.insertAlert() }
    @objc private func insertContentColumns(_ sender: NSMenuItem) { currentDocument()?.insertContentColumns() }
    @objc private func insertDetails(_ sender: NSMenuItem) { currentDocument()?.insertDetails() }
    @objc private func insertCodeBlock(_ sender: NSMenuItem) { currentDocument()?.insertCodeBlock() }
    @objc private func insertMermaidDiagram(_ sender: NSMenuItem) { currentDocument()?.insertMermaidDiagram() }
    @objc private func insertPlantUMLDiagram(_ sender: NSMenuItem) { currentDocument()?.insertPlantUMLDiagram() }
    @objc private func insertMathFormula(_ sender: NSMenuItem) { currentDocument()?.insertMathFormula() }
    @objc private func insertTechnicalAsset(_ sender: NSMenuItem) { currentDocument()?.insertTechnicalAsset() }
    @objc private func insertZeroFile(_ sender: NSMenuItem) { currentDocument()?.insertZeroFile() }
    @objc private func insertTaskList(_ sender: NSMenuItem) { currentDocument()?.insertTaskList() }
    @objc private func insertUnorderedList(_ sender: NSMenuItem) { currentDocument()?.insertUnorderedList() }
    @objc private func insertOrderedList(_ sender: NSMenuItem) { currentDocument()?.insertOrderedList() }
    @objc private func insertTable(_ sender: NSMenuItem) { currentDocument()?.insertTable() }
    @objc private func insertHorizontalRule(_ sender: NSMenuItem) { currentDocument()?.insertHorizontalRule() }

    private func refreshOpenDocuments() {
        NSDocumentController.shared.documents
            .compactMap { $0 as? ModernMarkdownDocument }
            .forEach { $0.refreshPreviewFromPreferences() }
    }

    private func currentDocument() -> ModernMarkdownDocument? {
        // 优先使用当前 keyWindow（正在操作的窗口）对应的文档，避免多窗口时插入到错误文档。
        return NSApp.keyWindow?.windowController?.document as? ModernMarkdownDocument
            ?? NSDocumentController.shared.currentDocument as? ModernMarkdownDocument
    }

    private func showInformationalAlert(title: String, message: String) {
        // 帮助菜单先用原生弹窗承载，后续可以替换为独立帮助窗口或本地文档页。
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let documentRequiredActions: [Selector] = [
            #selector(insertBold(_:)),
            #selector(insertItalic(_:)),
            #selector(insertInlineCode(_:)),
            #selector(insertLink(_:)),
            #selector(insertImage(_:)),
            #selector(insertAttachment(_:)),
            #selector(insertVideo(_:)),
            #selector(insertHeading(_:)),
            #selector(insertBlockquote(_:)),
            #selector(insertAlert(_:)),
            #selector(insertContentColumns(_:)),
            #selector(insertDetails(_:)),
            #selector(insertCodeBlock(_:)),
            #selector(insertMermaidDiagram(_:)),
            #selector(insertPlantUMLDiagram(_:)),
            #selector(insertMathFormula(_:)),
            #selector(insertTechnicalAsset(_:)),
            #selector(insertZeroFile(_:)),
            #selector(insertTaskList(_:)),
            #selector(insertUnorderedList(_:)),
            #selector(insertOrderedList(_:)),
            #selector(insertTable(_:)),
            #selector(insertHorizontalRule(_:)),
            #selector(exportHTML(_:)),
            #selector(selectWorkspaceMode(_:)),
            #selector(reloadPreview(_:))
        ]
        // 插入类菜单只有在当前存在 Markdown 文档时才可用，避免点击后看似无反应。
        if let action = menuItem.action, documentRequiredActions.contains(action) {
            return currentDocument() != nil
        }
        return true
    }
}
