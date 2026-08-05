/**
 * 文件说明：墨记插件管理器，从用户目录加载预览增强脚本。
 * 作者：Codex
 * 创建时间：2026-06-17
 */

import Foundation

/// MojiPluginSource 区分墨记内置增强和用户安装脚本。
enum MojiPluginSource {
    case builtIn
    case user
}

/// MojiPluginDescriptor 是设置页展示和插件加载共同使用的轻量描述对象。
struct MojiPluginDescriptor {
    let identifier: String
    let displayName: String
    let detail: String
    let source: MojiPluginSource
    let fileURL: URL?
    let isEnabled: Bool
}

/// MojiPluginManager 管理预览插件脚本。
/// 插件目录默认位于 Application Support（应用支持目录），用户可放入 `.js` 文件扩展预览能力。
final class MojiPluginManager {
    static let shared = MojiPluginManager()

    private let fileManager = FileManager.default

    /// CorePreviewExtension 表示 Markdown 阅读所必需的本地渲染能力。
    /// 核心能力不受插件总开关影响，避免关闭可选脚本后图表和公式退回源码展示。
    private enum CorePreviewExtension: CaseIterable {
        case mermaid
        case math
        case plantUML

        var script: String {
            switch self {
            case .mermaid: return MojiPluginManager.mermaidScript
            case .math: return MojiPluginManager.mathScript
            case .plantUML: return MojiPluginManager.plantUMLScript
            }
        }
    }

    /// BuiltInPlugin 表示可由用户启停的内置预览增强。
    private enum BuiltInPlugin: String, CaseIterable {
        case tableOfContents = "builtin.table-of-contents"
        case copyCode = "builtin.copy-code"

        var displayName: String {
            switch self {
            case .tableOfContents: return "文档目录"
            case .copyCode: return "代码复制"
            }
        }

        var detail: String {
            switch self {
            case .tableOfContents: return "将 [TOC] 生成为可跳转的标题目录"
            case .copyCode: return "为代码块增加复制按钮和操作反馈"
            }
        }

        var script: String {
            switch self {
            case .tableOfContents:
                return MojiPluginManager.tableOfContentsScript
            case .copyCode:
                return MojiPluginManager.copyCodeScript
            }
        }
    }

    private init() {}

