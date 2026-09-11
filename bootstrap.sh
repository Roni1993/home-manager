#!/usr/bin/env bash
# ── CachyOS Gaming PC Bootstrap ─────────────────────────────────
# Run once after a fresh CachyOS KDE install (with user "roni").
# Handles system packages, storage, Nix, and applies the HM config.
# Safe to re-run — all commands are idempotent.
#
# Manual steps before this script:
#   1. Update BIOS
#   2. Download CachyOS ISO (KDE variant)
#   3. Flash to USB, boot from it
#   4. In Calamares: NVMe → /boot/efi (1GB) + / (Btrfs, rest)
#                    User: roni
#                    HDD: leave untouched (script handles it)
#   5. Reboot, log into KDE session, open Konsole, run this script.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

section() { echo -e "\n${GREEN}>>>${NC} $*"; }
warn()   { echo -e "${YELLOW}!!!${NC} $*"; }
die()    { echo -e "${RED}ERR:${NC} $*" >&2; exit 1; }

# ── Logging ─────────────────────────────────────────────────────
# Every run is captured verbatim to a timestamped transcript under
# ~/.local/state/fleek/bootstrap/ (persists across reboots — /tmp is
# wiped). `latest` symlinks the most recent transcript so follow-ups
# are one command away: cat ~/.local/state/fleek/bootstrap/latest

LOG_DIR="$HOME/.local/state/fleek/bootstrap"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Run started: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Logging to: $LOG_FILE"

log_fail() {
  echo -e "${RED}LOGGED ERROR${NC} at line ${BASH_LINENO[0]}: ${BASH_COMMAND}" >&2
}

log_end() {
  echo ""
  echo "Bootstrap exited. Full transcript: $LOG_FILE"
  echo "   Follow up: cat $LOG_DIR/latest"
}

set -o errtrace
trap 'log_fail' ERR
trap 'log_end' EXIT

# ── Phase-3 restore (shared) ─────────────────────────────────────
# Restores the pre-wipe backup (SSH keys, sops age key, Firefox
# profile) from /mnt/staging/backup-for-cachyos. Idempotent — safe to
# re-run; already-restored items are skipped. Per wayfinder #8, the
# Firefox import is a curated copy into the HM-managed profile dir.

phase3_restore() {
  if ! mountpoint -q /mnt/staging 2>/dev/null; then
    warn "Staging not mounted — skipping Phase-3 restore. Check section 5."
    return 0
  fi

  B="/mnt/staging/backup-for-cachyos"

  if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ -f "$B/wsl-keys/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh"
    cp "$B/wsl-keys/id_ed25519" "$HOME/.ssh/id_ed25519"
    cp "$B/wsl-keys/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub"
    chmod 600 "$HOME/.ssh/id_ed25519"
    chmod 644 "$HOME/.ssh/id_ed25519.pub"
    echo "  SSH keypair restored to ~/.ssh"
  else
    echo "  SSH keypair already present, skipping."
  fi

  if [ ! -f "$HOME/.config/sops/age/keys.txt" ] && [ -f "$B/wsl-keys/keys.txt" ]; then
    mkdir -p "$HOME/.config/sops/age"
    cp "$B/wsl-keys/keys.txt" "$HOME/.config/sops/age/keys.txt"
    chmod 600 "$HOME/.config/sops/age/keys.txt"
    echo "  sops age key restored."
  else
    echo "  sops age key already present, skipping."
  fi

  FF_SRC="$B/firefox-profile"
  FF_DST="$HOME/.mozilla/firefox/roni"
  if [ -d "$FF_SRC" ] && [ -d "$FF_DST" ]; then
    if pgrep -x firefox &>/dev/null; then
      warn "Firefox is running — close it and re-run to import the profile."
    else
      echo "  Importing Firefox profile -> $FF_DST"
      BK_DIR="$HOME/.hm-restore-backup-$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$BK_DIR"
      # Curated list per wayfinder #8. logins.json+key4.db travel as a pair.
      # user.js/.keep/containers.json stay HM-managed and are NOT copied.
      # Gotcha (2026-08-08): places.sqlite/favicons.sqlite are WAL-mode SQLite —
      # a raw cp produces a corrupt DB (Firefox silently stops storing history).
      # They must be snapshotted with `sqlite3 .backup`, which yields a
      # consistent image. Everything else is a plain file/dir copy.
      for f in logins.json key4.db \
               permissions.sqlite cert9.db formhistory.sqlite cookies.sqlite \
               prefs.js search.json.mozlz4 handlers.json \
               extensions extensions.json browser-extension-data \
               storage storage-sync-v2.sqlite; do
        if [ -e "$FF_SRC/$f" ]; then
          [ -e "$FF_DST/$f" ] && cp -a "$FF_DST/$f" "$BK_DIR/"
          cp -a "$FF_SRC/$f" "$FF_DST/"
          echo "    restored: $f"
        fi
      done
      for f in places.sqlite favicons.sqlite; do
        if [ -e "$FF_SRC/$f" ]; then
          [ -e "$FF_DST/$f" ] && cp -a "$FF_DST/$f" "$BK_DIR/"
          if command -v sqlite3 &>/dev/null; then
            sqlite3 "$FF_SRC/$f" ".backup '$FF_DST/$f'" && \
            rm -f "$FF_DST/$f-wal" "$FF_DST/$f-shm" || warn "  $f snapshot FAILED"
            echo "    restored: $f (sqlite .backup snapshot)"
          else
            warn "  sqlite3 missing — $f would import corrupt; skipping."
          fi
        fi
      done
      chmod -R u+rwX "$FF_DST"
      echo "  Firefox profile imported (pre-import state backed up to $BK_DIR)."
      echo "  If a fresh default profile appears on first launch, fix via"
      echo "  about:profiles -> Set as default (see issue #8)."
    fi
  else
    warn "Firefox source or target missing — skipping import (src: $FF_SRC, dst: $FF_DST)."
  fi
}

