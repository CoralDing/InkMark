/**
 * 文件说明：墨记阅读时间示例插件，在预览顶部展示字数与预计阅读时长。
 * 作者：Codex
 * 创建时间：2026-07-29
 */

(() => {
  "use strict";

  // 每次编辑都会重载预览；标记用于防止同一次页面生命周期内重复插入组件。
  if (document.documentElement.dataset.mojiReadingTime === "ready") return;
  document.documentElement.dataset.mojiReadingTime = "ready";

  const content = document.body.innerText.trim();
  if (!content) return;

  // 中文按单字、英文按单词统计，并分别使用更接近实际阅读习惯的速度估算时长。
  const chineseCharacters = (content.match(/[\u3400-\u9fff]/g) || []).length;
  const latinContent = content.replace(/[\u3400-\u9fff]/g, " ");
  const latinWords = latinContent.match(/[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*/g) || [];
  const readingMinutes = Math.max(1, Math.ceil(chineseCharacters / 300 + latinWords.length / 200));
  const totalCount = chineseCharacters + latinWords.length;

  const summary = document.createElement("p");
  summary.className = "moji-reading-time";
  summary.setAttribute("role", "status");
  summary.setAttribute("aria-label", `约 ${totalCount} 字，预计阅读 ${readingMinutes} 分钟`);
  summary.textContent = `${totalCount} 字 · 约 ${readingMinutes} 分钟阅读`;

  const firstHeading = document.querySelector("h1, h2, h3");
  if (firstHeading) {
    firstHeading.insertAdjacentElement("afterend", summary);
  } else {
    document.body.prepend(summary);
  }

  const style = document.createElement("style");
  style.textContent = `
    .moji-reading-time {
      margin: -0.35rem 0 1.5rem;
      color: var(--muted);
      font-size: 0.8125rem;
      line-height: 1.5;
    }
  `;
  document.head.appendChild(style);
})();
