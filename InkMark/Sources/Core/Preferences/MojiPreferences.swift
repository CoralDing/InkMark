/**
 * 文件说明：墨记偏好设置模型，集中管理预览主题、插件开关等用户配置。
 * 作者：Codex
 * 创建时间：2026-06-17
 */

import Foundation

/// MojiPreferences 使用 UserDefaults（macOS 系统偏好存储）保存轻量配置。
/// 这样不依赖旧偏好设置框架，也方便后续扩展成真正的设置窗口。
final class MojiPreferences {
    static let shared = MojiPreferences()

    private enum Key {
        static let markdownStyle = "Moji.MarkdownStyle"
        static let pluginsEnabled = "Moji.PluginsEnabled"
        static let autoLinkBareURLs = "Moji.AutoLinkBareURLs"
        static let editorFontSize = "Moji.EditorFontSize"
        static let previewContentWidth = "Moji.PreviewContentWidth"
        static let disabledPluginIdentifiers = "Moji.DisabledPluginIdentifiers"
        static let createUntitledAtLaunch = "Moji.CreateUntitledAtLaunch"
    }

    private let defaults = UserDefaults.standard

    var markdownStyle: ModernMarkdownStyle {
        get {
            guard let rawValue = defaults.string(forKey: Key.markdownStyle),
                  let style = ModernMarkdownStyle(rawValue: rawValue) else {
                return .github
            }
            return style
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.markdownStyle)
        }
    }

    var pluginsEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.pluginsEnabled) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.pluginsEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.pluginsEnabled)
        }
    }

    var autoLinkBareURLs: Bool {
        get {
            // 默认开启裸 URL（网址）自动链接，符合多数 Markdown 预览工具的阅读习惯。
            guard defaults.object(forKey: Key.autoLinkBareURLs) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.autoLinkBareURLs)
        }
        set {
            defaults.set(newValue, forKey: Key.autoLinkBareURLs)
        }
    }

    var editorFontSize: Double {
        get {
            let storedValue = defaults.double(forKey: Key.editorFontSize)
            return storedValue == 0 ? 15 : min(max(storedValue, 12), 22)
        }
        set {
            defaults.set(min(max(newValue, 12), 22), forKey: Key.editorFontSize)
        }
    }

    var previewContentWidth: Int {
        get {
            let storedValue = defaults.integer(forKey: Key.previewContentWidth)
            return storedValue == 0 ? 900 : min(max(storedValue, 640), 1200)
        }
        set {
            defaults.set(min(max(newValue, 640), 1200), forKey: Key.previewContentWidth)
        }
    }

    /// 控制应用在没有恢复窗口或待打开文件时是否自动创建空白文档。
    /// 默认开启以保证首次启动后立即可写，同时允许偏好无窗口工作流的用户关闭。
    var createUntitledAtLaunch: Bool {
        get {
            guard defaults.object(forKey: Key.createUntitledAtLaunch) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.createUntitledAtLaunch)
        }
        set {
            defaults.set(newValue, forKey: Key.createUntitledAtLaunch)
        }
    }

    /// 保存被用户单独关闭的插件标识。
    /// 使用“默认启用、只记录关闭项”的方式，新安装插件可以立即使用，同时不会覆盖已有选择。
    var disabledPluginIdentifiers: Set<String> {
        get {
            return Set(defaults.stringArray(forKey: Key.disabledPluginIdentifiers) ?? [])
        }
        set {
            defaults.set(Array(newValue).sorted(), forKey: Key.disabledPluginIdentifiers)
        }
    }

    /// 查询单个插件是否启用。
    func isPluginEnabled(identifier: String) -> Bool {
        return !disabledPluginIdentifiers.contains(identifier)
    }

    /// 更新单个插件状态，并保留其他插件原有选择。
    func setPlugin(identifier: String, isEnabled: Bool) {
        var disabledIdentifiers = disabledPluginIdentifiers
        if isEnabled {
            disabledIdentifiers.remove(identifier)
        } else {
            disabledIdentifiers.insert(identifier)
        }
        disabledPluginIdentifiers = disabledIdentifiers
    }

    var renderOptions: MojiMarkdownRenderOptions {
        return MojiMarkdownRenderOptions(
            autoLinkBareURLs: autoLinkBareURLs,
            contentMaxWidth: previewContentWidth
        )
    }
}
