# CachyOS Gaming PC — Progress Tracker

## Legend
- `[x]` Done
- `[ ]` Not started
- `[~]` Blocked

---

## Phase 0 — Decisions (grill-me session) ✓

- [x] Base OS: **CachyOS** (ADR-0001)
- [x] Window manager: **Hyprland**
- [x] Bar/panel: **waybar**
- [x] Notification daemon: **swaync**
- [x] Launcher: **Vicinae** (nix Qt build can't init GL on NVIDIA — AUR vicinae-bin)
- [x] Lockscreen: **hyprlock**
- [x] Wallpaper daemon: **awww** (set-wallpaper script drives awww + matugen)
- [x] Idle manager: **hypridle**
- [x] Output management: **nwg-displays**
- [x] Clipboard: **vicinae native `clipboard:history`** (Super+V; cliphist was tried then removed as redundant — wl-clipboard stays for CLI)
- [x] Theming: **matugen** (Material-You palette from wallpaper; Super+T light/dark)
- [x] Night-light: **not needed** (theme toggle handles light/dark)
- [x] Terminal: **kitty** (primary) + **ghostty** (secondary)
- [x] Browser: **Firefox** (HM-managed)
- [x] Screenshot: **hyprshot** (grim+slurp wrapper)
- [x] File manager: **Dolphin** (from CachyOS KDE)
- [x] Polkit agent: **hyprpolkitagent**
- [x] Fonts: **JetBrains Mono Nerd Font + Noto**
- [x] Gaming tools: **gamemode + gamescope + mangohud + goverlay + protonup-qt**
- [x] NVIDIA tools: **nvtop + gwe**
- [x] Audio: **pavucontrol**
- [x] Storage: **Both drives** — active games on NVMe, library overflow on HDD
- [x] Nix install method: **Determinate installer**
- [x] Steam Deck UI: **gamescope-session-git** from AUR
- [x] Reproducibility: **bootstrap.sh** handles all system setup post-install

## Phase 1 — OS Installation (manual)

- [x] Download CachyOS ISO (KDE variant) → `cachyos-desktop-linux-260628.iso`
- [x] Flash ISO to USB → `/dev/sdf` (Kingston DataTraveler 3.0, COS_202606)
- [x] Pre-wipe backup staged to `D:\backup-for-cachyos\` (HDD, survives transition):
  - `wsl-keys/` — WSL SSH ed25519 key + sops age key
  - `firefox-profile/` — Firefox profile (404MB)
  - `windows-c/` — Windows C: irreplaceables (8.3MB): `.ssh` RSA key + known_hosts, house-purchase PDFs (Dragonstraat 24 Utrecht), ZMK corne firmware (UF2 + kernel patches), GitHub token + opencode auth
  - DECIDED to skip: other WSL distros (Debian/Ubuntu-20.04) uncommitted work, 168GB LLM models, game saves (Steam Cloud), Unreal/Godot projects
- [ ] Update BIOS (optional, recommended) — v2405 .CAP on USB sdf3 via EZ Flash 3
- [x] Boot from USB, run Calamares installer:
  - Partition NVMe 2TB: `/boot/efi` (1 GB, fat32) + `/` (rest, Btrfs)
  - Leave HDD 4TB untouched (bootstrap handles it)
  - Create user `roni`
- [x] Reboot into KDE session

## Phase 2 — Bootstrap (automated)

- [x] Push fleek changes to GitHub: `git push`
- [x] Open Konsole, run: `curl -sL https://raw.githubusercontent.com/Roni1993/fleek/main/bootstrap.sh | bash`
- [x] Bootstrap handles:
  - System update
  - base-devel + git
  - paru (AUR helper)
  - `cachyos-gaming-meta`
  - `gamescope-session-cachyos` (prebuilt CachyOS repo — NOT AUR, research #15)
  - `hyprpolkitagent` (Arch `extra`)
  - System Hyprland stack (`hyprland hyprlock hypridle hyprshot hyprpicker awww`) — nix builds crash on NVIDIA EGL/GBM
  - GUI apps with own GL renderers (`kitty ghostty discord mangohud`) as system builds
  - HDD mounted read-only at `/mnt/staging` (NTFS untouched, per #6; reformat to `/mnt/games` is #12)
  - NVIDIA driver verification
  - Determinate Nix install
  - Nix flakes enable
  - fleek clone + `nix run .#apply-gaming`
  - Hyprland login session registration + plasmalogin/SDDM autologin
  - All HM-managed tools installed

## Phase 3 — Verification

- [x] **Restore WSL keys from HDD**: `wsl-keys/keys.txt` → `~/.config/sops/age/keys.txt`, SSH keypair → `~/.ssh/` (id_ed25519 + .pub), perms 600. Note: old key is removed from GitHub — rotation pending.
- [x] **Import Firefox profile**: curated copy of `D:\backup-for-cachyos\firefox-profile\` into `~/.mozilla/firefox/roni/` per research #8 (places, favicons, logins+key4 pair, extensions, storage, prefs, cookies, certs). **Gotcha (fixed 2026-08-08)**: the raw `cp` of `places.sqlite` while its WAL/SHM were present produced a corrupt DB — Firefox silently stopped storing history. Correct procedure: with Firefox **closed**, copy the SQLite files via `sqlite3 src.db ".backup 'dest.db'"` (consistent snapshot) and delete the destination's `places.sqlite-wal`/`-shm`/`favicons.sqlite-wal`/`-shm`. Verified: 17,565 visits restored, `PRAGMA integrity_check` = ok.
- [x] Reboot, autologin lands in **Hyprland** (system 0.56.1), login
- [x] Verify WM starts, waybar renders
- [x] Verify: swaync (notifications), vicinae (Super+Space), hyprlock (Super+L) — #18; swaync double-launch fixed
- [x] Verify: awww wallpaper + clipboard history — #18; cliphist replaced by vicinae native `clipboard:history` (Super+V)
- [x] Verify: kitty terminal with nushell — #18
- [x] Verify: Firefox with Wayland flags (MOZ_ENABLE_WAYLAND) — profile imported, dual-Firefox conflict resolved
- [x] Verify: screenshot shortcuts (Print, Super+Shift+S) — #18
- [x] Verify: hyprpolkitagent (GParted GUI prompt is HITL) — #18; agent running
- [x] Verify: Steam starts, Proton works (in-game run is HITL) — #18
- [ ] Add `/mnt/games/SteamLibrary` in Steam > Settings > Storage (blocked by #12)
- [x] Test gamescope per-game — #18; `gamescope` installed, per-game launch option is user-side
- [x] Test Steam Game Mode session in plasmalogin/SDDM — #18; `gamescope-session.desktop` present
- [x] Run protonup-qt, install GE-Proton — #18; GE-Proton11-3 installed
- [x] Test gamemode: `gamemoderun %command%` — #18
- [x] Test nvtop + gwe — #18
- [x] Verify devbox shells rebuild correctly — #18

## Phase 4 — Polish

- [x] Stylix (superseded) — matugen pipeline themes everything; nix builds of GPU/GL apps abort on NVIDIA, so Stylix is intentionally not enabled (see `gaming.nix`)
- [x] Verify GTK/Qt theme consistency — `theme-toggle` flips `gsettings color-scheme` (GTK + Qt dialogs follow); Vicinae gets the matugen theme via post_hook
- [x] Write `~/.local/bin/theme-toggle` for light/dark switching
- [x] Per-game MangoHud overrides (optional) — base `~/.config/mangohud/MangoHud.conf` present; drop `<game-exe>.conf` beside it for per-game overrides
- [x] Backup strategy — see below
- [x] Store `flake.lock` in git

### Backup strategy

- **Snapper root** (`@` = `/`, covers `/nix`): manual + pacman pre/post snapshots; 62 on disk; `snapper-cleanup.timer` prunes to `NUMBER_LIMIT 50`. Rolling back the nix store is covered.
- **Snapper home** (`@home` = `/home`, NOT covered by root): added 2026-08-07 with `TIMELINE_CREATE=yes` (hourly) so user data/config gets automatic snapshots.
- **`/nix` "backup" = rebuildability**: the store is not copied off-machine; `flake.lock` is committed, so the whole environment is reproducible from `nix run .#apply-gaming` (this repo, mirrored on GitHub).
- **Config backup**: all HM config + matugen templates/palette.py live in this repo (GitHub remote = off-machine copy). Runtime configs (`hyprland-colors.conf`, kitty, swaync, waybar, …) are regenerated from templates, so nothing hand-edited is lost.
- **Off-machine**: the flake repo on GitHub is the external copy; #16 paper/QR backup covers SSH + sops keys.

## Phase 5 — Extras (optional)

- [ ] Decky Loader
- [ ] EmuDeck
- [ ] Waydroid
- [ ] Distrobox
- [ ] VirGL/QEMU virtualization
- [ ] VS Code / Cursor

---

## What Bootstrap Handles vs What HM Handles

| Layer | Managed by | How |
|---|---|---|
| Kernel, NVIDIA drivers | `cachyos-gaming-meta` | pacman (bootstrap) |
| Steam, Wine, Proton | `cachyos-gaming-meta` | pacman (bootstrap) |
| Gamescope (CLI + session) | `gamescope-session-cachyos` | prebuilt CachyOS repo (bootstrap) |
| hyprpolkitagent | Arch `extra` | pacman (bootstrap) |
| Hyprland compositor + hyprlock/hypridle/hyprshot/hyprpicker/awww | system (pacman) | nix builds abort on NVIDIA EGL/GBM + Hypr\* ABI guards (bootstrap) |
| kitty, ghostty, discord, mangohud (GL renderers / injectors) | system (pacman) | nix builds share kitty's NVIDIA EGL failure (bootstrap) |
| HDD staging mount (ro) | bootstrap.sh | ntfs-3g + fstab at `/mnt/staging` |
| Hyprland/hypridle/hyprlock/mangohud configs | home-manager | `home.file` (`gaming.nix`) |
| waybar, swaync, nwg-displays | home-manager | `programs.*` / `home.packages` (safe compositor clients) |
| firefox | home-manager | `programs.firefox` (nix build works; profile imported) |
| gamemode | system (pacman) | installed by bootstrap (not in gaming-meta); config via `~/.config/gamemode.ini` |
| protonup-qt, goverlay, nvtop, gwe, pavucontrol | home-manager | `home.packages` |
| Fonts (JetBrains Mono NF, Noto) | home-manager | `home.packages` |
| Matugen theming | home-manager | `home.file` matugen config + templates (`gaming.nix` + `profiles/matugen/`); stylix input kept but intentionally disabled |
| git, ssh, gpg | home-manager | `programs.*` |
| nushell, starship, atuin, etc. | shared modules | `programs.*` |

## Truly Manual Steps (4 total)

1. **BIOS update** — firmware, must be done from BIOS
2. **Download CachyOS ISO** — file download
3. **Flash ISO to USB** — `dd` or similar
4. **Run Calamares installer** — partition NVMe, create user `roni`, set locale

Everything after `curl bootstrap.sh | bash` is automated.
