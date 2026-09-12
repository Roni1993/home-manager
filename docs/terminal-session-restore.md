# Terminal session restore across a full reboot — 2026 state of the art

**Verdict first.** Run **tmux + tmux-resurrect + tmux-continuum** managed by a **systemd user service with `loginctl enable-linger`** (declared from home-manager). That is the only mainstream stack where sessions come back *automatically* after a hard reboot. Zellij has **on-disk session persistence since 0.39.0** (built-in "resurrection"), so the common claim "zellij has no on-disk persistence" is **outdated** — but zellij's restore is *semi-manual* (pick the session from the welcome screen / session manager), not fully automatic, and has known bugs on restore.

**Verified on:** 2026-09-08 (all links fetched live on this date).

---

## Quick comparison

| Tool | On-disk save | Auto-restore after reboot | Restore scope | Maintenance |
|---|---|---|---|---|
| **tmux + resurrect + continuum** | Yes (every 15 min + manual) | **Yes** (continuum: tmux auto-start + auto-restore) | layout, cwd, active panes, re-launch listed programs; not process state | resurrect HEAD commit 2023-03-06; continuum 2024-01-20; stable, unarchived, 13k/4.1k stars |
| **zellij (0.45.1)** | Yes, built-in (every ~1 min + explicit save) | **No** (manual: welcome screen / session manager resurrect) | tabs/panes, cwds, re-run recorded commands; not process state | active: v0.45.1 2026-08-28; active roadmap |
| **tmuxp / tmuxinator / smug** | No save-from-live (tmuxp `freeze` can snapshot) | No (config files; you wire a login hook) | predefined session layout | all maintained 2026 (tmuxp v1.74.0, tmuxinator v3.4.1, smug v0.3.19) |
| **kitty** | Yes: session files + **`save_as_session` since 0.43** | No (launch with `--session <file>`) | windows/tabs/layout + launch commands | very active (0.48.2, 2026-07-30) |
| **ghostty** | macOS only (`window-save-state`); **no Linux restore** | No | macOS: windows/tabs | active (v1.3.1) |
| **wezterm** | Mux server keeps panes alive while it runs; no reboot restore | No | nothing after reboot | active |
| **tty7 (2025-2026)** | Claims "quit or reboot; shells keep running" (background server) | Claims yes ("resume after reboot") | shells + supported agent sessions | new, pre-1.0, 846 stars |

---

## 1. Zellij — the "no persistence" claim is outdated, but not fully solved

**Current stable release: v0.45.1, released 2026-08-28.**
https://github.com/zellij-org/zellij/releases/tag/v0.45.1

### Built-in session resurrection (since 0.39.0, Nov 2023)

Official release post, **verified 2026-09-08**:

> "Zellij now includes built-in session resurrection capabilities. This means that **Zellij sessions can be restored after reboots or graceful quits**. Attaching to an exited session will resurrect it, allowing users to keep long-running named workspaces. Sessions are serialized as **Human readable Zellij layouts**, so they can also be shared across machines."

— https://zellij.dev/news/session-resurrection-ui-components/

Mechanics, from the changelog and default config (**verified** on the `main` branch):

