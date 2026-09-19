# pi-tui opt-in dimmed backdrop (pi-ui T9)

Local patch for **pi-coding-agent 0.85.1** that adds an opt-in dim factor for the
transcript line behind an overlay, so the T3 questions modal can darken the chat
behind it. Default behaviour with no flag is byte-identical.

## Apply

```sh
node pi-patches/pi-tui-backdrop.mjs /nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1
```

Idempotent (marker `pi-ui:backdrop`), nonzero exit if any anchor is missing.
The store is read-only, so nix wiring must copy/chmod the store first (owned by
another step). Verified against a writable copy under `/tmp`.

## Exact anchors (stock 0.85.1)

pi-tui unminified copy:
`<store>/lib/node_modules/pi-monorepo/node_modules/@earendil-works/pi-tui/dist/`

### `tui.js` (1054 lines)

- **L132–137** — `compositeTuiLine` definition; `extractSegments` call:
  ```js
  /** Composite overlay content into a terminal line at a fixed column. */
  export function compositeTuiLine(baseLine, overlayLine, startCol, overlayWidth, totalWidth) {
      if (isImageLine(baseLine))
          return baseLine;
      const afterStart = startCol + overlayWidth;
      const base = extractSegments(baseLine, startCol, afterStart, totalWidth - afterStart, true);
  ```
  This is where the base line (the transcript behind the overlay) is available.
  Dimming happens by scaling the base line's `38;2;r;g;b` / `48;2;r;g;b`
  components toward black *before* `extractSegments` slices it.

- **L951–961** — overlay splice loop inside `compositeOverlays`:
  ```js
  for (const { overlayLines, row, col, w } of rendered) {
      for (let i = 0; i < overlayLines.length; i++) {
          const idx = viewportStart + row + i;
          if (idx >= 0 && idx < result.length) {
              const truncatedOverlayLine = visibleWidth(overlayLines[i]) > w ? sliceByColumn(overlayLines[i], 0, w, true) : overlayLines[i];
              result[idx] = this.compositeLineAt(result[idx], truncatedOverlayLine, col, w, termWidth);
          }
      }
  }
  ```
  `result[idx]` is the base/transcript line. The first visible overlay that
  opts in (`options.backdrop` is a number) wins, read once and forwarded.

- **L974–976** — `compositeLineAt` delegating to `compositeTuiLine` (extended
  with a trailing `backdrop` parameter).

`OverlayOptions` is not referenced in `tui.js`; it is a structural/mapped type
and the options object is stored verbatim in the overlay stack entry
(`showOverlay`, **L347–355**: `...(options === undefined ? {} : { options })`),
so new fields pass through untouched.

### `tui.d.ts` (385 lines)

- **L134** — `export interface OverlayOptions`; `nonCapturing?: boolean;` at **L160**.
- **L207** — `export declare function compositeTuiLine(...)`.

### Overlay options forwarding (pi-coding-agent)

`<store>/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js`
**L2193–2206** (`custom<...>()` overlay branch):

```js
const resolveOptions = () => {
    if (options?.overlayOptions) {
        const opts = typeof options.overlayOptions === "function"
            ? options.overlayOptions()
            : options.overlayOptions;
        return opts;
    }
    const w = component.width;
    return w ? { width: w } : undefined;
};
const handle = this.ui.showOverlay(component, resolveOptions());
```

Unknown fields are **already forwarded verbatim** — `opts` is passed straight to
`showOverlay` — so **no pi-coding-agent patch is needed**. The `OverlayOptions`
type it imports (`dist/core/extensions/types.d.ts` L124) now carries the new
field from the patched `tui.d.ts`.

## Change

Three edits in `tui.js`, two in `tui.d.ts`, all inside `/* pi-ui:backdrop */`
markers:

1. New helper `dimBaseLine(line, factor)` — regex-scales every truecolor
   `38;2;r;g;b` / `48;2;r;g;b` to `round(c*factor)`. Returns the line unchanged
   when factor is absent/0/1/non-finite or the line is a Kitty image.
2. `compositeTuiLine` gains a trailing `backdrop` param and dims the base line
   before slicing.
3. `compositeOverlays` finds the first visible overlay with a numeric
   `entry.options?.backdrop` and passes it; `compositeLineAt` forwards it.
4. `OverlayOptions` gains `backdrop?: number`.
5. `compositeTuiLine` declaration gains `backdrop?: number`.

ANSI has no alpha; RGB scaling toward black is the software-blend equivalent of
opentui's alpha blend. pi emits truecolor as standalone sequences
(`theme.js` `fgAnsi`/`bgAnsi` → `\x1b[38;2;${r};${g};${b}m`), which the regex
matches exactly.

Limitations:
- The dim is applied inside `compositeTuiLine`, i.e. only to the base row each
  overlay row is spliced onto. To dim the whole transcript, size the overlay to
  cover the terminal (e.g. `width: "100%", maxHeight: "100%"`); the T3 modal
  normally just dims the rows it sits on.
- With multiple overlapping overlays that all opt in, the dim applies once per
  composite, so overlapping rows compound. Fine for a single questions modal.
- Only truecolor (`38;2` / `48;2`) sequences are scaled. When pi runs in
  256-colour mode (`fgAnsi` returns `38;5;N`) the backdrop has no effect; the
  primary pi-ui target terminal is truecolor.

## Opt-in usage (T3 questions modal)

```js
const result = await ctx.ui.custom(
  (tui, theme, keybindings, done) => new QuestionsComponent(tui, theme, keybindings, done),
  { overlay: true, overlayOptions: { backdrop: 0.5 } }, // 0 = no dim, 1 = black
);
```

`backdrop` may also be a function returning options:
`overlayOptions: () => ({ backdrop: 0.5 })`.

## Verify

```sh
cp -r /nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1 /tmp/pi-t9
chmod -R u+w /tmp/pi-t9
node pi-patches/pi-tui-backdrop.mjs /tmp/pi-t9   # patch
node pi-patches/pi-tui-backdrop.mjs /tmp/pi-t9   # no-op (idempotent)
node /tmp/pi-t9/lib/node_modules/pi-monorepo/dist/cli.js --version
```

Node unit check (primary proof): imports the patched `compositeTuiLine` and
asserts default output is unchanged and that a backdrop factor scales the base
line's truecolor values while the overlay line is untouched.
A full visual TUI check is not possible headlessly.
