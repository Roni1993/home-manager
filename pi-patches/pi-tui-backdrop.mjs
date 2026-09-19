#!/usr/bin/env node
/*
 * pi-ui: opt-in DIMMED BACKDROP for pi-tui overlays.
 *
 * Adds an optional numeric `backdrop` factor to OverlayOptions. When set on an
 * overlay (0 = no dim, 1 = black), the base line behind the overlay has its
 * truecolor fg/bg components scaled toward black before the overlay is spliced
 * in. Absent/0 -> byte-identical to stock behaviour.
 *
 * Usage:
 *   node pi-patches/pi-tui-backdrop.mjs <piStoreRoot>
 *
 * Idempotent: a marker comment (`pi-ui:backdrop`) makes a second run a no-op.
 * Exits nonzero with a clear message if an anchor is missing.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const MARKER = "pi-ui:backdrop";

const piStoreRoot = process.argv[2];
if (!piStoreRoot) {
  console.error("usage: node pi-tui-backdrop.mjs <piStoreRoot>");
  process.exit(2);
}

const TUI_DIR = join(
  piStoreRoot,
  "lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-tui/dist",
);
const TUI_JS = join(TUI_DIR, "tui.js");
const TUI_DTS = join(TUI_DIR, "tui.d.ts");

for (const f of [TUI_JS, TUI_DTS]) {
  if (!existsSync(f)) {
    console.error(`pi-ui:backdrop: missing file: ${f}`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// tui.js
// ---------------------------------------------------------------------------
const js = readFileSync(TUI_JS, "utf8");
if (js.includes(MARKER)) {
  console.log(`pi-ui:backdrop: already patched (marker found): ${TUI_JS}`);
} else {
  const ANCHOR_FN = [
    "/** Composite overlay content into a terminal line at a fixed column. */",
    "export function compositeTuiLine(baseLine, overlayLine, startCol, overlayWidth, totalWidth) {",
    "    if (isImageLine(baseLine))",
    "        return baseLine;",
    "    const afterStart = startCol + overlayWidth;",
    "    const base = extractSegments(baseLine, startCol, afterStart, totalWidth - afterStart, true);",
  ].join("\n");

  const REPLACEMENT_FN = `/* ${MARKER} */
/** Scale a terminal line's truecolor fg/bg components toward black by \`factor\` (0..1). */
export function dimBaseLine(line, factor) {
    if (typeof factor !== "number" || !Number.isFinite(factor) || factor <= 0 || factor >= 1 || isImageLine(line))
        return line;
    return line.replace(/\\x1b\\[(38|48);2;(\\d+);(\\d+);(\\d+)m/g, (match, layer, r, g, b) => \`\\x1b[\${layer};2;\${Math.round(Number(r) * factor)};\${Math.round(Number(g) * factor)};\${Math.round(Number(b) * factor)}m\`);
}
/* /${MARKER} */
/** Composite overlay content into a terminal line at a fixed column. */
export function compositeTuiLine(baseLine, overlayLine, startCol, overlayWidth, totalWidth, backdrop) {
    if (isImageLine(baseLine))
        return baseLine;
    const afterStart = startCol + overlayWidth;
    const base = extractSegments(dimBaseLine(baseLine, backdrop), startCol, afterStart, totalWidth - afterStart, true);`;

  const ANCHOR_LOOP = [
    "        for (const { overlayLines, row, col, w } of rendered) {",
    "            for (let i = 0; i < overlayLines.length; i++) {",
    "                const idx = viewportStart + row + i;",
    "                if (idx >= 0 && idx < result.length) {",
    "                    // Defensive: truncate overlay line to declared width before compositing",
    "                    // (components should already respect width, but this ensures it)",
    "                    const truncatedOverlayLine = visibleWidth(overlayLines[i]) > w ? sliceByColumn(overlayLines[i], 0, w, true) : overlayLines[i];",
    "                    result[idx] = this.compositeLineAt(result[idx], truncatedOverlayLine, col, w, termWidth);",
    "                }",
    "            }",
    "        }",
  ].join("\n");

  const REPLACEMENT_LOOP = [
    `        /* ${MARKER} */`,
    "        // First visible overlay that opts in wins; options are forwarded verbatim from ctx.ui.custom().",
    "        const backdrop = rendered.find((r) => typeof r.entry.options?.backdrop === \"number\")?.entry.options.backdrop;",
    `        /* /${MARKER} */`,
    "        for (const { overlayLines, row, col, w } of rendered) {",
    "            for (let i = 0; i < overlayLines.length; i++) {",
    "                const idx = viewportStart + row + i;",
    "                if (idx >= 0 && idx < result.length) {",
    "                    // Defensive: truncate overlay line to declared width before compositing",
    "                    // (components should already respect width, but this ensures it)",
    "                    const truncatedOverlayLine = visibleWidth(overlayLines[i]) > w ? sliceByColumn(overlayLines[i], 0, w, true) : overlayLines[i];",
    "                    result[idx] = this.compositeLineAt(result[idx], truncatedOverlayLine, col, w, termWidth, backdrop);",
    "                }",
    "            }",
    "        }",
  ].join("\n");

  const ANCHOR_METHOD = [
    "    compositeLineAt(baseLine, overlayLine, startCol, overlayWidth, totalWidth) {",
    "        return compositeTuiLine(baseLine, overlayLine, startCol, overlayWidth, totalWidth);",
    "    }",
  ].join("\n");

  const REPLACEMENT_METHOD = [
    "    compositeLineAt(baseLine, overlayLine, startCol, overlayWidth, totalWidth, backdrop) {",
    "        return compositeTuiLine(baseLine, overlayLine, startCol, overlayWidth, totalWidth, backdrop);",
    "    }",
  ].join("\n");

  const edits = [
    ["compositeTuiLine definition", ANCHOR_FN, REPLACEMENT_FN],
    ["compositeOverlays splice call", ANCHOR_LOOP, REPLACEMENT_LOOP],
    ["compositeLineAt method", ANCHOR_METHOD, REPLACEMENT_METHOD],
  ];

  let out = js;
  for (const [name, anchor, replacement] of edits) {
    if (!out.includes(anchor)) {
      console.error(`pi-ui:backdrop: ANCHOR NOT FOUND in ${TUI_JS}: ${name}. Pi-tui source changed; aborting.`);
      process.exit(1);
    }
    if (out.split(anchor).length !== 2) {
      console.error(`pi-ui:backdrop: ANCHOR NOT UNIQUE in ${TUI_JS}: ${name}. Pi-tui source changed; aborting.`);
      process.exit(1);
    }
    out = out.replace(anchor, replacement);
  }
  writeFileSync(TUI_JS, out);
  console.log(`pi-ui:backdrop: patched ${TUI_JS} (${edits.length} anchors)`);
}

