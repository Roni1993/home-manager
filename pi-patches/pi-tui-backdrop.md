# pi-tui opt-in dimmed backdrop (pi-ui T9)

Local patch for **pi-coding-agent 0.85.1** that adds an opt-in dim factor for the
transcript behind an overlay, so the T3 questions modal can darken the chat
behind it. Default behaviour with no flag is byte-identical (verified by
differential render against stock across 15 overlay configurations).

## Root-cause history (why the first version did nothing)

The first version dimmed the base line *inside* `compositeTuiLine`, i.e. only the
base row each overlay line is spliced onto. But `compositeTuiLine` **discards**
the base columns the overlay covers — it keeps only `base.before` / `base.after`
(left/right gutters) and draws the overlay text opaquely in the middle
(`tui.js` L145–152). Consequences:

- A full-width overlay (`width: "100%"`, or the default
  `width = min(80, termWidth)` on an ≤80-col terminal) covers the entire row, so
  there is **no base pixel left to dim**. `width: "100%"` makes it strictly
  worse, not better.
- Even with a narrow overlay, only the gutter columns dim, and only on the rows
  the overlay sits on. Rows above/below the modal never dim.

This patch moves the dim to the correct seam: `compositeOverlays` dims the whole
base buffer **once**, then splices the overlays on top. The modal stays opaque
over its own rectangle; everything around it (above, below, and beside) is
dimmed — the conventional modal backdrop. It works for any overlay width.

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

- **L132** — `/** Composite overlay content into a terminal line at a fixed
  column. */`. The helper `dimBaseLine(line, factor)` is inserted immediately
  before it (module-local, not exported). It regex-scales every truecolor
  `38;2;r;g;b` / `48;2;r;g;b` to `round(c*factor)`, and returns the line
  unchanged when `factor` is absent / `<= 0` / `>= 1` / non-finite / an image
  line.
- **L950** — the `// Composite each overlay` comment inside
  `compositeOverlays`, immediately before the splice loop
  (`for (const { overlayLines, row, col, w } of rendered) {`). The patch inserts,
  before the loop:

  ```js
  const backdrop = rendered.find((r) => typeof r.entry.options?.backdrop === "number")?.entry.options.backdrop;
  if (typeof backdrop === "number") {
      for (let i = 0; i < result.length; i++)
          result[i] = dimBaseLine(result[i], backdrop);
  }
  ```

  `result` is the base buffer already padded to terminal height, so this dims
  every base row once per frame. The splice loop then composites the opaque
  overlays on top.

No change to `compositeTuiLine` / `compositeLineAt` signatures in this version.

### `tui.d.ts` (385 lines)

- **L160** — `nonCapturing?: boolean;` in `export interface OverlayOptions`
  (L134). `backdrop?: number;` is added after it.

### Overlay options forwarding (pi-coding-agent)

`<store>/lib/node_modules/pi-monorepo/dist/modes/interactive/interactive-mode.js`
**L2195–2206** (`showExtensionCustom` overlay branch):

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

The type is declared at `dist/core/extensions/types.d.ts` L124
(`overlayOptions?: OverlayOptions | (() => OverlayOptions);`). Unknown fields
pass through verbatim: `showOverlay` stores the options object unchanged
(`tui.js` L347–355, `...(options === undefined ? {} : { options })`) and
`compositeOverlays` reads `entry.options?.backdrop` directly. **No
pi-coding-agent patch is needed**; a numeric `backdrop` survives verbatim.

## Change

Two edits in `tui.js`, one in `tui.d.ts`, all inside `/* pi-ui:backdrop */`
markers:

1. New module-local `dimBaseLine(line, factor)` helper (truecolor scaling).
2. `compositeOverlays` dims the whole base buffer once when any visible overlay
   carries a numeric `options.backdrop` (first by focus order wins), before the
   overlay splice loop.
3. `OverlayOptions` gains `backdrop?: number`.

ANSI has no alpha; RGB scaling toward black is the software-blend equivalent of
opentui's alpha blend. pi emits truecolor as standalone sequences
(`theme.js` `fgAnsi`/`bgAnsi` → `\x1b[38;2;${r};${g};${b}m`), which the regex
matches exactly.

Limitations:
- The whole base buffer is dimmed once per frame while a numeric `backdrop`
  overlay is visible. Cost is one regex pass per rendered line per frame;
  negligible for a modal, measurable only on very large transcripts.
- With multiple overlapping overlays that opt in, the first (bottom-most by
  focus order) factor wins; the dim is applied once, so rows do not compound.
- Only truecolor (`38;2` / `48;2`) sequences are scaled. A theme that defines
  colours as palette **numbers** emits `38;5;N` even on a truecolor terminal
  (`theme.js` L104–105, L121–122), and a 256-colour-only terminal emits
  `38;5;N` throughout — in both cases the backdrop silently no-ops. The primary
  target (default `dark` theme, `COLORTERM=truecolor`/kitty) emits truecolor;
  verified `capabilities.trueColor === true`, `theme.mode === "truecolor"`.

## Opt-in usage (T3 questions modal)

```js
const result = await ctx.ui.custom(
  (tui, theme, keybindings, done) => new QuestionsComponent(tui, theme, keybindings, done),
  { overlay: true, overlayOptions: { anchor: "center", maxHeight: "90%", backdrop: 0.5 } }, // 0 = no dim, 1 = black
);
```

A numeric factor is all that is required. `width` is irrelevant to the backdrop
now (a full-width overlay is fine; rows not covered by it still dim). `backdrop`
may also be a function returning options:
`overlayOptions: () => ({ anchor: "center", backdrop: 0.5 })`.

## Verify

```sh
cp -r /nix/store/m58mjsdjgk3zrwar1ckw2lb4q241l7j9-pi-coding-agent-0.85.1 /tmp/pi-t9
chmod -R u+w /tmp/pi-t9
node pi-patches/pi-tui-backdrop.mjs /tmp/pi-t9   # patch (2 js anchors, 1 dts)
node pi-patches/pi-tui-backdrop.mjs /tmp/pi-t9   # no-op (idempotent)
node /tmp/pi-t9/lib/node_modules/pi-monorepo/dist/cli.js --version
```

Real-path harness (not a synthetic call): instantiate the patched `TuiBase`,
`showOverlay(component, { backdrop: 0.5, ... })`, then call
`compositeOverlays(baseLines, width, height)` and assert on the emitted ANSI.
Expected with an 80-col terminal and a 10-row centered overlay: all 14 rows
outside the overlay carry `38;2;100;50;25` (200,100,50 scaled by 0.5); the 10
overlay rows carry the untouched overlay text. With no `backdrop`, output is
byte-identical to stock. A full interactive TUI check is not possible headlessly.
