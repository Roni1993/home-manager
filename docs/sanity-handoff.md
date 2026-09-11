# Sanity Handoff — CachyOS gaming / Nix hybrid setup

Handoff for the deep sanity/cleanup/review (#21). Written 2026-08-07 by the
main agent from the working session; the `frontier` agent (Kimi K3) reviews
against this doc + the repo.

## Overview

Hyprland desktop on **CachyOS**, config split across two worlds:

- **system / pacman / CachyOS** — the OS, kernel, NVIDIA driver, and the
  GPU/GL-heavy apps that fail to build under Nix on NVIDIA.
- **Nix + Home-Manager** — the `fleek` flake (this repo), applied with
  `nix run .#apply-gaming`. Manages HM config, matugen templates, most app
  configs, scripts, systemd user services.

Theming is a custom **matugen pipeline** (wallpaper → Material palette →
per-app configs). The setup is intended to be the user's **long-term daily
driver**.

## Hardware / OS / driver

- CachyOS, kernel 7.1.6, **NVIDIA** (driver 610.57.04, `nvidia_drm.modeset=1`).
- 4K monitor on HDMI-A-2 (3840x2160@60).
- btrfs root subvolume `@` (mounted `/`), separate `@home` for `/home`.

## Windowing & session

- Hyprland **system** (pacman) — nix builds abort on NVIDIA. Logged in via
  plasmalogin autologin → Hyprland.
- Waybar + swaync started by **HM systemd user services** (NOT exec-once —
  a second launch makes the service fail "instance already running" → start-limit).
- hypridle, vicinae server, awww-daemon (wallpaper), hyprpolkitagent,
  playerctld run via exec-once.
- Launcher = **Vicinae** (`vicinae-bin` AUR). Power menu = `.desktop` entries.
- Clipboard history = **vicinae native** `clipboard:history` on **Super+V**
  (input_server pastes to active window). cliphist was removed (redundant).

## Theming pipeline (matugen)

- `~/.config/matugen/palette.py` (vendored in repo) samples the wallpaper,
  dumps a Material `scheme-expressive` palette + custom ANSI roles
  (`colors.red/green/yellow/blue/magenta/cyan` + `*_bright`) into
  `~/.cache/matugen/scheme.json`, solves WCAG contrast per hue, then renders
  the HM-managed `config.toml` (material-role templates) and `kitty.toml`
  (custom-ANSI templates, post-patch). Caching off.
- `apply-theme.sh` = regenerate + `hyprctl reload` + reload waybar/swaync/kitty.
  Called at login (3s sleep) and by `theme-toggle` (Super+T) and
  `set-wallpaper`/`rotate-wallpaper.sh` (Super+W, 4h systemd timer).
- **Invariant: templates using custom ANSI roles live in kitty.toml;
  material-only templates live in config.toml.** matugen cannot create parent
  dirs → HM `.keep` files required.
- `theme-toggle` flips `gsettings color-scheme` (GTK/Qt follow); vicinae theme
  applied via config.toml post_hook (`vicinae theme set matugen`).

## System-vs-Nix seams (the seams frontier should investigate)

- **System (pacman/CachyOS):** Hyprland, hyprlock, hyprshot, hyprpicker, awww,
  kitty, ghostty, vicinae (AUR), Steam, gamescope, gamemode, mangohud, nvtop,
  gwe, fuzzel was tried+removed. Reason: nix GPU builds abort on NVIDIA EGL.
- **Nix/HM:** waybar, swaync, alacritty, btop, micro, nvim, helix, zed, Firefox
  (VA-API via LIBVA_DRIVER_NAME=nvidia), spicetify/Spotify, vesktop, matugen,
  devbox shells, all scripts (apply-theme/theme-toggle/set-wallpaper/
  rotate-wallpaper/idle-toggle), systemd user services, opencode config
  (incl. the `frontier` agent), ~/.config for everything above.
- **Matugen-owned runtime files** (generated, not HM): `hyprland-colors.conf`,
  `hyprlock-colors.conf`, waybar `style.css`, swaync `style.css`, kitty/ghostty/
  alacritty colors, btop/micro/nvim/helix themes, spicetify `color.ini`,
  vesktop theme, zed theme, steam.css, vicinae theme. All regenerable from
  `profiles/matugen/*.tmpl`.
- Known seam risks: version drift (system vs nix packages), hard-coded paths
  (`~/.local/bin/apply-theme.sh`, nix-store symlinks for HM-managed configs,
  `hyprland.conf` is an immutable nix-store symlink so some binds live in the
  matugen-generated `hyprland-colors.conf` instead), NVIDIA driver/kernel
  coupling (a reboot fixed an API mismatch that broke hyprlock typing).

## Backups / reproducibility

- **Snapper root** (`@`, covers `/nix`): manual + pacman pre/post snapshots,
  cleanup to 50. `first-good-snapshot` created (2026-08-07).
- **Snapper home** (`@home`, separate subvolume): added 2026-08-07,
  `TIMELINE_CREATE=yes` (hourly).
- **/nix "backup" = rebuildability**: `flake.lock` committed; whole env from
  `nix run .#apply-gaming`.
- **Config backup**: HM config + templates in repo, mirrored on GitHub.
- **Off-machine**: GitHub mirror + #16 paper/QR backup (SSH + sops age key).

## Board state (fleek repo issues)

- #5 map (open). #12 HDD→RPI migration (open, blocked on Pi prep). #20 quick
  wins (open). #21 this review (open). #16/#17/#18/#19 closed.

## Known risks / watch items

- NVIDIA driver 610.57.04 ↔ kernel 7.1.6 coupling (re-verify hyprlock typing
  + VA-API after kernel/driver updates).
- Spotify-launcher produces `~/core.*` core dumps (gitignored only).
- Steam CSS Loader plugin install is pending (HITL) for the matugen Steam theme.
- HITL confirmations pending: game-under-Proton run, mangohud overlay, gwe/nvtop
  render, GParted polkit prompt.

## Stated invariants (flag contradictions)

1. System Hyprland/kitty/ghostty on NVIDIA (nix GPU builds abort).
2. Vicinae = launcher + clipboard history (Super+V).
3. matugen theming everywhere; runtime files matugen-owned.
4. waybar + swaync via HM systemd services, no exec-once.
5. `theme-toggle` flips gsettings; light/dark supported.

## What frontier should do

1. Summarise + sanity-check the whole setup against this doc and the repo.
2. Investigate the CachyOS-vs-Nix seams & interactions for correctness,
   drift, breakage risk, and cleanup opportunities.
3. Propose prioritised long-term improvements (P0/P1/P2); apply safe/trivial
   fixes directly, report structural recommendations.
4. Flag anything contradicting the invariants.
