# Fleek — Home Manager Configuration

Declarative user environment management via home-manager, targeting multiple machines with profile-based composition. Each profile selects shell tools, desktop environment, and machine-specific packages.

## Language

**Profile**:
A named bundle of HM modules that configures one machine role (`work`, `private`, `gaming`). Profiles extend shared modules; only one is active per machine.
_Avoid_: Environment, role, persona

**Shared modules**:
HM modules applied to every profile — core CLI tools, shell config, paths, and programs that are universal across all machines.
_Avoid_: Common config, base, foundation

**Fleek**:
The name of this repository and the flake that builds all HM generations. Originally a fork of `ublue-os/fleek`, now manually maintained.
_Avoid_: Config repo, dotfiles

**Target**:
A fully qualified HM generation name in the format `user@profile`. Example: `roni@gaming`, `nixos@work`.
_Avoid_: Hostname, machine name, generation

**Apply**:
Running `home-manager switch --flake ...` to activate a profile. The flake provides `apply-*` convenience apps. Example: `nix run .#apply-gaming`.
_Avoid_: Install, deploy, build

**Gaming PC**:
The user's desktop machine (Intel i5-11400F, NVIDIA RTX 3060 Ti, 32 GB RAM, 2TB NVMe + 4TB HDD). Runs CachyOS with Hyprland as the WM, configured by the `gaming` profile.
_Avoid_: Desktop, main rig, battlestation

**CachyOS**:
Arch-based Linux distribution with a custom performance-optimized kernel (BORE scheduler, x86-64-v3 packages). Chosen over Bazzite for: mutable filesystem (full Nix compatibility), AUR access, and gaming-meta package for system-level gaming setup.
_Avoid_: Bazzite (rejected alternative)

**Matugen**:
Wallpaper-driven theming pipeline used by the gaming profile (superseded Stylix, which is disabled because nix GPU/GL builds abort on NVIDIA). `palette.py` samples the wallpaper into a Material palette + custom ANSI hues, writes `~/.cache/matugen/scheme.json`, and renders the HM-managed templates (`profiles/matugen/*.tmpl`) into app configs. Runtime outputs are matugen-owned and regenerable.
_Avoid_: Theming engine, color scheme manager

**Runtime theme switch**:
Keybind-triggered scripts (Super+T `theme-toggle`, Super+W `rotate-wallpaper.sh`) that re-run the matugen pipeline in light or dark mode and reload themed surfaces in place (hyprctl, waybar, swaync, kitty, gsettings color-scheme).
_Avoid_: Dark mode toggle, day/night mode

**Gamescope**:
Valve's micro-compositor used to launch individual games in an isolated Wayland session from Hyprland. Provides independent resolution scaling, FSR/NIS upscaling, frame limiting, and HDR passthrough.
_Avoid_: Game session, nested compositor
