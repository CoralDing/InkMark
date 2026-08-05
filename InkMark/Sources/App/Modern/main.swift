/**
 * 文件说明：墨记显式启动入口，在 AppKit 启动循环前安装应用代理和主菜单。
 * 作者：Codex
 * 创建时间：2026-06-18
 */

import AppKit

/// 使用显式 main.swift 可以先设置 NSApplicationDelegate（应用代理）和主菜单，
/// 避免系统只生成默认“应用菜单”而没有“文件/编辑/视图”等菜单。
let application = NSApplication.shared
let appDelegate = MojiAppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
// 显式触发 AppKit 完成启动，然后再安装菜单；这样可以避开 run() 内部创建默认最小菜单覆盖自定义菜单的问题。
application.finishLaunching()
appDelegate.installMainMenu()
application.run()