// ---------------------------------------------------------------------------
// tui.d.ts
// ---------------------------------------------------------------------------
const dts = readFileSync(TUI_DTS, "utf8");
if (dts.includes(MARKER)) {
  console.log(`pi-ui:backdrop: already patched (marker found): ${TUI_DTS}`);
} else {
  const ANCHOR_OPTIONS = [
    "    /** If true, don't capture keyboard focus when shown */",
    "    nonCapturing?: boolean;",
    "}",
  ].join("\n");
  const REPLACEMENT_OPTIONS = [
    "    /** If true, don't capture keyboard focus when shown */",
    "    nonCapturing?: boolean;",
    `    /* ${MARKER} Optional dim factor for the base line behind this overlay (0 = no dim, 1 = black). */`,
    "    backdrop?: number;",
    `    /* /${MARKER} */`,
    "}",
  ].join("\n");

  const ANCHOR_DECL =
    "export declare function compositeTuiLine(baseLine: string, overlayLine: string, startCol: number, overlayWidth: number, totalWidth: number): string;";
  const REPLACEMENT_DECL =
    "export declare function compositeTuiLine(baseLine: string, overlayLine: string, startCol: number, overlayWidth: number, totalWidth: number, backdrop?: number): string;";

  const edits = [
    ["OverlayOptions interface", ANCHOR_OPTIONS, REPLACEMENT_OPTIONS],
    ["compositeTuiLine declaration", ANCHOR_DECL, REPLACEMENT_DECL],
  ];

  let out = dts;
  for (const [name, anchor, replacement] of edits) {
    if (!out.includes(anchor)) {
      console.error(`pi-ui:backdrop: ANCHOR NOT FOUND in ${TUI_DTS}: ${name}. Pi-tui source changed; aborting.`);
      process.exit(1);
    }
    if (out.split(anchor).length !== 2) {
      console.error(`pi-ui:backdrop: ANCHOR NOT UNIQUE in ${TUI_DTS}: ${name}. Pi-tui source changed; aborting.`);
      process.exit(1);
    }
    out = out.replace(anchor, replacement);
  }
  writeFileSync(TUI_DTS, out);
  console.log(`pi-ui:backdrop: patched ${TUI_DTS} (${edits.length} anchors)`);
}

console.log("pi-ui:backdrop: done");
