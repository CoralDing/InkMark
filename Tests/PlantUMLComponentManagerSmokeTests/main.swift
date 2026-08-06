/**
 * 文件说明：验证 PlantUML 按需组件的导入、渲染与移除完整链路。
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-06
 */

import Foundation

/// ComponentManagerSmokeTestError 将异步安装和渲染失败转为命令行可读错误，便于 CI 定位问题。
enum ComponentManagerSmokeTestError: LocalizedError {
    case missingSourceDirectory
    case timedOut(String)
    case invalidSVG

    var errorDescription: String? {
        switch self {
        case .missingSourceDirectory:
            return "请传入已解压的 PlantUML 组件目录。"
        case .timedOut(let operation):
            return "\(operation) 超时。"
        case .invalidSVG:
            return "PlantUML 未返回有效 SVG。"
        }
    }
}

/// 等待组件管理器的异步回调，同时运行主线程事件循环，保证回调能按其 API 约定回到主线程。
func waitForResult<Value>(
    operation: String,
    timeout: TimeInterval = 30,
    start: (@escaping (Result<Value, Error>) -> Void) -> Void
) throws -> Value {
    let deadline = Date().addingTimeInterval(timeout)
    var result: Result<Value, Error>?
    start { callbackResult in
        result = callbackResult
    }

    while result == nil, Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    guard let result else {
        throw ComponentManagerSmokeTestError.timedOut(operation)
    }
    return try result.get()
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw ComponentManagerSmokeTestError.missingSourceDirectory
    }
    let sourceDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let componentManager = MojiPlantUMLComponentManager.shared

    // 测试使用 CFFIXED_USER_HOME 隔离应用支持目录，因此可安全覆盖同名组件并在结束时移除。
    try? componentManager.removeInstalledComponent()
    let component = try waitForResult(operation: "PlantUML 组件导入") { completion in
        componentManager.install(fromDirectory: sourceDirectory, completion: completion)
    }
    guard component.byteCount > 0,
          componentManager.componentURLs() != nil else {
        throw ComponentManagerSmokeTestError.invalidSVG
    }

    let svg = try waitForResult(operation: "PlantUML 图表渲染") { completion in
        MojiPlantUMLRenderer.shared.render(
            source: "@startuml\nAlice -> Bob: Component test\n@enduml",
            completion: completion
        )
    }
    guard svg.range(of: "<svg", options: .caseInsensitive) != nil else {
        throw ComponentManagerSmokeTestError.invalidSVG
    }

    try componentManager.removeInstalledComponent()
    print("PlantUML 按需组件冒烟测试通过。")
} catch {
    fputs("测试失败：\(error.localizedDescription)\n", stderr)
    exit(1)
}
