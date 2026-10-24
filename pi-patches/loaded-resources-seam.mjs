#!/usr/bin/env node
/*
 * pi-ui: LOADED-RESOURCES SEAM for the startup resource block.
 *
 * `pi` renders a small "[Context] / [Skills] / [Prompts] / [Extensions] /
 * [Themes]" block above the transcript at startup. There is no
 * ExtensionUIContext hook for it: `setHeader` styles the logo/banner, a
 * different container. This patch adds one opt-in per-section renderer so an
 * extension can style those sections.
 *
 * Seam: `ctx.ui.setLoadedResources(factory)` where
 *   factory(section, tui, theme) -> Component | undefined
 *   section = { name, header, collapsedBody, expandedBody, color, expanded }
 * The factory is consulted once per section inside `addLoadedSection` (the
 * single chokepoint all five named sections route through). Returning a
 * Component replaces that section; returning undefined (or throwing) keeps the
 * stock ExpandableText for that section. With no factory registered the stock
 * code runs verbatim, so default behaviour is byte-identical.
 *
 * The seam is added at the unminified dist tree:
 *   <piStoreRoot>/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js
 * and the public type at:
 *   <piStoreRoot>/lib/node_modules/pi-monorepo/dist/core/extensions/types.d.ts
 *
 * Usage:
 *   node pi-patches/loaded-resources-seam.mjs <piStoreRoot>
 *
 * Idempotent: a marker comment (`pi-ui:loaded-resources-seam`) makes a second
 * run a no-op. Exits nonzero with a clear message if any anchor is missing or
 * not unique, so a future pi bump fails loudly.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MARKER = "pi-ui:loaded-resources-seam";

const piStoreRoot = process.argv[2];
if (!piStoreRoot) {
  console.error("usage: node loaded-resources-seam.mjs <piStoreRoot>");
  process.exit(2);
}

const IM = join(
  piStoreRoot,
  "lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js",
);
const TYPES = join(
  piStoreRoot,
  "lib/node_modules/pi-monorepo/dist/core/extensions/types.d.ts",
);

for (const f of [IM, TYPES]) {
  if (!existsSync(f)) {
    console.error(`pi-ui:loaded-resources-seam: missing file: ${f}`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// interactive-mode.js
// ---------------------------------------------------------------------------
const im = readFileSync(IM, "utf8");
if (im.includes(MARKER)) {
  console.log(`pi-ui:loaded-resources-seam: already patched (marker found): ${IM}`);
} else {
  // 1. Per-section interception inside showLoadedResources' addLoadedSection.
  const ANCHOR_SECTION = [
    '        const addLoadedSection = (name, collapsedBody, expandedBody = collapsedBody, color = "mdHeading") => {',
    '            const section = new ExpandableText(() => `${sectionHeader(name, color)}\\n${collapsedBody}`, () => `${sectionHeader(name, color)}\\n${expandedBody}`, this.getStartupExpansionState(), 0, 0);',
    "            this.loadedResourcesContainer.addChild(section);",
    "            this.loadedResourcesContainer.addChild(new Spacer(1));",
    "        };",
  ].join("\n");

  const REPLACEMENT_SECTION = [
    '        const addLoadedSection = (name, collapsedBody, expandedBody = collapsedBody, color = "mdHeading") => {',
    `            /* ${MARKER} */`,
    "            // Opt-in extension renderer for this section. The stock path",
    "            // below runs untouched when no factory is registered or it",
    "            // declines (undefined / throw) for this section.",
    "            if (typeof this.loadedResourcesFactory === \"function\") {",
    "                let seamSection;",
    "                try {",
    "                    seamSection = this.loadedResourcesFactory({",
    "                        name,",
    "                        header: sectionHeader(name, color),",
    "                        collapsedBody,",
    "                        expandedBody,",
    "                        color,",
    "                        expanded: this.getStartupExpansionState(),",
    "                    }, this.ui, theme);",
    "                }",
    "                catch {",
    "                    seamSection = undefined;",
    "                }",
    "                if (seamSection) {",
    "                    this.loadedResourcesContainer.addChild(seamSection);",
    "                    this.loadedResourcesContainer.addChild(new Spacer(1));",
    "                    return;",
    "                }",
    "            }",
    `            /* /${MARKER} */`,
    '            const section = new ExpandableText(() => `${sectionHeader(name, color)}\\n${collapsedBody}`, () => `${sectionHeader(name, color)}\\n${expandedBody}`, this.getStartupExpansionState(), 0, 0);',
    "            this.loadedResourcesContainer.addChild(section);",
    "            this.loadedResourcesContainer.addChild(new Spacer(1));",
    "        };",
  ].join("\n");

  // 2. Accessor method, inserted before setExtensionHeader.
  const ANCHOR_SETTER = "    setExtensionHeader(factory) {";
  const REPLACEMENT_SETTER = [
    `    /* ${MARKER} */`,
    "    /**",
    "     * Register (or clear with undefined) a per-section renderer for the",
    "     * startup loaded-resources block ([Context], [Skills], [Prompts],",
    "     * [Extensions], [Themes]). The factory is consulted by addLoadedSection",
    "     * in showLoadedResources(); returning a Component replaces that section,",
    "     * undefined / a throw keeps the stock ExpandableText. Extensions should",
    "     * call this during activation, before the startup block is first drawn.",
    "     */",
    "    setLoadedResources(factory) {",
    "        this.loadedResourcesFactory = factory;",
    "        this.ui?.requestRender?.();",
    "    }",
    `    /* /${MARKER} */`,
    ANCHOR_SETTER,
  ].join("\n");

  // 3. Expose the accessor on the extension UI context.
  const ANCHOR_UICONTEXT = "            setHeader: (factory) => this.setExtensionHeader(factory),";
  const REPLACEMENT_UICONTEXT = [
    ANCHOR_UICONTEXT,
    `            /* ${MARKER} */`,
    "            setLoadedResources: (factory) => this.setLoadedResources(factory),",
    `            /* /${MARKER} */`,
  ].join("\n");

  const edits = [
    ["showLoadedResources addLoadedSection", ANCHOR_SECTION, REPLACEMENT_SECTION],
    ["setLoadedResources accessor", ANCHOR_SETTER, REPLACEMENT_SETTER],
    ["ExtensionUIContext exposure", ANCHOR_UICONTEXT, REPLACEMENT_UICONTEXT],
  ];

  let out = im;
  for (const [name, anchor, replacement] of edits) {
    if (!out.includes(anchor)) {
      console.error(
        `pi-ui:loaded-resources-seam: ANCHOR NOT FOUND in ${IM}: ${name}. Pi source changed; aborting.`,
      );
      process.exit(1);
    }
    if (out.split(anchor).length !== 2) {
      console.error(
        `pi-ui:loaded-resources-seam: ANCHOR NOT UNIQUE in ${IM}: ${name}. Pi source changed; aborting.`,
      );
      process.exit(1);
    }
    out = out.replace(anchor, replacement);
  }
  writeFileSync(IM, out);
  console.log(`pi-ui:loaded-resources-seam: patched ${IM} (${edits.length} anchors)`);
}

// ---------------------------------------------------------------------------
// types.d.ts
// ---------------------------------------------------------------------------
const dts = readFileSync(TYPES, "utf8");
if (dts.includes(MARKER)) {
  console.log(`pi-ui:loaded-resources-seam: already patched (marker found): ${TYPES}`);
} else {
  const ANCHOR_TYPES = [
    "    setHeader(factory: ((tui: TUI, theme: Theme) => Component & {",
    "        dispose?(): void;",
    "    }) | undefined): void;",
  ].join("\n");

  const REPLACEMENT_TYPES = [
    ANCHOR_TYPES,
    `    /* ${MARKER} */`,
    "    /**",
    "     * Render the startup loaded-resources sections ([Context], [Skills],",
    "     * [Prompts], [Extensions], [Themes]). Consulted once per section;",
    "     * return a Component to replace that section, or undefined to keep the",
    "     * stock ExpandableText. Absent -> stock behaviour.",
    "     */",
    "    setLoadedResources(factory?: (section: {",
    "        name: string;",
    "        header: string;",
    "        collapsedBody: string;",
    "        expandedBody: string;",
    "        color: string;",
    "        expanded: boolean;",
    "    }, tui: TUI, theme: Theme) => (Component & {",
    "        dispose?(): void;",
    "    }) | undefined): void;",
    `    /* /${MARKER} */`,
  ].join("\n");

  if (!dts.includes(ANCHOR_TYPES)) {
    console.error(
      `pi-ui:loaded-resources-seam: ANCHOR NOT FOUND in ${TYPES}: setHeader interface. Pi source changed; aborting.`,
    );
    process.exit(1);
  }
  if (dts.split(ANCHOR_TYPES).length !== 2) {
    console.error(
      `pi-ui:loaded-resources-seam: ANCHOR NOT UNIQUE in ${TYPES}: setHeader interface. Pi source changed; aborting.`,
    );
    process.exit(1);
  }
  writeFileSync(TYPES, dts.replace(ANCHOR_TYPES, REPLACEMENT_TYPES));
  console.log(`pi-ui:loaded-resources-seam: patched ${TYPES} (1 anchor)`);
}

console.log("pi-ui:loaded-resources-seam: done");
