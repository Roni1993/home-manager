#!/usr/bin/env node
/*
 * pi-ui: opt-in DIMMED BACKDROP for pi-tui overlays.
 *
 * Adds an optional numeric `backdrop` factor to OverlayOptions. When any visible
 * overlay opts in (0 = no dim, 1 = black), every base/transcript line is scaled
 * toward black once, then the overlays are spliced on top. The opaque overlay
 * covers its own rectangle; the rows above, below and beside it show the dimmed
 * transcript, which is the conventional modal backdrop. Absent -> byte-identical
 * to stock behaviour.
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
  const ANCHOR_FN = "/** Composite overlay content into a terminal line at a fixed column. */";

  const REPLACEMENT_FN = `/* ${MARKER} */
/** Scale a terminal line's truecolor fg/bg components toward black by \`factor\` (0..1). */
function dimBaseLine(line, factor) {
    if (typeof factor !== "number" || !Number.isFinite(factor) || factor <= 0 || factor >= 1 || isImageLine(line))
        return line;
    return line.replace(/\\x1b\\[(38|48);2;(\\d+);(\\d+);(\\d+)m/g, (match, layer, r, g, b) => \`\\x1b[\${layer};2;\${Math.round(Number(r) * factor)};\${Math.round(Number(g) * factor)};\${Math.round(Number(b) * factor)}m\`);
}
/* /${MARKER} */
${ANCHOR_FN}`;

  const ANCHOR_LOOP = [
    "        // Composite each overlay",
    "        for (const { overlayLines, row, col, w } of rendered) {",
  ].join("\n");

  const REPLACEMENT_LOOP = [
    `        /* ${MARKER} */`,
    "        // Opt-in dim backdrop: the first visible overlay with a numeric",
    "        // options.backdrop wins. Dim the whole base buffer once, then splice",
    "        // overlays on top, so rows outside the overlay stay dimmed.",
    "        const backdrop = rendered.find((r) => typeof r.entry.options?.backdrop === \"number\")?.entry.options.backdrop;",
    "        if (typeof backdrop === \"number\") {",
    "            for (let i = 0; i < result.length; i++)",
    "                result[i] = dimBaseLine(result[i], backdrop);",
    "        }",
    `        /* /${MARKER} */`,
    "        // Composite each overlay",
    "        for (const { overlayLines, row, col, w } of rendered) {",
  ].join("\n");

  const edits = [
    ["compositeTuiLine helper insert", ANCHOR_FN, REPLACEMENT_FN],
    ["compositeOverlays dim-backdrop", ANCHOR_LOOP, REPLACEMENT_LOOP],
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
    `    /* ${MARKER} Optional dim factor for the base transcript behind overlays (0 = no dim, 1 = black, exclusive). */`,
    "    backdrop?: number;",
    `    /* /${MARKER} */`,
    "}",
  ].join("\n");

  const edits = [["OverlayOptions interface", ANCHOR_OPTIONS, REPLACEMENT_OPTIONS]];

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
