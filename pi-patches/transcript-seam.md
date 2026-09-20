# Built-in transcript renderer seam (pi-ui T7)

Local patch for **pi-coding-agent 0.85.1** that lets an extension render the
**built-in `user` / `assistant` transcript turns**, not just custom messages.
`pi.registerMessageRenderer(key, renderer)` already exists but was only ever
consulted for messages carrying a `customType`; this patch makes the same
registry lookup happen for the role keys `"user"` and `"assistant"`.

Default behaviour with no role renderer registered is unchanged: the helper
returns `undefined` before constructing anything and every call site falls
through to the stock component.

## Apply

```sh
node pi-patches/transcript-seam.mjs /nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1
```

Idempotent (marker `pi-ui:transcript-seam`): a second run prints
`already patched (marker found)` and exits 0. Exits **nonzero** with a clear
message if any of the five anchors is missing or not unique, so a future pi bump
fails loudly instead of silently no-op'ing.

The nix store is read-only, so the nix wiring must copy/chmod the store first
(owned by another step — no `pi.nix` / `flake.nix` edits here). Verified against
a writable copy under `/tmp`.

## Why the unminified tree

`bin/pi` runs the minified esbuild bundle `dist/bundle/cli.js`, which is
impractical to string-patch. The package also ships the unminified build under
`lib/node_modules/pi-monorepo/dist/**`, and
`node <store>/lib/node_modules/pi-monorepo/dist/cli.js --version` prints
`0.85.1`. This patch targets that unminified entry, so pi must be launched via
`dist/cli.js` (or `dist/main.js`) for the seam to take effect.

## Exact anchors (stock 0.85.1)

File (unminified, 5546 lines):
`<store>/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js`

| # | Stock line | Anchor |
|---|-----------|--------|
| 1 | **189** | `export class InteractiveMode {` — insertion point for the adapter class |
| 2 | **2914** | `    addMessageToChat(message, options) {` — insertion point for the lookup helper |
| 3 | **2948** | `case "user": {` + `const textContent = this.getUserMessageText(message);` + `if (textContent) {` — static user turn |
| 4 | **2977** | `case "assistant": {` + stock `AssistantMessageComponent` construction — static assistant turn |
| 5 | **2615** | `else if (event.message.role === "assistant") {` + stock streaming construction — live `message_start` turn |

### Anchor 1 — class extent (L189)

```js
export class InteractiveMode {
```

### Anchor 2 — lookup site (L2914)

```js
    addMessageToChat(message, options) {
        switch (message.role) {
```

### Anchor 3 — static user turn (L2948–2950)

```js
            case "user": {
                const textContent = this.getUserMessageText(message);
                if (textContent) {
```

### Anchor 4 — static assistant turn (L2977–2981)

```js
            case "assistant": {
                const assistantComponent = new AssistantMessageComponent(message, this.hideThinkingBlock, this.getMarkdownThemeWithSettings(), this.hiddenThinkingLabel, this.outputPad, this.getMarkdownTransformers());
                this.chatContainer.addChild(assistantComponent);
                break;
            }
```

### Anchor 5 — live streaming assistant turn (L2615–2617)

```js
                else if (event.message.role === "assistant") {
                    this.streamingComponent = new AssistantMessageComponent(undefined, this.hideThinkingBlock, this.getMarkdownThemeWithSettings(), this.hiddenThinkingLabel, this.outputPad, this.getMarkdownTransformers());
                    this.streamingMessage = event.message;
```

There is **no separate `setChatRenderer`** in 0.85.1; the seam reuses the
existing `ExtensionRunner.getMessageRenderer(key)` (`dist/core/extensions/runner.js`
L425), which already iterates `ext.messageRenderers`, so no registry change is
needed. `registerMessageRenderer` (`dist/core/extensions/loader.js` L274–277)
stores into a plain `Map` keyed by an arbitrary string, so role keys are
accepted without any change.

## Change (5 string replacements, ~134 inserted lines)

All inserted code is wrapped in `/* pi-ui:transcript-seam */` … `/* /pi-ui:transcript-seam */`
and is ES2022-compatible, no TypeScript. Net: stock 5546 lines → patched 5680 lines.

1. **Adapter class** before `InteractiveMode` — `BuiltinMessageRendererComponent
   extends Container`. Calls the renderer with `(message, options, theme)`,
   adds the returned component, forwards `setExpanded` / `setOutputPad` when the
   returned component supports them, and exposes `updateContent(message, isStreaming)`
   so the streaming loop can drive it. A throwing renderer is swallowed
   (component renders nothing) rather than crashing the transcript.
   - **Spacing parity.** Stock `AssistantMessageComponent` prepends a
     `Spacer(1)` before visible content when it rebuilds. The adapter replaces
     that component, so it reproduces the same leading blank line for the
     `"assistant"` role (`if (this.role === "assistant") this.addChild(new Spacer(1))`
     before the returned component). Stock **user** turns get their separator from
     `addMessageToChat` instead, which the adapter cannot cover internally (it does
     not know the container), so the `case "user"` edit adds the same
     `Spacer(1)` the stock branch adds. Net vertical rhythm is identical to stock;
     without this, seam-rendered turns sat flush against the previous component.
   - `hasContent()` returns true only when the renderer produced a component
     (built from the same tick that produced the component, so it cannot go stale).
