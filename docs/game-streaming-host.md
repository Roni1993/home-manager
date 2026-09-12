# Game-streaming HOST on the CachyOS / Hyprland / RTX 3060 Ti box — 2026 state of the art

**Verdict first.** Run **Sunshine** as the host and **Moonlight** on the receiving devices. On this exact machine Sunshine has a capture path that does not depend on the (currently missing) Hyprland screencast portal — `capture = wlr` (wlr-screencopy), with `kms` as the fallback — plus NVENC on Linux and an official Arch package that sets the needed capabilities. **Steam Remote Play is a fallback, not the primary host**: on Wayland it needs Steam launched with `-pipewire` (still not default as of 2026-09-12) **and** a working ScreenCast portal, and this box has **no `xdg-desktop-portal-hyprland` installed**. Steam Link also has **no LG webOS client** — only Samsung Smart TVs — while Moonlight has a community LG webOS client (developer mode required).

**Verified on:** 2026-09-12 (all links fetched live on this date; host machine state inspected live on the same date).

---

## Quick comparison

| | **Sunshine + Moonlight** (recommended) | **Steam Remote Play / Steam Link** |
|---|---|---|
| Latest, 2026-09-12 | Sunshine stable **v2026.906.222525** (2026-09-06) | Steam client update **2026-09-01** |
| Host on Hyprland/Wayland | `wlr` capture is explicitly documented for Hyprland; `kms` fallback; **no portal needed** | Needs `-pipewire` **+** xdg-desktop-portal ScreenCast backend; **xdg-desktop-portal-hyprland is not installed here** |
| NVIDIA encode | **NVENC ✅ on Linux** (official packages ship CUDA-bound build) | NVIDIA hw encode ✅ on Linux (fixed 2024-12); `NVFBC`/`NVIFR` on X11, PipeWire on Wayland |
| 4K@60 / HEVC / AV1 | 4K: RTX 2000-series+ ✅; `hevc_mode`/`av1_mode` configurable | 4K yes; HEVC/AV1 used internally, not user-selectable; recent "Improved video color range" |
| HDR | Documented "Intel/AMD VAAPI + KMS" but changelog says **NVIDIA Linux HDR via CUDA/CUDA-GL** — **contradiction, unverified** | HDR streaming exists; Sept 1 2026 added HDR to Steam Deck OLED; washed-out HDR bug open |
| LG TV client | Community **Moonlight TV** (webOS, developer mode/sideload) | **None official** — Steam Link app list has Samsung TVs only; needs a stick/console/Apple TV |
| Steam Deck client | Moonlight via Flathub (`com.moonlight_stream.Moonlight`); native is Steam Remote Play | **Built in** (zero install) |
| Linux laptop client | `moonlight-qt` in Arch `extra` (6.1.0-7) or Flathub | Steam Link app on Flathub (1.3.32.316) |
| Host session required | Yes (graphical session); headless needs a virtual display | Yes (Steam running + logged in) |
| Config surface | Plain-text `~/.config/sunshine/sunshine.conf` + `apps.json`, web UI on :47990 | Steam UI; hidden `-pipewire` launch arg |
| Input | libvirtualhid (`uinput`/`uhid`); user must be in `input` group | Steam injects input; needs `/dev/uinput` rw; **no rumble on Linux hosts** |
| Package here | AUR `sunshine` (upstream-maintained) or LizardByte's official pacman repo; **not** in Arch/CachyOS repos | Already installed (Steam) |

---

## 1. Steam Remote Play as host on Linux/Wayland — 2026 status

### Naming and scope
Valve's product page and FAQ define three features ([store.steampowered.com/remoteplay](https://store.steampowered.com/remoteplay/), [help.steampowered.com FAQ 0689-74B8-92AC-10F2](https://help.steampowered.com/en/faqs/view/0689-74B8-92AC-10F2), both checked 2026-09-12):

- **Remote Play Anywhere** — stream a game from the PC that owns it to another computer or a device running the **Steam Link** app, signed into the same Steam account.
- **Remote Play Together** — invite Steam Friends into a local co-op game; only the host needs the game.
- **VR streaming** — separate, Windows 10+ / NVIDIA GTX 970+ requirement per the product page.

"All Steam games can be played streaming between your own computers" (FAQ). **Streaming non-Steam games is not officially supported** (FAQ, Known Issues).

