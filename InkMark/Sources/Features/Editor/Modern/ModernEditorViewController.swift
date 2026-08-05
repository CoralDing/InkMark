/**
 * 文件说明：墨记现代编辑器控制器，提供 Swift/AppKit 文本编辑入口。
 * 作者：Codex
 * 创建时间：2026-06-17
 */

import AppKit

/// ModernEditorViewController 是新架构里的编辑器视图控制器。
/// 它使用 NSTextView（macOS 原生文本编辑控件）并通过轻量样式优化写作体验。
final class ModernEditorViewController: NSViewController, NSTextViewDelegate {
    /// EditorPalette 保存源码区与预览主题对应的核心颜色。
    /// 两侧使用同一组视觉语义，可以避免夜间预览配浅色编辑器造成强烈割裂。
    private struct EditorPalette {
        let background: NSColor
        let text: NSColor
        let accent: NSColor
        let link: NSColor
        let codeBackground: NSColor
        let inlineCode: NSColor
    }

    private let containerView = AppearanceAwareEditorView()
    private let scrollView = NSScrollView()
    private(set) var textView = NSTextView()
    private var isApplyingSyntaxHighlighting = false
    private var lineStartOffsets: [Int] = [0]
    private var scrollObservation: NSObjectProtocol?
    private var pendingScrollCallback: DispatchWorkItem?
    private var synchronizedScrollReset: DispatchWorkItem?
    private var isApplyingSynchronizedScroll = false
    var onTextChange: ((String) -> Void)?
    var onScrollSourceLineChange: ((Double) -> Void)?

    deinit {
        if let scrollObservation {
            NotificationCenter.default.removeObserver(scrollObservation)
        }
    }