- **On-disk save is ON by default.** `session_serialization` defaults to `true`; the config comment says sessions are "serialized to the cache folder (including their tabs/panes, cwds and running commands) so that they can later be resurrected" — https://github.com/zellij-org/zellij/blob/main/zellij-utils/assets/config/default.kdl (a commented-out `session_serialization false` line shows how to disable).
- Snapshots land in the cache dir (`~/.cache/zellij/` on Linux; users reference it e.g. in https://github.com/zellij-org/zellij/issues/3663 and https://github.com/zellij-org/zellij/issues/3374).
- Serialized automatically on an interval — default reduced to **1 minute** and made configurable (PR #2923) — plus an **explicit save** command (PR #4654, "allow explicitly saving current session for resurrection rather than waiting on the resurrection interval"). Both in https://github.com/zellij-org/zellij/blob/main/CHANGELOG.md
- Since **v0.44.0 (2026-03-23)** sessions are compatible across zellij versions (protobuf client/server contract, PR #4439), and the session-manager UI lists and resurrects "exited" sessions — https://github.com/zellij-org/zellij/blob/main/CHANGELOG.md ; release notes at https://github.com/zellij-org/zellij/releases/tag/v0.44.0

### How restore works (and why it's not "automatic")

- Restore is a **manual pick**: the welcome screen / session manager lists exited sessions; typing a name that has exited **resurrects** it. Official tutorial, verified: https://zellij.dev/tutorials/session-management/ ("If the session exists, we will attach to it. If it has exited, we will resurrect it. Otherwise, we will start a new session."). FAQ: https://zellij.dev/faq/
- There is **no continuum-style "auto-resurrect everything at login"** built in. `zellij setup` can generate shell **autostart** code (attach-or-create in every new shell; a Nushell variant exists — https://github.com/zellij-org/zellij/pull/3206), but it has had real-world issues (login hangs/black screen: https://github.com/zellij-org/zellij/issues/3327, https://github.com/zellij-org/zellij/issues/5132). Autostart ≠ boot restore; after a reboot you still open a terminal and attach/resurrect.

### Known restore bugs (open, verified 2026-09-08)

- Restore can drop tabs (https://github.com/zellij-org/zellij/issues/3752) and resurrected nvim launches without config (https://github.com/zellij-org/zellij/issues/3156).
- A reported cwd-loss-on-restore-after-reboot was **fixed/closed** (https://github.com/zellij-org/zellij/issues/3374, closed 2025-11-10) — good signal the flow works across reboot in 0.40.x+.
- Open feature asks: "Resurrect process with a shell instance" (https://github.com/zellij-org/zellij/issues/4485).

### Plugins

- No third-party "resurrect plugin" is needed or prominent (verified via repo search, 2026-09-08) — persistence is built in. Plugin API grew in 0.44 (read pane scrollback, explicit session save) — https://github.com/zellij-org/zellij/releases/tag/v0.44.0

### "zellij as a systemd service + attach" pattern

- Zellij is a TUI (client+server in one binary); there is no supported headless systemd server like tmux's `new-session -d`. The practical pattern is: **terminal emulator opens `zellij` (optionally `zellij -l welcome`) per window**; the session server keeps running between window closures; after a reboot you attach/resurrect from the welcome screen. Server flag discussion/CLI docs: https://zellij.dev/documentation/controlling-zellij-through-cli.html

---

## 2. tmux + tmux-resurrect + tmux-continuum — the automatic option

Both plugins are in the official **tmux-plugins** GitHub org.

### tmux-resurrect
- Repo tagline: "Persists tmux environment across system restarts." — https://github.com/tmux-plugins/tmux-resurrect
- **Maintenance (verified):** default-branch HEAD commit **2023-03-06** (last repo push 2024-08-13); 13k stars, not archived. Stable and unmaintained-in-practice but still the standard.
- Restores: all sessions/windows/panes + order, **cwd per pane**, exact layouts, active/alt session/window, **programs running in a pane** — README: https://github.com/tmux-plugins/tmux-resurrect#about
- **What it does NOT restore:** process state. Restore = **re-launch the recorded command line** in the saved cwd/layout. Only a conservative default list is re-launched (`vi vim nvim emacs man less more tail top htop irssi weechat mutt`); everything else needs `@resurrect-processes`; `':all:'` is documented as dangerous (it will blindly re-run any saved command, e.g. a `sudo mkfs.vfat`): https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_programs.md
- Optional: vim/nvim session restore and pane-contents (scrollback) restore — https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_vim_and_neovim_sessions.md, https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_pane_contents.md

### tmux-continuum
- Provides: continuous save (every 15 min), **automatic tmux start at boot**, and **automatic restore when tmux starts** — https://github.com/tmux-plugins/tmux-continuum
- Maintenance (verified): HEAD commit **2024-01-20**, 4.1k stars.
- Auto-restore triggers **exclusively on tmux server start**; enable with `set -g @continuum-restore 'on'`. Continuous save needs the status line on (uses `status-right`; a theme overwriting `status-right` breaks autosave — documented known issue in the README).
- **Linux/systemd auto-start is built in**: continuum generates and enables a user unit at `~/.config/systemd/user/tmux.service` (default `ExecStart=tmux new-session -d`, configurable via `@continuum-systemd-start-cmd`; control with `systemctl --user status tmux.service`): https://github.com/tmux-plugins/tmux-continuum/blob/master/docs/systemd_details.md and https://github.com/tmux-plugins/tmux-continuum/blob/master/docs/automatic_start.md
- macOS boot options include `kitty`, `alacritty`, `iterm` (launchd-based) — same doc.

**Net effect:** with continuum you get *exactly* "comes back automatically after full reboot" — tmux server starts at login/boot and immediately resurrects the last saved environment.

---

## 3. Config-file-based session managers (rebuild predefined sessions)

All three are **maintained in 2026** (verified HEAD/releases, 2026-09-08):

- **tmuxp** — HEAD commit 2026-09-05, v1.74.0 (2026-07-04); 4.5k stars. https://github.com/tmux-python/tmuxp — and notably it can **snapshot a live tmux session to a file** with `tmuxp freeze` (source: `src/tmuxp/cli/freeze.py`, docs `docs/cli/freeze.md`).
- **tmuxinator** — HEAD 2026-07-10, v3.4.1 (2026-07-03); 13.7k stars. https://github.com/tmuxinator/tmuxinator
- **smug** — HEAD 2026-06-30, v0.3.19 (2026-06-30); 912 stars. https://github.com/ivaaaan/smug

These rebuild a *defined* layout (sessions/windows/panes/cwds/commands) on demand; none save runtime state. **Auto-run-at-boot is not built in** — you wire it yourself (a systemd user unit or login hook that runs `tmuxp load <ws>` / `tmuxinator start <proj>`).

---

## 4. New tools (2024-2026) and the "can't survive reboot" question

### Arbitrary processes cannot survive a reboot — confirmed
Reboot terminates the kernel and all userspace: `reboot(2)` documents that on `LINUX_REBOOT_CMD_RESTART` the init (PID 1) process is terminated and everything under it dies — https://man7.org/linux/man-pages/man2/reboot.2.html. **Restore therefore always means "re-invoke from recorded state."** The only true process checkpoint/restore is **CRIU** (https://criu.org/Main_Page), used in containers, and **no mainstream terminal multiplexer uses it**.

### What's actually new
- **tty7** (`l0ng-ai/tty7`) — Rust "terminal workbench"; a **background server owns shells/panes**; README claims *"Persistent sessions — quit or reboot; your shells and supported agent sessions keep running, no tmux"* and *"resume after reboot"* for supported coding-agent CLIs (Claude Code, Codex…). 846 stars, very active (pushed 2026-09-08), **pre-1.0**. https://github.com/l0ng-ai/tty7 — closest thing to native reboot persistence in a terminal, but young.
- Trendy 2026 "agent terminal" projects exist (herdr 36k stars https://github.com/herdrdev/herdr, cmux 26k Ghostty-based https://github.com/manaflow-ai/cmux, horizon 705 stars GPU "infinite canvas" https://github.com/peters/horizon) — agent-centric, not verified for full terminal session restore.
- **No new multiplexer has displaced tmux-resurrect or zellij-resurrection** for reboot persistence of plain terminal sessions.

---

## 5. Terminal-emulator level

- **kitty** — session **files** have long defined windows/tabs at startup. **New since 0.43 (2025): snapshot-from-live** — "create and switch between sessions with a single keypress and also to manually setup some tabs/windows in kitty and **save it as a session file**" via the `save_as_session` action; 0.46+ preserved visual tab order/active tab and added `--base-dir`, `focus_tab`, and auto-`.kitty-session` extension. Verified in the changelog: https://sw.kovidgoyal.net/kitty/changelog/ (current release **0.48.2, 2026-07-30**). Restore by relaunching `kitty --session <file>` (docs: https://sw.kovidgoyal.net/kitty/sessions/). It restores the **layout + launch commands, not process state**, and there is no auto-restore-after-reboot.
- **ghostty** — `window-save-state` exists but is **macOS-only** (Apple `NSWindowRestoration`). Linux/GTK equivalent is an open feature request with official "wait for GTK" position (https://github.com/ghostty-org/ghostty/discussions/12055); a community **stop-gap PR was closed unmerged** (https://github.com/ghostty-org/ghostty/pull/12962). Latest tag v1.3.1. **No Linux session restore as of 2026.**
- **wezterm** — has a built-in **mux server** (background process owning panes; the CLI prefers talking to the GUI instance or the "background mux server", see changelog https://wezterm.org/changelog.html). Panes survive closing the GUI while the server runs (built-in detach), but the server is a userspace process **killed by reboot**; wezterm has **no resurrect**. The sanctioned persistence is a user-built Lua "Workspaces / Sessions" recipe: https://wezterm.org/recipes/workspaces.html

---

## 6. Recommendation for this stack (CachyOS/Arch, Hyprland, kitty, nushell, home-manager)

### Do this: tmux + resurrect + continuum, systemd user service + linger, from home-manager

1. **tmux + plugins.** In `programs.tmux` (home-manager `modules/programs/tmux.nix` has a `plugins` option — https://github.com/nix-community/home-manager/blob/master/modules/programs/tmux.nix), load `tmux-plugins/tmux-resurrect` + `tmux-plugins/tmux-continuum` via TPM, with:
   ```
   set -g @continuum-restore 'on'
   set -g @continuum-boot 'on'
   set -g @resurrect-processes 'opencode nushell devbox'
   ```
   Add your real programs to `@resurrect-processes` (default list is tiny — see §2). `@continuum-boot 'on'` makes continuum generate + enable `~/.config/systemd/user/tmux.service` so tmux starts at login and **auto-restores on server start** (docs: https://github.com/tmux-plugins/tmux-continuum/blob/master/docs/systemd_details.md).

2. **`loginctl enable-linger`** — required if you want restore to happen **at boot before you log in graphically** (the whole point of "full reboot → back automatically"). Primary definition: "If enabled for a specific user, **a user manager is spawned for the user at boot and kept around after logouts**… allows users who are not logged in to run long-running services" — https://www.freedesktop.org/software/systemd/man/latest/loginctl.html. **home-manager has no linger option** (verified: no `linger` in the source tree, 2026-09-08), so set it once (`loginctl enable-linger $USER`) — or via a system-level module — and declare the user service declaratively:
   - `systemd.user.services` option in home-manager (`modules/systemd.nix` — https://github.com/nix-community/home-manager/blob/master/modules/systemd.nix) to declare/own the tmux service and any attach-time services.
   - With linger on, user services start against `default.target` at boot even with no session, so a `WantedBy=default.target` service running `tmux new-session -A -s main` resurrects before Hyprland even starts.

3. **kitty layout.** Point kitty at a session file that opens the windows you want (e.g. one window per workspace), each running `tmux new-session -A -s <name>` (or just `tmux attach`), so the GUI comes back too. Use kitty's **`save_as_session`** (since 0.43) to capture your current tab/window setup into `~/.config/kitty/session` (https://sw.kovidgoyal.net/kitty/sessions/).

4. **nushell caveat.** Nushell isn't bash; put the tmux/attach command in a nushell-friendly startup (e.g. an env-file or `startup` hook), or keep kitty launching tmux directly. Zellij's `zellij setup` autostart covers nushell via PR https://github.com/zellij-org/zellij/pull/3206, but the tmux route avoids that integration.

### Pitfalls (all verified / documented)

- **Boot ordering & mounts.** A user service starting at boot may run before network/`$HOME` mounts; programs restored before their cwd/tools exist will fail. tmux-resurrect re-runs commands immediately — if a mount isn't up, the pane dies. Mitigate with `After=`/`Wants=` on your mount/network units and `Restart=on-failure`, or accept re-running the failed pane.
- **User-service environment.** systemd user units don't inherit your login-shell env (nushell `env.nu`, mise/devbox PATH etc.). Restored commands launched by tmux-resurrect run under tmux's server env — export what you need via `systemd.user.services.*.environment` / `programs.tmux.extraConfig` `set-environment`, or absolute paths. (Home-manager `systemd.user.services` supports `environment`.)
- **Resurrect only re-invokes command lines**, not process state (§2). Shell panes come back at the right cwd with a fresh shell; long-running interactive state (in-progress builds, devbox shells mid-command, opencode agent *conversation state*) is **not** restored — the process is re-started. Coding agents that support `--continue`/resume can be made to resume manually; nothing auto-resumes them across reboot today (except tty7's agent hooks, §4).
- **`':all:'` is dangerous** — it re-runs every saved commandline blindly (§2, restoring_programs.md).
- **Zellij alternative:** if you prefer zellij, its **built-in resurrection survives reboot** (snapshots on disk, §1) — you just pick the session from the welcome screen after boot; there is no continuum-style auto-restore, and restore bugs (#3752, #3156) are still open. For *automatic* return, tmux wins.

---

## Sources index

- Zellij: releases https://github.com/zellij-org/zellij/releases/tag/v0.45.1 · resurrection post https://zellij.dev/news/session-resurrection-ui-components/ · tutorial https://zellij.dev/tutorials/session-management/ · FAQ https://zellij.dev/faq/ · default.kdl https://github.com/zellij-org/zellij/blob/main/zellij-utils/assets/config/default.kdl · CHANGELOG https://github.com/zellij-org/zellij/blob/main/CHANGELOG.md · issues #575 #1468 #3663 #3374 #3752 #3156 #4485 #3327 #5132 · PRs #2923 #3206 #4439 #4654
- tmux: resurrect https://github.com/tmux-plugins/tmux-resurrect (+docs/restoring_programs.md, restoring_pane_contents.md, restoring_vim_and_neovim_sessions.md) · continuum https://github.com/tmux-plugins/tmux-continuum (+docs/automatic_start.md, docs/systemd_details.md)
- Managers: tmuxp https://github.com/tmux-python/tmuxp · tmuxinator https://github.com/tmuxinator/tmuxinator · smug https://github.com/ivaaaan/smug
- New: tty7 https://github.com/l0ng-ai/tty7 · herdr https://github.com/herdrdev/herdr · cmux https://github.com/manaflow-ai/cmux · horizon https://github.com/peters/horizon · CRIU https://criu.org/Main_Page
- Emulators: kitty sessions https://sw.kovidgoyal.net/kitty/sessions/ · kitty changelog https://sw.kovidgoyal.net/kitty/changelog/ · ghostty discussion #12055, PR #12962, issue #1847, config ref https://ghostty.org/docs/config/reference · wezterm https://wezterm.org/recipes/workspaces.html, https://wezterm.org/changelog.html
- Wiring: loginctl(1) https://www.freedesktop.org/software/systemd/man/latest/loginctl.html · reboot(2) https://man7.org/linux/man-pages/man2/reboot.2.html · home-manager modules/systemd.nix & modules/programs/tmux.nix https://github.com/nix-community/home-manager
