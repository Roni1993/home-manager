#!/usr/bin/env node
/*
 * pi-ui: MODEL-SELECTOR SEAM.
 *
 * `showModelSelector()` builds a private `ModelSelectorComponent` and shows it
 * via `showSelector()`. There is no ExtensionUIContext hook for it, so an
 * extension cannot restyle it. This patch adds an opt-in factory:
 *
 *   ctx.ui.setModelSelector(factory)
 *     factory({ models, current, select, cancel }, tui, theme) -> Component | undefined
 *
 * When a factory is registered and returns a Component, it is used in place of
 * the stock selector (same `showSelector` overlay/focus/key handling). Calling
 * `select(model, persist)` runs the EXISTING selectModel path, so behaviour is
 * preserved. Returning undefined (or throwing) falls back to stock, and with no
 * factory registered the stock code runs verbatim.
 *
 * Targets (unminified dist):
 *   <piStoreRoot>/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js
 *   <piStoreRoot>/lib/node_modules/pi-monorepo/dist/core/extensions/types.d.ts
 *
 * Usage: node pi-patches/model-selector-seam.mjs <piStoreRoot>
 * Idempotent (marker), fail-loud on missing/ambiguous anchors.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MARKER = "pi-ui:model-selector-seam";

const piStoreRoot = process.argv[2];
if (!piStoreRoot) {
  console.error("usage: node model-selector-seam.mjs <piStoreRoot>");
  process.exit(2);
}

const IM = join(piStoreRoot, "lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js");
const TYPES = join(piStoreRoot, "lib/node_modules/pi-monorepo/dist/core/extensions/types.d.ts");
for (const f of [IM, TYPES]) {
  if (!existsSync(f)) {
    console.error(`pi-ui:model-selector-seam: missing file: ${f}`);
    process.exit(1);
  }
}

const im = readFileSync(IM, "utf8");
if (im.includes(MARKER)) {
  console.log(`pi-ui:model-selector-seam: already patched (marker found): ${IM}`);
} else {
  const ANCHOR_SELECTOR =
    "            const selector = new ModelSelectorComponent(this.ui, this.session.model, this.session.modelRuntime, this.session.scopedModels, (model) => selectModel(model, false), () => {";

  const SEAM = [
    `            /* ${MARKER} */`,
    "            // Opt-in extension renderer. The stock path below runs untouched",
    "            // when no factory is registered or it declines for this call.",
    '            if (typeof this.modelSelectorFactory === "function") {',
    "                let seamModels = [];",
    "                try {",
    "                    seamModels = [...this.session.modelRuntime.getAvailableSnapshot()];",
    "                }",
    "                catch {",
    "                    seamModels = [];",
    "                }",
    "                let seamComponent;",
    "                try {",
    "                    seamComponent = this.modelSelectorFactory({",
    "                        models: seamModels,",
    "                        current: this.session.model,",
    "                        select: (model, persist) => selectModel(model, persist === true),",
    "                        cancel: () => {",
    "                            done();",
    "                            this.ui.requestRender();",
    "                        },",
    "                    }, this.ui, undefined);",
    "                }",
    "                catch {",
    "                    seamComponent = undefined;",
    "                }",
    "                if (seamComponent) {",
    "                    return {",
    "                        component: seamComponent,",
    "                        focus: seamComponent,",
    "                        dispose: () => seamComponent.dispose?.(),",
    "                    };",
    "                }",
    "            }",
    `            /* /${MARKER} */`,
  ].join("\n");

  const ANCHOR_SETTER = "    setExtensionHeader(factory) {";
  const SETTER = [
    `    /* ${MARKER} */`,
    "    /**",
    "     * Register (or clear with undefined) a renderer for the model selector",
    "     * opened by /model. Consulted by showModelSelector(); returning a",
    "     * Component replaces the stock selector, undefined / a throw keeps it.",
    "     */",
    "    setModelSelector(factory) {",
    "        this.modelSelectorFactory = factory;",
    "    }",
    `    /* /${MARKER} */`,
    ANCHOR_SETTER,
  ].join("\n");

  const ANCHOR_UICONTEXT = "            setHeader: (factory) => this.setExtensionHeader(factory),";
  const UICONTEXT = [
    ANCHOR_UICONTEXT,
    `            /* ${MARKER} */`,
    "            setModelSelector: (factory) => this.setModelSelector(factory),",
    `            /* /${MARKER} */`,
  ].join("\n");

  const edits = [
    ["showModelSelector seam", ANCHOR_SELECTOR, SEAM + "\n" + ANCHOR_SELECTOR],
    ["setModelSelector accessor", ANCHOR_SETTER, SETTER],
    ["ExtensionUIContext exposure", ANCHOR_UICONTEXT, UICONTEXT],
  ];

  let out = im;
  for (const [name, anchor, replacement] of edits) {
    if (!out.includes(anchor)) {
      console.error(`pi-ui:model-selector-seam: ANCHOR NOT FOUND in ${IM}: ${name}. Pi source changed; aborting.`);
      process.exit(1);
    }
    if (out.split(anchor).length !== 2) {
      console.error(`pi-ui:model-selector-seam: ANCHOR NOT UNIQUE in ${IM}: ${name}. Pi source changed; aborting.`);
      process.exit(1);
    }
    out = out.replace(anchor, replacement);
  }
  writeFileSync(IM, out);
  console.log(`pi-ui:model-selector-seam: patched ${IM} (${edits.length} anchors)`);
}

const dts = readFileSync(TYPES, "utf8");
if (dts.includes(MARKER)) {
  console.log(`pi-ui:model-selector-seam: already patched (marker found): ${TYPES}`);
} else {
  const ANCHOR_TYPES = "    setHeader(factory: ((tui: TUI, theme: Theme) => Component & {";
  const TYPES_BLOCK = [
    `    /* ${MARKER} */`,
    "    /**",
    "     * Render the model selector (/model). Consulted by showModelSelector();",
    "     * return a Component to replace the stock selector, or undefined to keep",
    "     * it. `select(model, persist)` runs the normal selection path.",
    "     */",
    "    setModelSelector(factory?: (data: {",
    "        models: unknown[];",
    "        current: unknown;",
    "        select: (model: unknown, persist?: boolean) => void;",
    "        cancel: () => void;",
    "    }, tui: TUI, theme: Theme) => (Component & {",
    "        dispose?(): void;",
    "    }) | undefined): void;",
    `    /* /${MARKER} */`,
    ANCHOR_TYPES,
  ].join("\n");

  if (!dts.includes(ANCHOR_TYPES)) {
    console.error(`pi-ui:model-selector-seam: ANCHOR NOT FOUND in ${TYPES}. Pi source changed; aborting.`);
    process.exit(1);
  }
  if (dts.split(ANCHOR_TYPES).length !== 2) {
    console.error(`pi-ui:model-selector-seam: ANCHOR NOT UNIQUE in ${TYPES}. Pi source changed; aborting.`);
    process.exit(1);
  }
  writeFileSync(TYPES, dts.replace(ANCHOR_TYPES, TYPES_BLOCK));
  console.log(`pi-ui:model-selector-seam: patched ${TYPES} (1 anchor)`);
}

console.log("pi-ui:model-selector-seam: done");
