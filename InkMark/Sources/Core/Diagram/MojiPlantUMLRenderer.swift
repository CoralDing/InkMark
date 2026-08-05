/**
 * 文件说明：墨记 PlantUML 本地渲染器，使用随应用分发的 Java 运行时生成 SVG。
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-05
 */

import Foundation

/// MojiPlantUMLRenderer 在独立串行队列中执行 PlantUML，避免并发 Java 进程占用过多内存。
/// 渲染结果按源码缓存，实时编辑或切换视图时无需重复计算相同图表。
final class MojiPlantUMLRenderer {
    static let shared = MojiPlantUMLRenderer()

    /// RendererError 为网页预览提供可直接展示的中文错误信息。
    private enum RendererError: LocalizedError {
        case emptySource
        case sourceTooLarge
        case missingRuntime
        case launchFailed(String)
        case renderingFailed(String)
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .emptySource:
                return "图表源码为空。"
            case .sourceTooLarge:
                return "图表源码超过 1 MB 安全限制。"
            case .missingRuntime:
                return "应用内置的 PlantUML 或 Java 运行时缺失。"
            case .launchFailed(let message):
                return "无法启动本地渲染器：\(message)"
            case .renderingFailed(let message):
                return message.isEmpty ? "PlantUML 未能生成图表。" : message
            case .invalidOutput:
                return "PlantUML 生成了无效的 SVG 内容。"
            }
        }
    }

    private let renderQueue = DispatchQueue(label: "io.github.dingyi60.moji.plantuml", qos: .userInitiated)
    private let cache = NSCache<NSString, NSString>()
    private let maximumSourceSize = 1_048_576

    private init() {
        // SVG 通常体积较小；限制条目数量可避免长时间编辑大量不同图表后持续占用内存。
        cache.countLimit = 64
    }

    /// 异步渲染 PlantUML 源码，并保证完成回调始终回到主线程更新 WebKit。
    func render(source: String, completion: @escaping (Result<String, Error>) -> Void) {
        let sourceData = Data(source.utf8)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(RendererError.emptySource))
            return
        }
        guard sourceData.count <= maximumSourceSize else {
            completion(.failure(RendererError.sourceTooLarge))
            return
        }

        if let cachedSVG = cache.object(forKey: source as NSString) {
            completion(.success(cachedSVG as String))
            return
        }

        renderQueue.async { [weak self] in
            guard let self else { return }
            // Smetana 是 PlantUML 内置布局引擎，可让类图等场景不依赖用户额外安装 Graphviz。
            let preparedSourceData = Data(self.sourceUsingBundledLayoutEngine(source).utf8)
            let result = self.renderSynchronously(sourceData: preparedSourceData)
            if case .success(let svg) = result {
                self.cache.setObject(svg as NSString, forKey: source as NSString)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// 为未指定布局引擎的 UML 文档注入 Smetana 配置。
    /// 用户已经明确写出 `!pragma layout` 时尊重原配置，避免覆盖高级用法。
    private func sourceUsingBundledLayoutEngine(_ source: String) -> String {
        guard source.range(of: "!pragma layout", options: .caseInsensitive) == nil else {
            return source
        }

        var lines = source.components(separatedBy: .newlines)
        guard let startIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("@startuml")
        }) else {
            return source
        }
        lines.insert("!pragma layout smetana", at: startIndex + 1)
        return lines.joined(separator: "\n")
    }

    /// 启动随应用分发的 Java 进程，通过标准输入传入源码，并从临时文件读取 SVG。
    /// 输出使用文件而不是双向管道，避免大型图表填满缓冲区后让父子进程互相等待。
    private func renderSynchronously(sourceData: Data) -> Result<String, Error> {
        guard let javaURL = bundledJavaURL(),
              let jarURL = bundledPlantUMLURL(),
              FileManager.default.isExecutableFile(atPath: javaURL.path),
              FileManager.default.fileExists(atPath: jarURL.path) else {
            return .failure(RendererError.missingRuntime)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moji-plantuml-\(UUID().uuidString)", isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("output.svg")
        let errorURL = temporaryDirectory.appendingPathComponent("error.txt")

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            FileManager.default.createFile(atPath: errorURL.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            let inputPipe = Pipe()
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            let errorHandle = try FileHandle(forWritingTo: errorURL)
            defer {
                try? outputHandle.close()
                try? errorHandle.close()
            }

            let process = Process()
            process.executableURL = javaURL
            process.arguments = [
                "-Djava.awt.headless=true",
                "-jar", jarURL.path,
                "-pipe",
                "-tsvg",
                "-charset", "UTF-8"
            ]
            process.standardInput = inputPipe
            process.standardOutput = outputHandle
            process.standardError = errorHandle
            // SECURE 安全配置禁止图表通过 include 指令读取本机文件或访问网络。
            var environment = ProcessInfo.processInfo.environment
            environment["PLANTUML_SECURITY_PROFILE"] = "SECURE"
            process.environment = environment

            do {
                try process.run()
            } catch {
                return .failure(RendererError.launchFailed(error.localizedDescription))
            }

            inputPipe.fileHandleForWriting.write(sourceData)
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            try? outputHandle.synchronize()
            try? errorHandle.synchronize()

            let errorMessage = (try? String(contentsOf: errorURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0 else {
                return .failure(RendererError.renderingFailed(errorMessage))
            }

            guard let svg = try? String(contentsOf: outputURL, encoding: .utf8),
                  svg.range(of: "<svg", options: .caseInsensitive) != nil else {
                return .failure(RendererError.invalidOutput)
            }
            return .success(svg)
        } catch {
            return .failure(RendererError.launchFailed(error.localizedDescription))
        }
    }

    /// 根据当前应用进程架构选择匹配的 Java 运行时，保证通用应用在 Apple 芯片和 Intel 上均可执行。
    private func bundledJavaURL() -> URL? {
        #if arch(arm64)
        let runtimeDirectory = "runtime-arm64"
        #elseif arch(x86_64)
        let runtimeDirectory = "runtime-x86_64"
        #else
        return nil
        #endif

        return Bundle.main.resourceURL?
            .appendingPathComponent("PlantUML", isDirectory: true)
            .appendingPathComponent(runtimeDirectory, isDirectory: true)
            .appendingPathComponent("Contents/Home/bin/java")
    }

    /// 返回随应用分发的 PlantUML JAR（Java 归档程序）位置。
    private func bundledPlantUMLURL() -> URL? {
        return Bundle.main.resourceURL?
            .appendingPathComponent("PlantUML", isDirectory: true)
            .appendingPathComponent("plantuml.jar")
    }
}
