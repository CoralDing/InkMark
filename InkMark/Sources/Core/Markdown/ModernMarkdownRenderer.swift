/**
 * 文件说明：墨记现代 Markdown 渲染器，用 Swift 生成可被 WKWebView 展示的 HTML。
 * 作者：Codex
 * 创建时间：2026-06-17
 */

import Foundation

/// ModernMarkdownStyle 表示预览区的视觉风格。
/// 默认使用 GitHub 风格，符合大多数 Markdown（轻量标记语言）用户对预览效果的预期。
enum ModernMarkdownStyle: String, CaseIterable {
    case github
    case clean
    case paper
    case night
    case sepia
    case manuscript

    var displayName: String {
        switch self {
        case .github: return "Git 风格"
        case .clean: return "清爽"
        case .paper: return "纸张"
        case .night: return "夜间"
        case .sepia: return "暖色"
        case .manuscript: return "手稿"
        }
    }
}

/// MojiMarkdownRenderOptions 表示可在偏好设置中切换的渲染选项。
/// 这些选项和主题不同，主要控制 Markdown（轻量标记语言）解析能力或阅读增强能力。
struct MojiMarkdownRenderOptions {
    var autoLinkBareURLs: Bool = true
    var contentMaxWidth: Int = 900
}

/// ModernMarkdownRenderer 是新架构里的 Markdown 渲染入口。
/// 当前实现常用 GitHub Flavored Markdown（GitHub 风格 Markdown）子集，保证文档、表格和任务列表正常展示。
final class ModernMarkdownRenderer {
    /// CodeFence 记录当前围栏代码块的符号、长度和语言信息。
    /// 保存围栏长度可以正确处理内容中较短的反引号或波浪线，避免代码块被提前关闭。
    private struct CodeFence {
        let marker: Character
        let length: Int
        let info: String
    }

    /// ResourceCardKind 表示可由纯文本围栏描述的外部资源类型。
    /// 这些卡片只保存标题、地址和说明，不绑定任何企业内部接口，开源版本也能正常退化为链接。
    private enum ResourceCardKind: String {
        case attachment
        case asset
        case zero

        var displayName: String {
            switch self {
            case .attachment: return "附件"
            case .asset: return "技术资产"
            case .zero: return "ZERO 文件"
            }
        }
    }

    var style: ModernMarkdownStyle = .github
    var options = MojiMarkdownRenderOptions()

