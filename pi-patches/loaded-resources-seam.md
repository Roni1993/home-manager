# Startup loaded-resources renderer seam (pi-ui T10)

Local patch for **pi-coding-agent 0.85.1** that lets an extension supply the
rendered content for the startup loaded-resources block —
`[Context]`, `[Skills]`, `[Prompts]`, `[Extensions]`, `[Themes]`.

There is no `ExtensionUIContext` hook for this block. `setHeader` styles the
logo/banner, a different container (`headerContainer`, a sibling of
`loadedResourcesContainer`), so an extension cannot restyle the resource block.
This patch adds one opt-in, per-section renderer.

With no factory registered the stock code runs verbatim, so default behaviour is
byte-identical (proved by differential harness, below).

## Apply

```sh
node pi-patches/loaded-resources-seam.mjs /nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1
```

Idempotent (marker `pi-ui:loaded-resources-seam`): a second run prints
`already patched (marker found)` and exits 0. Exits **nonzero** with a clear
message if any anchor is missing or not unique, so a future pi bump fails loudly.

The nix store is read-only, so nix wiring copies/chmods the store first
(`pi-ui.nix`). `pi-ui.nix` now runs three patch scripts in order:
`transcript-seam.mjs`, `pi-tui-backdrop.mjs`, `loaded-resources-seam.mjs`.

## Why the unminified tree

`bin/pi` (the nix wrapper) launches the unminified
`lib/node_modules/pi-monorepo/dist/cli.js`, so string patches against
`dist/**` take effect. This patch targets the unminified
`interactive-mode.js` plus the `ExtensionUIContext` `.d.ts`.

## Exact anchors (stock 0.85.1)

### `dist/modes/interactive/interactive-mode.js` (5546 lines)

| # | Stock line | Anchor |
|---|-----------|--------|
| 1 | **1255–1259** | `const addLoadedSection = (name, collapsedBody, expandedBody = collapsedBody, color = "mdHeading") => {` … — the single chokepoint all five named sections route through |
| 2 | **1823** | `    setExtensionHeader(factory) {` — insertion point for the accessor method |
| 3 | **1916** | `            setHeader: (factory) => this.setExtensionHeader(factory),` — `createExtensionUIContext()` object, where the accessor is exposed |

### Anchor 1 — `addLoadedSection` (L1255–1259)

Every `[Context]` (L1305), `[Skills]` (L1315), `[Prompts]` (L1332),
`[Extensions]` (L1341) and `[Themes]` (L1356) call goes through this helper; it
constructs the stock `ExpandableText` (L1256) and appends a `Spacer(1)`.

```js
        const addLoadedSection = (name, collapsedBody, expandedBody = collapsedBody, color = "mdHeading") => {
            const section = new ExpandableText(() => `${sectionHeader(name, color)}\n${collapsedBody}`, () => `${sectionHeader(name, color)}\n${expandedBody}`, this.getStartupExpansionState(), 0, 0);
            this.loadedResourcesContainer.addChild(section);
            this.loadedResourcesContainer.addChild(new Spacer(1));
        };
```

### Anchor 2 — accessor site (L1823)

```js
    setExtensionHeader(factory) {
```

### Anchor 3 — ui context (L1916)

```js
            setHeader: (factory) => this.setExtensionHeader(factory),
```

### `dist/core/extensions/types.d.ts` (1351 lines)

| # | Stock line | Anchor |
|---|-----------|--------|
| 4 | **110–113** | `setHeader(factory: ((tui: TUI, theme: Theme) => Component & {` … inside `export interface ExtensionUIContext` (L68) |

## Seam API

`ctx.ui.setLoadedResources(factory)` — factory is optional; `undefined` clears it.

```ts
setLoadedResources(
  factory?: (
    section: {
      name: string;          // "Context" | "Skills" | "Prompts" | "Extensions" | "Themes"
      header: string;        // pre-colored "[Name]" (e.g. theme.fg(color, "[Skills]"))
      collapsedBody: string; // stock collapsed body, already color-wrapped
      expandedBody: string;  // stock expanded body, already color-wrapped
      color: string;         // stock header color name ("mdHeading", …)
      expanded: boolean;     // pi's current startup expansion state
    },
    tui: TUI,
    theme: Theme,
  ) => (Component & { dispose?(): void }) | undefined,
): void;
```

