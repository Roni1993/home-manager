#!/usr/bin/env node
/*
 * pi-ui: SELECTOR-OVERLAY SEAM.
 *
 * pi's `showSelector()` renders every selector (settings, model, scoped-models,
 * session, tree, user-message, theme, thinking, show-images, login/OAuth/trust)
 * into `editorContainer` — the bottom editor slot, NOT a centred overlay. That
 * is why the restyled model modal still appears off-centre and why selectors
 * cannot dim the transcript.
 *
 * This patch reroutes `showSelector()` through the real overlay path
 * (`ui.showOverlay(component, { anchor:"center", …, backdrop })`) so EVERY
 * selector becomes a centred, dimmed modal in one edit. `done()` hides the
 * overlay and restores focus to the editor; the editor is no longer removed
 * from its slot. Behaviour is otherwise unchanged, and the anchor/width/backdrop
 * are plain constants here so they are easy to tune.
 *
 * Target: <piStoreRoot>/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js
 * Usage:  node pi-patches/selector-overlay-seam.mjs <piStoreRoot>
 * Idempotent (marker), fail-loud on missing/ambiguous anchors.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MARKER = "pi-ui:selector-overlay-seam";

const piStoreRoot = process.argv[2];
if (!piStoreRoot) {
  console.error("usage: node selector-overlay-seam.mjs <piStoreRoot>");
  process.exit(2);
}

const IM = join(piStoreRoot, "lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js");
if (!existsSync(IM)) {
  console.error(`pi-ui:selector-overlay-seam: missing file: ${IM}`);
  process.exit(1);
}

const im = readFileSync(IM, "utf8");
if (im.includes(MARKER)) {
  console.log(`pi-ui:selector-overlay-seam: already patched (marker found): ${IM}`);
  console.log("pi-ui:selector-overlay-seam: done");
  process.exit(0);
}

// 1. done(): hide the overlay instead of restoring the editor into its slot.
const ANCHOR_DONE = [
  "            if (this.activeSelectorToken !== token)",
  "                return;",
  "            this.activeSelectorToken = undefined;",
  "            this.activeSelectorDispose = undefined;",
  "            this.editorContainer.clear();",
  "            this.editorContainer.addChild(this.editor);",
  "            this.ui.setFocus(this.editor);",
  "        };",
].join("\n");

const REPLACEMENT_DONE = [
  "            if (this.activeSelectorToken !== token)",
  "                return;",
  "            this.activeSelectorToken = undefined;",
  "            this.activeSelectorDispose = undefined;",
  `            /* ${MARKER} */`,
  "            // The selector was shown as an overlay, so the editor was never",
  "            // removed from its slot — just hide the overlay and refocus it.",
  "            this.ui.hideOverlay();",
  `            /* /${MARKER} */`,
  "            this.ui.setFocus(this.editor);",
  "            this.ui.requestRender();",
  "        };",
].join("\n");

// 2. Show: overlay (centred, dimmed) instead of the editor slot.
const ANCHOR_SHOW = [
  "        const created = create(done);",
  "        dispose = created.dispose;",
  "        this.disposeActiveSelector();",
  "        this.activeSelectorToken = token;",
  "        this.activeSelectorDispose = dispose;",
  "        this.editorContainer.clear();",
  "        this.editorContainer.addChild(created.component);",
  "        this.ui.setFocus(created.focus);",
  "        this.ui.requestRender();",
  "    }",
].join("\n");

const REPLACEMENT_SHOW = [
  "        const created = create(done);",
  "        dispose = created.dispose;",
  "        this.disposeActiveSelector();",
  "        this.activeSelectorToken = token;",
  "        this.activeSelectorDispose = dispose;",
  `        /* ${MARKER} */`,
  "        // Centred, dimmed modal instead of the editor slot. Tune here.",
  "        this.ui.showOverlay(created.component, {",
  '            anchor: "center",',
  '            width: "80%",',
  '            maxHeight: "85%",',
  "            backdrop: 0.5,",
  "        });",
  "        this.ui.setFocus(created.focus);",
  "        this.ui.requestRender();",
  `        /* /${MARKER} */`,
  "    }",
].join("\n");

const edits = [
  ["showSelector done()", ANCHOR_DONE, REPLACEMENT_DONE],
  ["showSelector show", ANCHOR_SHOW, REPLACEMENT_SHOW],
];

let out = im;
for (const [name, anchor, replacement] of edits) {
  if (!out.includes(anchor)) {
    console.error(`pi-ui:selector-overlay-seam: ANCHOR NOT FOUND in ${IM}: ${name}. Pi source changed; aborting.`);
    process.exit(1);
  }
  if (out.split(anchor).length !== 2) {
    console.error(`pi-ui:selector-overlay-seam: ANCHOR NOT UNIQUE in ${IM}: ${name}. Pi source changed; aborting.`);
    process.exit(1);
  }
  out = out.replace(anchor, replacement);
}
writeFileSync(IM, out);
console.log(`pi-ui:selector-overlay-seam: patched ${IM} (${edits.length} anchors)`);
console.log("pi-ui:selector-overlay-seam: done");