### Hardware / host requirements
- CPU: "minimum of a quad-core CPU for the computer running the game" (FAQ). The client "should have a GPU that supports hardware accelerated H264 decoding."
- NVIDIA hardware encoding: "If you have a GTX 650 or newer and the latest NVIDIA drivers" enable *Enable hardware encoding* in Remote Play → Advanced Host Options; the performance overlay shows `NVFBC`/`NVIFR` when active (FAQ). The RTX 3060 Ti qualifies.
- Linux host hw encode regressed and was fixed in the **2024-12-03 Steam client update**: "Fixed issue preventing Linux users with Nvidia cards from using their GPU to accelerate video encoding" ([Steam news via ISteamNews API, appid 593110](https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=593110), checked 2026-09-12).

### Wayland capture path — `-pipewire`, and why it matters here
Steam's Wayland host capture is **PipeWire via the ScreenCast portal**, and it is **opt-in via a launch flag**:

- Open feature request, **2026-09-12**: "**all Wayland steam sessions require the `-pipewire` launch flag to support acting as a Remote Play host**… the client will even tell the user currently that the host needs to have enabled pipewire" — [steam-for-linux #13609](https://github.com/ValveSoftware/steam-for-linux/issues/13609) (checked 2026-09-12). So it is **not** default as of this date.
- Confirmed in release notes: Sept 1 2026 Steam client update, Remote Play section — "Fixed video frame being clipped when using **pipewire capture** with desktop scaling on Wayland" ([Steam news, 2026-09-01](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1842846814438758), checked 2026-09-12).

**This machine has no Hyprland ScreenCast portal backend.** Live check 2026-09-12: installed portals are `xdg-desktop-portal`, `-gtk`, `-kde`; `/usr/share/xdg-desktop-portal/portals/` contains `gtk.portal`, `kde.portal`, `kwallet.portal`, `plasmanotify.portal`. **`xdg-desktop-portal-hyprland` is not installed** (Arch `extra` `1.4.1-2`; [archlinux.org package search](https://archlinux.org/packages/?q=xdg-desktop-portal-hyprland), checked 2026-09-12). The KDE portal only serves KWin, so Steam's `-pipewire` capture and Sunshine's `portal` capture have no working backend on this box today.

### Known Wayland bugs (all checked 2026-09-12)
- [#13585](https://github.com/ValveSoftware/steam-for-linux/issues/13585) (open): with `-pipewire`, video is "black, frozen, or updates only sporadically", ~35 fps at a 60 fps target, `DroppedNetworkLost`; with `-pipewire -pipewire-dmabuf` DMA-BUF fails.
- [#13179](https://github.com/ValveSoftware/steam-for-linux/issues/13179) (open): the **client** `streaming_client` crashes at `eglGetDisplay` on **every** Wayland DE/WM tested (KDE, Hyprland, Sway); X11 works.
- [#13578](https://github.com/ValveSoftware/steam-for-linux/issues/13578) (closed): native-Wayland Proton games (`PROTON_ENABLE_WAYLAND=1`) stream a **black frame**; the X11 fallback can't read a Wayland-native surface. Workaround implied: run games under XWayland.
- [#13340](https://github.com/ValveSoftware/steam-for-linux/issues/13340) (open): host hangs after the first stream on KDE Wayland (PipeWire/ScreenCast session not released).

### HDR, audio, input
- **HDR:** Sept 1 2026 client update added "support for HDR streaming on Steam Deck OLED" (news above). HDR is still visibly broken in the field — [#13600](https://github.com/ValveSoftware/steam-for-linux/issues/13600) (open, 2026-09-10) reports washed-out colors / raised blacks on Deck OLED. Whether a **Linux + NVIDIA + Hyprland host** can send HDR is not established by any primary source I found. On this machine HDR is a non-goal: the LG link is HDMI-2.0-class and HDR was deliberately disabled to stop chroma flicker (ROADMAP §Phase 3).
- **Audio:** captured by Steam; no user-facing PipeWire sink routing. Known JACK-surround channel-map bugs exist ([#6150](https://github.com/ValveSoftware/steam-for-linux/issues/6150), open).
- **Input:** Linux hosts need `/dev/uinput` (or `/dev/input/uinput`) readable/writable by Steam; **"Currently, there is no rumble support for Linux machines"** (FAQ, SteamOS/Linux Known Issues). DirectInput wheels/flight sticks are unsupported; XInput gamepads are.

### Ports (for firewalling)
"Streaming uses **UDP ports 27031 and 27036 and TCP ports 27036 and 27037**" (FAQ). On this box `ufw` is installed but **inactive** (live check 2026-09-12), so no rule is needed unless it is enabled.

### Headless / real-session
Remote Play grants "access to the host computer outside of the game being streamed" (FAQ) and the 2025-11-17 client update added a "Connect" button to stream the remote desktop, but it still requires **Steam running and logged in inside a graphical session**. A game that loses focus makes Steam stream the desktop (FAQ, Known Issues). There is no documented supported headless mode; a virtual display is the usual workaround.

---

## 2. Sunshine as host on Linux — 2026 status

### Release and Linux support matrix
**Latest stable: v2026.906.222525, released 2026-09-06** ([GitHub releases API](https://api.github.com/repos/LizardByte/Sunshine/releases/latest), checked 2026-09-12). It contains **critical security fixes** (five GHSAs) — update promptly ([CHANGELOG](https://github.com/LizardByte/Sunshine/blob/changelog/CHANGELOG.md), checked 2026-09-12). From the official [README support matrix](https://github.com/LizardByte/Sunshine/blob/master/README.md) (checked 2026-09-12):

- **Encoding (Linux):** NVENC (NVIDIA) ✅, VAAPI (AMD/Intel/NVIDIA) ✅, Vulkan Video (AMD ✅ / NVIDIA 🟡 partial), software ✅.
- **Capture (Linux):** KMS/DRM ✅, NvFBC ✅ (**X11 only**), Wayland (wlroots) ✅, X11 ✅, XDG Desktop Portal ✅, KWin Screencast ✅.
- **Capture → NVENC:** KMS/DRM ✅, Wayland (wlroots) ✅, X11 ✅, XDG Portal ✅.
- **4K:** NVIDIA "RTX 2000 series or higher" on Linux. **RTX 3060 Ti qualifies.**
- **HDR:** NVIDIA "Pascal (GTX 10-series) or higher".

### Capture on Hyprland specifically
The `capture` setting ([configuration docs](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html), checked 2026-09-12) lists `nvfbc`, `wlr`, `kms`, `kwin`, `x11` (plus Windows-only values). Default is automatic, "first capture method available in the order of the table above", and the README's table order puts **KMS/DRM first** on Linux, then NvFBC, then Wayland (wlroots), then X11, then XDG Portal, then KWin.

The `wlr` description is explicit about Hyprland:

> "Capture for wlroots based Wayland compositors via wlr-screencopy-unstable-v1. **It is possible to capture virtual displays in e.g. Hyprland using this method.**"

`kms`: "DRM/KMS screen capture from the kernel. This requires that Sunshine has `cap_sys_admin` capability." On NVIDIA, KMS capture needs `nvidia_drm.modeset=1` to avoid a black stream ([troubleshooting](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2troubleshooting.html), checked 2026-09-12) — **already set on this box**.

Portal capture on Hyprland is a known open failure: [#4662](https://github.com/LizardByte/Sunshine/issues/4662) (open since 2026-02-04, still relevant 2026-07) — "`xdg portal / pipewire capture works on kde but not hyprland`", log `Pipewire Error… no more input formats`. Combined with the missing `xdg-desktop-portal-hyprland` on this machine, **portal capture is a non-starter here**.

The current troubleshooting guidance recommends, for "GNOME / other" (Hyprland is "other"): `portal` capture + `vulkan` encoding when Vulkan works, else **`kms` capture + `nvenc`**. Note the config-choices table does not list `portal` even though the troubleshooting page uses it — a documentation gap I could not resolve (see §6).

Hyprland-specific quirks worth knowing:
- [#5087](https://github.com/LizardByte/Sunshine/issues/5087) (**closed** 2026-05-09): with `wlr`, a Hyprland **headless** output name in `output_name` is ignored; use the **numeric index** (e.g. `output_name = 1`). This is the pattern for a virtual display.
- [#5586](https://github.com/LizardByte/Sunshine/issues/5586) (open): SIGSEGV during service shutdown on **Hyprland/NVIDIA** — affects clean shutdown, not streaming.
- [#5671](https://github.com/LizardByte/Sunshine/issues/5671) (open): `wlr-screencopy` DMA-BUF regression on v2026.906 — reported on **AMD**/Hyprland, not confirmed on NVIDIA.

### HDR on Linux — conflicting primary sources
- [Getting Started](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html) (checked 2026-09-12) says HDR on Linux is "supported for **Intel and AMD GPUs** … using VAAPI", that **"the KMS capture backend is required for HDR capture"**, and that the compositor must support HDR rendering (Gamescope or KDE Plasma 6).
- The **v2026.906.222525 changelog** says: "**Hardware YUV 4:4:4 and HDR encoding on NVIDIA Linux systems.** CUDA and CUDA-GL capture paths can now provide higher-quality chroma reproduction, **including HDR configurations**" ([PR #4965](https://github.com/LizardByte/Sunshine/pull/4965), [#5315](https://github.com/LizardByte/Sunshine/pull/5315)), plus "automatic SDR fallback when HDR is unavailable" and PipeWire HDR/Rec.2020-PQ handling ([#5025](https://github.com/LizardByte/Sunshine/pull/5025)).

I could not reconcile these on NVIDIA + Hyprland. Treat **HDR on this box as unverified and out of scope** — the HDMI 2.0-class link already forces HDR off.

### Audio (PipeWire)
Sunshine captures audio from a named sink via `audio_sink`. Docs (checked 2026-09-12): "The name of the audio sink used for audio loopback… **FreeBSD/Linux + pipewire:** `pactl info | grep Source`" (try `Sink` if `Source` fails). To also mute the host speakers, use `virtual_sink` (e.g. Steam Streaming Speakers). On this box PipeWire is 1.6.8 (PulseAudio-on-PipeWire); `pactl info` default source is currently the analog **microphone**, so `audio_sink` must be set to the monitor of the output sink, or a virtual sink must be created.

### Input
Sunshine migrated to **libvirtualhid** in v2026.906 (changelog), which replaces Inputtino on Linux. Inputs may not work until udev rules are active; docs say reload them and, if still broken, add the user to the `input` group ([troubleshooting](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2troubleshooting.html)). **Live check 2026-09-12: `roni` is not in the `input` group, `uinput` is loaded but `uhid` is not.** The AUR package's `.install` script runs `setcap cap_sys_admin,cap_sys_nice+p`, reloads udev, and `modprobe uinput uhid` (checked 2026-09-12).

### Packaging
- **Not in Arch `core`/`extra` or CachyOS repos.** `https://archlinux.org/packages/search/json/?q=sunshine` returns 0 results (checked 2026-09-12). `moonlight-qt` **is** in `extra` (6.1.0-7).
- **AUR `sunshine` 2026.906.222525-1, maintained by `LizardByte` (the upstream project)** — [aur.archlinux.org/packages/sunshine](https://aur.archlinux.org/packages/sunshine) (checked 2026-09-12). Builds CUDA/NVENC only if `cuda` is installed (`_use_cuda=detect`; optdepend "cuda: Nvidia GPU encoding support"). Also `sunshine-bin`, `sunshine-git`, `sunshine-beta-bin`.
- **LizardByte's own pacman repo** (the only package source LizardByte supports): add to `/etc/pacman.conf` and `pacman -S lizardbyte/sunshine` ([LizardByte/pacman-repo](https://github.com/LizardByte/pacman-repo), checked 2026-09-12). The prebuilt `sunshine-2026.906.222525-1-x86_64.pkg.tar.zst` is CUDA-compatible with min driver 590.48.01 and **does not require installing `cuda`** (getting-started CUDA table), so it is the least-friction option on this box (driver 610.57.04).
- **nixpkgs:** `pkgs/by-name/su/sunshine/package.nix` and a NixOS module `nixos/modules/services/networking/sunshine.nix` exist (nixos-unstable tree, checked 2026-09-12). **There is no home-manager module** (home-manager `master` tree contains no `sunshine`). The nixpkgs package lags (2026.516.143833) and only enables CUDA behind `cudaSupport`.
- **systemd:** ships a **user** unit `app-dev.lizardbyte.app.Sunshine` (alias `sunshine.service`), enabled with `systemctl --user enable --now app-dev.lizardbyte.app.Sunshine`; the NixOS module wires it to `graphical-session.target` (getting-started + NixOS module, checked 2026-09-12).

### Ports (for firewalling)
Base port default **47989**; offsets (NixOS module, checked 2026-09-12): **TCP 47984, 47989, 47990, 48010; UDP 47998, 47999, 48000, 48002, 48010.** `ufw` is inactive here, so no rule needed unless enabled.

### Moonlight clients (receiving end)
From [moonlight-stream.org](https://moonlight-stream.org/) (checked 2026-09-12): Moonlight PC (`moonlight-qt` — Windows, macOS, Linux, **Steam Link hardware**, Raspberry Pi 4), Android, iOS/Apple TV, ChromeOS, embedded, plus community homebrew ports for **LG webOS (developer mode)**, Tizen, PS Vita, Switch, Wii U, Xbox. On Linux, `moonlight-qt` is in Arch `extra` (6.1.0-7); on Steam Deck install it from Flathub (`com.moonlight_stream.Moonlight`). The LG webOS client is `mariotaku/moonlight-tv` (v1.6.36, 2025-10-18; repo active 2026-09-07), installed via `dev-manager-desktop`/IPK — i.e. **sideload, developer mode**.

---

## 3. Head-to-head for THIS machine

**The decisive fact:** this Hyprland box has **no ScreenCast portal backend** (`xdg-desktop-portal-hyprland` absent, live 2026-09-12). Steam Remote Play's only Wayland capture path is PipeWire-via-portal, so it is broken here until xdph is installed *and* the open PipeWire-streaming bugs don't bite. Sunshine's `wlr` and `kms` capture paths do not use the portal, so they work with the stack as it stands.

**Ranked options**

1. **Sunshine host + Moonlight clients — recommended.**
   Trade-off: best odds of working on Hyprland/Wayland + NVIDIA (wlr-screencopy, no portal); costs a package install and one config file. LG TV requires a sideloaded community client.
2. **Sunshine host + Steam Link only on the Deck, Moonlight elsewhere** — a variant of #1.
   Trade-off: Deck gets zero-install Steam Link; other devices use Moonlight. But Steam Link can't reach Sunshine, so you'd still be running two hosts (Steam Remote Play + Sunshine) — extra moving parts.
3. **Steam Remote Play only.**
   Trade-off: zero install and native on Deck/PC, but on this box it needs `steam -pipewire` **plus** `xdg-desktop-portal-hyprland`, and there are open black-video/low-FPS/crash bugs. No LG webOS client at all.
4. **gamescope-session “Game Mode” + either** — **rejected** in ROADMAP (2026-09-08): unresolvable input latency and 60 Hz fps cap. Do not revisit.

**Wayland screen-capture problem, per stack**

- **Sunshine `wlr`:** wlr-screencopy directly against Hyprland; no portal, no XWayland. This is the documented Hyprland path.
- **Sunshine `kms`:** kernel DRM scanout; needs `cap_sys_admin` (set by the package) and `nvidia_drm.modeset=1` (already set). Good fallback; also the documented HDR path on Linux.
- **Steam Remote Play:** `-pipewire` → PipeWire via xdg-desktop-portal ScreenCast. **No xdph here → fails.** X11 fallback can't read Wayland-native surfaces (black frames for native-Wayland games/Big Picture).

**Audio routing (PipeWire)**

- Sunshine streams what a named sink receives; set `audio_sink` to the monitor of the default output (`pactl info | grep Source`, then verify with `pactl list short sources`), or create a virtual sink and set both `audio_sink` and `virtual_sink`. This lets you mute the host TV while streaming.
- Steam Remote Play handles audio internally; no user routing. Known surround channel-map bugs.

**Input**

- Both inject input into the host’s logged-in session; **neither makes host input exclusive** — the physical keyboard/mouse at the PC still acts. For a couch setup where nobody is at the PC, this is fine; if someone is, both inputs mix.
- Sunshine: virtual gamepads via libvirtualhid (`uinput`/`uhid`); add `roni` to `input` and reload udev. Steam Remote Play: needs `/dev/uinput` rw and has **no rumble on Linux hosts**; XInput gamepads work, wheels/flight sticks don’t.

**Host session / headless**

- Both need a running graphical session. If you want to stream with the TV/PC display off, create a **virtual display**: either a Hyprland headless output (`hyprctl output create headless`, then `wlr` + numeric `output_name`) or a dummy HDMI EDID plug. For Sunshine+KMS, a dummy plug is the most robust; for Sunshine+wlr, the Hyprland headless output is documented — but use the **numeric index** for `output_name` (#5087).

---

## 4. Integration notes for the fleek repo

The repo’s own rule applies: **GPU-adjacent apps are system packages, not nix** (nix GPU/GL builds abort on this NVIDIA box; `profiles/gaming.nix` header + ROADMAP). Sunshine links NVENC/CUDA and EGL, so **do not use `pkgs.sunshine`** — install the system package.

**`bootstrap.sh` (system layer)**
1. Add the LizardByte pacman repo to `/etc/pacman.conf` (or use AUR `paru -S sunshine`; if AUR, install `cuda` first so the build keeps NVENC):
   ```
   [lizardbyte]
   SigLevel = Optional
   Server = https://github.com/LizardByte/pacman-repo/releases/latest/download
   ```
   then `sudo pacman -S --needed lizardbyte/sunshine`.
2. `sudo usermod -aG input roni` and `sudo modprobe uhid` (the package’s `.install` already reloads udev and sets `cap_sys_admin,cap_sys_nice+p`).
3. `systemctl --user enable --now app-dev.lizardbyte.app.Sunshine` (bootstrap already runs as the user; if a root context is ever needed, use `systemctl --user -M roni@.host`).
4. Only if you enable `ufw`: open TCP `47984,47989,47990,48010` and UDP `47998,47999,48000,48002,48010`. Currently `ufw` is inactive, so skip.

**home-manager (`profiles/gaming.nix` / a shared module)**
- There is **no HM module** for Sunshine, so declare files with `home.file`:
  - `~/.config/sunshine/sunshine.conf` — a good starting point for this machine:
    ```
    sunshine_name = fleek-gaming
    capture = wlr
    encoder = nvenc
    output_name = HDMI-A-2
    hevc_mode = 2
    # audio_sink = <monitor source from `pactl info | grep Source`>
    ```
    (Use the numeric display index instead of `HDMI-A-2` when targeting a Hyprland headless output — see #5087.)
  - `~/.config/sunshine/apps.json` — e.g. a `Desktop` entry and a Big Picture entry (`steam -bigpicture`). Note Sunshine terminates an already-running app when starting an app; for a plain desktop stream, add an app named `Desktop`.
- The upstream package owns the user unit; if you would rather own it declaratively, add a `systemd.user.services.sunshine` unit that `ExecStart`s `/usr/bin/sunshine` and `WantedBy = [ "graphical-session.target" ]` (the NixOS module is the reference shape, but it is NixOS-only).
- If you also want **Steam Remote Play** to work on Hyprland, add system `xdg-desktop-portal-hyprland` (Arch `extra`) and launch Steam with `-pipewire`. Until then, don’t rely on it.

**NVIDIA/Hyprland-specific**
- `nvidia_drm.modeset=1` — already set; this is the documented fix for black KMS streams on NVIDIA.
- No new Hyprland env vars are required for `wlr`/`kms` capture. PipeWire is already running; Sunshine is a normal client.
- Kernel modules `uinput` (loaded) and `uhid` (load/enable) for virtual input.

---

## 5. Concrete setup path (recommended: Sunshine host)

1. On the gaming PC, add the LizardByte repo and install: `sudo pacman -S --needed lizardbyte/sunshine`, then `sudo usermod -aG input roni` and `sudo modprobe uhid`. Log out/in.
2. Write `~/.config/sunshine/sunshine.conf` (HM `home.file`) with `capture = wlr`, `encoder = nvenc`, `output_name = HDMI-A-2`, `hevc_mode = 2`, and `audio_sink` set to the PipeWire monitor source (or a virtual sink).
3. `systemctl --user enable --now app-dev.lizardbyte.app.Sunshine`, then open `https://localhost:47990` to pair a client (the web UI is the sanctioned setup surface).
4. On the **laptop**: install `moonlight-qt` (Arch `extra`) or Flathub Moonlight; add the host by IP/PIN.
5. On the **Steam Deck**: install Moonlight from Flathub (`com.moonlight_stream.Moonlight`) and pair the same way (Steam Remote Play remains available as the built-in fallback).
6. On the **LG TV**: install the community **Moonlight TV** client (`mariotaku/moonlight-tv`) via `dev-manager-desktop`/developer mode, then pair. There is no official Steam Link app for LG webOS, so Sunshine+Moonlight is the only path that doesn’t require an extra streaming stick.
7. If capture misbehaves: try the automatic default, then force `capture = kms` (uses the `cap_sys_admin` the package sets); for a headless/virtual display, switch to the numeric `output_name` and/or a dummy HDMI plug.

---

## 6. High-uncertainty / could not verify

- **Sunshine HDR on NVIDIA + Linux.** The changelog claims CUDA/CUDA-GL HDR support; the getting-started page still says Linux HDR is Intel/AMD VAAPI + KMS-only. I could not resolve which is authoritative for this GPU/compositor. Not blocking: HDR is disabled on this HDMI link anyway.
- **Sunshine `portal` capture option name.** The troubleshooting page recommends `portal` capture, but the `capture` config-choices table does not list `portal` (only `nvfbc`, `wlr`, `kms`, `kwin`, `x11`). Portal capture is definitely in the source (`src/platform/linux/portalgrab.cpp`) but is broken on Hyprland (#4662).
- **Whether `wlr` capture reliably works on Hyprland + NVIDIA in the current stable build.** The documented Hyprland support and #5087 suggest yes with the numeric index, but #5586 (NVIDIA/NVIDIA-shutdown crash) and general Hyprland/NVIDIA fragility mean this needs a live test.
- **Steam Remote Play HDR from a Linux + NVIDIA + Hyprland host.** Not documented by Valve; only Deck-OLED HDR was announced. Unverified.
- **Steam's `-pipewire` default status is a moving target.** #13609 (2026-09-12) says it is still required; a future client could make it default.
- **LG webOS Moonlight TV store availability.** Primary sources (`moonlight-stream.org`, `mariotaku/moonlight-tv` README) describe developer-mode/sideload installation, not an official LG Content Store listing. I did not verify an LG store presence.

---

## Sources index

- **Steam Remote Play:** product page https://store.steampowered.com/remoteplay/ · Remote Play FAQ https://help.steampowered.com/en/faqs/view/0689-74B8-92AC-10F2 · Steam Link FAQ https://help.steampowered.com/en/faqs/view/7E9D-27C8-EB08-21D9 · Steam client news (appid 593110) https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=593110&count=100 · Sept 1 2026 update https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1842846814438758 · Dec 3 2024 update https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/1784506359193587
- **steam-for-linux issues:** #13609, #13585, #13179, #13578, #13340, #13600, #6150 — https://github.com/ValveSoftware/steam-for-linux/issues
- **Sunshine:** repo https://github.com/LizardByte/Sunshine · README support matrix, capture/encoding tables, requirements https://github.com/LizardByte/Sunshine/blob/master/README.md · getting started (install, services, HDR) https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2getting__started.html · configuration (`capture`, `encoder`, `output_name`, `audio_sink`, `virtual_sink`, `port`, `hevc_mode`, `av1_mode`) https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html · troubleshooting (recommended capture/encoder, portal token, KMS/NVIDIA modeset, input group) https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2troubleshooting.html · changelog (v2026.906.222525) https://github.com/LizardByte/Sunshine/blob/changelog/CHANGELOG.md · issues #4662, #5087, #5586, #5671 https://github.com/LizardByte/Sunshine/issues
- **Packaging:** LizardByte pacman repo https://github.com/LizardByte/pacman-repo · AUR `sunshine` https://aur.archlinux.org/packages/sunshine (PKGBUILD + `.install` via https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=sunshine) · AUR RPC https://aur.archlinux.org/rpc/v5/info?arg[]=sunshine · Arch `moonlight-qt` https://archlinux.org/packages/?q=moonlight-qt · Arch `xdg-desktop-portal-hyprland` https://archlinux.org/packages/?q=xdg-desktop-portal-hyprland · nixpkgs `pkgs/by-name/su/sunshine/package.nix` + `nixos/modules/services/networking/sunshine.nix` https://github.com/NixOS/nixpkgs
- **Moonlight:** project site + client list https://moonlight-stream.org/ · moonlight-qt https://github.com/moonlight-stream/moonlight-qt · Moonlight TV (LG webOS, community) https://github.com/mariotaku/moonlight-tv · Flathub Moonlight `com.moonlight_stream.Moonlight` https://flathub.org/apps/com.moonlight_stream.Moonlight · Steam Link (Linux) Flathub https://flathub.org/apps/com.valvesoftware.SteamLink
