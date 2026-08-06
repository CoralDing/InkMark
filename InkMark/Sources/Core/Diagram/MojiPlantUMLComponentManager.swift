/**
 * 文件说明：管理按需下载的 PlantUML 本地渲染组件，避免 Java 运行时增加默认安装包体积。
 * 作者：dingyi60(Codex)
 * 创建时间：2026-08-06
 */

import CryptoKit
import Foundation

/// MojiPlantUMLComponentError 为下载、导入和校验失败提供清晰的本地化错误信息。
enum MojiPlantUMLComponentError: LocalizedError {
    case unsupportedArchitecture
    case componentUnavailable
    case installationInProgress
    case downloadFailed(String)
    case invalidChecksum
    case invalidArchive
    case invalidComponent
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            return "当前 Mac 架构暂不支持 PlantUML 本地组件。"
        case .componentUnavailable:
            return "PlantUML 本地组件尚未安装。"
        case .installationInProgress:
            return "PlantUML 组件正在处理，请稍候。"
        case .downloadFailed(let message):
            return message.isEmpty ? "无法下载 PlantUML 组件，请检查网络后重试。" : "无法下载 PlantUML 组件：\(message)"
        case .invalidChecksum:
            return "下载的 PlantUML 组件校验失败，已取消安装。"
        case .invalidArchive:
            return "所选文件不是可用的 PlantUML 组件压缩包。"
        case .invalidComponent:
            return "PlantUML 组件缺少与当前 Mac 匹配的 Java 运行时或程序文件。"
        case .installationFailed(let message):
            return message.isEmpty ? "PlantUML 组件安装失败。" : "PlantUML 组件安装失败：\(message)"
        }
    }
}

/// MojiPlantUMLInstalledComponent 描述本机已完成校验的组件，供设置页展示位置和占用空间。
struct MojiPlantUMLInstalledComponent {
    let directoryURL: URL
    let byteCount: Int64

    /// 使用系统单位格式化组件体积，避免设置页在不同语言环境下显示生硬的字节数。
    var formattedSize: String {
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

/// MojiPlantUMLComponentManager 将大型 PlantUML JAR（Java 归档程序）与 Java 运行时安装到用户目录。
/// 默认应用包只保留轻量预览能力，用户实际使用 UML 时才下载当前 CPU 架构对应的本地组件。
final class MojiPlantUMLComponentManager {
    static let shared = MojiPlantUMLComponentManager()
    static let didChangeNotification = Notification.Name("io.github.dingyi60.moji.plantumlComponentDidChange")

    /// ComponentURLs 只在组件完整且与当前进程架构匹配时返回，渲染器不需要了解磁盘目录细节。
    struct ComponentURLs {
        let javaURL: URL
        let jarURL: URL
    }

    private let fileManager = FileManager.default
    private let installationQueue = DispatchQueue(label: "io.github.dingyi60.moji.plantumlComponent", qos: .userInitiated)
    private let stateLock = NSLock()
    private var installationInProgress = false

    private init() {}

    /// 当前架构组件的稳定 Release（发行版）附件名称。
    private var archiveFileName: String? {
        guard let architecture = currentArchitecture else { return nil }
        return "InkMark-PlantUML-\(architecture).zip"
    }

    /// 组件固定安装在应用支持目录，既不会污染应用包，也不会占用用户的下载文件夹。
    var componentDirectory: URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return applicationSupportURL
            .appendingPathComponent("InkMark", isDirectory: true)
            .appendingPathComponent("PlantUML", isDirectory: true)
    }

    /// 用于“打开组件目录”按钮；只创建父目录，不会误创建一个看似已安装的空 PlantUML 目录。
    var componentContainerDirectory: URL {
        return componentDirectory.deletingLastPathComponent()
    }

    /// 设置页通过此状态禁用重复点击，避免两个解压进程同时替换同一组件。
    var isInstalling: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return installationInProgress
    }

    /// 返回当前架构可执行的 Java 与 PlantUML JAR 路径；缺任一文件时视为未安装。
    func componentURLs() -> ComponentURLs? {
        return validComponentURLs(in: componentDirectory)
    }

    /// 读取已安装组件的状态和实际磁盘占用，供设置窗口即时展示。
    func installedComponent() -> MojiPlantUMLInstalledComponent? {
        guard componentURLs() != nil else { return nil }
        return MojiPlantUMLInstalledComponent(
            directoryURL: componentDirectory,
            byteCount: directorySize(at: componentDirectory)
        )
    }