    var pluginDirectory: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseURL.appendingPathComponent("墨记/Plugins", isDirectory: true)
    }

    func ensurePluginDirectoryExists() {
        try? fileManager.createDirectory(at: pluginDirectory, withIntermediateDirectories: true)
    }

    /// 返回全部可管理插件，内置插件固定在前，用户插件按文件名排序。
    func availablePlugins() -> [MojiPluginDescriptor] {
        let builtInPlugins = BuiltInPlugin.allCases.map { plugin in
            MojiPluginDescriptor(
                identifier: plugin.rawValue,
                displayName: plugin.displayName,
                detail: plugin.detail,
                source: .builtIn,
                fileURL: nil,
                isEnabled: MojiPreferences.shared.isPluginEnabled(identifier: plugin.rawValue)
            )
        }
        return builtInPlugins + userPluginDescriptors()
    }

    /// 更新指定插件的启用状态。
    func setPlugin(identifier: String, isEnabled: Bool) {
        MojiPreferences.shared.setPlugin(identifier: identifier, isEnabled: isEnabled)
    }

    /// 把用户选择的脚本复制到插件目录。
    /// 同名文件不会直接覆盖，而是自动追加序号，避免误删用户已有插件。
    @discardableResult
    func installPluginFiles(from sourceURLs: [URL]) throws -> [URL] {
        ensurePluginDirectoryExists()
        return try sourceURLs.map { sourceURL in
            let destinationURL = uniqueDestinationURL(for: sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }
    }

    func loadPluginScripts() -> [String] {
        // Mermaid、数学公式和 PlantUML 属于文档格式能力，必须始终先于可选插件加载。
        let coreScripts = CorePreviewExtension.allCases.map(\.script)
        guard MojiPreferences.shared.pluginsEnabled else { return coreScripts }

        let optionalScripts: [String] = availablePlugins().compactMap { descriptor -> String? in
            guard descriptor.isEnabled else { return nil }
            switch descriptor.source {
            case .builtIn:
                return BuiltInPlugin(rawValue: descriptor.identifier)?.script
            case .user:
                guard let fileURL = descriptor.fileURL else { return nil }
                return try? String(contentsOf: fileURL, encoding: .utf8)
            }
        }
        return coreScripts + optionalScripts
    }

    /// 扫描插件目录，只接受普通、非隐藏且不超过 1 MB 的 JavaScript 文件。
    /// 文件大小限制能防止误放入大型资源文件后拖慢每次预览刷新。
    private func userPluginDescriptors() -> [MojiPluginDescriptor] {
        ensurePluginDirectoryExists()
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: pluginDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension.lowercased() == "js" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { fileURL in
                guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize <= 1_048_576 else {
                    return nil
                }
                let identifier = "user.\(fileURL.lastPathComponent)"
                return MojiPluginDescriptor(
                    identifier: identifier,
                    displayName: fileURL.deletingPathExtension().lastPathComponent,
                    detail: "用户脚本 · \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))",
                    source: .user,
                    fileURL: fileURL,
                    isEnabled: MojiPreferences.shared.isPluginEnabled(identifier: identifier)
                )
            }
    }

    /// 为同名插件生成不会覆盖现有文件的目标地址。
    private func uniqueDestinationURL(for fileName: String) -> URL {
        let sourceName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        var candidateURL = pluginDirectory.appendingPathComponent(fileName)
        var suffix = 2
        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = pluginDirectory.appendingPathComponent("\(sourceName) \(suffix).\(fileExtension)")
            suffix += 1
        }
        return candidateURL
    }

    /// 内置“文档目录”插件：把占位符替换为当前文档标题树，并补充平滑跳转样式。
    private static let tableOfContentsScript = """
    (() => {
      const placeholder = document.querySelector('.toc-placeholder');
      if (!placeholder) return;
      window.mojiWillChangeLayout?.();
      const headings = Array.from(document.querySelectorAll('h1, h2, h3'));
      placeholder.innerHTML = '';
      const title = document.createElement('strong');
      title.textContent = '目录';
      placeholder.appendChild(title);
      if (headings.length === 0) {
        const empty = document.createElement('p');
        empty.textContent = '当前文档暂无标题';
        placeholder.appendChild(empty);
        window.mojiDidChangeLayout?.();
        return;
      }
      const list = document.createElement('ol');
      list.className = 'moji-toc-list';
      headings.forEach((heading, index) => {
        if (!heading.id) heading.id = `moji-heading-${index + 1}`;
        const item = document.createElement('li');
        item.className = `moji-toc-level-${heading.tagName.substring(1)}`;
        const link = document.createElement('a');
        link.href = `#${heading.id}`;
        link.textContent = heading.textContent || `标题 ${index + 1}`;
        item.appendChild(link);
        list.appendChild(item);
      });
      placeholder.appendChild(list);
      const style = document.createElement('style');
      style.textContent = '.moji-toc-list{margin:12px 0 0;padding-left:20px}.moji-toc-list li{margin:5px 0}.moji-toc-level-2{margin-left:14px!important}.moji-toc-level-3{margin-left:28px!important}html{scroll-behavior:smooth}';
      document.head.appendChild(style);
      window.mojiDidChangeLayout?.();
    })();
    """

    /// 内置“代码复制”插件：使用系统剪贴板 API，并在不可用时回退到旧复制命令。
    private static let copyCodeScript = """
    (() => {
      const style = document.createElement('style');
      style.textContent = 'pre{position:relative}.moji-copy-code{position:absolute;top:8px;right:8px;border:1px solid var(--border);border-radius:6px;padding:4px 9px;background:var(--content-bg);color:var(--muted);font:12px -apple-system;cursor:pointer;opacity:0;transition:opacity .15s ease}pre:hover .moji-copy-code,.moji-copy-code:focus{opacity:1}';
      document.head.appendChild(style);
      document.querySelectorAll('pre > code').forEach((code) => {
        const button = document.createElement('button');
        button.className = 'moji-copy-code';
        button.type = 'button';
        button.textContent = '复制';
        button.addEventListener('click', async () => {
          const value = code.textContent || '';
          try {
            await navigator.clipboard.writeText(value);
          } catch (_) {
            const area = document.createElement('textarea');
            area.value = value;
            document.body.appendChild(area);
            area.select();
            document.execCommand('copy');
            area.remove();
          }
          button.textContent = '已复制';
          window.setTimeout(() => { button.textContent = '复制'; }, 1200);
        });
        code.parentElement.appendChild(button);
      });
    })();
    """

    /// Mermaid 核心扩展：先加载随应用打包的官方运行库，再把对应代码块替换为 SVG 图表。
    private static var mermaidScript: String {
        guard let libraryURL = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let library = try? String(contentsOf: libraryURL, encoding: .utf8) else {
            return "console.error('墨记：Mermaid 运行库缺失');"
        }
        return library + """

        (() => {
          const blocks = Array.from(document.querySelectorAll('pre > code.language-mermaid'));
          if (!blocks.length || typeof mermaid === 'undefined') return;
          window.mojiWillChangeLayout?.();
          const colorScheme = getComputedStyle(document.documentElement).colorScheme || '';
          mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            theme: colorScheme.includes('dark') ? 'dark' : 'default'
          });
          blocks.forEach((code) => {
            const container = document.createElement('div');
            container.className = 'mermaid';
            container.textContent = code.textContent || '';
            const sourceBlock = code.parentElement;
            if (sourceBlock?.dataset.sourceLine) container.dataset.sourceLine = sourceBlock.dataset.sourceLine;
            sourceBlock.replaceWith(container);
          });
          mermaid.run({ nodes: document.querySelectorAll('.mermaid') })
            .then(() => { window.mojiDidChangeLayout?.(); })
            .catch((error) => {
              console.error('墨记 Mermaid 渲染失败', error);
              window.mojiDidChangeLayout?.();
            });
        })();
        """
    }

    /// 数学公式核心扩展：加载随应用分发的 KaTeX、自动渲染扩展和内嵌字体样式。
    /// 所有公式都在本地 WKWebView 中计算，不会把文档内容发送到网络。
    private static var mathScript: String {
        guard let libraryURL = Bundle.main.url(forResource: "katex.min", withExtension: "js"),
              let autoRenderURL = Bundle.main.url(forResource: "katex-auto-render.min", withExtension: "js"),
              let styleURL = Bundle.main.url(forResource: "katex.min", withExtension: "css"),
              let library = try? String(contentsOf: libraryURL, encoding: .utf8),
              let autoRender = try? String(contentsOf: autoRenderURL, encoding: .utf8),
              let style = try? String(contentsOf: styleURL, encoding: .utf8),
              let encodedStyleData = try? JSONEncoder().encode(style),
              let encodedStyle = String(data: encodedStyleData, encoding: .utf8) else {
            return "console.error('墨记：KaTeX 运行库缺失');"
        }
        return library + "\n" + autoRender + "\n" + """
        (() => {
          if (typeof renderMathInElement !== 'function') return;
          window.mojiWillChangeLayout?.();
          const style = document.createElement('style');
          style.dataset.mojiKatex = 'ready';
          style.textContent = \(encodedStyle);
          document.head.appendChild(style);
          renderMathInElement(document.querySelector('.markdown-body'), {
            delimiters: [
              { left: '$$', right: '$$', display: true },
              { left: '\\[', right: '\\]', display: true },
              { left: '$', right: '$', display: false },
              { left: '\\(', right: '\\)', display: false }
            ],
            ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
            throwOnError: false,
            strict: false,
            trust: false
          });
          window.mojiDidChangeLayout?.();
        })();
        """
    }

    /// PlantUML 核心扩展：把代码块发送到墨记原生层，并使用随应用分发的运行时在本地生成 SVG。
    /// 网页端只负责请求、状态展示和安全导入，任何图表源码都不会离开本机。
    private static let plantUMLScript = """
    (() => {
      const pendingContainers = new Map();
      const style = document.createElement('style');
      style.textContent = '.moji-plantuml{margin:20px 0;padding:18px;overflow:auto;text-align:center;border:1px solid var(--border);border-radius:8px;background:var(--content-bg)}.moji-plantuml svg{display:inline-block;max-width:100%;height:auto}.moji-plantuml-status{color:var(--muted);font:13px -apple-system,BlinkMacSystemFont,sans-serif}.moji-plantuml-error{color:#c23b32;text-align:left;white-space:pre-wrap}';
      document.head.appendChild(style);

      // 原生层返回完整 SVG 文本；解析后删除可执行节点和事件属性再导入预览页面。
      window.mojiCompletePlantUML = (identifier, svgText, errorMessage) => {
        const container = pendingContainers.get(identifier);
        if (!container || !container.isConnected) return;
        window.mojiWillChangeLayout?.();
        const finishLayoutChange = () => { window.mojiDidChangeLayout?.(); };
        pendingContainers.delete(identifier);
        if (errorMessage) {
          container.classList.add('moji-plantuml-error');
          container.textContent = `PlantUML 本地渲染失败：${errorMessage}`;
          finishLayoutChange();
          return;
        }

        const parsed = new DOMParser().parseFromString(svgText || '', 'image/svg+xml');
        const svg = parsed.documentElement;
        if (!svg || svg.localName !== 'svg' || parsed.querySelector('parsererror')) {
          container.classList.add('moji-plantuml-error');
          container.textContent = 'PlantUML 本地渲染失败：生成结果不是有效的 SVG。';
          finishLayoutChange();
          return;
        }
        parsed.querySelectorAll('script,foreignObject,iframe,object,embed').forEach((node) => node.remove());
        parsed.querySelectorAll('*').forEach((node) => {
          Array.from(node.attributes).forEach((attribute) => {
            const name = attribute.name.toLowerCase();
            const value = attribute.value.trim().toLowerCase();
            if (name.startsWith('on') || ((name === 'href' || name.endsWith(':href')) && value.startsWith('javascript:'))) {
              node.removeAttribute(attribute.name);
            }
          });
        });
        container.replaceChildren(document.importNode(svg, true));
        finishLayoutChange();
      };

      window.mojiWillChangeLayout?.();
      document.querySelectorAll('pre > code.language-plantuml, pre > code.language-puml').forEach((code, index) => {
        const identifier = `plantuml-${Date.now()}-${index}-${Math.random().toString(36).slice(2)}`;
        const container = document.createElement('div');
        container.className = 'moji-plantuml';
        container.setAttribute('role', 'img');
        container.setAttribute('aria-label', 'PlantUML 图表');
        const status = document.createElement('span');
        status.className = 'moji-plantuml-status';
        status.textContent = '正在本地渲染 PlantUML…';
        container.appendChild(status);
        const sourceBlock = code.parentElement;
        if (sourceBlock?.dataset.sourceLine) container.dataset.sourceLine = sourceBlock.dataset.sourceLine;
        sourceBlock.replaceWith(container);
        pendingContainers.set(identifier, container);

        // 短暂延迟可丢弃实时编辑期间被迅速替换的旧页面，避免每个按键都启动 Java 进程。
        window.setTimeout(() => {
          if (!container.isConnected) return;
          const handler = window.webkit?.messageHandlers?.mojiPlantUML;
          if (!handler) {
            window.mojiCompletePlantUML(identifier, null, '本地渲染通道不可用。');
            return;
          }
          handler.postMessage({ identifier, source: code.textContent || '' });
        }, 220);
      });
      window.mojiDidChangeLayout?.();
    })();
    """
}