    override func loadView() {
        // 源码编辑区使用稳定纯色背景，长时间写作时比透明材质更清晰，也不会受桌面颜色干扰。
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = currentPalette().background.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 22, left: 0, bottom: 22, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 6)

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.insertionPointColor = currentPalette().accent
        textView.font = NSFont.monospacedSystemFont(
            ofSize: MojiPreferences.shared.editorFontSize,
            weight: .regular
        )
        textView.textColor = currentPalette().text
        textView.textContainerInset = NSSize(width: 28, height: 28)
        textView.defaultParagraphStyle = makeParagraphStyle()
        textView.typingAttributes = makeTypingAttributes()
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.72)
        ]
        textView.delegate = self

        // 设置文本容器宽度随视图变化，避免横向滚动影响写作专注度。
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObservation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleScrollCallback()
        }
        containerView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        containerView.onAppearanceChange = { [weak self] in
            // “清爽”主题跟随系统深浅外观，系统切换后立即刷新动态颜色。
            self?.applyPreferences()
        }
        self.view = containerView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 宽窗口下把源码列控制在适合阅读的宽度，分栏或窄窗口下则保留至少 24 点边距。
        let horizontalInset = max(24, (view.bounds.width - 780) / 2)
        textView.textContainerInset = NSSize(width: horizontalInset, height: 28)
    }

    func setText(_ text: String) {
        // 初始化或载入文档时只更新编辑器内容，不能触发“用户已编辑”回调。
        // 否则刚打开的空白文档会被错误标记为已修改，退出时出现不必要的保存提示。
        textView.string = text
        rebuildLineStartOffsets()
        applySyntaxHighlighting()
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
    }

    /// 应用编辑器偏好设置。
    /// 设置窗口修改字号后，所有已打开文档都会立即更新，不需要重新打开应用。
    func applyPreferences() {
        let palette = currentPalette()
        containerView.layer?.backgroundColor = palette.background.cgColor
        textView.insertionPointColor = palette.accent
        textView.textColor = palette.text
        textView.font = NSFont.monospacedSystemFont(
            ofSize: MojiPreferences.shared.editorFontSize,
            weight: .regular
        )
        textView.defaultParagraphStyle = makeParagraphStyle()
        textView.typingAttributes = makeTypingAttributes()
        applySyntaxHighlighting()
    }

    /// 创建适合源码写作的段落样式。
    /// 轻微增加行距能降低长文档的视觉拥挤，同时不改变 Markdown 文件中的任何真实字符。
    private func makeParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = 0
        style.defaultTabInterval = 28
        return style
    }

    /// 统一编辑器后续输入的字体、颜色和段落属性，避免修改字号后新旧文字视觉不一致。
    private func makeTypingAttributes() -> [NSAttributedString.Key: Any] {
        let palette = currentPalette()
        return [
            .font: NSFont.monospacedSystemFont(
                ofSize: MojiPreferences.shared.editorFontSize,
                weight: .regular
            ),
            .foregroundColor: palette.text,
            .paragraphStyle: makeParagraphStyle()
        ]
    }

    func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        // Markdown 编辑器常用“包裹选区”来插入粗体、斜体、代码等格式。
        // 如果没有选中文本，就插入占位文本并选中它，方便用户直接输入替换。
        let selectedRange = textView.selectedRange()
        let currentText = textView.string as NSString
        let selectedText = selectedRange.length > 0 ? currentText.substring(with: selectedRange) : placeholder
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        textView.insertText(replacement, replacementRange: selectedRange)

        if selectedRange.length == 0 {
            let placeholderStart = selectedRange.location + (prefix as NSString).length
            textView.setSelectedRange(NSRange(location: placeholderStart, length: (placeholder as NSString).length))
        }
        // insertText 会统一触发 textDidChange，避免这里再次回调造成重复渲染和修改计数。
    }

    func insertBlock(_ block: String, selectedPlaceholder: String? = nil) {
        // 块级插入用于标题、引用、代码块、表格等结构化 Markdown，尽量自动补换行，减少手工整理。
        let selectedRange = textView.selectedRange()
        let needsLeadingNewline = selectedRange.location > 0 && !(textView.string as NSString).substring(to: selectedRange.location).hasSuffix("\n")
        let prefix = needsLeadingNewline ? "\n" : ""
        let replacement = prefix + block
        textView.insertText(replacement, replacementRange: selectedRange)

        if let selectedPlaceholder, let range = (replacement as NSString).range(of: selectedPlaceholder).toOptional() {
            textView.setSelectedRange(NSRange(location: selectedRange.location + range.location, length: range.length))
        }
        // 块级插入同样交给 NSTextViewDelegate（文本编辑代理）统一通知文档层。
    }

    func textDidChange(_ notification: Notification) {
        rebuildLineStartOffsets()
        applySyntaxHighlighting()
        onTextChange?(textView.string)
    }

    /// 把预览区报告的 Markdown 源行定位到编辑器中的对应垂直位置。
    /// 使用相邻两行的排版坐标做插值，可让预览在段落之间连续滚动时编辑器也保持平滑。
    func scrollToSourceLine(_ sourceLine: Double) {
        guard isViewLoaded, !textView.string.isEmpty, !lineStartOffsets.isEmpty,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let clampedLine = min(max(sourceLine, 1), Double(lineStartOffsets.count))
        let lowerIndex = max(0, min(Int(floor(clampedLine)) - 1, lineStartOffsets.count - 1))
        let upperIndex = min(lowerIndex + 1, lineStartOffsets.count - 1)
        let fraction = clampedLine - floor(clampedLine)
        let lowerY = verticalPosition(forLineIndex: lowerIndex, layoutManager: layoutManager, textContainer: textContainer)
        let upperY = verticalPosition(forLineIndex: upperIndex, layoutManager: layoutManager, textContainer: textContainer)
        let targetY = lowerY + (upperY - lowerY) * CGFloat(fraction)
        let clipView = scrollView.contentView
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maximumY = max(0, documentHeight - clipView.bounds.height)
        let synchronizedY: CGFloat
        if clampedLine <= 1.001 {
            synchronizedY = 0
        } else if clampedLine >= Double(lineStartOffsets.count) - 0.001 {
            // 最后一行必须映射到滚动终点，否则两侧高度不同会让文档底部永远无法对齐。
            synchronizedY = maximumY
        } else {
            synchronizedY = min(max(targetY, 0), maximumY)
        }

        isApplyingSynchronizedScroll = true
        synchronizedScrollReset?.cancel()
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: synchronizedY))
        scrollView.reflectScrolledClipView(clipView)

        // AppKit 会异步补发滚动通知；短暂保留抑制状态，避免程序滚动再次驱动预览形成回路。
        let reset = DispatchWorkItem { [weak self] in
            self?.isApplyingSynchronizedScroll = false
        }
        synchronizedScrollReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: reset)
    }

    /// 合并同一帧中的连续触控板事件，减少两侧跨进程桥接调用并保持滚动流畅。
    private func scheduleScrollCallback() {
        guard !isApplyingSynchronizedScroll else { return }
        pendingScrollCallback?.cancel()
        let callback = DispatchWorkItem { [weak self] in
            guard let self, !self.isApplyingSynchronizedScroll else { return }
            self.onScrollSourceLineChange?(self.visibleSourceLine())
        }
        pendingScrollCallback = callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: callback)
    }

    /// 返回编辑器视口顶部对应的 Markdown 行号。
    /// 行首偏移表配合二分查找，长文档滚动时无需反复扫描全部文本。
    private func visibleSourceLine() -> Double {
        let visibleY = max(0, scrollView.contentView.documentVisibleRect.minY)
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maximumY = max(0, documentHeight - scrollView.contentView.bounds.height)
        if visibleY <= 1 { return 1 }
        if maximumY > 0, visibleY >= maximumY - 1 {
            return Double(lineStartOffsets.count)
        }
        let characterIndex = min(
            textView.characterIndexForInsertion(at: NSPoint(x: textView.textContainerInset.width, y: visibleY + 1)),
            (textView.string as NSString).length
        )
        var lowerBound = 0
        var upperBound = lineStartOffsets.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if lineStartOffsets[middle] <= characterIndex {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        let lineIndex = max(0, lowerBound - 1)
        guard lineIndex + 1 < lineStartOffsets.count,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return Double(lineIndex + 1)
        }
        layoutManager.ensureLayout(for: textContainer)
        let currentY = verticalPosition(forLineIndex: lineIndex, layoutManager: layoutManager, textContainer: textContainer)
        let nextY = verticalPosition(forLineIndex: lineIndex + 1, layoutManager: layoutManager, textContainer: textContainer)
        let fraction = nextY > currentY ? min(max((visibleY - currentY) / (nextY - currentY), 0), 1) : 0
        return Double(lineIndex + 1) + Double(fraction)
    }

    /// 重建每一行在 UTF-16 文本中的起始位置，与 NSTextView 使用的 NSRange 坐标保持一致。
    private func rebuildLineStartOffsets() {
        let text = textView.string as NSString
        var offsets = [0]
        var searchLocation = 0
        while searchLocation < text.length {
            let lineRange = text.lineRange(for: NSRange(location: searchLocation, length: 0))
            let nextLocation = NSMaxRange(lineRange)
            guard nextLocation > searchLocation else { break }
            if nextLocation < text.length {
                offsets.append(nextLocation)
            }
            searchLocation = nextLocation
        }
        // 文档以换行符结束时，文件语义上仍有一个末尾空行；保留它才能与渲染器的总行数一致。
        if text.length > 0, text.substring(from: text.length - 1) == "\n" {
            offsets.append(text.length)
        }
        lineStartOffsets = offsets
    }

    /// 获取指定源行在文本排版中的顶部坐标，并扣除文本容器上边距以对齐视口顶部。
    private func verticalPosition(
        forLineIndex lineIndex: Int,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> CGFloat {
        let textLength = layoutManager.textStorage?.length ?? 0
        let characterLocation = min(lineStartOffsets[lineIndex], textLength)
        if characterLocation == textLength {
            return layoutManager.usedRect(for: textContainer).maxY + textView.textContainerInset.height
        }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterLocation)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return lineRect.minY + textView.textContainerInset.height
    }

    /// 对 Markdown 源码应用轻量语法着色。
    /// 这里只调整显示属性，不修改文件字符；目标是提升扫描效率，而不是模拟所见即所得编辑器。
    private func applySyntaxHighlighting() {
        guard !isApplyingSyntaxHighlighting, let textStorage = textView.textStorage else { return }
        isApplyingSyntaxHighlighting = true
        defer { isApplyingSyntaxHighlighting = false }

        let palette = currentPalette()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let baseAttributes = makeTypingAttributes()
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: fullRange)

        // 标题整行使用更有层级的字重，Markdown 标记本身使用系统强调色。
        applyPattern("(?m)^(#{1,6})(?=\\s).*$", to: textStorage) { match in
            let level = min(match.range(at: 1).length, 6)
            let baseSize = CGFloat(MojiPreferences.shared.editorFontSize)
            let sizeOffsets: [CGFloat] = [0, 5, 3, 2, 1, 0, 0]
            textStorage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: baseSize + sizeOffsets[level], weight: .semibold),
                .foregroundColor: palette.text
            ], range: match.range)
            textStorage.addAttribute(.foregroundColor, value: palette.accent, range: match.range(at: 1))
        }

        // 引用、列表和代码围栏只突出结构符号，正文仍保持稳定的主文字颜色。
        applyPattern("(?m)^(\\s*>)(?=\\s|$)|^(\\s*(?:[-+*]|\\d+\\.))(?=\\s)|^(\\s*(?:```+|~~~+)).*$", to: textStorage) { match in
            for groupIndex in 1..<match.numberOfRanges where match.range(at: groupIndex).location != NSNotFound {
                textStorage.addAttribute(.foregroundColor, value: palette.accent, range: match.range(at: groupIndex))
            }
        }

        // 容器扩展、GitHub 提示块和公式分隔符属于新增结构语法，使用强调色帮助用户快速识别边界。
        applyPattern("(?m)^\\s*:::(?:\\s+(?:columns|column|details)(?:\\s+.*)?)?\\s*$|^\\s*>\\s*\\[!(?:NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]\\s*$", to: textStorage) { match in
            textStorage.addAttribute(.foregroundColor, value: palette.accent, range: match.range)
        }
        applyPattern("(?<!\\$)\\$[^$\\n]+\\$(?!\\$)", to: textStorage) { match in
            textStorage.addAttribute(.foregroundColor, value: palette.inlineCode, range: match.range)
        }

        // 链接和行内代码使用轻量颜色区分，避免源码区变成过度花哨的代码编辑器。
        applyPattern("\\[[^\\]\\n]+\\]\\([^\\)\\n]+\\)", to: textStorage) { match in
            textStorage.addAttribute(.foregroundColor, value: palette.link, range: match.range)
        }
        applyPattern("`[^`\\n]+`", to: textStorage) { match in
            textStorage.addAttributes([
                .foregroundColor: palette.inlineCode,
                .backgroundColor: palette.codeBackground
            ], range: match.range)
        }
        applyPattern("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__", to: textStorage) { match in
            textStorage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: MojiPreferences.shared.editorFontSize, weight: .semibold),
                range: match.range
            )
        }
        textStorage.endEditing()
        textView.typingAttributes = baseAttributes
    }

    /// 根据当前阅读主题返回源码区配色。
    /// 颜色与渲染器 CSS（层叠样式表）保持同源，但编辑器仍使用原生 NSColor 以保证光标和选区正常。
    private func currentPalette() -> EditorPalette {
        switch MojiPreferences.shared.markdownStyle {
        case .github:
            return EditorPalette(
                background: color(0xFFFFFF), text: color(0x1F2328), accent: color(0x0969DA),
                link: color(0x0969DA), codeBackground: color(0xEFF1F3), inlineCode: color(0xCF222E)
            )
        case .clean:
            return EditorPalette(
                background: .textBackgroundColor, text: .labelColor, accent: .controlAccentColor,
                link: .linkColor, codeBackground: .controlBackgroundColor, inlineCode: .systemPink
            )
        case .paper:
            return EditorPalette(
                background: color(0xFBF4E8), text: color(0x2F2A22), accent: color(0x9A5B1F),
                link: color(0x9A5B1F), codeBackground: color(0xF8EDDD), inlineCode: color(0x8C3B22)
            )
        case .night:
            return EditorPalette(
                background: color(0x0F1420), text: color(0xD7DEF0), accent: color(0x8AADFF),
                link: color(0x8AADFF), codeBackground: color(0x171D2B), inlineCode: color(0xF2A7C3)
            )
        case .sepia:
            return EditorPalette(
                background: color(0xFFF8EA), text: color(0x3D3326), accent: color(0xB2642A),
                link: color(0xA85420), codeBackground: color(0xF5E7CF), inlineCode: color(0x914A24)
            )
        case .manuscript:
            return EditorPalette(
                background: color(0xFFFFFF), text: color(0x222222), accent: color(0x555555),
                link: color(0x444444), codeBackground: color(0xF1F1F1), inlineCode: color(0x555555)
            )
        }
    }

    /// 把十六进制 RGB 颜色转换为 AppKit 颜色，确保源码区和网页预览使用完全一致的色值。
    private func color(_ hexadecimal: Int) -> NSColor {
        return NSColor(
            calibratedRed: CGFloat((hexadecimal >> 16) & 0xFF) / 255,
            green: CGFloat((hexadecimal >> 8) & 0xFF) / 255,
            blue: CGFloat(hexadecimal & 0xFF) / 255,
            alpha: 1
        )
    }

    /// 执行一个语法着色规则；无效规则直接忽略，不能影响用户继续编辑文档。
    private func applyPattern(
        _ pattern: String,
        to textStorage: NSTextStorage,
        apply: (NSTextCheckingResult) -> Void
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: textStorage.length)
        expression.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
            guard let match else { return }
            apply(match)
        }
    }
}

/// AppearanceAwareEditorView 只负责把系统外观变化通知给编辑器控制器。
/// 使用原生视图回调可以避免轮询，也不会把主题逻辑耦合到应用生命周期中。
private final class AppearanceAwareEditorView: NSView {
    var onAppearanceChange: (() -> Void)?

    /// 系统在浅色与深色模式之间切换时调用，让动态颜色立即重新解析并写入文本属性。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

private extension NSRange {
    func toOptional() -> NSRange? {
        // NSString.range(of:) 找不到内容时会返回 NSNotFound；封装一下让调用点更清晰。
        return location == NSNotFound ? nil : self
    }
}