# `bootstrap.sh --restore` runs ONLY the Phase-3 restore (idempotent).
if [ "${1:-}" = "--restore" ]; then
  section "Phase-3 restore only (--restore)"
  phase3_restore
  exit 0
fi

# ── Preflight ────────────────────────────────────────────────────

[ "$USER" = "roni" ] || warn "Expected user 'roni', got '$USER'."
command -v pacman &>/dev/null || die "pacman not found — are you on CachyOS?"

# ── 0. Sudo safety check ─────────────────────────────────────────
# Before running any sudo commands, verify the password works.
# If it doesn't, offer a root fallback to set up passwordless sudo.

section "Sudo password check"
if ! sudo -v 2>/dev/null; then
  warn "sudo failed — password may be wrong or sudoers is misconfigured."
  echo ""
  echo "  Two options:"
  echo "    1. Reset password: boot from CachyOS USB, mount NVMe,"
  echo "       arch-chroot /mnt && passwd roni"
  echo "    2. Use root password to enable passwordless sudo NOW:"
  echo "       su -c 'echo \"%wheel ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/wheel-nopasswd'"
  echo ""
  printf "Enter '2' to attempt root fallback, or anything else to abort: "
  read -r choice
  if [ "$choice" = "2" ]; then
    echo "Running: su -c 'echo ... > /etc/sudoers.d/wheel-nopasswd'"
    su -c 'echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd' || die "Root fallback failed."
    echo "Passwordless sudo enabled. Continuing..."
    sudo -v || die "sudo still broken after root fallback — check /etc/sudoers."
  else
    die "Cannot proceed without sudo. Run option 1 (USB chroot) first, then re-run this script."
  fi
else
  echo "sudo works."
fi

# ── 1. System update ────────────────────────────────────────────

section "System update"
sudo pacman -Syu --noconfirm

# ── 2. Base tools + AUR helper ──────────────────────────────────

section "Base development tools"
sudo pacman -S --noconfirm --needed base-devel git curl wget
# kitty is the primary terminal (gaming.nix manages config via home.file,
# the binary is system-provided to avoid the nix libglvnd/NVIDIA EGL crash).
sudo pacman -S --noconfirm --needed kitty

if ! command -v paru &>/dev/null; then
  section "Installing paru (AUR helper)"
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  (cd /tmp/paru && makepkg -si --noconfirm)
  rm -rf /tmp/paru
fi

# ── 3. Gaming system packages ───────────────────────────────────

section "NVIDIA driver stack (userspace) — must precede gaming-meta"
# cachyos-gaming-meta depends on the virtual 'lib32-vulkan-driver' provider.
# Installing the NVIDIA stack first satisfies it; otherwise --noconfirm would
# auto-select the first provider (lib32-nvidia-390xx-utils) and conflict.
# The kernel module is installed by the CachyOS installer (chwd) during setup.
sudo pacman -S --noconfirm --needed nvidia-utils lib32-nvidia-utils