2. **Helper method** `createBuiltinMessageComponent(role, message, extra)` before
   `addMessageToChat` — looks up the renderer, returns `undefined` when absent
   (default path), otherwise builds the adapter with `expanded: this.toolOutputExpanded`,
   `outputPad: this.outputPad`, `markdownTransformers: this.getMarkdownTransformers()`.
3. **Static user turn** — consult `"user"` first; on a **content-bearing** hit add
   the stock `Spacer(1)` (guarded by `children.length > 0`, exactly as stock) then
   the adapter, still honour `options.populateHistory`, `break`. On miss, original
   code runs untouched (spacing included).
4. **Static assistant turn** — consult `"assistant"` first; on a content-bearing
   hit add the adapter (which already carries the leading spacer) and `break`;
   otherwise stock `AssistantMessageComponent`.
5. **Live streaming turn** — `this.streamingComponent = this.createBuiltinMessageComponent("assistant", event.message, { streaming: true }) ?? new AssistantMessageComponent(...)`.
   The adapter has no-op `setHideThinkingBlock` / `setHiddenThinkingLabel` so the
   existing streaming loop (`message_update`, `message_end`, `setHiddenThinkingLabel`,
   `setOutputPad`) works unchanged. The adapter's own leading spacer covers the
   live path too.

Minimal diff (condensed; the script writes the full text):

```diff
+/* pi-ui:transcript-seam */
+class BuiltinMessageRendererComponent extends Container {
+    constructor(role, renderer, message, options = {}) { ... this.rebuild(); }
+    setExpanded(e) { ... }
+    setOutputPad(p) { ... }
+    setHideThinkingBlock() { }
+    setHiddenThinkingLabel() { }
+    updateContent(message, isStreaming = false) { this.message = message; this.isStreaming = isStreaming; this.rebuild(); }
+    rebuild() {
+        this.clear(); this.hasRenderedContent = false;
+        /* renderer(...) */
+        if (!component) return;
+        this.hasRenderedContent = true;
+        if (this.role === "assistant") this.addChild(new Spacer(1)); // stock spacing
+        /* forward setExpanded/setOutputPad */ this.addChild(component);
+    }
+    hasContent() { return this.hasRenderedContent === true; }
+}
+/* /pi-ui:transcript-seam */
 export class InteractiveMode {

+    /* pi-ui:transcript-seam */
+    createBuiltinMessageComponent(role, message, extra = {}) {
+        const renderer = this.session?.extensionRunner?.getMessageRenderer(role);
+        if (typeof renderer !== "function") return undefined;
+        return new BuiltinMessageRendererComponent(role, renderer, message, { ... });
+    }
+    /* /pi-ui:transcript-seam */
     addMessageToChat(message, options) {

             case "user": {
+                const seamUser = this.createBuiltinMessageComponent("user", message);
+                if (seamUser && seamUser.hasContent()) {
+                    if (this.chatContainer.children.length > 0) this.chatContainer.addChild(new Spacer(1)); // stock spacing
+                    add; populateHistory; break;
+                }
                 const textContent = this.getUserMessageText(message);
                 ...
             case "assistant": {
+                const seamAssistant = this.createBuiltinMessageComponent("assistant", message);
+                if (seamAssistant && seamAssistant.hasContent()) { add; break; } // spacer lives in the adapter
                 const assistantComponent = new AssistantMessageComponent(...);
                 ...
                 else if (event.message.role === "assistant") {
-                    this.streamingComponent = new AssistantMessageComponent(undefined, ...);
+                    this.streamingComponent = this.createBuiltinMessageComponent("assistant", event.message, { streaming: true });
+                    this.streamingComponent ??= new AssistantMessageComponent(undefined, ...);
                     this.streamingMessage = event.message;
```

## Registration contract for T8

The existing API and type signature are unchanged; only the accepted **key**
set is widened.

```ts
pi.registerMessageRenderer(key, renderer)
  key:      "user" | "assistant"        // NEW: built-in role keys
            | <customType: string>      // existing custom-message behaviour
  renderer: (message, options, theme) => Component | undefined

  message:  the pi message object for that turn.
            user:      { role: "user", content: string | ContentBlock[] }
            assistant: { role: "assistant", content: ContentBlock[], ... }
  options:  {
            expanded: boolean,          // pi's toolOutputExpanded state
            outputPad: number,          // pi's outputPad setting
            isStreaming: boolean,       // NEW (additive) — true on live turns
            markdownTransformers: readonly MarkdownTransformer[],
          }
  theme:    the active pi theme object (same one custom renderers receive)
  returns:  a pi-tui Component (e.g. Container subclass), or undefined / a
            throw to fall back to stock rendering for that turn.
```

