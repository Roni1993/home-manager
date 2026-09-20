#!/usr/bin/env node
/*
 * pi-ui: transcript-seam spacing check.
 *
 * The seam replaces stock user/assistant components, so it must reproduce the
 * stock vertical rhythm itself:
 *   - assistant: stock AssistantMessageComponent prepends Spacer(1) before
 *     visible content; the adapter does the same internally.
 *   - user: stock addMessageToChat adds Spacer(1) when the chat already has
 *     children; the case "user" edit does the same.
 *
 * This loads the REAL patched interactive-mode.js and drives the real
 * addMessageToChat, asserting the resulting chatContainer child layout. Run:
 *
 *   cp -r /nix/store/<pi>-0.85.1 /tmp/pi-seam && chmod -R u+w /tmp/pi-seam
 *   node pi-patches/transcript-seam.mjs /tmp/pi-seam
 *   node pi-patches/transcript-seam.test.mjs /tmp/pi-seam
 */
import { pathToFileURL } from "node:url";

const root = process.argv[2];
if (!root) {
  console.error("usage: node transcript-seam.test.mjs <patchedPiRoot>");
  process.exit(2);
}

const { InteractiveMode } = await import(
  pathToFileURL(`${root}/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js`).href
);
const { Spacer, Container } = await import(
  pathToFileURL(`${root}/lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-tui/dist/index.js`).href
);

class FakeComp extends Container {
  render() {
    return ["fake"];
  }
}

const renderers = {};
const makeThis = () => {
  const children = [];
  return {
    chatContainer: {
      children,
      addChild(c) {
        children.push(c);
      },
    },
    session: { extensionRunner: { getMessageRenderer: (k) => renderers[k] } },
    toolOutputExpanded: false,
    outputPad: 1,
    hiddenThinkingLabel: "Thinking...",
    hideThinkingBlock: false,
    editor: { addToHistory() {} },
    getUserMessageText: (m) => (typeof m.content === "string" ? m.content : ""),
    getMarkdownThemeWithSettings: () => ({}),
    getMarkdownTransformers: () => [],
    createBuiltinMessageComponent: InteractiveMode.prototype.createBuiltinMessageComponent,
  };
};
const layout = (children) => children.map((c) => (c instanceof Spacer ? "spacer" : c.constructor.name));

let checks = 0;
let fails = 0;
const check = (cond, msg) => {
  checks++;
  if (!cond) {
    fails++;
    console.error(`FAIL: ${msg}`);
  }
};

renderers.user = () => new FakeComp();
renderers.assistant = () => new FakeComp();

// user after an existing component → one container Spacer before the adapter
{
  const t = makeThis();
  t.chatContainer.children.push(new FakeComp());
  InteractiveMode.prototype.addMessageToChat.call(t, { role: "user", content: "hello" });
  const l = layout(t.chatContainer.children);
  check(JSON.stringify(l) === JSON.stringify(["FakeComp", "spacer", "BuiltinMessageRendererComponent"]), `user layout: ${l}`);
}

// user as the first component → no leading spacer (stock children.length > 0 guard)
{
  const t = makeThis();
  InteractiveMode.prototype.addMessageToChat.call(t, { role: "user", content: "hello" });
  check(layout(t.chatContainer.children).filter((x) => x === "spacer").length === 0, "user-first must have no spacer");
}

// assistant after an existing component → adapter renders a leading blank line
{
  const t = makeThis();
  t.chatContainer.children.push(new FakeComp());
  InteractiveMode.prototype.addMessageToChat.call(t, { role: "assistant", content: [{ type: "text", text: "hi" }] });
  const adapter = t.chatContainer.children[1];
  check(adapter.render(40)[0] === "", `assistant adapter first line blank, got ${JSON.stringify(adapter.render(40)[0])}`);
  check(adapter.hasContent() === true, "hasContent true when renderer produced a component");
}

// live streaming path uses the same adapter (blank leading line)
{
  const t = makeThis();
  const comp = InteractiveMode.prototype.createBuiltinMessageComponent.call(
    t,
    "assistant",
    { content: [{ type: "text", text: "streaming" }] },
    { streaming: true },
  );
  check(comp.render(40)[0] === "", `streaming adapter first line blank, got ${JSON.stringify(comp.render(40)[0])}`);
}

// renderer returns undefined → hasContent false, caller keeps stock path
{
  renderers.user = () => undefined;
  const t = makeThis();
  const comp = InteractiveMode.prototype.createBuiltinMessageComponent.call(t, "user", { content: "" }, {});
  check(comp.hasContent() === false, "hasContent false when renderer returned undefined");
  renderers.user = () => new FakeComp();
}

console.log(fails === 0 ? `PASS — ${checks} transcript-seam spacing checks` : `FAIL — ${fails}/${checks}`);
process.exit(fails === 0 ? 0 : 1);