section "CachyOS gaming meta-package (kernel, drivers, Steam, Wine)"
sudo pacman -S --noconfirm --needed cachyos-gaming-meta

section "CachyOS gamescope-session (Steam Deck Game Mode UI)"
sudo pacman -S --noconfirm --needed gamescope-session-cachyos

section "hyprpolkitagent (privilege escalation for Hyprland)"
sudo pacman -S --noconfirm --needed hyprpolkitagent

section "Hyprland stack (system builds — nix builds crash on NVIDIA EGL/GBM)"
# The nix/hyprland build aborts on this box (bundled mesa can't find
# /run/opengl-driver/lib/gbm/dri_gbm.so on CachyOS -> DRM backend fails,
# black screen). System builds link against system mesa + NVIDIA stack.
sudo pacman -S --noconfirm --needed hyprland hyprlock hypridle hyprshot hyprpicker awww

section "GUI apps with own GL renderers (system builds)"
# nix ghostty/discord/mangohud share kitty's failure mode (bundled GL/EGL
# can't talk to NVIDIA, or inject into system processes with nix libs).
sudo pacman -S --noconfirm --needed ghostty discord mangohud

section "Gaming tooling (system builds)"
# gamemode is NOT pulled in by cachyos-gaming-meta; install it explicitly.
sudo pacman -S --noconfirm --needed gamemode
# playerctl drives waybar's mpris (now-playing) module.
sudo pacman -S --noconfirm --needed playerctl
# matugen: theming pipeline (palette.py renders the gaming profile's
# templates). Must be system — the nix build aborts on NVIDIA.
sudo pacman -S --noconfirm --needed matugen
# nautilus: GTK4 file manager (Super+E). Follows the matugen gtk-4.0 css.
sudo pacman -S --noconfirm --needed nautilus
# papirus-icon-theme: base for the matugen-tinted folder icons
# (apply-icons.sh builds a Papirus-Matugen overlay from it).
sudo pacman -S --noconfirm --needed papirus-icon-theme

section "Vicinae launcher (AUR — nix Qt build can't init OpenGL on NVIDIA)"
paru -S --noconfirm vicinae-bin
# spicetify-cli (AUR): Spotify theming, driven by apply-theme.sh via the
# matugen spicetify template.
paru -S --noconfirm spicetify-cli
# zapzap (AUR): native GTK4 WhatsApp client (no Electron) — picks up the
# matugen gtk-4.0 css automatically.
paru -S --noconfirm zapzap

# ── 3b. Remove noctalia (notification daemon) ────────────────────
# noctalia ships with CachyOS KDE and claims org.freedesktop.Notifications
# on D-Bus, which prevents swaync (configured in our gaming profile)
# from starting. Remove it so swaync can claim the name.

if pacman -Q noctalia &>/dev/null; then
  section "Removing noctalia (notification daemon) — conflicts with swaync"
  sudo pacman -R --noconfirm noctalia
else
  echo "noctalia not installed, skipping."
fi

# ── 4. NVIDIA verification ──────────────────────────────────────

section "Routing core dumps to systemd-coredump"
# Kernel default (core_pattern=core) drops dumps into the process cwd
# (e.g. ~/core.* from spotify-launcher). Route them to systemd-coredump
# (bounded, stored in the journal) so they don't accumulate in $HOME.
echo "kernel.core_pattern=|/usr/lib/systemd/systemd-coredump %P %u %g %s %t %c %h" \
  | sudo tee /etc/sysctl.d/99-core-pattern.conf >/dev/null
sudo sysctl --system >/dev/null

section "Verifying NVIDIA drivers"
if command -v nvidia-smi &>/dev/null; then
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader \
    || warn "nvidia-smi reported an error (driver may not be loaded yet). Continue anyway."
else
  warn "nvidia-smi not found. GPU drivers may not be loaded."
  warn "Run: sudo pacman -S nvidia-dkms && reboot"
fi

# ── 5. HDD setup (NTFS staging, read-only) ──────────────────────
# Per wayfinder #6: the 4TB HDD stays NTFS untouched through the
# transition. It is mounted READ-ONLY at /mnt/staging so the Phase-3
# restore (keys, Firefox profile) can read it. NO wiping, NO repartition.
# After private data migrates to the Pi (#12), reformat to a single ext4
# /mnt/games — that is owned by ticket #12, not this script.

