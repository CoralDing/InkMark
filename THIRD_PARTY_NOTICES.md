<!--
文件说明：墨记第三方与上游项目声明，记录需要随源码分发的版权信息。
作者：Codex
创建时间：2026-07-29
-->

# 第三方与上游声明

## 当前运行依赖

墨记链接 macOS 系统提供的 Cocoa/AppKit、Foundation 和 WebKit 框架，并随应用打包 Mermaid、KaTeX、PlantUML 与 Temurin JRE。

## Mermaid

Mermaid 用于在本地预览 `mermaid` 代码块，项目地址为 [mermaid-js/mermaid](https://github.com/mermaid-js/mermaid)，按照 MIT License 分发。

```text
Copyright (c) 2014 - 2022 Knut Sveidqvist
```

完整许可文本见 [LICENSES/Mermaid.txt](LICENSES/Mermaid.txt)。

## KaTeX

KaTeX 用于在本地预览 LaTeX 数学公式，项目地址为 [KaTeX/KaTeX](https://github.com/KaTeX/KaTeX)，按照 MIT License 分发。

```text
Copyright (c) 2013-2020 Khan Academy and other contributors
```

完整许可文本见 [LICENSES/KaTeX.txt](LICENSES/KaTeX.txt)。发行版本中的 WOFF2 字体会内嵌到 CSS，公式渲染不请求网络资源。

## PlantUML

PlantUML 1.2025.10 用于在本机把 `plantuml` 和 `puml` 代码块生成为 SVG，项目地址为 [plantuml/plantuml](https://github.com/plantuml/plantuml)，按照 GNU GPL v3 或更高版本分发。

```text
Copyright (c) 2009-2024 Arnaud Roques
```

完整 GNU GPL v3 文本见 [LICENSES/PlantUML.txt](LICENSES/PlantUML.txt)。PlantUML JAR 内还保留其依赖组件的原始许可声明。

## Eclipse Temurin

Eclipse Temurin 17.0.20+8 JRE 为 PlantUML 提供本地 Java 运行环境。墨记同时分发 Apple 芯片与 Intel 版本，按照 GNU GPL v2 with Classpath Exception 分发。

概览见 [LICENSES/Temurin.txt](LICENSES/Temurin.txt)；每套运行时的 `Contents/Home/legal/` 目录和 `NOTICE` 文件均完整保留在应用资源中。

用户自行安装的预览插件不属于墨记发行内容，其作者和分发者负责提供对应许可证与安全说明。