    /// 从 GitHub 最新 Release 下载当前架构组件，并在 SHA-256（文件完整性摘要）校验通过后安装。
    func installLatest(completion: @escaping (Result<MojiPlantUMLInstalledComponent, Error>) -> Void) {
        guard let archiveFileName else {
            completeInstallation(.failure(MojiPlantUMLComponentError.unsupportedArchitecture), completion: completion)
            return
        }
        guard beginInstallation() else {
            completeOnMain(.failure(MojiPlantUMLComponentError.installationInProgress), completion: completion)
            return
        }

        postComponentChange()
        let archiveURL = URL(string: "https://github.com/CoralDing/InkMark/releases/latest/download/\(archiveFileName)")!
        let checksumURL = archiveURL.appendingPathExtension("sha256")
        let downloadTask = URLSession.shared.downloadTask(with: archiveURL) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            guard error == nil,
                  let temporaryURL,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusText = (response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" } ?? error?.localizedDescription ?? ""
                self.completeInstallation(
                    .failure(MojiPlantUMLComponentError.downloadFailed(statusText)),
                    completion: completion
                )
                return
            }

            // URLSession 的临时文件会在回调结束后回收，先复制到自己的临时路径再异步解压。
            let localArchiveURL = self.fileManager.temporaryDirectory
                .appendingPathComponent("moji-plantuml-download-\(UUID().uuidString).zip")
            do {
                try self.fileManager.copyItem(at: temporaryURL, to: localArchiveURL)
            } catch {
                self.completeInstallation(.failure(error), completion: completion)
                return
            }

            self.installationQueue.async {
                defer { try? self.fileManager.removeItem(at: localArchiveURL) }
                do {
                    let checksumData = try Data(contentsOf: checksumURL)
                    try self.verifyChecksum(of: localArchiveURL, expectedChecksumData: checksumData)
                    try self.installArchiveSynchronously(from: localArchiveURL)
                    guard let component = self.installedComponent() else {
                        throw MojiPlantUMLComponentError.invalidComponent
                    }
                    self.completeInstallation(.success(component), completion: completion)
                } catch {
                    self.completeInstallation(.failure(error), completion: completion)
                }
            }
        }
        downloadTask.resume()
    }

    /// 从用户已下载的 ZIP（压缩包）安装组件，适合离线分发或网络受限环境。
    func install(fromArchive archiveURL: URL, completion: @escaping (Result<MojiPlantUMLInstalledComponent, Error>) -> Void) {
        guard beginInstallation() else {
            completeOnMain(.failure(MojiPlantUMLComponentError.installationInProgress), completion: completion)
            return
        }

        postComponentChange()
        installationQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.installArchiveSynchronously(from: archiveURL)
                guard let component = self.installedComponent() else {
                    throw MojiPlantUMLComponentError.invalidComponent
                }
                self.completeInstallation(.success(component), completion: completion)
            } catch {
                self.completeInstallation(.failure(error), completion: completion)
            }
        }
    }

    /// 从已解压的组件目录安装，便于开发测试或用户保留离线组件目录。
    func install(fromDirectory directoryURL: URL, completion: @escaping (Result<MojiPlantUMLInstalledComponent, Error>) -> Void) {
        guard beginInstallation() else {
            completeOnMain(.failure(MojiPlantUMLComponentError.installationInProgress), completion: completion)
            return
        }

        postComponentChange()
        installationQueue.async { [weak self] in
            guard let self else { return }
            do {
                let sourceDirectory = try self.findComponentDirectory(in: directoryURL)
                try self.replaceInstalledComponent(with: sourceDirectory)
                guard let component = self.installedComponent() else {
                    throw MojiPlantUMLComponentError.invalidComponent
                }
                self.completeInstallation(.success(component), completion: completion)
            } catch {
                self.completeInstallation(.failure(error), completion: completion)
            }
        }
    }

    /// 移除本地组件后，默认应用仍可继续编辑和预览其他 Markdown 内容。
    func removeInstalledComponent() throws {
        guard !isInstalling else {
            throw MojiPlantUMLComponentError.installationInProgress
        }
        guard fileManager.fileExists(atPath: componentDirectory.path) else { return }
        try fileManager.removeItem(at: componentDirectory)
        postComponentChange()
    }

    /// 根据当前编译架构选择 Release 中的独立组件，不让通用应用同时下载两份 Java 运行时。
    private var currentArchitecture: String? {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return nil
        #endif
    }

    /// 检查组件目录是否完整，并返回渲染进程直接需要的两个入口文件。
    private func validComponentURLs(in directoryURL: URL, requiresExecutable: Bool = true) -> ComponentURLs? {
        guard let architecture = currentArchitecture else { return nil }
        let javaURL = directoryURL
            .appendingPathComponent("runtime-\(architecture)", isDirectory: true)
            .appendingPathComponent("Contents/Home/bin/java")
        let jarURL = directoryURL.appendingPathComponent("plantuml.jar")
        guard fileManager.fileExists(atPath: javaURL.path),
              fileManager.fileExists(atPath: jarURL.path),
              !requiresExecutable || fileManager.isExecutableFile(atPath: javaURL.path) else {
            return nil
        }
        return ComponentURLs(javaURL: javaURL, jarURL: jarURL)
    }

    /// 在线组件校验文件只接受标准 SHA-256 十六进制摘要，避免错误页面被误当作组件安装。
    private func verifyChecksum(of archiveURL: URL, expectedChecksumData: Data) throws {
        guard let expectedContents = String(data: expectedChecksumData, encoding: .utf8),
              let expectedHash = expectedContents
                .split(whereSeparator: { $0.isWhitespace })
                .first?
                .lowercased(),
              expectedHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw MojiPlantUMLComponentError.invalidChecksum
        }
        let archiveData = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        let actualHash = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualHash == expectedHash else {
            throw MojiPlantUMLComponentError.invalidChecksum
        }
    }

    /// 使用系统 ditto（文件复制与归档工具）解压 ZIP，保持 Java 运行时中的符号链接结构。
    private func installArchiveSynchronously(from archiveURL: URL) throws {
        guard archiveURL.pathExtension.lowercased() == "zip" else {
            throw MojiPlantUMLComponentError.invalidArchive
        }
        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("moji-plantuml-expand-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, stagingRoot.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw MojiPlantUMLComponentError.installationFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            throw MojiPlantUMLComponentError.invalidArchive
        }

        let sourceDirectory = try findComponentDirectory(in: stagingRoot)
        try replaceInstalledComponent(with: sourceDirectory)
    }

    /// Release ZIP 的根目录为 PlantUML；为手动导入兼容直接选中该目录的情况。
    private func findComponentDirectory(in rootURL: URL) throws -> URL {
        let namedDirectory = rootURL.appendingPathComponent("PlantUML", isDirectory: true)
        if validComponentURLs(in: namedDirectory, requiresExecutable: false) != nil {
            return namedDirectory
        }
        if validComponentURLs(in: rootURL, requiresExecutable: false) != nil {
            return rootURL
        }
        throw MojiPlantUMLComponentError.invalidComponent
    }

    /// 用临时目录替换旧组件，安装中断时保留旧版本，避免用户进入不可渲染的半安装状态。
    private func replaceInstalledComponent(with sourceDirectory: URL) throws {
        guard validComponentURLs(in: sourceDirectory, requiresExecutable: false) != nil else {
            throw MojiPlantUMLComponentError.invalidComponent
        }
        let containerURL = componentContainerDirectory
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)

        let replacementURL = containerURL.appendingPathComponent(".PlantUML-replacement-\(UUID().uuidString)", isDirectory: true)
        let backupURL = containerURL.appendingPathComponent(".PlantUML-backup-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: replacementURL)
            try? fileManager.removeItem(at: backupURL)
        }

        try fileManager.copyItem(at: sourceDirectory, to: replacementURL)
        guard let copiedURLs = validComponentURLs(in: replacementURL, requiresExecutable: false) else {
            throw MojiPlantUMLComponentError.invalidComponent
        }
        // GitHub Artifact（构建产物）不会可靠保留 Unix 可执行权限，安装时统一恢复 Java 启动权限。
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copiedURLs.javaURL.path)

        let hadExistingComponent = fileManager.fileExists(atPath: componentDirectory.path)
        if hadExistingComponent {
            try fileManager.moveItem(at: componentDirectory, to: backupURL)
        }
        do {
            try fileManager.moveItem(at: replacementURL, to: componentDirectory)
        } catch {
            if hadExistingComponent, fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: componentDirectory)
            }
            throw MojiPlantUMLComponentError.installationFailed(error.localizedDescription)
        }
    }

    /// 递归统计普通文件大小，目录和符号链接本身不计入，避免展示误导性的磁盘占用。
    private func directorySize(at directoryURL: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }

    /// 开始安装前锁住状态，确保在线下载、ZIP 导入和目录导入互斥。
    private func beginInstallation() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !installationInProgress else { return false }
        installationInProgress = true
        return true
    }

    /// 结束安装时先释放状态锁，再在主线程更新设置页和预览窗口。
    private func completeInstallation(
        _ result: Result<MojiPlantUMLInstalledComponent, Error>,
        completion: @escaping (Result<MojiPlantUMLInstalledComponent, Error>) -> Void
    ) {
        stateLock.lock()
        installationInProgress = false
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.postComponentChange()
            completion(result)
        }
    }

    /// 未进入安装流程的快速失败也必须回到主线程，保证 AppKit（macOS 原生界面框架）调用安全。
    private func completeOnMain(
        _ result: Result<MojiPlantUMLInstalledComponent, Error>,
        completion: @escaping (Result<MojiPlantUMLInstalledComponent, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }

    /// 状态通知总在主线程发出，使设置页面可直接重建布局而无需额外线程切换。
    private func postComponentChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }
}