HDD_DEV=""
# Scan all SATA and NVMe devices for a disk >= 3.5 TB (accounts for
# manufacturer vs OS size reporting). Exclude the boot NVMe (<= 2TB)
# and removable devices (USB stick).
for dev in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
  [ -b "$dev" ] || continue
  # Skip the boot NVMe (CachyOS is installed on nvme0n1, ~1.8TB)
  [[ "$dev" == /dev/nvme0n1 ]] && continue
  size=$(lsblk -dbno SIZE "$dev" 2>/dev/null | head -1 || true)
  if [ "$size" -ge 3500000000000 ] 2>/dev/null; then
    HDD_DEV="$dev"
    break
  fi
done

if [ -z "$HDD_DEV" ]; then
  warn "Could not auto-detect the 4 TB HDD."
  warn "Available block devices:"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
  printf "Enter HDD device (e.g. /dev/sda) or leave empty to skip: "
  read -r HDD_DEV
fi

if [ -n "$HDD_DEV" ] && ! mount | grep -q "/mnt/staging"; then
  # Find the NTFS *data* partition on the disk. Hardcoding "${HDD_DEV}1" was
  # wrong — many 4TB disks (incl. ST4000LM024) have a 16M reserved part1 and
  # the NTFS volume on part2, so the old code mounted/blanked the wrong device.
  HDD_PART=$(lsblk -rno NAME,FSTYPE "$HDD_DEV" 2>/dev/null \
    | awk '$2=="ntfs" {print "/dev/"$1; exit}')
  if [ -z "$HDD_PART" ] || [ ! -b "$HDD_PART" ]; then
    warn "No NTFS partition found on $HDD_DEV — expected an NTFS data partition."
    warn "Disk layout:"; lsblk -o NAME,SIZE,TYPE,FSTYPE "$HDD_DEV"
    warn "You may need to mount it manually for the Phase-3 restore."
  else
    section "Mounting $HDD_PART read-only at /mnt/staging"
    HDD_UUID=$(sudo blkid -s UUID -o value "$HDD_PART")
    sudo mkdir -p /mnt/staging
    # ntfs-3g userspace driver for read-only staging mounts.
    sudo pacman -S --noconfirm --needed ntfs-3g
    if ! grep -q "$HDD_UUID" /etc/fstab; then
      echo "UUID=$HDD_UUID  /mnt/staging  ntfs  ro,noatime,nofail  0 0" | sudo tee -a /etc/fstab
    fi
    sudo mount /mnt/staging 2>/dev/null || sudo mount -o ro /mnt/staging || \
      warn "Mount failed. Check the partition and fstab entry; restore data manually."
    lsblk "$HDD_DEV"
    echo "/mnt/staging ready (read-only). Phase-3 will restore keys + Firefox from /mnt/staging/backup-for-cachyos."
  fi
elif mount | grep -q "/mnt/staging"; then
  section "HDD already mounted read-only at /mnt/staging"
fi

# ── 6. Nix installation ──────────────────────────────────────────

section "Installing Determinate Nix"
if ! command -v nix &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  # Source nix into this shell
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
  echo "Nix already installed: $(nix --version)"
fi

# nushell is THE shell ("nu everywhere"): login shell + kitty's shell.
# Needs Nix present (profile path below) and an /etc/shells entry.
if ! grep -q ".nix-profile/bin/nu" /etc/shells; then
  echo "/home/roni/.nix-profile/bin/nu" | sudo tee -a /etc/shells >/dev/null
fi
sudo chsh -s /home/roni/.nix-profile/bin/nu roni

# ── 7. Nix flakes ────────────────────────────────────────────────

section "Enabling Nix flakes"
mkdir -p ~/.config/nix
if ! grep -q "experimental-features" ~/.config/nix/nix.conf 2>/dev/null; then
  echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
  echo "Flakes enabled."
else
  echo "Flakes already configured."
fi

# ── 7b. Clear conflicting files before HM activation ────────────
# Home-manager manages these paths as symlinks into the nix store.
# Pre-existing files/dirs block the symlink creation and cause HM to
# abort. Back up any that exist, then remove them.
#
# List derived from: shell.nix (bash), gaming.nix (kitty, waybar,
# swaync, rofi, hyprland), programs.nix (starship, nushell, etc.),
# and home.nix (fontconfig).

