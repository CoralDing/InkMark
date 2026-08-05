/**
 * 文件说明：墨记现代预览控制器，使用 WKWebView 替代旧 WebView 作为新预览组件。
 * 作者：Codex
 * 创建时间：2026-06-17
 */

import AppKit
import WebKit

/// ModernPreviewViewController 负责展示 Markdown 渲染后的 HTML。
/// 它使用稳定背景承载 WKWebView（网页预览控件），保证不同主题下都有可靠的文字对比度。
final class ModernPreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    /// CachedLocalImage 保存本地图片的修改时间和内嵌结果，避免每次输入都重复读取同一文件。
    private struct CachedLocalImage {
        let modificationDate: Date?
        let dataURI: String
    }

    private let containerView = NSView()
    private let scrollMessageName = "mojiScrollSync"
    private let plantUMLMessageName = "mojiPlantUML"
    private(set) var webView: WKWebView!
    private var pendingScrollRatio: Double = 0
    private var loadGeneration = 0
    private var hasRequestedInitialLoad = false
    private var localImageCache: [URL: CachedLocalImage] = [:]
    var onScrollSourceLineChange: ((Double) -> Void)?

    override func loadView() {
        // 预览内容本身会按主题绘制背景，外层保持系统窗口色，避免透明材质造成左右区域色彩污染。
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.suppressesIncrementalRendering = false
        // 使用弱引用消息代理接收网页滚动位置，避免 WKUserContentController 与控制器形成引用循环。
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: scrollMessageName
        )
        // PlantUML 源码只通过进程内消息交给原生渲染器，不建立任何网络请求。
        configuration.userContentController.add(
            WeakScriptMessageHandler(delegate: self),
            name: plantUMLMessageName
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        // WKWebView（网页预览控件）必须正常绘制页面背景；强制透明会导致部分 macOS 版本文字存在但不可见。

        containerView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.webView = webView
        self.view = containerView
    }

    /// 加载完整 HTML 内容。
    /// baseURL 使用文档所在目录，让相对图片和相对文件链接按照 Markdown 文件位置解析。
    /// 插件通过 WKUserScript（WebKit 原生脚本注入）加载，避免脚本文本破坏 HTML 页面结构。
    func load(html: String, baseURL: URL?, pluginScripts: [String]) {
        loadGeneration += 1
        let currentGeneration = loadGeneration
        let preparedHTML = embedLocalImages(in: html, baseURL: baseURL)

        // WKWebView 的初始空页面还不能稳定执行脚本，首次内容必须直接加载。
        guard hasRequestedInitialLoad else {
            hasRequestedInitialLoad = true
            pendingScrollRatio = 0
            // 文档窗口创建阶段 WKWebView 可能尚未挂到窗口；延后一轮可避免首个 loadHTMLString 被 WebKit 丢弃。
            DispatchQueue.main.async { [weak self] in
                guard let self, currentGeneration == self.loadGeneration else { return }
                self.performLoad(html: preparedHTML, baseURL: baseURL, pluginScripts: pluginScripts)
            }
            return
        }

        // 实时输入会频繁重载预览；先记录阅读比例，避免每次敲字都跳回文档顶部。
        let scrollScript = "window.scrollY / Math.max(1, document.documentElement.scrollHeight - window.innerHeight)"
        webView.evaluateJavaScript(scrollScript) { [weak self] result, _ in
            guard let self, currentGeneration == self.loadGeneration else { return }
            self.pendingScrollRatio = (result as? NSNumber)?.doubleValue ?? 0
            self.performLoad(html: preparedHTML, baseURL: baseURL, pluginScripts: pluginScripts)
        }
    }

    /// 把文档目录中的相对图片转换为 data URI（内嵌数据地址）。
    /// WKWebView 默认会拦截 loadHTMLString 引用的本地文件；内嵌后既能正常展示，也无需放宽网页读取权限。
    private func embedLocalImages(in html: String, baseURL: URL?) -> String {
        guard let baseURL, baseURL.isFileURL,
              let expression = try? NSRegularExpression(pattern: "src=\\\"([^\\\"]+)\\\"") else {
            return html
        }

        let mutableHTML = NSMutableString(string: html)
        let fullRange = NSRange(location: 0, length: mutableHTML.length)
        let matches = expression.matches(in: html, range: fullRange)

        // 从后向前替换可保证前面匹配项的 NSRange（UTF-16 字符范围）不会因字符串长度变化而失效。
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let sourceRange = match.range(at: 1)
            let encodedSource = mutableHTML.substring(with: sourceRange)
            let source = decodeHTMLEntities(encodedSource)

            guard !source.hasPrefix("data:"),
                  !source.hasPrefix("http://"),
                  !source.hasPrefix("https://"),
                  let imageURL = resolveLocalImageURL(source, relativeTo: baseURL),
                  let dataURI = localImageDataURI(for: imageURL) else {
                continue
            }
            mutableHTML.replaceCharacters(in: sourceRange, with: dataURI)
        }
        return mutableHTML as String
    }

    /// 解析相对图片路径，并限制在当前文档目录内。
    /// 该边界避免恶意 Markdown 通过 `../` 路径把用户其他目录文件嵌入预览页面。
    private func resolveLocalImageURL(_ source: String, relativeTo baseURL: URL) -> URL? {
        let decodedSource = source.removingPercentEncoding ?? source
        let candidateURL: URL
        if decodedSource.hasPrefix("file://"), let fileURL = URL(string: decodedSource) {
            candidateURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        } else {
            candidateURL = URL(fileURLWithPath: decodedSource, relativeTo: baseURL)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        }

        let basePath = baseURL.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidateURL.path
        guard candidatePath == basePath || candidatePath.hasPrefix(basePath + "/") else { return nil }
        return candidateURL
    }

    /// 读取并缓存小于 20 MB 的常见图片文件。
    /// 大文件继续交给原始加载流程，避免一次预览占用过多内存。
    private func localImageDataURI(for url: URL) -> String? {
        guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
              resourceValues.isRegularFile == true,
              let fileSize = resourceValues.fileSize,
              fileSize <= 20 * 1024 * 1024 else {
            return nil
        }
        if let cached = localImageCache[url], cached.modificationDate == resourceValues.contentModificationDate {
            return cached.dataURI
        }
        guard let mimeType = imageMIMEType(for: url.pathExtension),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let dataURI = "data:\(mimeType);base64,\(data.base64EncodedString())"
        localImageCache[url] = CachedLocalImage(
            modificationDate: resourceValues.contentModificationDate,
            dataURI: dataURI
        )
        return dataURI
    }

    /// 返回预览安全策略允许的常见图片 MIME（媒体类型）名称。
    private func imageMIMEType(for pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        default: return nil
        }
    }

    /// 还原渲染器为 HTML 属性安全而编码的少量实体，供本地文件路径解析使用。
    private func decodeHTMLEntities(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 配置当前插件并执行真正的 HTML 加载。
    /// 单独封装可以保证滚动位置读取完成后再重载页面，避免异步结果覆盖更新内容。
    private func performLoad(html: String, baseURL: URL?, pluginScripts: [String]) {
        let userContentController = webView.configuration.userContentController
        userContentController.removeAllUserScripts()
        // 同步基础设施必须先于渲染扩展注入，让目录、公式和图表能在改变布局前保存语义位置。
        userContentController.addUserScript(
            WKUserScript(
                source: Self.scrollSynchronizationScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        pluginScripts.forEach { source in
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(script)
        }
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// 页面渲染完成后恢复之前的相对阅读位置。
    /// 使用比例而不是固定像素，文档内容长度变化时仍能停留在大致相同段落。
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let ratio = min(max(pendingScrollRatio, 0), 1)
        let restoreScript = "window.mojiScrollToRatio ? window.mojiScrollToRatio(\(ratio)) : window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(ratio))"
        webView.evaluateJavaScript(restoreScript, completionHandler: nil)
    }

    /// 按 Markdown 源行滚动预览区。
    /// 网页端会根据相邻源行锚点插值，图片或代码块高度较大时仍能落到对应内容附近。
    func scrollToSourceLine(_ sourceLine: Double) {
        guard sourceLine.isFinite, isViewLoaded else { return }
        let clampedLine = max(1, sourceLine)
        webView.evaluateJavaScript("window.mojiScrollToSourceLine?.(\(clampedLine))", completionHandler: nil)
    }

    /// 接收预览网页消息：滚动消息用于同步编辑器，PlantUML 消息交给本地渲染器。
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case scrollMessageName:
            guard let number = message.body as? NSNumber,
                  number.doubleValue.isFinite else {
                return
            }
            onScrollSourceLineChange?(max(1, number.doubleValue))
        case plantUMLMessageName:
            handlePlantUMLMessage(message)
        default:
            return
        }
    }

    /// 校验网页传入的 PlantUML 请求，并在当前页面仍有效时回传本地生成的 SVG。
    /// 页面代次检查可以阻止旧文档的异步结果覆盖用户刚刚输入的新内容。
    private func handlePlantUMLMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let identifier = body["identifier"] as? String,
              !identifier.isEmpty,
              identifier.count <= 200,
              let source = body["source"] as? String else {
            return
        }

        let requestGeneration = loadGeneration
        MojiPlantUMLRenderer.shared.render(source: source) { [weak self] result in
            guard let self, requestGeneration == self.loadGeneration else { return }
            switch result {
            case .success(let svg):
                self.completePlantUML(identifier: identifier, svg: svg, errorMessage: nil)
            case .failure(let error):
                self.completePlantUML(
                    identifier: identifier,
                    svg: nil,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    /// 使用 JSON（结构化数据格式）编码回传参数，避免图表文本中的引号或换行破坏 JavaScript。
    private func completePlantUML(identifier: String, svg: String?, errorMessage: String?) {
        let arguments: [Any] = [identifier, svg ?? NSNull(), errorMessage ?? NSNull()]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        webView.evaluateJavaScript("window.mojiCompletePlantUML?.(...\(json))", completionHandler: nil)
    }

    /// 预览滚动同步脚本：在源行锚点之间双向插值，并抑制原生代码触发的回传事件。
    /// requestAnimationFrame（浏览器逐帧回调）会把高频触控板事件压缩为每帧一次消息。
    private static let scrollSynchronizationScript = """
    (() => {
      if (window.mojiScrollSynchronizationReady) return;
      window.mojiScrollSynchronizationReady = true;
      let isApplyingNativeScroll = false;
      let scheduledFrame = 0;
      let synchronizedScrollTimer = 0;
      let layoutStabilizationTimer = 0;
      let layoutChangeGeneration = 0;
      let pendingLayoutSourceLine = null;
      let userScrollIntentUntil = 0;
      let lastKnownSourceLine = 1;
      let lastRequestedScrollY = 0;

      const maximumScrollY = () => Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      const totalSourceLines = () => Math.max(1, Number(document.querySelector('.markdown-body')?.dataset.sourceLineCount || 1));
      const documentTop = (element) => {
        let top = 0;
        let current = element;
        while (current) {
          top += Number(current.offsetTop || 0);
          current = current.offsetParent;
        }
        return top;
      };
      const anchors = () => {
        const maximum = maximumScrollY();
        const total = totalSourceLines();
        // 只使用正文直属块作为全局锚点；嵌套列表、表格行和分栏子列可能与源码顺序不同。
        const rawItems = Array.from(document.querySelectorAll('.markdown-body > [data-source-line]')).map((element) => ({
          line: Number(element.dataset.sourceLine),
          // offsetTop（布局顶部坐标）不受当前滚动位置影响，比视口坐标换算更适合双向映射。
          top: documentTop(element)
        }))
        .filter((item) => Number.isFinite(item.line) && Number.isFinite(item.top))
        .sort((left, right) => left.line - right.line || left.top - right.top);

        // 嵌套容器会让同一源行拥有多个锚点；内容分栏还会让后面的源行出现在更高位置。
        // 按源行合并后执行单调化，保证二分区间始终同时按源行和页面位置递增。
        const mergedItems = [];
        rawItems.forEach((item) => {
          const line = Math.min(total, Math.max(1, item.line));
          const top = Math.min(maximum, Math.max(0, item.top));
          const previous = mergedItems[mergedItems.length - 1];
          if (previous && previous.line === line) {
            previous.top = Math.min(previous.top, top);
          } else {
            mergedItems.push({ line, top });
          }
        });

        if (!mergedItems.length || mergedItems[0].line > 1) {
          mergedItems.unshift({ line: 1, top: 0 });
        } else {
          mergedItems[0].top = 0;
        }
        if (mergedItems[mergedItems.length - 1].line < total) {
          mergedItems.push({ line: total, top: maximum });
        }

        // 先固定首行端点再执行单调化，避免首个实际元素的瞬时异常坐标污染整张映射表。
        let monotonicTop = 0;
        mergedItems.forEach((item) => {
          item.top = Math.max(monotonicTop, item.top);
          monotonicTop = item.top;
        });
        mergedItems[mergedItems.length - 1].top = maximum;
        return mergedItems;
      };

      const interpolate = (value, lowerValue, upperValue, lowerResult, upperResult) => {
        if (upperValue <= lowerValue) return lowerResult;
        const fraction = Math.min(1, Math.max(0, (value - lowerValue) / (upperValue - lowerValue)));
        return lowerResult + (upperResult - lowerResult) * fraction;
      };

      const scrollYForSourceLine = (sourceLine) => {
        const items = anchors();
        const maximum = maximumScrollY();
        const total = totalSourceLines();
        if (sourceLine <= 1) return 0;
        if (sourceLine >= total) return maximum;
        if (!items.length) return maximum * ((sourceLine - 1) / Math.max(1, totalSourceLines() - 1));
        if (sourceLine <= items[0].line) return interpolate(sourceLine, 1, items[0].line, 0, items[0].top);
        for (let index = 1; index < items.length; index += 1) {
          if (sourceLine <= items[index].line) {
            return interpolate(sourceLine, items[index - 1].line, items[index].line, items[index - 1].top, items[index].top);
          }
        }
        const last = items[items.length - 1];
        return interpolate(sourceLine, last.line, totalSourceLines(), last.top, maximum);
      };

      const sourceLineForScrollY = (scrollY) => {
        const items = anchors();
        const maximum = maximumScrollY();
        const total = totalSourceLines();
        if (scrollY <= 1) return 1;
        if (maximum > 0 && scrollY >= maximum - 1) return total;
        if (!items.length) return 1 + (totalSourceLines() - 1) * (scrollY / Math.max(1, maximum));
        if (scrollY <= items[0].top) return interpolate(scrollY, 0, items[0].top, 1, items[0].line);
        for (let index = 1; index < items.length; index += 1) {
          if (scrollY <= items[index].top) {
            return interpolate(scrollY, items[index - 1].top, items[index].top, items[index - 1].line, items[index].line);
          }
        }
        const last = items[items.length - 1];
        return interpolate(scrollY, last.top, maximum, last.line, totalSourceLines());
      };

      const performNativeScroll = (targetY, sourceLine) => {
        isApplyingNativeScroll = true;
        window.clearTimeout(synchronizedScrollTimer);
        lastRequestedScrollY = Math.min(maximumScrollY(), Math.max(0, targetY));
        window.scrollTo(0, lastRequestedScrollY);
        lastKnownSourceLine = Number.isFinite(sourceLine) ? sourceLine : sourceLineForScrollY(window.scrollY);
        synchronizedScrollTimer = window.setTimeout(() => {
          lastKnownSourceLine = sourceLineForScrollY(window.scrollY);
          isApplyingNativeScroll = false;
        }, 90);
      };

      window.mojiScrollYForSourceLine = scrollYForSourceLine;
      window.mojiSourceLineForScrollY = sourceLineForScrollY;
      window.mojiScrollAnchors = anchors;
      window.mojiScrollSynchronizationState = () => ({
        sourceLine: lastKnownSourceLine,
        scrollY: window.scrollY,
        lastRequestedScrollY,
        expectedY: scrollYForSourceLine(lastKnownSourceLine),
        maximumY: maximumScrollY(),
        documentHeight: document.documentElement.scrollHeight,
        isApplyingNativeScroll
      });
      window.mojiWillChangeLayout = (sourceLine) => {
        layoutChangeGeneration += 1;
        const explicitLine = Number(sourceLine);
        if (pendingLayoutSourceLine === null) {
          pendingLayoutSourceLine = Number.isFinite(explicitLine) ? explicitLine : lastKnownSourceLine;
        }
        window.clearTimeout(layoutStabilizationTimer);
      };
      window.mojiDidChangeLayout = () => {
        window.clearTimeout(layoutStabilizationTimer);
        const currentLayoutGeneration = layoutChangeGeneration;
        let remainingCorrections = 4;
        const restoreStableLine = () => {
          if (currentLayoutGeneration !== layoutChangeGeneration) return;
          const stableLine = pendingLayoutSourceLine;
          if (!Number.isFinite(stableLine) || window.scrollY <= 1) {
            pendingLayoutSourceLine = null;
            return;
          }
          performNativeScroll(scrollYForSourceLine(stableLine), stableLine);
          remainingCorrections -= 1;
          if (remainingCorrections > 0) {
            layoutStabilizationTimer = window.setTimeout(restoreStableLine, 120);
          } else {
            pendingLayoutSourceLine = null;
          }
        };
        layoutStabilizationTimer = window.setTimeout(restoreStableLine, 0);
      };
      window.mojiScrollToSourceLine = (sourceLine) => {
        const line = Math.min(totalSourceLines(), Math.max(1, Number(sourceLine)));
        layoutChangeGeneration += 1;
        window.clearTimeout(layoutStabilizationTimer);
        pendingLayoutSourceLine = null;
        performNativeScroll(scrollYForSourceLine(line), line);
      };
      window.mojiScrollToRatio = (ratio) => {
        const targetY = maximumScrollY() * Math.min(1, Math.max(0, Number(ratio)));
        layoutChangeGeneration += 1;
        window.clearTimeout(layoutStabilizationTimer);
        pendingLayoutSourceLine = null;
        performNativeScroll(targetY, sourceLineForScrollY(targetY));
      };

      window.addEventListener('scroll', () => {
        if (isApplyingNativeScroll || scheduledFrame) return;
        scheduledFrame = window.requestAnimationFrame(() => {
          scheduledFrame = 0;
          if (isApplyingNativeScroll) return;
          // DOM 变化可能触发 WebKit 自带的被动滚动；没有近期滚轮意图时不能覆盖待恢复源行。
          if (pendingLayoutSourceLine !== null && performance.now() > userScrollIntentUntil) return;
          lastKnownSourceLine = sourceLineForScrollY(window.scrollY);
          // 用户在布局稳定等待期间继续滚动时，以最新主动位置为准。
          if (pendingLayoutSourceLine !== null) pendingLayoutSourceLine = lastKnownSourceLine;
          window.webkit.messageHandlers.mojiScrollSync.postMessage(lastKnownSourceLine);
        });
      }, { passive: true });
      window.addEventListener('wheel', () => {
        userScrollIntentUntil = performance.now() + 240;
      }, { passive: true });
    })();
    """

    /// 把用户点击的外部链接交给系统默认应用处理，避免预览区离开当前 Markdown 文档。
    /// 页内 `#标题` 锚点继续留在 WKWebView 内完成滚动。
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.fragment != nil && (url.scheme == nil || url.isFileURL) {
            decisionHandler(.allow)
            return
        }

        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") || url.isFileURL {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

/// WeakScriptMessageHandler 弱持有真正的消息接收者，解决 WebKit 消息通道的强引用循环。
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    /// WebKit 收到网页消息后透传给仍存活的预览控制器。
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