- Consulted **once per section** inside `addLoadedSection`, before the stock
  `ExpandableText` is built.
- Returning a truthy component replaces that section. Returning `undefined`, or
  throwing, keeps the stock `ExpandableText` for that section (per-section
  opt-in).
- The `Spacer(1)` that follows every section is preserved either way.
- Extensions should register during activation (before the startup block is
  first drawn at `bindCurrentSessionExtensions`, `interactive-mode.js:1472`).
  The setter is a plain field assignment plus `ui.requestRender()`; it does not
  re-run `showLoadedResources()` itself, to avoid rendering mid-bind.

### Why per-section, not whole-block

`addLoadedSection` is the one place all five named sections pass through, and it
already holds the fully-formatted bodies. Intercepting there needs no data
plumbing and gives a natural per-section fallback. A whole-block factory would
have to thread the five bodies and the diagnostics out of
`showLoadedResources`, or expose resource-loader internals — more surface for
the same styling goal.

## Change (4 string replacements)

All inserted code is wrapped in `/* pi-ui:loaded-resources-seam */` …
`/* /pi-ui:loaded-resources-seam */`, ES2022-only, no TypeScript at runtime.

1. **`addLoadedSection` interception** — if a factory is registered, call it
   with the section object; on a truthy return add it plus `Spacer(1)` and
   `return`; otherwise fall through to the untouched stock lines.
2. **`setLoadedResources(factory)` accessor** before `setExtensionHeader` —
   stores `this.loadedResourcesFactory` and requests a render.
3. **`createExtensionUIContext()` exposure** — `setLoadedResources:
   (factory) => this.setLoadedResources(factory)` after `setHeader`. The
   extension runner spreads the ui context (`runner.js:275`), so the method
   reaches `ctx.ui`.
4. **`ExtensionUIContext.setLoadedResources`** type in `types.d.ts`.

Minimal diff (condensed; the script writes the full text):

```diff
         const addLoadedSection = (name, collapsedBody, expandedBody = collapsedBody, color = "mdHeading") => {
+            /* pi-ui:loaded-resources-seam */
+            if (typeof this.loadedResourcesFactory === "function") {
+                let seamSection;
+                try {
+                    seamSection = this.loadedResourcesFactory({
+                        name, header: sectionHeader(name, color),
+                        collapsedBody, expandedBody, color,
+                        expanded: this.getStartupExpansionState(),
+                    }, this.ui, theme);
+                } catch { seamSection = undefined; }
+                if (seamSection) {
+                    this.loadedResourcesContainer.addChild(seamSection);
+                    this.loadedResourcesContainer.addChild(new Spacer(1));
+                    return;
+                }
+            }
+            /* /pi-ui:loaded-resources-seam */
             const section = new ExpandableText(...);
 
+    setLoadedResources(factory) {
+        this.loadedResourcesFactory = factory;
+        this.ui?.requestRender?.();
+    }
     setExtensionHeader(factory) {
 
             setHeader: (factory) => this.setExtensionHeader(factory),
+            setLoadedResources: (factory) => this.setLoadedResources(factory),
 
 interface ExtensionUIContext {
     setHeader(...): void;
+    setLoadedResources(factory?: (section: {...}, tui: TUI, theme: Theme) => (Component & { dispose?(): void }) | undefined): void;
 ```

`loadedResourcesFactory` is a dynamic property (no class-field declaration), so
the patch adds no field anchor.

### Rendering expectations for component authors

The stock sections are `ExpandableText extends Text`; any replacement should obey
the same constraints as other pi-tui components: report true terminal width via
`visibleWidth(...)` and clip with `truncateToWidth(...)` from
`@earendil-works/pi-tui` rather than JS string `.length`, because theme colors
are ANSI escapes. The seam itself does no rendering — that is the extension's job.

## Verify

Commands run against writable `/tmp` copies (store untouched). Stock store:
`/nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1`.

```sh
cp -r <stock> /tmp/pi-lr && chmod -R u+w /tmp/pi-lr
node pi-patches/loaded-resources-seam.mjs /tmp/pi-lr
# pi-ui:loaded-resources-seam: patched .../interactive-mode.js (3 anchors)
# pi-ui:loaded-resources-seam: patched .../types.d.ts (1 anchor)
node pi-patches/loaded-resources-seam.mjs /tmp/pi-lr          # second run -> no-op, exit 0
node --check /tmp/pi-lr/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js
node /tmp/pi-lr/lib/node_modules/pi-monorepo/dist/cli.js --version   # 0.85.1
```