CONFLICT_PATHS=(
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
  "$HOME/.profile"
  "$HOME/.config/kitty/kitty.conf"
  "$HOME/.config/starship.toml"
  "$HOME/.config/nushell/env.nu"
  "$HOME/.config/nushell/config.nu"
  "$HOME/.config/waybar/config.jsonc"
  "$HOME/.config/waybar/style.css"
  "$HOME/.config/swaync/config.json"
  "$HOME/.config/swaync/style.css"
  "$HOME/.config/rofi/config.rasi"
  "$HOME/.config/hypr/hyprland.conf"
  "$HOME/.config/hypr/hyprlock.conf"
  "$HOME/.config/hypr/hypridle.conf"
  "$HOME/.config/direnv/direnv.toml"
  "$HOME/.config/broot/config.toml"
  "$HOME/.config/atuin/config.toml"
  "$HOME/.config/git/config"
  "$HOME/.config/gh/config.yml"
  "$HOME/.mozilla/firefox/profiles.ini"
)

section "Checking for files that conflict with home-manager"
BACKUP_DIR="$HOME/.hm-backup-$(date +%Y%m%d-%H%M%S)"
found_any=false
for path in "${CONFLICT_PATHS[@]}"; do
  if [ -f "$path" ] && [ ! -L "$path" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "${path#$HOME/}")"
    cp "$path" "$BACKUP_DIR/${path#$HOME/}"
    rm -f "$path"
    warn "Backed up and removed: $path"
    found_any=true
  fi
done
if [ "$found_any" = false ]; then
  echo "No conflicting files found."
else
  echo "Backups saved to: $BACKUP_DIR"
  echo "You can restore them later if needed."
fi

# ── 8. Home-manager apply ────────────────────────────────────────

REPO_URL="${FLEEK_REPO_URL:-https://github.com/Roni1993/fleek.git}"
REPO_DIR="$HOME/projects/fleek"

section "Setting up fleek home-manager config"
if [ -d "$REPO_DIR/.git" ]; then
  echo "Repo exists. Pulling latest..."
  git -C "$REPO_DIR" pull --ff-only
else
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR" || {
    warn "Git clone failed — is the repo pushed and SSH key added?"
    warn "If you haven't pushed yet, push from your WSL machine first."
    warn "Repo URL: $REPO_URL"
    warn "You can re-run this script after pushing."
    exit 1
  }
fi

section "Applying gaming profile"
nix run "$REPO_DIR#apply-gaming"

# ── 8a. Register Hyprland login session + autologin ──────────────
# Hyprland is now a SYSTEM package (see section 3) whose hyprland.desktop
# is installed to /usr/share/wayland-sessions directly — nothing to
# register. This block only warns if it's unexpectedly missing, then
# points autologin at Hyprland for whichever login manager is installed.

section "Registering Hyprland login session + autologin"
for sess in hyprland hyprland-uwsm; do
  if [ -f "/usr/share/wayland-sessions/$sess.desktop" ]; then
    echo "  Present: /usr/share/wayland-sessions/$sess.desktop"
  else
    warn "Missing session file (system package should provide it): $sess"
  fi
done

if [ -f /etc/plasmalogin.conf ]; then
  # plasmalogin (Plasma >=6.4) reads ONLY /etc/plasmalogin.conf — conf.d
  # drop-ins are ignored, so write the autologin session to the main file.
  printf '[Autologin]\nUser=%s\nSession=hyprland\n' "$USER" \
    | sudo tee /etc/plasmalogin.conf >/dev/null
  # CachyOS ships a user service that rewrites a gamescope autologin drop-in
  # (via pkexec) on every login; disable it so it can't fight this setting.
  systemctl --user disable cachyos-gamescope-autologin.service 2>/dev/null || true
  echo "  plasmalogin autologin -> Hyprland ($USER)"
elif [ -f /etc/sddm.conf ]; then
  sudo mkdir -p /etc/sddm.conf.d
  printf '[Autologin]\nUser=%s\nSession=hyprland.desktop\n' "$USER" \
    | sudo tee /etc/sddm.conf.d/10-hyprland-autologin.conf >/dev/null
  echo "  SDDM autologin -> Hyprland ($USER)"
else
  warn "No plasmalogin or SDDM config found — set Hyprland autologin manually."
fi

# ── 8b. Project checkouts ──────────────────────────────────────
# Clone every local project into ~/projects, mirroring the old WSL layout.
# Format: "url|dir|branch". Skip if the dir already exists (idempotent).
# Private repos (homelab, gameServerHosting) need `gh auth login` or an SSH
# key added to GitHub; clone failure for them is a warning, not an abort.

