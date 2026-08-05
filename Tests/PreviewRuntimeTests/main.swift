/**
 * 文件说明：墨记预览运行时测试，验证核心图表与公式在插件开关两种状态下均完成本地渲染。
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-05
 */

import AppKit
import Foundation
import WebKit

/// RuntimeSnapshot 对应网页端返回的核心渲染结果数量。
private struct RuntimeSnapshot: Decodable {
    let mermaid: Int
    let math: Int
    let plantUML: Int
}

/// ScrollMappingSnapshot 保存网页端滚动映射的端点和单调性检查结果。
private struct ScrollMappingSnapshot: Decodable {
    let topLine: Double
    let bottomLine: Double
    let topY: Double
    let bottomY: Double
    let maximumY: Double
    let totalLines: Double
    let monotonic: Bool
}

/// PreviewRuntimeTestError 让命令行测试失败时明确指出缺失的运行能力。
private enum PreviewRuntimeTestError: LocalizedError {
    case timeout(String)
    case invalidResult
    case invalidScrollMapping(String)
    case unstableLayout(Double, Double, String)

    var errorDescription: String? {
        switch self {
        case .timeout(let state): return "预览运行时测试超时：\(state)"
        case .invalidResult: return "预览运行时返回了无法解析的结果。"
        case .invalidScrollMapping(let state): return "滚动映射测试失败：\(state)"
        case .unstableLayout(let before, let after, let state):
            return "页面异步增高后源行发生偏移：\(before) -> \(after)，\(state)"
        }
    }
}