    /// 把 Markdown 文本渲染为完整 HTML（网页结构内容）。
    /// 先转义用户输入，再处理常见 Markdown 语法，避免直接拼接用户原始 HTML 带来脚本注入风险。
    func renderHTML(from markdown: String) -> String {
        let body = renderBlocks(from: markdown)
        let normalizedLineCount = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").count
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src file: data: https: http:; media-src file: data: https: http:; style-src 'unsafe-inline'; font-src data:; connect-src 'none';">
          <style>\(baseCSS())\n\(themeCSS())</style>
        </head>
        <body>
          <main class="markdown-body" data-source-line-count="\(normalizedLineCount)">\(body)</main>
        </body>
        </html>
        """
    }

    /// 渲染块级结构，并为主要内容节点写入原始 Markdown 行号。
    /// 行号锚点让编辑区与预览区可以按内容位置同步，而不是只按两侧总高度做粗略换算。
    private func renderBlocks(from markdown: String, sourceLineOffset: Int = 0) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let visibleMarkdown = stripHTMLCommentsPreservingCodeFences(from: normalized)
        guard !visibleMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // 空文档预览保持纯净，不重复展示品牌或操作说明，避免干扰左侧写作区域。
            return "<div class=\"empty\" aria-hidden=\"true\"></div>"
        }

        let lines = visibleMarkdown.components(separatedBy: "\n")
        var index = 0
        var htmlBlocks: [String] = []
        var paragraphLines: [String] = []
        var paragraphStartLine: Int?
        var unorderedItems: [String] = []
        var orderedItems: [String] = []
        var codeLines: [String] = []
        var activeCodeFence: CodeFence?
        var codeLanguage = ""
        var codeStartLine: Int?

        func sourceLine(at lineIndex: Int) -> Int {
            return sourceLineOffset + lineIndex + 1
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty, let startLine = paragraphStartLine else { return }
            let text = paragraphLines.joined(separator: " ")
            htmlBlocks.append("<p data-source-line=\"\(startLine)\">\(renderInline(text))</p>")
            paragraphLines.removeAll()
            paragraphStartLine = nil
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            htmlBlocks.append("<ul>\(unorderedItems.joined())</ul>")
            unorderedItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            htmlBlocks.append("<ol>\(orderedItems.joined())</ol>")
            orderedItems.removeAll()
        }

        func flushLists() {
            flushUnorderedList()
            flushOrderedList()
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let activeFence = activeCodeFence {
                if let closingFence = parseCodeFence(line),
                   closingFence.marker == activeFence.marker,
                   closingFence.length >= activeFence.length,
                   closingFence.info.isEmpty {
                    let startLine = codeStartLine ?? sourceLine(at: index)
                    htmlBlocks.append(renderFencedCodeBlock(
                        language: codeLanguage,
                        content: codeLines.joined(separator: "\n"),
                        sourceLine: startLine
                    ))
                    codeLines.removeAll()
                    codeLanguage = ""
                    codeStartLine = nil
                    activeCodeFence = nil
                } else {
                    codeLines.append(rawLine)
                }
                index += 1
                continue
            }

            if let openingFence = parseCodeFence(line) {
                flushParagraph()
                flushLists()
                codeLanguage = openingFence.info
                codeStartLine = sourceLine(at: index)
                activeCodeFence = openingFence
                index += 1
                continue
            }

            if line.isEmpty {
                flushParagraph()
                flushLists()
                index += 1
                continue
            }

            if line.hasPrefix("::: details") {
                flushParagraph()
                flushLists()
                let detailsResult = renderDetails(startingAt: index, in: lines, sourceLineOffset: sourceLineOffset)
                htmlBlocks.append(detailsResult.html)
                index = detailsResult.nextIndex
                continue
            }

            if line == "::: columns" {
                flushParagraph()
                flushLists()
                let columnsResult = renderColumns(startingAt: index, in: lines, sourceLineOffset: sourceLineOffset)
                htmlBlocks.append(columnsResult.html)
                index = columnsResult.nextIndex
                continue
            }

            if line == "[TOC]" || line == "[[TOC]]" {
                flushParagraph()
                flushLists()
                htmlBlocks.append("<nav class=\"toc-placeholder\" data-source-line=\"\(sourceLine(at: index))\"><strong>目录</strong><p>目录插件启用后会在这里生成文档结构。</p></nav>")
                index += 1
                continue
            }

            if isTableHeader(at: index, in: lines) {
                flushParagraph()
                flushLists()
                let tableResult = renderTable(startingAt: index, in: lines, sourceLineOffset: sourceLineOffset)
                htmlBlocks.append(tableResult.html)
                index = tableResult.nextIndex
                continue
            }

            if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                flushLists()
                htmlBlocks.append("<hr data-source-line=\"\(sourceLine(at: index))\">")
                index += 1
                continue
            }

            if let heading = renderHeading(line, sourceLine: sourceLine(at: index)) {
                flushParagraph()
                flushLists()
                htmlBlocks.append(heading)
                index += 1
                continue
            }

            if isIndentedCodeLine(rawLine) {
                flushParagraph()
                flushLists()
                let result = renderIndentedCodeBlock(startingAt: index, in: lines, sourceLineOffset: sourceLineOffset)
                htmlBlocks.append(result.html)
                index = result.nextIndex
                continue
            }

            if isBlockquoteLine(line) {
                flushParagraph()
                flushLists()
                let blockquoteResult = renderBlockquote(startingAt: index, in: lines, sourceLineOffset: sourceLineOffset)
                htmlBlocks.append(blockquoteResult.html)
                index = blockquoteResult.nextIndex
                continue
            }

            if let unorderedItem = renderUnorderedListItem(line, sourceLine: sourceLine(at: index)) {
                flushParagraph()
                flushOrderedList()
                unorderedItems.append(unorderedItem)
                index += 1
                continue
            }

            if let orderedItem = renderOrderedListItem(line, sourceLine: sourceLine(at: index)) {
                flushParagraph()
                flushUnorderedList()
                orderedItems.append(orderedItem)
                index += 1
                continue
            }

            if paragraphLines.isEmpty {
                paragraphStartLine = sourceLine(at: index)
            }
            paragraphLines.append(line)
            index += 1
        }

        if activeCodeFence != nil {
            let startLine = codeStartLine ?? sourceLine(at: max(0, lines.count - 1))
            htmlBlocks.append(renderFencedCodeBlock(
                language: codeLanguage,
                content: codeLines.joined(separator: "\n"),
                sourceLine: startLine
            ))
        }
        flushParagraph()
        flushLists()
        return htmlBlocks.joined(separator: "\n")
    }

    /// 移除正文中的 HTML 注释，同时保留代码围栏中的原始示例。
    /// 不能直接对整篇文档使用正则删除，否则代码块里用于教学的 `<!-- 注释 -->` 也会消失。
    private func stripHTMLCommentsPreservingCodeFences(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var activeCodeFence: CodeFence?
        var isInComment = false
        var visibleLines: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if let activeFence = activeCodeFence {
                visibleLines.append(line)
                if let closingFence = parseCodeFence(trimmedLine),
                   closingFence.marker == activeFence.marker,
                   closingFence.length >= activeFence.length,
                   closingFence.info.isEmpty {
                    activeCodeFence = nil
                }
                continue
            }

            if let openingFence = parseCodeFence(trimmedLine) {
                activeCodeFence = openingFence
                visibleLines.append(line)
                continue
            }

            var remainder = line[...]
            var visibleLine = ""

            // 同一行可能包含多个注释，或承接上一行未结束的多行注释，因此循环处理到行尾。
            while !remainder.isEmpty {
                if isInComment {
                    guard let commentEnd = remainder.range(of: "-->") else {
                        remainder = remainder[remainder.endIndex...]
                        break
                    }
                    remainder = remainder[commentEnd.upperBound...]
                    isInComment = false
                    continue
                }

                guard let commentStart = remainder.range(of: "<!--") else {
                    visibleLine += remainder
                    break
                }
                visibleLine += remainder[..<commentStart.lowerBound]
                remainder = remainder[commentStart.upperBound...]
                isInComment = true
            }

            visibleLines.append(visibleLine)
        }

        return visibleLines.joined(separator: "\n")
    }

    /// 解析反引号或波浪线围栏。
    /// Markdown 允许至少三个相同符号开头，开头后面的文本作为代码语言，关闭围栏则不能带语言信息。
    private func parseCodeFence(_ line: String) -> CodeFence? {
        guard let marker = line.first, marker == "`" || marker == "~" else { return nil }
        let markerLength = line.prefix { $0 == marker }.count
        guard markerLength >= 3 else { return nil }
        let info = String(line.dropFirst(markerLength)).trimmingCharacters(in: .whitespaces)
        // 反引号围栏的语言信息中不能再次出现反引号，否则容易把普通正文误判为代码块。
        guard marker != "`" || !info.contains("`") else { return nil }
        return CodeFence(marker: marker, length: markerLength, info: info)
    }

    /// 判断一行是否属于引用块，包括只包含 `>` 的引用段落分隔行。
    private func isBlockquoteLine(_ line: String) -> Bool {
        return blockquoteContent(from: line) != nil
    }

    /// 移除引用标记并返回正文。
    /// `>` 后可能是半角空格、制表符、全角空格或不间断空格；统一按空白处理，避免符号泄漏到预览正文。
    private func blockquoteContent(from line: String) -> String? {
        guard line.first == ">" else { return nil }

        let contentStart = line.index(after: line.startIndex)
        guard contentStart < line.endIndex else { return "" }

        let firstContentCharacter = line[contentStart]
        guard firstContentCharacter.isWhitespace else { return nil }
        return String(line[line.index(after: contentStart)...])
    }

    /// 合并连续引用行，并递归渲染引用内部的段落与行内样式。
    /// 这样 `>` 空行会成为引用内部的段落间距，不会以孤立符号泄漏到正文中。
    private func renderBlockquote(
        startingAt index: Int,
        in lines: [String],
        sourceLineOffset: Int
    ) -> (html: String, nextIndex: Int) {
        var cursor = index
        var quoteLines: [String] = []
        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard let quoteContent = blockquoteContent(from: line) else { break }
            quoteLines.append(quoteContent)
            cursor += 1
        }
        let quoteMarkdown = quoteLines.joined(separator: "\n")
        if let alert = renderAlertBlockquote(
            quoteLines: quoteLines,
            sourceLine: sourceLineOffset + index + 1,
            sourceLineOffset: sourceLineOffset + index
        ) {
            return (alert, cursor)
        }
        // 全空引用仍保留引用容器，但不能递归触发文档级空状态品牌页。
        let quoteHTML = quoteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : renderBlocks(from: quoteMarkdown, sourceLineOffset: sourceLineOffset + index)
        let sourceLine = sourceLineOffset + index + 1
        return ("<blockquote data-source-line=\"\(sourceLine)\">\(quoteHTML)</blockquote>", cursor)
    }

    /// 渲染 GitHub Alerts（GitHub 提示块）语法，例如 `> [!WARNING]`。
    /// 不认识的类型继续按普通引用处理，避免扩展语法误伤已有文档。
    private func renderAlertBlockquote(
        quoteLines: [String],
        sourceLine: Int,
        sourceLineOffset: Int
    ) -> String? {
        guard let marker = quoteLines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              marker.hasPrefix("[!"), marker.hasSuffix("]") else {
            return nil
        }
        let type = String(marker.dropFirst(2).dropLast()).uppercased()
        let titles: [String: String] = [
            "NOTE": "说明",
            "TIP": "提示",
            "IMPORTANT": "重要",
            "WARNING": "警告",
            "CAUTION": "注意"
        ]
        guard let title = titles[type] else { return nil }
        let content = quoteLines.dropFirst().joined(separator: "\n")
        let contentHTML = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : renderBlocks(from: content, sourceLineOffset: sourceLineOffset + 1)
        return "<aside class=\"moji-alert moji-alert-\(type.lowercased())\" data-source-line=\"\(sourceLine)\"><strong class=\"moji-alert-title\">\(title)</strong>\(contentHTML)</aside>"
    }

    /// 渲染 `::: details 标题` 折叠容器。
    /// 如果缺少关闭标记，则把剩余内容全部纳入容器，保证未完成输入时预览仍然稳定。
    private func renderDetails(
        startingAt index: Int,
        in lines: [String],
        sourceLineOffset: Int
    ) -> (html: String, nextIndex: Int) {
        let openingLine = lines[index].trimmingCharacters(in: .whitespaces)
        let title = String(openingLine.dropFirst("::: details".count)).trimmingCharacters(in: .whitespaces)
        let endIndex = directiveEndIndex(startingAt: index, in: lines) ?? lines.count
        let contentStart = index + 1
        let contentLines = contentStart < endIndex ? Array(lines[contentStart..<endIndex]) : []
        let content = contentLines.joined(separator: "\n")
        let contentHTML = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : renderBlocks(from: content, sourceLineOffset: sourceLineOffset + contentStart)
        let sourceLine = sourceLineOffset + index + 1
        let nextIndex = endIndex < lines.count ? endIndex + 1 : endIndex
        return (
            "<details class=\"moji-details\" data-source-line=\"\(sourceLine)\"><summary>\(renderInline(title.isEmpty ? "详细内容" : title))</summary><div class=\"moji-details-content\">\(contentHTML)</div></details>",
            nextIndex
        )
    }

    /// 渲染 `::: columns` 内容分栏，使用 `::: column` 划分每一列。
    /// 窄窗口会自动改为纵向排列，避免固定列宽导致正文溢出。
    private func renderColumns(
        startingAt index: Int,
        in lines: [String],
        sourceLineOffset: Int
    ) -> (html: String, nextIndex: Int) {
        let endIndex = directiveEndIndex(startingAt: index, in: lines) ?? lines.count
        var columnRanges: [Range<Int>] = []
        var columnStart = index + 1
        var nestedDepth = 0
        var cursor = index + 1

        while cursor < endIndex {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("::: details") || line == "::: columns" {
                nestedDepth += 1
            } else if line == ":::" && nestedDepth > 0 {
                nestedDepth -= 1
            } else if line == "::: column" && nestedDepth == 0 {
                if columnStart < cursor {
                    columnRanges.append(columnStart..<cursor)
                }
                columnStart = cursor + 1
            }
            cursor += 1
        }
        if columnStart < endIndex {
            columnRanges.append(columnStart..<endIndex)
        }
        if columnRanges.isEmpty {
            columnRanges = [(index + 1)..<endIndex]
        }

        let columnsHTML = columnRanges.map { range in
            let content = lines[range].joined(separator: "\n")
            let rendered = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : renderBlocks(from: content, sourceLineOffset: sourceLineOffset + range.lowerBound)
            return "<section class=\"moji-column\" data-source-line=\"\(sourceLineOffset + range.lowerBound + 1)\">\(rendered)</section>"
        }.joined()
        let sourceLine = sourceLineOffset + index + 1
        let nextIndex = endIndex < lines.count ? endIndex + 1 : endIndex
        return ("<div class=\"moji-columns\" data-source-line=\"\(sourceLine)\">\(columnsHTML)</div>", nextIndex)
    }

    /// 查找容器指令对应的关闭行，并正确跳过内部嵌套容器。
    private func directiveEndIndex(startingAt index: Int, in lines: [String]) -> Int? {
        var depth = 1
        var cursor = index + 1
        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("::: details") || line == "::: columns" {
                depth += 1
            } else if line == ":::" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }

    /// 根据围栏语言渲染代码、视频、附件、资源卡片和块级数学公式。
    /// 未识别语言保持普通代码块，确保传统 Markdown 文档行为不变。
    private func renderFencedCodeBlock(language: String, content: String, sourceLine: Int) -> String {
        let normalizedLanguage = language.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        switch normalizedLanguage {
        case "video":
            return renderVideo(content: content, sourceLine: sourceLine)
        case "attachment":
            return renderResourceCard(kind: .attachment, content: content, sourceLine: sourceLine)
        case "asset":
            return renderResourceCard(kind: .asset, content: content, sourceLine: sourceLine)
        case "zero":
            return renderResourceCard(kind: .zero, content: content, sourceLine: sourceLine)
        case "math":
            return "<div class=\"moji-math\" data-source-line=\"\(sourceLine)\">$$\(escapeHTML(content))$$</div>"
        default:
            return "<pre data-source-line=\"\(sourceLine)\"><code class=\"language-\(escapeAttribute(language))\">\(escapeHTML(content))</code></pre>"
        }
    }

    /// 把视频围栏渲染为原生 HTML5 视频控件；地址可以是相对路径或 HTTPS 链接。
    private func renderVideo(content: String, sourceLine: Int) -> String {
        let fields = parseMetadataBlock(content)
        let source = fields["url"] ?? fields["src"] ?? fields["value"] ?? ""
        guard !source.isEmpty, isAllowedResourceURL(source) else {
            return "<div class=\"moji-resource-error\" data-source-line=\"\(sourceLine)\">视频地址为空或格式不受支持</div>"
        }
        let title = fields["title"] ?? "视频"
        return "<figure class=\"moji-video\" data-source-line=\"\(sourceLine)\"><video controls preload=\"metadata\" src=\"\(escapeAttribute(source))\"></video><figcaption>\(renderInline(title))</figcaption></figure>"
    }

    /// 把附件、技术资产和 ZERO 围栏渲染为统一资源卡片。
    private func renderResourceCard(kind: ResourceCardKind, content: String, sourceLine: Int) -> String {
        let fields = parseMetadataBlock(content)
        let url = fields["url"] ?? fields["href"] ?? fields["value"] ?? ""
        guard !url.isEmpty, isAllowedResourceURL(url) else {
            return "<div class=\"moji-resource-error\" data-source-line=\"\(sourceLine)\">\(kind.displayName)地址为空或格式不受支持</div>"
        }
        let fallbackName = URL(string: url)?.lastPathComponent.removingPercentEncoding
        let fallbackTitle = fallbackName.flatMap { $0.isEmpty ? nil : $0 } ?? kind.displayName
        let title = fields["title"] ?? fallbackTitle
        let detail = fields["description"] ?? fields["detail"] ?? url
        return "<a class=\"moji-resource-card moji-resource-\(kind.rawValue)\" data-source-line=\"\(sourceLine)\" href=\"\(escapeAttribute(url))\"><span class=\"moji-resource-kind\">\(kind.displayName)</span><strong>\(escapeHTML(title))</strong><small>\(escapeHTML(detail))</small></a>"
    }

    /// 只允许本地相对地址、文件地址、数据地址和常见网络媒体协议。
    /// 显式拒绝脚本协议，避免资源卡片或视频地址变成可执行导航。
    private func isAllowedResourceURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased() else {
            return true
        }
        return ["http", "https", "file", "data"].contains(scheme)
    }

    /// 解析围栏中的 `key: value` 元数据；只有一行时把它视为资源地址。
    private func parseMetadataBlock(_ content: String) -> [String: String] {
        var fields: [String: String] = [:]
        let lines = content.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else {
                if fields["value"] == nil { fields["value"] = line }
                continue
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if ["title", "url", "src", "href", "description", "detail"].contains(key), !value.isEmpty {
                fields[key] = value
            } else if fields["value"] == nil {
                // `https://` 中也包含冒号；未知键按完整地址处理，避免把 URL 错拆成键值对。
                fields["value"] = line
            }
        }
        return fields
    }

    private func renderHeading(_ line: String, sourceLine: Int) -> String? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }
        let text = String(line.dropFirst(level + 1))
        return "<h\(level) data-source-line=\"\(sourceLine)\">\(renderInline(text))</h\(level)>"
    }

    private func renderUnorderedListItem(_ line: String, sourceLine: Int) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        var text = String(line.dropFirst(2))
        var taskPrefix = ""
        if text.hasPrefix("[ ] ") {
            taskPrefix = "<input type=\"checkbox\" disabled> "
            text = String(text.dropFirst(4))
        } else if text.lowercased().hasPrefix("[x] ") {
            taskPrefix = "<input type=\"checkbox\" checked disabled> "
            text = String(text.dropFirst(4))
        }
        return "<li data-source-line=\"\(sourceLine)\">\(taskPrefix)\(renderInline(text))</li>"
    }

    private func renderOrderedListItem(_ line: String, sourceLine: Int) -> String? {
        guard let range = line.range(of: "^\\d+\\.\\s+", options: .regularExpression) else { return nil }
        let text = String(line[range.upperBound...])
        return "<li data-source-line=\"\(sourceLine)\">\(renderInline(text))</li>"
    }

    private func isIndentedCodeLine(_ line: String) -> Bool {
        // Markdown 里 4 个空格或 1 个制表符可表示缩进代码块；排除空行避免误吞普通段落。
        return (line.hasPrefix("    ") || line.hasPrefix("\t")) && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func renderIndentedCodeBlock(
        startingAt index: Int,
        in lines: [String],
        sourceLineOffset: Int
    ) -> (html: String, nextIndex: Int) {
        var cursor = index
        var codeLines: [String] = []
        while cursor < lines.count {
            let line = lines[cursor]
            if line.hasPrefix("    ") {
                codeLines.append(String(line.dropFirst(4)))
            } else if line.hasPrefix("\t") {
                codeLines.append(String(line.dropFirst()))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                codeLines.append("")
            } else {
                break
            }
            cursor += 1
        }
        let sourceLine = sourceLineOffset + index + 1
        return ("<pre data-source-line=\"\(sourceLine)\"><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>", cursor)
    }

    private func isTableHeader(at index: Int, in lines: [String]) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let divider = lines[index + 1].trimmingCharacters(in: .whitespaces)
        // GitHub Flavored Markdown（GitHub 风格 Markdown）的表格分隔行可以写成 ---、:---、---:、:---:。
        // 这里不用一条复杂正则硬匹配，避免中文内容、前后竖线省略、空格不同导致表格整体失效。
        guard header.contains("|") else { return false }
        let headerCells = splitTableRow(header)
        let dividerCells = splitTableRow(divider)
        guard headerCells.count > 1, dividerCells.count == headerCells.count else { return false }
        return dividerCells.allSatisfy { cell in
            cell.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil
        }
    }

    private func renderTable(
        startingAt index: Int,
        in lines: [String],
        sourceLineOffset: Int
    ) -> (html: String, nextIndex: Int) {
        let headers = splitTableRow(lines[index])
        let alignments = splitTableRow(lines[index + 1]).map(tableAlignmentClass)
        var rows: [[String]] = []
        var cursor = index + 2
        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard line.contains("|"), !line.isEmpty else { break }
            rows.append(splitTableRow(line))
            cursor += 1
        }

        let headerHTML = headers.indices.map { column -> String in
            let className = column < alignments.count ? alignments[column] : ""
            return "<th\(classAttribute(className))>\(renderInline(headers[column]))</th>"
        }.joined()
        let bodyHTML = rows.enumerated().map { rowIndex, row in
            let cells = headers.indices.map { column -> String in
                let value = column < row.count ? row[column] : ""
                let className = column < alignments.count ? alignments[column] : ""
                return "<td\(classAttribute(className))>\(renderInline(value))</td>"
            }.joined()
            let sourceLine = sourceLineOffset + index + rowIndex + 3
            return "<tr data-source-line=\"\(sourceLine)\">\(cells)</tr>"
        }.joined()
        let sourceLine = sourceLineOffset + index + 1
        return ("<table data-source-line=\"\(sourceLine)\"><thead><tr>\(headerHTML)</tr></thead><tbody>\(bodyHTML)</tbody></table>", cursor)
    }

    private func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        // 表格单元格允许用 \| 表示普通竖线，所以这里按字符扫描，避免内容里的转义竖线被误切列。
        var cells: [String] = []
        var current = ""
        var isEscaped = false
        for character in trimmed {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll()
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private func tableAlignmentClass(_ dividerCell: String) -> String {
        if dividerCell.hasPrefix(":") && dividerCell.hasSuffix(":") { return "align-center" }
        if dividerCell.hasSuffix(":") { return "align-right" }
        return ""
    }

    private func classAttribute(_ className: String) -> String {
        return className.isEmpty ? "" : " class=\"\(className)\""
    }

    private func renderInline(_ text: String) -> String {
        let protectedMath = protectInlineMath(in: text)
        var output = escapeHTML(protectedMath.text)
        output = replaceInlineCode(in: output)
        output = replaceStrongText(in: output)
        output = replaceEmphasisText(in: output)
        output = replaceStrikethrough(in: output)
        output = replaceImages(in: output)
        output = replaceLinks(in: output)
        output = replaceAutolinks(in: output)
        for (index, formula) in protectedMath.formulas.enumerated() {
            output = output.replacingOccurrences(
                of: "MOJIMATHSEGMENT\(index)TOKEN",
                with: escapeHTML(formula)
            )
        }
        return output
    }

    /// 临时保护行内和块级公式分隔内容，避免公式中的 `*`、链接字符等先被 Markdown 行内规则改写。
    private func protectInlineMath(in text: String) -> (text: String, formulas: [String]) {
        let pattern = #"\$\$[^\n]+?\$\$|(?<!\$)\$[^$\n]+?\$(?!\$)|\\\([^\n]+?\\\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let source = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return (text, []) }

        let mutable = NSMutableString(string: text)
        var formulas = Array(repeating: "", count: matches.count)
        // 从后向前替换以保持前面匹配项的 UTF-16 范围稳定。
        for (index, match) in matches.enumerated().reversed() {
            formulas[index] = source.substring(with: match.range)
            mutable.replaceCharacters(in: match.range, with: "MOJIMATHSEGMENT\(index)TOKEN")
        }
        return (mutable as String, formulas)
    }

    private func replaceImages(in text: String) -> String {
        return text.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\(([^\\s)]+)\\)",
            with: "<img alt=\"$1\" src=\"$2\">",
            options: .regularExpression
        )
    }

    private func replaceLinks(in text: String) -> String {
        return text.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^\\s)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
    }

    private func replaceInlineCode(in text: String) -> String {
        return text.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
    }

    private func replaceStrongText(in text: String) -> String {
        return text.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
    }

    private func replaceEmphasisText(in text: String) -> String {
        return text.replacingOccurrences(of: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", with: "<em>$1</em>", options: .regularExpression)
    }

    private func replaceStrikethrough(in text: String) -> String {
        return text.replacingOccurrences(of: "~~([^~]+)~~", with: "<del>$1</del>", options: .regularExpression)
    }

    private func replaceAutolinks(in text: String) -> String {
        guard options.autoLinkBareURLs else { return text }
        // 将裸 URL（网址）自动转成链接，这是预览工具里非常常用的阅读增强功能。
        return text.replacingOccurrences(
            of: "(?<![\"'=>])(https?://[^\\s<]+)",
            with: "<a href=\"$1\">$1</a>",
            options: .regularExpression
        )
    }

    private func escapeHTML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            // 行内链接和图片最终会进入双引号属性；提前编码引号可阻止属性边界被文档内容打断。
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func escapeAttribute(_ text: String) -> String {
        return escapeHTML(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func baseCSS() -> String {
        return """
        :root { color-scheme: light; }
        * { box-sizing: border-box; }
        ::selection { background: color-mix(in srgb, var(--accent) 22%, transparent); }
        /* 禁用浏览器按 DOM 节点进行的像素滚动锚定，统一交给墨记按 Markdown 源行保持位置。 */
        html, body { min-height: 100%; overflow-anchor: none; }
        body { margin: 0; background: var(--page-bg); -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
        .markdown-body {
          max-width: \(options.contentMaxWidth)px;
          min-height: 100vh;
          margin: 0 auto;
          padding: 36px 42px 80px;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, "Apple Color Emoji", "Segoe UI Emoji", sans-serif;
          font-size: 16px;
          line-height: 1.5;
          color: var(--text);
          background: var(--content-bg);
        }
        h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; color: var(--heading); }
        .markdown-body > :first-child { margin-top: 0; }
        h1 { padding-bottom: 0.3em; font-size: 2em; border-bottom: 1px solid var(--border-muted); }
        h2 { padding-bottom: 0.3em; font-size: 1.5em; border-bottom: 1px solid var(--border-muted); }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1em; }
        h5 { font-size: 0.875em; }
        h6 { font-size: 0.85em; color: var(--muted); }
        p { margin-top: 0; margin-bottom: 16px; }
        a { color: var(--accent); text-decoration: none; }
        a:hover { text-decoration: underline; }
        img { max-width: 100%; height: auto; border-radius: 8px; }
        .moji-alert { margin: 18px 0; padding: 12px 16px; border: 1px solid var(--border); border-left-width: 4px; border-radius: 6px; background: var(--soft-bg); }
        .moji-alert-title { display: block; margin-bottom: 6px; color: var(--heading); font-size: 0.92em; }
        .moji-alert > :last-child { margin-bottom: 0; }
        .moji-alert-note { border-left-color: #0969da; }
        .moji-alert-tip { border-left-color: #1a7f37; }
        .moji-alert-important { border-left-color: #8250df; }
        .moji-alert-warning { border-left-color: #bf8700; }
        .moji-alert-caution { border-left-color: #cf222e; }
        .moji-columns { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(260px, 100%), 1fr)); gap: 18px; margin: 20px 0; align-items: start; }
        .moji-column { min-width: 0; padding: 0 18px; border-left: 1px solid var(--border-muted); }
        .moji-column:first-child { padding-left: 0; border-left: 0; }
        .moji-column:last-child { padding-right: 0; }
        .moji-column > :first-child { margin-top: 0; }
        .moji-column > :last-child { margin-bottom: 0; }
        .moji-details { margin: 18px 0; border: 1px solid var(--border); border-radius: 7px; background: var(--content-bg); }
        .moji-details summary { padding: 11px 14px; color: var(--heading); font-weight: 600; cursor: pointer; user-select: none; }
        .moji-details[open] summary { border-bottom: 1px solid var(--border-muted); }
        .moji-details-content { padding: 14px 16px 2px; }
        .moji-video { margin: 20px 0; }
        .moji-video video { display: block; width: 100%; max-height: 68vh; border-radius: 7px; background: #000; }
        .moji-video figcaption { margin-top: 8px; color: var(--muted); font-size: 0.88em; text-align: center; }
        .moji-resource-card { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: 3px 12px; margin: 14px 0; padding: 13px 15px; border: 1px solid var(--border); border-radius: 7px; color: var(--text); background: var(--content-bg); text-decoration: none; }
        .moji-resource-card:hover { border-color: var(--accent); text-decoration: none; background: var(--soft-bg); }
        .moji-resource-card .moji-resource-kind { grid-row: 1 / span 2; align-self: center; min-width: 62px; color: var(--accent); font-size: 0.78em; font-weight: 650; }
        .moji-resource-card strong, .moji-resource-card small { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .moji-resource-card strong { color: var(--heading); }
        .moji-resource-card small { color: var(--muted); }
        .moji-resource-error { margin: 14px 0; padding: 12px 14px; border: 1px dashed var(--border); border-radius: 7px; color: var(--muted); background: var(--soft-bg); }
        .moji-math { overflow-x: auto; margin: 18px 0; padding: 8px 0; text-align: center; }
        .mermaid { overflow: auto; margin: 20px 0; padding: 12px 0; text-align: center; }
        .mermaid svg { max-width: 100%; height: auto; }
        .moji-plantuml { display: block; margin: 20px auto; }
        code { font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, Liberation Mono, monospace; font-size: 85%; padding: 0.2em 0.4em; border-radius: 6px; background: var(--code-bg); }
        pre { overflow: auto; padding: 16px; border: 1px solid var(--border-muted); border-radius: 8px; background: var(--code-bg); }
        pre code { padding: 0; background: transparent; border-radius: 0; line-height: 1.55; }
        blockquote { margin: 0 0 16px; padding: 0 1em; color: var(--muted); border-left: 0.25em solid var(--border); }
        blockquote > :last-child { margin-bottom: 0; }
        ul, ol { padding-left: 2em; margin-top: 0; margin-bottom: 16px; }
        li { margin: 0.25em 0; }
        table { width: max-content; max-width: 100%; border-collapse: collapse; margin-top: 0; margin-bottom: 16px; display: block; overflow: auto; }
        th, td { min-width: 72px; border: 1px solid var(--border); padding: 6px 13px; text-align: left; vertical-align: top; overflow-wrap: anywhere; }
        th.align-center, td.align-center { text-align: center; }
        th.align-right, td.align-right { text-align: right; }
        th { font-weight: 600; white-space: nowrap; background: var(--table-head); }
        tr { background: var(--content-bg); border-top: 1px solid var(--border-muted); }
        tr:nth-child(2n) td { background: var(--table-alt); }
        input[type="checkbox"] { transform: translateY(1px); margin-right: 6px; }
        hr { height: 0.25em; padding: 0; margin: 24px 0; background-color: var(--border-muted); border: 0; }
        .toc-placeholder { border: 1px solid var(--border-muted); border-radius: 8px; padding: 16px 18px; color: var(--muted); background: var(--soft-bg); }
        .empty { min-height: calc(100vh - 116px); }
        @media (max-width: 700px) {
          .markdown-body { padding: 28px 26px 64px; }
          .moji-columns { grid-template-columns: 1fr; gap: 14px; }
          .moji-column, .moji-column:first-child, .moji-column:last-child { padding: 0; border-left: 0; }
          .moji-column + .moji-column { padding-top: 14px; border-top: 1px solid var(--border-muted); }
        }
        """
    }

    private func themeCSS() -> String {
        switch style {
        case .github:
            // 固定 GitHub README 浅色风格，不跟随系统深色模式，避免用户感觉“不像 Git 风格”。
            return ":root { --page-bg: #ffffff; --content-bg: #ffffff; --text: #1f2328; --heading: #1f2328; --muted: #57606a; --accent: #0969da; --border: #d0d7de; --border-muted: #d8dee4; --soft-bg: #f6f8fa; --code-bg: rgba(175,184,193,0.2); --table-head: #ffffff; --table-alt: #f6f8fa; }"
        case .clean:
            return ":root { color-scheme: light dark; --page-bg: transparent; --content-bg: transparent; --text: CanvasText; --heading: CanvasText; --muted: color-mix(in srgb, CanvasText 62%, transparent); --accent: -apple-system-control-accent; --border: color-mix(in srgb, CanvasText 14%, transparent); --border-muted: color-mix(in srgb, CanvasText 12%, transparent); --soft-bg: color-mix(in srgb, CanvasText 5%, transparent); --code-bg: color-mix(in srgb, CanvasText 8%, transparent); --table-head: color-mix(in srgb, CanvasText 6%, transparent); --table-alt: color-mix(in srgb, CanvasText 3%, transparent); }"
        case .paper:
            return ":root { --page-bg: #fbf4e8; --content-bg: #fbf4e8; --text: #2f2a22; --heading: #1f1a14; --muted: #756b5d; --accent: #9a5b1f; --border: #e4d6c4; --border-muted: #eadcca; --soft-bg: #fff7ea; --code-bg: #f8eddd; --table-head: #f8eddd; --table-alt: #fff9f0; }"
        case .night:
            return ":root { color-scheme: dark; --page-bg: #0f1420; --content-bg: #0f1420; --text: #d7def0; --heading: #f4f7ff; --muted: #8993aa; --accent: #8aadff; --border: #2c3446; --border-muted: #30394f; --soft-bg: #171d2b; --code-bg: #111827; --table-head: #171d2b; --table-alt: #111827; }"
        case .sepia:
            return ":root { --page-bg: #fff8ea; --content-bg: #fff8ea; --text: #3d3326; --heading: #231b13; --muted: #7a6a55; --accent: #b2642a; --border: #ead9bf; --border-muted: #ecdcc4; --soft-bg: #fff6e4; --code-bg: #f5e7cf; --table-head: #f5e7cf; --table-alt: #fffaf0; } body { background: linear-gradient(180deg, #fff8ea 0%, #fbefd9 100%); }"
        case .manuscript:
            return ":root { --page-bg: #ffffff; --content-bg: #ffffff; --text: #222; --heading: #111; --muted: #777; --accent: #444; --border: #d8d8d8; --border-muted: #e5e5e5; --soft-bg: #f7f7f7; --code-bg: #f1f1f1; --table-head: #f1f1f1; --table-alt: #fafafa; } .markdown-body { max-width: 760px; font-family: Georgia, 'Times New Roman', serif; }"
        }
    }
}