Precedence: role renderers are per-extension `Map` entries like custom ones;
`getMessageRenderer` returns the **first** extension that registered the key
(registration order), so the earlier-registered extension wins. Registering a
role key never affects custom-message rendering, and vice versa.

Notes / caveats for T8:
- Return `undefined` (or throw) to keep stock rendering — useful for a
  conditional renderer.
- If the returned component implements `setOutputPad(number)` /
  `setExpanded(boolean)`, pi forwards both. Otherwise the component just does
  not react to those settings.
- During live streaming the same component instance is reused and
  `updateContent(message, isStreaming)` is called as the message grows;
  re-read `message.content` on each render rather than caching.
- For a persistent custom look on already-loaded sessions, `addMessageToChat`
  (static path) and the streaming path both route through the seam, so role
  renderers apply on initial load, rebuild, and live turns.
- Tool results (`role: "toolResult"`) are **not** part of this seam — they render
  inline with their tool call.
- Skill-invocation user turns (`parseSkillBlock`): when a `"user"` renderer is
  registered the whole user turn goes through the adapter, so the stock
  skill-block specific rendering does not run for that turn. The renderer gets
  the raw user message. Omit a `"user"` renderer if skill-block rendering matters.

## Verify

All commands run against a writable copy under `/tmp` (store itself untouched):

```sh
cp -r /nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1 /tmp/pi-t7
chmod -R u+w /tmp/pi-t7

node pi-patches/transcript-seam.mjs /tmp/pi-t7
# pi-ui:transcript-seam: patched .../interactive-mode.js (5 anchors)
# pi-ui:transcript-seam: done                                      (exit 0)

node pi-patches/transcript-seam.mjs /tmp/pi-t7
# pi-ui:transcript-seam: already patched (marker found): ...
# pi-ui:transcript-seam: done                                      (exit 0)

node /tmp/pi-t7/lib/node_modules/pi-monorepo/dist/cli.js --version
# 0.85.1                                                           (exit 0)
```

Observed extra checks:
- `node --check dist/modes/interactive/interactive-mode.js` → exit 0.
- Fresh-copy patch output is **byte-identical** to the first copy (deterministic).
- Fail-loud: mutating one anchor then running → `ANCHOR NOT FOUND ... aborting` exit 1.
- Missing store → `missing file: ...` exit 1. No argument → usage, exit 2.
- Real extension load, proving the registry accepts role keys through the actual
  loader (extension writes a canary file on load):
  ```sh
  node /tmp/pi-t7/lib/node_modules/pi-monorepo/dist/cli.js -ne -e /tmp/pi-t7-smoke-ext.ts --help
  # exit 0; canary: {"loaded":true,"registered":["user","assistant"]}
  ```
- Node reachability suite importing the patched module (26/26 passing): helper
  returns `undefined` for both roles with no renderer; registered role renderer
  is resolved and invoked with the message/theme/options; `isStreaming` is true
  on the live `message_start` branch and false on static; adapter `updateContent`
  re-invokes the renderer; real `addMessageToChat` user/assistant branches use
  the wrapper when registered and fall through to stock components when not; a
  throwing renderer degrades to an empty component; live `message_start` with no
  renderer yields a stock `AssistantMessageComponent`.
- Spacing reachability suite (`pi-patches/transcript-seam.test.mjs`, 6/6 passing)
  drives the real `addMessageToChat` and asserts the child layout: user turn after
  a previous component inserts exactly one `Spacer(1)` before the adapter; a first
  user turn inserts none; the assistant adapter renders a blank first line (its
  internal `Spacer(1)`); the streaming adapter does too; `hasContent()` is false
  when the renderer returns undefined. Run it after patching a `/tmp` copy:
  ```sh
  cp -r /nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1 /tmp/pi-seam \
    && chmod -R u+w /tmp/pi-seam
  node pi-patches/transcript-seam.mjs /tmp/pi-seam
  node pi-patches/transcript-seam.test.mjs /tmp/pi-seam
  # PASS — 6 transcript-seam spacing checks
  ```
- Real e2e (`pi-workflow/tests/ui-e2e.sh` against the nix-built patched pi):
  PASS=36 FAIL=0 SKIP=1 (the one skip is a model run with no thinking block).

## Not verified

- **No visual TUI check.** A full interactive render (real terminal, an actual
  user/assistant turn painted with a custom component) cannot be exercised
  headlessly. The seam's runtime dispatch is proven by importing the patched
  module and driving the real `addMessageToChat` / `handleEvent` methods, and by
  the tmux e2e suite; exact pixel output is not asserted.
- **Nix wiring not exercised.** The store copy under `/tmp` is manual; patching
  at build time and launching pi via the unminified `dist/cli.js` entry is owned
  by another step.
- **No end-to-end model turn.** The smoke extension registers renderers but no
  live model call was made, so a real streamed assistant turn rendering through
  the adapter was not observed.