/// 验证滚动映射的首尾端点、单调性，以及异步布局变化后的语义位置保持能力。
private func verifyScrollSynchronization(in controller: ModernPreviewViewController) throws {
    let mappingScript = """
    (() => {
      const total = Number(document.querySelector('.markdown-body')?.dataset.sourceLineCount || 1);
      const maximum = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      const lines = [1, total * 0.2, total * 0.4, total * 0.6, total * 0.8, total];
      const positions = lines.map((line) => window.mojiScrollYForSourceLine(line));
      return JSON.stringify({
        topLine: window.mojiSourceLineForScrollY(0),
        bottomLine: window.mojiSourceLineForScrollY(maximum),
        topY: positions[0],
        bottomY: positions[positions.length - 1],
        maximumY: maximum,
        totalLines: total,
        monotonic: positions.every((value, index) => index === 0 || value >= positions[index - 1])
      });
    })()
    """
    var mappingResult: String?
    controller.webView.evaluateJavaScript(mappingScript) { result, _ in
        mappingResult = result as? String
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    guard let mappingResult,
          let data = mappingResult.data(using: .utf8),
          let snapshot = try? JSONDecoder().decode(ScrollMappingSnapshot.self, from: data) else {
        throw PreviewRuntimeTestError.invalidResult
    }
    let endpointsAreValid = snapshot.maximumY <= 1 || (
        abs(snapshot.bottomLine - snapshot.totalLines) < 0.01 &&
        abs(snapshot.bottomY - snapshot.maximumY) < 1
    )
    guard snapshot.monotonic,
          abs(snapshot.topLine - 1) < 0.01,
          abs(snapshot.topY) < 1,
          endpointsAreValid else {
        throw PreviewRuntimeTestError.invalidScrollMapping(mappingResult)
    }
    // 内容未超过视口时不存在可验证的滚动位置，端点检查通过后直接结束。
    guard snapshot.maximumY > 1 else { return }

    let targetLine = max(2, snapshot.totalLines * 0.65)
    controller.webView.evaluateJavaScript("window.mojiScrollToSourceLine(\(targetLine))", completionHandler: nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    var sourceLineBefore = 0.0
    controller.webView.evaluateJavaScript("window.mojiSourceLineForScrollY(window.scrollY)") { result, _ in
        sourceLineBefore = (result as? NSNumber)?.doubleValue ?? 0
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))

    // 在正文顶部注入无源行占位高度，模拟图片或图表晚于页面加载完成的场景。
    controller.webView.evaluateJavaScript(
        "window.mojiWillChangeLayout(\(sourceLineBefore));const spacer=document.createElement('div');spacer.style.height='700px';document.querySelector('.markdown-body')?.prepend(spacer);window.mojiDidChangeLayout();"
    )
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    var sourceLineAfter = 0.0
    controller.webView.evaluateJavaScript("window.mojiSourceLineForScrollY(window.scrollY)") { result, _ in
        sourceLineAfter = (result as? NSNumber)?.doubleValue ?? 0
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    guard abs(sourceLineAfter - sourceLineBefore) <= 1 else {
        var synchronizationState = "无法读取同步状态"
        controller.webView.evaluateJavaScript("JSON.stringify({...window.mojiScrollSynchronizationState(),anchors:window.mojiScrollAnchors().filter((item)=>item.line>=190&&item.line<=240)})") { result, _ in
            synchronizationState = result as? String ?? synchronizationState
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        throw PreviewRuntimeTestError.unstableLayout(sourceLineBefore, sourceLineAfter, synchronizationState)
    }
}

/// 运行一次真实 WKWebView 预览，并等待三个核心渲染器都生成可见 DOM 节点。
private func runPreviewTest(
    markdown: String,
    pluginsEnabled: Bool,
    expectedMermaid: Int,
    expectedPlantUML: Int
) throws {
    MojiPreferences.shared.pluginsEnabled = pluginsEnabled
    let renderer = ModernMarkdownRenderer()

    let controller = ModernPreviewViewController()
    controller.loadView()
    // WKWebView 必须挂入真实窗口才能返回与应用一致的滚动坐标；纯离屏视图的 DOM 几何值不可靠。
    let testWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    testWindow.isReleasedWhenClosed = false
    testWindow.contentViewController = controller
    testWindow.orderFront(nil)
    defer { testWindow.close() }
    controller.load(
        html: renderer.renderHTML(from: markdown),
        baseURL: Bundle.main.resourceURL,
        pluginScripts: MojiPluginManager.shared.loadPluginScripts()
    )

    let deadline = Date().addingTimeInterval(20)
    var latestState = "尚未读取"
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        var resultText: String?
        controller.webView.evaluateJavaScript(
            "JSON.stringify({mermaid:document.querySelectorAll('.mermaid svg').length,math:document.querySelectorAll('.katex').length,plantUML:document.querySelectorAll('.moji-plantuml svg').length})"
        ) { result, _ in
            resultText = result as? String
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        guard let resultText else { continue }
        latestState = resultText
        guard let data = resultText.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(RuntimeSnapshot.self, from: data) else {
            throw PreviewRuntimeTestError.invalidResult
        }
        if snapshot.mermaid == expectedMermaid,
           snapshot.math >= 1,
           snapshot.plantUML == expectedPlantUML {
            // SVG 节点出现后再等待一次布局稳定，覆盖多个 PlantUML 串行返回的最后一轮尺寸通知。
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            try verifyScrollSynchronization(in: controller)
            print("通过：pluginsEnabled=\(pluginsEnabled)，\(resultText)")
            return
        }
    }
    throw PreviewRuntimeTestError.timeout(latestState)
}

_ = NSApplication.shared

let basicMarkdown = """
```mermaid
flowchart LR
  A --> B
```

行内公式：$E = mc^2$

```plantuml
@startuml
Alice -> Bob: Local
@enduml
```
"""

do {
    try runPreviewTest(
        markdown: basicMarkdown,
        pluginsEnabled: true,
        expectedMermaid: 1,
        expectedPlantUML: 1
    )
    try runPreviewTest(
        markdown: basicMarkdown,
        pluginsEnabled: false,
        expectedMermaid: 1,
        expectedPlantUML: 1
    )
    if CommandLine.arguments.count > 1 {
        let demoMarkdown = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        try runPreviewTest(
            markdown: demoMarkdown,
            pluginsEnabled: true,
            expectedMermaid: 4,
            expectedPlantUML: 3
        )
    }
    print("墨记核心预览运行时测试全部通过。")
} catch {
    fputs("测试失败：\(error.localizedDescription)\n", stderr)
    exit(1)
}
