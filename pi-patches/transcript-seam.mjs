#!/usr/bin/env node
/*
 * pi-ui: TRANSCRIPT SEAM for built-in user/assistant messages.
 *
 * `pi.registerMessageRenderer(key, renderer)` already exists, but only CUSTOM
 * messages (messages carrying a `customType`) ever consult it. This patch makes
 * the same registry lookup happen for the built-in roles `"user"` and
 * `"assistant"`, so an extension can register a renderer under a role key and
 * have that built-in turn render with the returned component.
 *
 * The seam is added at the unminified dist entry:
 *   <piStoreRoot>/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js
 *
 * Default behaviour is byte-identical when no renderer is registered for the
 * role: `getMessageRenderer(role)` returns undefined and every call site falls
 * straight through to the stock component.
 *
 * It covers BOTH paths a built-in turn can take:
 *   - static/session rebuild: `addMessageToChat` cases "user" / "assistant"
 *   - live streaming:        the `message_start` assistant branch, via an
 *                            adapter component whose `updateContent` re-renders
 *
 * Usage:
 *   node pi-patches/transcript-seam.mjs <piStoreRoot>
 *
 * Idempotent: a marker comment (`pi-ui:transcript-seam`) makes a second run a
 * no-op. Exits nonzero with a clear message if any anchor is missing or not
 * unique, so a future pi bump fails loudly.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MARKER = "pi-ui:transcript-seam";

const piStoreRoot = process.argv[2];
if (!piStoreRoot) {
  console.error("usage: node transcript-seam.mjs <piStoreRoot>");
  process.exit(2);
}

const TARGET = join(
  piStoreRoot,
  "lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js",
);
if (!existsSync(TARGET)) {
  console.error(`pi-ui:transcript-seam: missing file: ${TARGET}`);
  process.exit(1);
}

const source = readFileSync(TARGET, "utf8");
if (source.includes(MARKER)) {
  console.log(`pi-ui:transcript-seam: already patched (marker found): ${TARGET}`);
  console.log("pi-ui:transcript-seam: done");
  process.exit(0);
}

// ---------------------------------------------------------------------------
// 1. Adapter component (top-level, before the InteractiveMode class).
// ---------------------------------------------------------------------------
const ANCHOR_CLASS = "export class InteractiveMode {";

const WRAPPER_CLASS = [
  `/* ${MARKER} */`,
  "/**",
  " * Adapter that lets an extension MessageRenderer registered for a built-in",
  ' * role ("user"/"assistant") drive a built-in transcript turn, including live',
  " * streaming: the streaming loop calls updateContent(), which re-runs the",
  " * renderer with the latest partial/complete message.",
  " */",
  "class BuiltinMessageRendererComponent extends Container {",
  "    constructor(role, renderer, message, options = {}) {",
  "        super();",
  "        this.role = role;",
  "        this.renderer = renderer;",
  "        this.message = message;",
  "        this.outputPad = options.outputPad ?? 1;",
  "        this.expanded = options.expanded ?? false;",
  "        this.isStreaming = options.streaming ?? false;",
  "        this.markdownTransformers = options.markdownTransformers;",
  "        this.rebuild();",
  "    }",
  "    setExpanded(expanded) {",
  "        if (this.expanded !== expanded) {",
  "            this.expanded = expanded;",
  "            this.rebuild();",
  "        }",
  "    }",
  "    setOutputPad(outputPad) {",
  "        if (this.outputPad !== outputPad) {",
  "            this.outputPad = outputPad;",
  "            this.rebuild();",
  "        }",
  "    }",
  "    // Accepted and ignored so the streaming loop can call these uniformly.",
  "    setHideThinkingBlock() { }",
  "    setHiddenThinkingLabel() { }",
  "    updateContent(message, isStreaming = false) {",
  "        this.message = message;",
  "        this.isStreaming = isStreaming;",
  "        this.rebuild();",
  "    }",
  "    invalidate() {",
  "        super.invalidate();",
  "        this.rebuild();",
  "    }",
  "    rebuild() {",
  "        this.clear();",
  "        this.hasRenderedContent = false;",
  "        let component;",
  "        try {",
  "            component = this.renderer(this.message, {",
  "                expanded: this.expanded,",
  "                outputPad: this.outputPad,",
  "                isStreaming: this.isStreaming,",
  "                markdownTransformers: this.markdownTransformers,",
  "            }, theme);",
  "        }",
  "        catch {",
  "            component = undefined;",
  "        }",
  "        if (!component)",
  "            return;",
  "        this.hasRenderedContent = true;",
  "        // Stock AssistantMessageComponent prepends a Spacer(1) before visible",
  "        // content; the seam replaces that component, so reproduce the leading",
  "        // blank here or a seam assistant turn sits flush on the previous one.",
  "        // Stock USER turns get their Spacer from addMessageToChat instead (see",
  "        // the case \"user\" edit), so only assistant adds it internally.",
  "        if (this.role === \"assistant\")",
  "            this.addChild(new Spacer(1));",
  "        if (typeof component.setExpanded === \"function\")",
  "            component.setExpanded(this.expanded);",
  "        if (typeof component.setOutputPad === \"function\")",
  "            component.setOutputPad(this.outputPad);",
  "        this.addChild(component);",
  "    }",
  "    /**",
  "     * True when the renderer produced a component. An extension that returns",
  "     * undefined (nothing renderable) leaves this false so the caller can fall",
  "     * through to stock rendering, including its spacing.",
  "     */",
  "    hasContent() {",
  "        return this.hasRenderedContent === true;",
  "    }",
  "}",
  `/* /${MARKER} */`,
  ANCHOR_CLASS,
].join("\n");

// ---------------------------------------------------------------------------
// 2. Lookup helper method (inside the class, just before addMessageToChat).
// ---------------------------------------------------------------------------
const ANCHOR_HELPER = "    addMessageToChat(message, options) {";

const REPLACEMENT_HELPER = [
  `    /* ${MARKER} */`,
  "    /**",
  '     * Consult a renderer registered for a built-in role ("user"/"assistant").',
  "     * Returns undefined when none is registered, so callers fall back to the",
  "     * stock rendering path (default behaviour is unchanged).",
  "     */",
  "    createBuiltinMessageComponent(role, message, extra = {}) {",
  "        const renderer = this.session?.extensionRunner?.getMessageRenderer(role);",
  "        if (typeof renderer !== \"function\") {",
  "            return undefined;",
  "        }",
  "        return new BuiltinMessageRendererComponent(role, renderer, message, {",
  "            expanded: this.toolOutputExpanded,",
  "            outputPad: this.outputPad,",
  "            markdownTransformers: this.getMarkdownTransformers(),",
  "            ...extra,",
  "        });",
  "    }",
  `    /* /${MARKER} */`,
  ANCHOR_HELPER,
].join("\n");

// ---------------------------------------------------------------------------
// 3. Static user turn.
// ---------------------------------------------------------------------------
const ANCHOR_USER = [
  '            case "user": {',
  "                const textContent = this.getUserMessageText(message);",
  "                if (textContent) {",
].join("\n");

const REPLACEMENT_USER = [
  '            case "user": {',
  `                /* ${MARKER} */`,
  '                const seamUser = this.createBuiltinMessageComponent("user", message);',
  "                if (seamUser && seamUser.hasContent()) {",
  "                    // Stock spacing: a blank line separates this turn from the",
  "                    // previous component (see the stock textContent branch below).",
  "                    if (this.chatContainer.children.length > 0) {",
  "                        this.chatContainer.addChild(new Spacer(1));",
  "                    }",
  "                    this.chatContainer.addChild(seamUser);",
  "                    if (options?.populateHistory) {",
  "                        const seamUserText = this.getUserMessageText(message);",
  "                        if (seamUserText)",
  "                            this.editor.addToHistory?.(seamUserText);",
  "                    }",
  "                    break;",
  "                }",
  `                /* /${MARKER} */`,
  "                const textContent = this.getUserMessageText(message);",
  "                if (textContent) {",
].join("\n");

// ---------------------------------------------------------------------------
// 4. Static assistant turn.
// ---------------------------------------------------------------------------
const ANCHOR_ASSISTANT = [
  '            case "assistant": {',
  "                const assistantComponent = new AssistantMessageComponent(message, this.hideThinkingBlock, this.getMarkdownThemeWithSettings(), this.hiddenThinkingLabel, this.outputPad, this.getMarkdownTransformers());",
  "                this.chatContainer.addChild(assistantComponent);",
  "                break;",
  "            }",
].join("\n");

const REPLACEMENT_ASSISTANT = [
  '            case "assistant": {',
  `                /* ${MARKER} */`,
  '                const seamAssistant = this.createBuiltinMessageComponent("assistant", message);',
  "                if (seamAssistant && seamAssistant.hasContent()) {",
  "                    // The assistant adapter carries its own leading Spacer(1),",
  "                    // matching stock AssistantMessageComponent; no container",
  "                    // spacer is used on this path in stock pi.",
  "                    this.chatContainer.addChild(seamAssistant);",
  "                    break;",
  "                }",
  `                /* /${MARKER} */`,
  "                const assistantComponent = new AssistantMessageComponent(message, this.hideThinkingBlock, this.getMarkdownThemeWithSettings(), this.hiddenThinkingLabel, this.outputPad, this.getMarkdownTransformers());",
  "                this.chatContainer.addChild(assistantComponent);",
  "                break;",
  "            }",
].join("\n");

// ---------------------------------------------------------------------------
// 5. Live streaming assistant turn (message_start).
// ---------------------------------------------------------------------------
const ANCHOR_STREAM = [
  '                else if (event.message.role === "assistant") {',
  "                    this.streamingComponent = new AssistantMessageComponent(undefined, this.hideThinkingBlock, this.getMarkdownThemeWithSettings(), this.hiddenThinkingLabel, this.outputPad, this.getMarkdownTransformers());",
  "                    this.streamingMessage = event.message;",
].join("\n");

const REPLACEMENT_STREAM = [
  '                else if (event.message.role === "assistant") {',
  `                    /* ${MARKER} */`,
  "                    // Extension renderer, if registered, drives the live turn.",
  '                    this.streamingComponent = this.createBuiltinMessageComponent("assistant", event.message, { streaming: true });',
  `                    /* /${MARKER} */`,
  "                    this.streamingComponent ??= new AssistantMessageComponent(undefined, this.hideThinkingBlock, this.getMarkdownThemeWithSettings(), this.hiddenThinkingLabel, this.outputPad, this.getMarkdownTransformers());",
  "                    this.streamingMessage = event.message;",
].join("\n");

const EDITS = [
  ["BuiltinMessageRendererComponent adapter", ANCHOR_CLASS, WRAPPER_CLASS],
  ["createBuiltinMessageComponent helper", ANCHOR_HELPER, REPLACEMENT_HELPER],
  ["static user turn", ANCHOR_USER, REPLACEMENT_USER],
  ["static assistant turn", ANCHOR_ASSISTANT, REPLACEMENT_ASSISTANT],
  ["streaming assistant turn", ANCHOR_STREAM, REPLACEMENT_STREAM],
];

let out = source;
for (const [name, anchor, replacement] of EDITS) {
  if (!out.includes(anchor)) {
    console.error(
      `pi-ui:transcript-seam: ANCHOR NOT FOUND in ${TARGET}: ${name}. Pi source changed; aborting.`,
    );
    process.exit(1);
  }
  if (out.split(anchor).length !== 2) {
    console.error(
      `pi-ui:transcript-seam: ANCHOR NOT UNIQUE in ${TARGET}: ${name}. Pi source changed; aborting.`,
    );
    process.exit(1);
  }
  out = out.replace(anchor, replacement);
}

writeFileSync(TARGET, out);
console.log(`pi-ui:transcript-seam: patched ${TARGET} (${EDITS.length} anchors)`);
console.log("pi-ui:transcript-seam: done");