- **Idempotent:** second run prints `already patched (marker found)` for both
  files, exit 0.
- **Fail-loud:** mutating one anchor then running → `ANCHOR NOT FOUND … aborting`,
  exit 1. Missing store → `missing file: …`, exit 1. No arg → usage, exit 2.
- **Full stack order (`pi-ui.nix` order):** fresh copy, run
  `transcript-seam.mjs` → `pi-tui-backdrop.mjs` → `loaded-resources-seam.mjs`;
  all anchors found, `node --check` passes, CLI prints `0.85.1`.
- **Headless harness** (`/tmp/lr-seam-harness.mjs`): imports both the stock and
  patched `interactive-mode.js`, builds an instance with
  `Object.create(InteractiveMode.prototype)` and a stubbed `session`, then calls
  the real `showLoadedResources({ force: true })`. Output:

  ```
  PASS default path unchanged: [{"ctor":"ExpandableText","collapsed":"\u001b[38;2;240;198;116m[Skills]\u001b[39m\n\u001b[38;2;102;102;102m  demo\u001b[39m"},{"ctor":"Spacer"}]
  PASS factory consulted: [{"name":"Skills","header":"\u001b[38;2;240;198;116m[Skills]\u001b[39m","expanded":false,"hasTui":true,"hasTheme":true,"collapsed":"\u001b[38;2;102;102;102m  demo\u001b[39m"}]
  PASS undefined falls back to stock ExpandableText
  PASS throw falls back to stock ExpandableText
  PASS setLoadedResources accessor
  PASS ui.setLoadedResources wired to accessor
  PASS smoke extension end-to-end: {"SMOKE_REPLACEMENT":"Skills","collapsed":"\u001b[38;2;102;102;102m  demo\u001b[39m"}
  ALL SEAM CHECKS PASSED
  ```

  The harness also passes against the tree with all three patches applied.
  It proves: stock vs patched-no-factory children are deep-equal (same
  `ExpandableText` + `Spacer`, same collapsed text); a factory is invoked once
  per section with `{name, header, collapsedBody, expandedBody, color, expanded}`
  plus `tui`/`theme`, and its component replaces the stock one; declining or
  throwing falls back per section.
- **Smoke extension** (`/tmp/pi-lr-smoke-ext.mjs`): `export default (pi) =>
  pi.on("session_start", (_e, ctx) => ctx.ui.setLoadedResources(...))`. The
  harness imports it, invokes the captured `session_start` handler with the real
  `createExtensionUIContext()` from the patched module, then drives
  `showLoadedResources` and asserts the extension's component replaced the
  `[Skills]` section.
- **Nix build** (`pi-ui.nix` header command):

  ```sh
  nix build --impure --expr 'let f = builtins.getFlake (toString ./.); in import ./pi-ui.nix { pkgs = f.inputs.nixpkgs-pi.legacyPackages.x86_64-linux; inputs = f.inputs; }'
  # -> /nix/store/3pfbd0yhdggmpcskl3kxzrxdpba1623g-pi-coding-agent-ui-0.85.1
  ```

  Result carries all three patches: `pi-ui:transcript-seam` in
  `interactive-mode.js`, `pi-ui:backdrop` in `pi-tui/dist/tui.js` + `tui.d.ts`,
  `pi-ui:loaded-resources-seam` in `interactive-mode.js` (6) and
  `types.d.ts`. `result/bin/pi --version` → `0.85.1`.

## Not verified

- **No visual TUI check.** A real terminal painting the startup block through a
  custom component cannot be exercised headlessly (this environment has no
  interactive TTY). The seam's dispatch is proven by importing the patched
  module and driving the real `showLoadedResources`; actual on-screen output is
  not.
- **No live extension load through the interactive runner.** The harness
  invokes the extension's `session_start` handler directly; the patched ui
  context and `showLoadedResources` are real, but a full interactive session
  (TTY + model) was not started.
- **No real pi-tui component rendering.** The harness uses a sentinel object, so
  `visibleWidth`/`truncateToWidth` behavior of a real replacement component is
  documented but not exercised.