PROJECTS=(
  "https://github.com/Roni1993/homelab.git|homelab|main"
  "https://github.com/Trusty-Serva/gameServerHosting.git|gameServerHosting|main"
  "https://github.com/thebracket/JetBrainsBevy|JetBrainsBevy|main"
  "https://github.com/raspberrypi/pico-examples.git|pico-examples|master"
  "https://github.com/steam-deck-controller/steam-deck-controller.git|steam-deck-controller|freertos"
)

section "Cloning projects into ~/projects"
for entry in "${PROJECTS[@]}"; do
  url="${entry%%|*}"; rest="${entry#*|}"; dir="${rest%%|*}"; branch="${rest#*|}"
  target="$HOME/projects/$dir"
  if [ -d "$target/.git" ]; then
    echo "  $dir: already present, pulling..."
    git -C "$target" pull --ff-only 2>/dev/null || echo "  $dir: pull skipped (uncommitted changes?)"
  else
    mkdir -p "$HOME/projects"
    echo "  $dir: cloning ($branch)..."
    if git clone --branch "$branch" --single-branch "$url" "$target" 2>/dev/null; then
      echo "  $dir: OK"
    else
      warn "$dir: clone failed. If private, run \`gh auth login\` first (or add SSH key), then re-run."
    fi
  fi
done

# ── 9. Post-bootstrap verification ──────────────────────────────

section "Post-bootstrap verification"

errors=0

echo -n "  NVIDIA driver... "
if nvidia-smi --query-gpu=name --format=csv,noheader &>/dev/null; then
  echo "OK ($(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null))"
else
  echo "FAIL"; errors=$((errors + 1))
fi

echo -n "  HDD at /mnt/staging... "
if mountpoint -q /mnt/staging 2>/dev/null; then
  echo "OK ($(lsblk -no SIZE /dev/sda2 2>/dev/null | head -1))"
else
  echo "NOT MOUNTED"; errors=$((errors + 1))
fi

echo -n "  Home-manager generation... "
if home-manager generations 2>/dev/null | head -1 | grep -q current; then
  echo "OK"
else
  echo "FAIL"; errors=$((errors + 1))
fi

echo -n "  Nix daemon... "
if systemctl status nix-daemon &>/dev/null; then
  echo "OK"
else
  echo "NOT RUNNING"; errors=$((errors + 1))
fi

echo -n "  Hyprland config... "
if [ -f "$HOME/.config/hypr/hyprland.conf" ]; then
  echo "OK"
else
  echo "MISSING"; errors=$((errors + 1))
fi

echo -n "  Kitty... "
if command -v kitty &>/dev/null; then
  echo "OK ($(kitty --version))"
else
  echo "NOT FOUND"; errors=$((errors + 1))
fi

echo -n "  Hyprland login session... "
if [ -f /usr/share/wayland-sessions/hyprland.desktop ]; then
  echo "OK"
else
  echo "MISSING"; errors=$((errors + 1))
fi

echo -n "  Hyprland autologin (plasmalogin/SDDM)... "
if grep -qs "Session=hyprland" /etc/plasmalogin.conf /etc/sddm.conf /etc/sddm.conf.d/ 2>/dev/null; then
  echo "OK"
else
  echo "NOT SET"; errors=$((errors + 1))
fi

echo ""
if [ "$errors" -gt 0 ]; then
  warn "$errors check(s) failed — review above and fix manually."
else
  echo "All checks passed."
fi

# ── 9b. Phase-3 restore from staging ─────────────────────────────
# Restores the pre-wipe backup (SSH keys, sops age key, Firefox
# profile) from /mnt/staging/backup-for-cachyos. Idempotent — safe to
# re-run; already-restored items are skipped. Per wayfinder #8, the
# Firefox import is a curated copy into the HM-managed profile dir.

section "Phase-3 restore from /mnt/staging"
phase3_restore

# ── 10. Done ────────────────────────────────────────────────────

echo ""
echo "==========================================="
echo "  Bootstrap complete!"
echo ""
echo "  Next steps:"
echo "    1. Reboot"
echo "    2. plasmalogin autologin lands in the Hyprland session"
echo "    3. Login — waybar, swaync, vicinae should start"
echo "    4. Run protonup-qt to install GE-Proton"
echo "    5. HDD becomes a games disk later — owned by wayfinder ticket #12"
echo "==========================================="
