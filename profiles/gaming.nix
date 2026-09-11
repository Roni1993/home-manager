{ pkgs, lib, inputs, ... }: {
  # ── Gaming profile — CachyOS + Hyprland ────────────────────────
  # Target machine: Intel i5-11400F, NVIDIA RTX 3060 Ti, 32 GB RAM,
  # 2 TB NVMe (OS + active games) + 4 TB HDD (game library overflow).
  #
  # CachyOS provides: kernel (BORE scheduler), NVIDIA drivers,
  # Steam, PipeWire, plasmalogin, KDE base, gaming-meta package.
  # This profile provides: Hyprland companion tools, theming via the
  # matugen pipeline (palette.py + templates), gaming performance
  # tools, and user-level configs.
  #
  # Apply with: nix run ~/projects/fleek#apply-gaming
  # ─────────────────────────────────────────────────────────────────

  # ── User-level packages (not provided by CachyOS base) ──
  # GPU-adjacent apps are system-provided (pacman): nix builds crash on
  # NVIDIA EGL/GBM (nix kitty, nix hyprland) or inject into system
  # processes (mangohud). Only non-GPU CLI/TUI tools stay in nix.
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    # Gaming tools (system: discord, mangohud)
    protonup-qt
    goverlay
    nvtopPackages.full
    gwe

    # Hyprland ecosystem (system: hyprland/hyprlock/hyprshot/hyprpicker/awww).
    # nwg-displays is a plain GTK client — safe.
    nwg-displays

    # Audio
    pavucontrol

    # Clipboard
    wl-clipboard

    # Fonts
    (nerd-fonts.jetbrains-mono)
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # ── Git ──
  programs.git = {
    enable = true;
    settings = {
      user.name = "Roman";
      user.email = "roman.weintraub@gmail.com";
      alias = {
        pushall = "!git remote | xargs -L1 git push --all";
        graph = "log --decorate --oneline --graph";
        add-nowhitespace = "!git diff -U0 -w --no-color | git apply --cached --ignore-whitespace --unidiff-zero -";
      };
      feature.manyFiles = true;
      init.defaultBranch = "main";
      gpg.format = "ssh";
      credential.helper = "!gh auth git-credential";
    };
    signing = {
      key = "";
      signByDefault = builtins.stringLength "" > 0;
    };
    lfs.enable = true;
    ignores = [ ".direnv" "result" ];
  };

  # ── Hyprland WM ──
  # The COMPOSITOR is system-provided (pacman `hyprland`). The nix/HM
  # hyprland build aborts on this machine: its bundled mesa looks for
  # /run/opengl-driver/lib/gbm/dri_gbm.so (a NixOS path) which doesn't
  # exist on CachyOS, so the DRM backend fails -> black screen. The
  # system build links against system mesa + NVIDIA stack (same as KDE).
  # Config is managed here via home.file instead of the HM module.
  home.file.".config/hypr/hyprland.conf" = {
    text = ''
      $mod=SUPER
      # matugen-generated palette (wallpaper-driven); absent until `matugen
      # image <wall>` runs — hyprland warns but continues.
      source = ~/.config/hypr/hyprland-colors.conf
      exec-once=/usr/bin/dbus-update-activation-environment --systemd DISPLAY HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE

      env=XCURSOR_SIZE,24
      env=XDG_CURRENT_DESKTOP,Hyprland
      env=XDG_SESSION_TYPE,wayland
      env=XDG_SESSION_DESKTOP,Hyprland
      env=QT_QPA_PLATFORM,wayland;xcb
      env=QT_WAYLAND_DISABLE_WINDOWDECORATION,1
      env=SDL_VIDEODRIVER,wayland
      env=MOZ_ENABLE_WAYLAND,1
      # NVIDIA VA-API hw decode for the nix Firefox: select the system
      # libva-nvidia-driver and let the RDD process open /dev/nvidia*.
      env=LIBVA_DRIVER_NAME,nvidia
      env=LIBVA_DRIVERS_PATH,/usr/lib/dri
      env=NVD_BACKEND,direct
      env=MOZ_DISABLE_RDD_SANDBOX,1
      env=GDK_BACKEND,wayland,x11

      exec-once=awww-daemon
      exec-once=hypridle
      exec-once=vicinae server
      # waybar + swaync are started by their HM systemd user services (no
      # exec-once — a second launch makes the service fail with "instance
      # already running" and hit start-limit). Re-apply the theme after login
      # so all matugen outputs match the persisted mode/wallpaper (kitty etc.
      # read them fresh at startup).
      exec-once=sh -c 'sleep 3; ~/.local/bin/apply-theme.sh "$(cat ~/.cache/theme-mode 2>/dev/null || echo dark)"'
      # clipboard history is vicinae-native (Super+V); no cliphist.
      exec-once=/usr/lib/hyprpolkitagent/hyprpolkitagent
      # env import happens once, at the top of this file (the
      # dbus-update-activation-environment exec-once above covers DISPLAY,
      # WAYLAND_DISPLAY, XDG_* and HYPRLAND_INSTANCE_SIGNATURE).

      monitor=,preferred,auto,1

      input {
        kb_layout=us
        follow_mouse=1
        touchpad {
          natural_scroll=true
        }
      }

      general {
        gaps_in=5
        gaps_out=10
        border_size=2
        col.active_border=$primary $secondary
        col.inactive_border=$outline_variant
        layout=dwindle
      }

      decoration {
        rounding=10
        blur {
          enabled=true
          size=3
          passes=1
          new_optimizations=true
        }
        shadow {
          enabled=true
          range=4
          render_power=3
          color=rgba(1a1a1aee)
        }
      }

      animations {
        enabled=true
        bezier=myBezier, 0.05, 0.9, 0.1, 1.05
        bezier=linear, 0, 0, 1, 1
        animation=windows, 1, 7, myBezier
        animation=windowsOut, 1, 7, default, popin 80%
        animation=border, 1, 10, default
        animation=fade, 1, 7, default
        animation=workspaces, 1, 6, default
      }

      misc {
        disable_hyprland_logo=true
        disable_splash_rendering=true
      }

      render {
        direct_scanout=true
      }

      dwindle {
        preserve_split=true
      }

      master {
        new_on_top=true
      }

      bind=$mod, RETURN, exec, kitty
      bind=$mod, Q, killactive
      bind=$mod, M, exit
      bind=$mod, E, exec, nautilus
      bind=$mod, F, fullscreen
      bind=$mod SHIFT, SPACE, togglefloating
      bind=$mod, R, exec, vicinae toggle
      bind=$mod, P, pseudo
      bind=$mod, SPACE, exec, vicinae toggle
      bind=$mod, L, exec, hyprlock
      bind=$mod, T, exec, ~/.local/bin/theme-toggle
      bind=$mod, W, exec, ~/.local/bin/rotate-wallpaper.sh

      bind=, PRINT, exec, hyprshot -m region
      bind=$mod SHIFT, S, exec, hyprshot -m region
      bind=$mod, PRINT, exec, hyprshot -m output
      bind=$mod, N, exec, swaync-client -t

      # clipboard history (Super+V → vicinae clipboard:history) bind lives
      # in matugen/hyprland-colors.tmpl (sourced by hyprland.conf) so it also
      # works pre-rebuild and survives reloads.

      bind=$mod, 1, workspace, 1
      bind=$mod, 2, workspace, 2
      bind=$mod, 3, workspace, 3
      bind=$mod, 4, workspace, 4
      bind=$mod, 5, workspace, 5
      bind=$mod, 6, workspace, 6
      bind=$mod, 7, workspace, 7
      bind=$mod, 8, workspace, 8
      bind=$mod, 9, workspace, 9
      bind=$mod, 0, workspace, 10

      bind=$mod SHIFT, 1, movetoworkspacesilent, 1
      bind=$mod SHIFT, 2, movetoworkspacesilent, 2
      bind=$mod SHIFT, 3, movetoworkspacesilent, 3
      bind=$mod SHIFT, 4, movetoworkspacesilent, 4
      bind=$mod SHIFT, 5, movetoworkspacesilent, 5
      bind=$mod SHIFT, 6, movetoworkspacesilent, 6
      bind=$mod SHIFT, 7, movetoworkspacesilent, 7
      bind=$mod SHIFT, 8, movetoworkspacesilent, 8
      bind=$mod SHIFT, 9, movetoworkspacesilent, 9
      bind=$mod SHIFT, 0, movetoworkspacesilent, 10

      bind=$mod, mouse_down, workspace, e+1
      bind=$mod, mouse_up, workspace, e-1

      binde=, XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
      binde=, XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
      binde=, XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle

      bindl=, XF86AudioPlay, exec, playerctl play-pause
      bindl=, XF86AudioNext, exec, playerctl next
      bindl=, XF86AudioPrev, exec, playerctl previous

      bindm=$mod, mouse:272, movewindow
      bindm=$mod, mouse:273, resizewindow

      # 0.56 windowrule syntax: `<rule> <match>` (space-separated, no comma).
      # fullscreen works; noblur/nomaximizerequest were removed in 0.56.
      windowrule=fullscreen class:^(.*.exe)$
    '';
  };

  # ── Dynamic theming — matugen + palette.py (custom scheme) ──
  # palette.py dumps matugen's scheme-expressive Material palette (UI chrome)
  # then injects six ANSI hues sampled from the wallpaper's actual hue
  # distribution (Material fixed hues as fallback for empty slots), and renders
  # config.toml + kitty.toml. HM manages matugen's config + templates; the
  # generated files (~/.config/hypr/hyprland-colors.conf etc.) are matugen-owned
  # runtime configs. Re-run with:
  #   python3 ~/.config/matugen/palette.py ~/Pictures/wallpaper.jpg dark
  home.file.".config/matugen/config.toml" = {
    text = ''
      [config]
      caching = false
      prefer = "darkness"

      [templates.hyprland]
      # absolute path: config.toml is a nix-store symlink, so relative
      # input_paths would resolve into the store
      input_path = "~/.config/matugen/templates/hyprland-colors.conf"
      output_path = "~/.config/hypr/hyprland-colors.conf"

      [templates.waybar]
      input_path = "~/.config/matugen/templates/waybar-style.css"
      output_path = "~/.config/waybar/style.css"

      [templates.swaync]
      input_path = "~/.config/matugen/templates/swaync-style.css"
      output_path = "~/.config/swaync/style.css"

      [templates.gtk3]
      input_path = "~/.config/matugen/templates/gtk.css"
      output_path = "~/.config/gtk-3.0/gtk.css"

      [templates.gtk4]
      input_path = "~/.config/matugen/templates/gtk.css"
      output_path = "~/.config/gtk-4.0/gtk.css"

      [templates.vicinae]
      input_path = "~/.config/matugen/templates/vicinae.toml"
      output_path = "~/.local/share/vicinae/themes/matugen.toml"
      post_hook = "vicinae theme set matugen"

      [templates.firefox_websites]
      input_path = "~/.config/matugen/templates/firefox_websites.css"
      output_path = "~/.config/matugen/generated/firefox_websites.css"

      [templates.btop]
      input_path = "~/.config/matugen/templates/btop.theme"
      output_path = "~/.config/btop/themes/matugen.theme"

      [templates.micro]
      input_path = "~/.config/matugen/templates/micro.micro"
      output_path = "~/.config/micro/colorschemes/matugen.micro"

      [templates.hyprlock]
      input_path = "~/.config/matugen/templates/hyprlock-colors.conf"
      output_path = "~/.config/hypr/hyprlock-colors.conf"


      [templates.nvim]
      input_path = "~/.config/matugen/templates/nvim-colors.lua"
      output_path = "~/.config/nvim/matugen.lua"

      [templates.helix]
      input_path = "~/.config/matugen/templates/helix-theme.toml"
      output_path = "~/.config/helix/themes/matugen.toml"

      [templates.midnight_discord]
      input_path = "~/.config/matugen/templates/midnight-discord.css"
      output_path = "~/.config/vesktop/themes/midnight-discord.css"

      [templates.spicetify]
      input_path = "~/.config/matugen/templates/spicetify.ini"
      output_path = "~/.config/spicetify/Themes/matugen/color.ini"

      [templates.zed]
      input_path = "~/.config/matugen/templates/zed-theme.json"
      output_path = "~/.config/zed/themes/matugen.json"

      [templates.steam]
      input_path = "~/.config/matugen/templates/steam.css"
      output_path = "~/.config/matugen/generated/steam.css"
      # CSS Loader (Decky) reads ~/homebrew/themes/<name>/theme.css; copy the
      # rendered file there so it shows up as an enablable theme.
      post_hook = "mkdir -p ~/homebrew/themes/matugen && cp ~/.config/matugen/generated/steam.css ~/homebrew/themes/matugen/theme.css"
    '';
  };
  home.file.".config/matugen/templates/hyprland-colors.conf" = {
    source = ./matugen/hyprland-colors.tmpl;
  };
  home.file.".config/matugen/kitty.toml" = {
    # Terminal palettes rendered AFTER palette.py injects the custom ANSI
    # roles (red/green/.../cyan_bright), so kitty/ghostty/alacritty share the
    # same wallpaper-derived scheme. Rendered via `matugen json` (post-patch).
    text = ''
      [config]
      prefer = "darkness"
      # no caching: palette.py always computes fresh from the wallpaper
      [templates.kitty]
      input_path = "~/.config/matugen/templates/kitty-colors.conf"
      output_path = "~/.config/kitty/kitty-colors.conf"

      [templates.ghostty]
      input_path = "~/.config/matugen/templates/ghostty-colors.conf"
      output_path = "~/.config/ghostty/themes/matugen"

      [templates.alacritty]
      input_path = "~/.config/matugen/templates/alacritty-colors.toml"
      output_path = "~/.config/alacritty/colors.toml"
    '';
  };
  home.file.".config/matugen/templates/kitty-colors.conf" = {
    source = ./matugen/kitty-colors.tmpl;
  };
  home.file.".config/matugen/palette.py" = {
    source = ./matugen/palette.py;
    executable = true;
  };
  home.file.".config/matugen/templates/waybar-style.css" = {
    source = ./matugen/waybar-style.css.tmpl;
  };
  home.file.".config/matugen/templates/swaync-style.css" = {
    source = ./matugen/swaync-style.css.tmpl;
  };
  home.file.".config/matugen/templates/gtk.css" = {
    source = ./matugen/gtk.css.tmpl;
  };
  home.file.".config/matugen/templates/vicinae.toml" = {
    source = ./matugen/vicinae.toml;
  };
  home.file.".config/matugen/templates/firefox_websites.css" = {
    source = ./matugen/firefox_websites.css.tmpl;
  };
  home.file.".config/matugen/templates/ghostty-colors.conf" = {
    source = ./matugen/ghostty-colors.tmpl;
  };
  home.file.".config/matugen/templates/alacritty-colors.toml" = {
    source = ./matugen/alacritty-colors.tmpl;
  };
  home.file.".config/matugen/templates/btop.theme" = {
    source = ./matugen/btop.theme.tmpl;
  };
  home.file.".config/matugen/templates/micro.micro" = {
    source = ./matugen/micro.micro.tmpl;
  };
  home.file.".config/matugen/templates/hyprlock-colors.conf" = {
    source = ./matugen/hyprlock-colors.tmpl;
  };
  home.file.".config/matugen/templates/nvim-colors.lua" = {
    source = ./matugen/nvim-colors.lua.tmpl;
  };
  home.file.".config/matugen/templates/helix-theme.toml" = {
    source = ./matugen/helix-theme.toml.tmpl;
  };
  home.file.".config/matugen/templates/midnight-discord.css" = {
    source = ./matugen/midnight-discord.css.tmpl;
  };
  home.file.".config/matugen/templates/spicetify.ini" = {
    source = ./matugen/spicetify.ini.tmpl;
  };
  home.file.".config/matugen/templates/zed-theme.json" = {
    source = ./matugen/zed-theme.json.tmpl;
  };
  home.file.".config/matugen/templates/steam.css" = {
    source = ./matugen/steam.css.tmpl;
  };
  # matugen can't create this dir; HM ensures it exists for the theme output
  home.file.".config/zed/themes/.keep" = {
    text = "";
  };
  # ── App theming wiring (matugen-generated files) ──
  home.file.".config/ghostty/config.ghostty" = {
    text = ''
      # Ghostty (HM-managed); colors come from the matugen-generated theme
      # (~/.config/ghostty/themes/matugen). NOTE: ghostty 1.3 has no auto-reload
      # on theme change — press ctrl+shift+r (or the default ctrl+shift+,) to
      # apply colors after a theme switch.
      theme = matugen
      background-opacity = 0.8
      keybind = ctrl+shift+r=reload_config
    '';
  };
  # matugen can't create this dir; HM ensures it exists for the theme output
  home.file.".config/ghostty/themes/.keep" = {
    text = "";
  };
  home.file.".config/alacritty/alacritty.toml" = {
    text = ''
      [general]
      working_directory = "None"
      live_config_reload = true
      # matugen-generated colors (colors.toml); the inline [colors] blocks were
      # removed so the import isn't overridden.
      import = ["~/.config/alacritty/colors.toml"]

      [env]
      TERM = "xterm-256color"
      WINIT_X11_SCALE_FACTOR = "1.0"

      [window]
      dimensions = { columns = 100, lines = 30 }
      dynamic_padding = true
      decorations = "Full"
      opacity = 0.8
      title = "Alacritty@CachyOS"
      class = { instance = "Alacritty", general = "Alacritty" }
      decorations_theme_variant = "Dark"

      [scrolling]
      history = 10000
      multiplier = 3

      [font]
      normal = { family = "monospace", style = "Regular" }
      bold = { family = "monospace", style = "Bold" }
      italic = { family = "monospace", style = "Italic" }
      bold_italic = { family = "monospace", style = "Bold Italic" }
      size = 12.0

      [selection]
      semantic_escape_chars = ",│`|:\"' ()[]{}<>\t"
      save_to_clipboard = true

      [cursor]
      style = { shape = "Underline", blinking = "Off" }
      unfocused_hollow = true
      thickness = 0.15

      [mouse]
      hide_when_typing = true
      bindings = [
      { mouse = "Middle", mods = "None", action = "PasteSelection" },
      ]

      [keyboard]
      bindings = [
      { key = "Paste", mods = "None", action = "Paste" },
      { key = "Copy", mods = "None", action = "Copy" },
      { key = "L", mods = "Control", action = "ClearLogNotice" },
      { key = "L", mods = "Control", mode = "~Vi", chars = "\f" },
      { key = "PageUp", mods = "Shift", mode = "~Alt", action = "ScrollPageUp" },
      { key = "PageDown", mods = "Shift", mode = "~Alt", action = "ScrollPageDown" },
      { key = "Home", mods = "Shift", mode = "~Alt", action = "ScrollToTop" },
      { key = "End", mods = "Shift", mode = "~Alt", action = "ScrollToBottom" },
      { key = "V", mods = "Control|Shift", action = "Paste" },
      { key = "C", mods = "Control|Shift", action = "Copy" },
      { key = "F", mods = "Control|Shift", action = "SearchForward" },
      { key = "B", mods = "Control|Shift", action = "SearchBackward" },
      { key = "C", mods = "Control|Shift", mode = "Vi", action = "ClearSelection" },
      { key = "Key0", mods = "Control", action = "ResetFontSize" },
      ]
    '';
  };
  home.file.".config/btop/btop.conf" = {
    text = ''
      color_theme = "matugen"
    '';
  };
  home.file.".config/micro/settings.json" = {
    text = ''
      {
        "colorscheme": "matugen"
      }
    '';
  };
  # opencode config (HM-managed)
  # NOTE: the opencode-chrome-devtools plugin drives browser_* tools via its
  # companion binary ~/.local/bin/ocx (v2, manual install, unmanaged on purpose
  # — matches the pinned HM opencode version's plugin expectations).
  home.file.".config/opencode/opencode.jsonc" = {
    text = ''
      {
        "$schema": "https://opencode.ai/config.json",
        "plugin": [
          "opencode-chrome-devtools"
        ],
        "agent": {
          "frontier": {
            "mode": "subagent",
            "model": "opencode-go/kimi-k3",
            "description": "Deep-review and cleanup agent for the CachyOS+Nix setup (runs on Kimi K3). Use for sanity checks, cleanup, and improvement investigations.",
            "permission": {
              "edit": "allow",
              "bash": "allow"
            },
            "prompt": "You are 'frontier', a deep-review and cleanup agent for this CachyOS + Nix hybrid setup. Investigate the environment and repo, find issues and improvement opportunities, apply only safe/trivial fixes, and report findings clearly. The specific task and scope are given when you are invoked."
          }
        }
      }
    '';
  };
  # idle-guard plugin: signals real agent activity to opencode-idle-guard.
  # Touches ~/.cache/opencode/active on tool exec / message stream; removes it
  # on session.idle. The guard holds the hypridle inhibitor only while this
  # marker is fresh — so an idle-but-open TUI does NOT block the lockscreen.
  home.file.".config/opencode/plugins/idle-guard.ts" = {
    text = ''
      import * as fs from "node:fs/promises"
      import * as path from "node:path"
      import * as os from "node:os"
      import type { Plugin } from "@opencode-ai/plugin"
      import type { Event } from "@opencode-ai/sdk"

      const MARKER = path.join(os.homedir(), ".cache/opencode/active")

      async function markActive() {
        try {
          await fs.mkdir(path.dirname(MARKER), { recursive: true })
          await fs.writeFile(MARKER, String(Date.now()))
        } catch {}
      }
      async function clearActive() {
        try {
          await fs.rm(MARKER, { force: true })
        } catch {}
      }

      export const IdleGuardPlugin: Plugin = async () => {
        return {
          "tool.execute.before": async () => {
            await markActive()
          },
          event: async ({ event }: { event: Event }) => {
            const e = event as { type: string }
            if (e.type === "message.part.updated") {
              await markActive()
            } else if (e.type === "session.idle") {
              await clearActive()
            }
          },
        }
      }
    '';
  };
  # nvim: minimal config that loads the matugen-generated colorscheme
  home.file.".config/nvim/init.lua" = {
    text = ''
      local matugen_file = vim.fn.stdpath("config") .. "/matugen.lua"
      if vim.fn.filereadable(matugen_file) == 1 then
        dofile(matugen_file)
      else
        vim.cmd("colorscheme habamax")
      end
    '';
  };
  # helix: use the matugen-generated theme
  home.file.".config/helix/config.toml" = {
    text = ''
      theme = "matugen"
    '';
  };
  # matugen can't create this dir; HM ensures it exists for the theme output
  home.file.".config/helix/themes/.keep" = {
    text = "";
  };

  # ── MatugenFox (Firefox dynamic theming) ──
  # Live, dynamic webpage theming for Firefox powered by matugen. The extension
  # (installed from AMO) talks to the vendored native host below, which watches
  # the matugen-generated firefox_websites.css. See MatugenFox README.
  home.file.".local/bin/matugenfox_host.py" = {
    source = ./matugenfox/matugenfox_host.py;
    executable = true;
  };
  home.file.".mozilla/native-messaging-hosts/matugenfox.json" = {
    text = ''
      {
        "name": "matugenfox",
        "description": "MatugenFox Native Messaging Host",
        "path": "/home/roni/.local/bin/matugenfox_host.py",
        "type": "stdio",
        "allowed_extensions": [
          "matugenfox@ubaid.com"
        ]
      }
    '';
  };
  home.file.".config/matugenfox/config.json" = {
    text = ''
      {
        "ecoMode": true,
        "colorsPath": "~/.config/matugen/generated/firefox_websites.css",
        "websitesDir": "~/.config/dusky_sites",
        "browserThemeEnabled": true,
        "webThemeEnabled": false,
        "firefoxProfilePath": "/home/roni/.mozilla/firefox/roni"
      }
    '';
  };
  # MatugenFox site-specific themes dir — must exist or the extension warns
  # "Paths Not Found". Drop per-domain CSS here (github.css etc.).
  home.file.".config/dusky_sites/README.md" = {
    text = ''
      # MatugenFox site-specific themes
      Place per-site .css files here (e.g. github.css with an
      `@-moz-document domain("github.com")` rule). The MatugenFox extension
      injects them using the --mg-* palette variables.
    '';
  };
  # userChrome.css is HM-managed rather than relying on the extension's toggle
  # (whose WRITE_USER_CHROME didn't reliably reach the native host). This is
  # the compact-toolbar/scrollbar CSS the host would write; browser CHROME
  # COLORS still come from MatugenFox's browser-theme path (works).
  home.file.".mozilla/firefox/roni/chrome/userChrome.css" = {
    text = ''
      /* MatugenFox userChrome.css - Auto-generated, do not edit manually */
      /* Font size: 13px */

      /* ── Scrollbar ── */
      :root {
        --uc-base-font-size: 13px;
        scrollbar-width: thin;
      }

      /* ── Toolbar compact ── */
      #nav-bar {
        height: calc(var(--uc-base-font-size) * 2.8) !important;
      }

      /* ── Context menu ── */
      menupopup > menuitem,
      menupopup > menu {
        font-size: var(--uc-base-font-size) !important;
        min-height: calc(var(--uc-base-font-size) * 1.8) !important;
      }
    '';
  };

  # ── Bar ──
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 36;
        margin-top = 6;
        margin-left = 8;
        margin-right = 8;
        modules-left = [ "hyprland/workspaces" "hyprland/window" "mpris" ];
        modules-center = [ "clock" ];
        modules-right = [ "tray" "custom/idle" "bluetooth" "pulseaudio" "network" "temperature" "cpu" "memory" "battery" "custom/updates" "custom/power" ];

        "hyprland/workspaces" = {
          all-outputs = true;
          format = "{name}";
        };
        "hyprland/window" = {
          format = "{title}";
          max-length = 40;
          separate-outputs = true;
        };
        "mpris" = {
          format = "{status_icon} {player_icon} {dynamic}";
          dynamic-order = [ "title" "artist" ];
          status-icons = {
            paused = "⏵";
            playing = "⏸";
            stopped = "⏹";
          };
          player-icons = {
            default = "󰓇";
          };
        };
        clock = {
          format = "{:%H:%M:%S}";
          tooltip-format = "{:%A, %d %B %Y}";
        };
        tray = {
          spacing = 8;
        };
        "custom/idle" = {
          format = "󰂢 {0}";
          tooltip-format = "Idle inhibitor: {0}";
          exec = "~/.local/bin/idle-toggle.sh status";
          on-click = "~/.local/bin/idle-toggle.sh toggle";
          interval = 5;
        };
        bluetooth = {
          format = "{status}";
          format-connected = "󰂯 {device_alias}";
          format-off = "󰂲";
          format-disabled = "󰂲";
          tooltip-format = "{controller_alias}  {num_connections} connected";
          on-click = "bluetoothctl power toggle";
        };
        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟 muted";
          format-icons = {
            default = [ "󰕿" "󰖀" "󰕾" ];
          };
          tooltip-format = "{desc}  {volume}%";
          on-click = "pavucontrol";
          on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
          on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        };
        network = {
          format-wifi = "󰤨 {essid} {signalStrength}%";
          format-ethernet = "󰈀 connected";
          format-disconnected = "󰤮";
          tooltip-format = "{ifname}  {ipaddr}";
          on-click = "nmtui";
        };
        temperature = {
          thermal-zone = 1;
          format = "󰔄 {temperatureC}°C";
          critical-threshold = 85;
          tooltip-format = "CPU {temperatureC}°C";
        };
        cpu = {
          format = "󰻠 {usage}%";
          tooltip-format = "Load {load_percent}% ({load_1}/{load_5}/{load_15})";
        };
        memory = {
          format = "󰍛 {}%";
          tooltip-format = "{used:0.1f} GiB / {total:0.1f} GiB";
        };
        battery = {
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-icons = [ "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
          tooltip-format = "{timeTo}";
        };
        "custom/updates" = {
          exec = "checkupdates 2>/dev/null | wc -l";
          exec-on-event = true;
          interval = 1800;
          format = "󰮯 {0}";
          tooltip-format = "{0} pacman updates";
        };
        "custom/power" = {
          format = "󰐥";
          tooltip-format = "Power — Lock / Logout / Reboot / Shutdown (Vicinae)";
          on-click = "vicinae toggle";
        };
      };
    };
    # style.css is generated by matugen (see "Dynamic theming" above)
  };

  # ── Wallpaper rotation ──
  # Every few hours pick the next wallpaper from ~/Pictures/wallpapers and
  # re-theme the whole session (awww + matugen via set-wallpaper).
  home.file.".local/bin/rotate-wallpaper.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      pool="$HOME/Pictures/wallpapers"
      state="$HOME/.cache/wallpaper-index"
      mapfile -t wps < <(find "$pool" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort)
      [ "''${#wps[@]}" -eq 0 ] && exit 1
      idx=$(cat "$state" 2>/dev/null || echo 0)
      next=$(( (idx + 1) % "''${#wps[@]}" ))
      echo "$next" > "$state"
      exec "$HOME/.local/bin/set-wallpaper" "''${wps[$next]}"
    '';
  };
  systemd.user.services.rotate-wallpaper = {
    Unit = { Description = "Rotate wallpaper + re-theme"; };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/rotate-wallpaper.sh";
    };
  };
  systemd.user.timers.rotate-wallpaper = {
    Unit = { Description = "Wallpaper rotation schedule (every 4h)"; };
    Timer = {
      OnCalendar = "0/4:00:00";
      Persistent = true;
    };
    Install = { WantedBy = [ "timers.target" ]; };
  };

  # ── Bar helpers ──
  # opencode idle guard: holds a DBus ScreenSaver inhibitor on hypridle
  # (org.freedesktop.ScreenSaver.Inhibit) while an opencode agent is actually
  # working. Activity is signaled by the idle-guard opencode plugin, which
  # touches ~/.cache/opencode/active on tool exec / message streaming and
  # removes it on session.idle. The inhibitor is held only while that marker
  # is fresh (< 60s) — an idle-but-open TUI does NOT block the lockscreen.
  # Connection-tied: the inhibitor auto-releases if the guard dies.
  home.file.".local/bin/opencode-idle-guard.py" = {
    executable = true;
    text = ''
      #!/usr/bin/env python3
      import os
      import time
      import gi
      gi.require_version("Gio", "2.0")
      from gi.repository import Gio, GLib

      DEST = "org.freedesktop.ScreenSaver"
      PATH = "/org/freedesktop/ScreenSaver"
      IFACE = "org.freedesktop.ScreenSaver"
      MARKER = os.path.expanduser("~/.cache/opencode/active")
      STALE_AFTER = 60.0

      conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

      def agent_active():
          try:
              if not os.path.exists(MARKER):
                  return False
              return (time.time() - os.path.getmtime(MARKER)) < STALE_AFTER
          except Exception:
              return False

      cookie = None

      def tick():
          global cookie
          try:
              if agent_active():
                  if cookie is None:
                      res = conn.call_sync(
                          DEST, PATH, IFACE, "Inhibit",
                          GLib.Variant("(ss)", ("opencode-idle-guard", "opencode agent active")),
                          GLib.VariantType("(u)"),
                          Gio.DBusCallFlags.NONE, -1, None,
                      )
                      cookie = res.unpack()[0]
              else:
                  if cookie is not None:
                      conn.call_sync(
                          DEST, PATH, IFACE, "UnInhibit",
                          GLib.Variant("(u)", (cookie,)),
                          None, Gio.DBusCallFlags.NONE, -1, None,
                      )
                      cookie = None
          except Exception as e:
              print(f"guard error: {e}", flush=True)
              cookie = None
          return True

      GLib.timeout_add_seconds(5, tick)
      tick()
      GLib.MainLoop().run()
    '';
  };
  systemd.user.services.opencode-idle-guard = {
    Unit = {
      Description = "Hold idle inhibitor while opencode is running";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/opencode-idle-guard.py";
      Restart = "on-failure";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };
  # idle-toggle: hypridle runs via exec-once, so pause it with SIGSTOP/CONT
  home.file.".local/bin/idle-toggle.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      pids=$(pgrep -x hypridle)
      [ -z "$pids" ] && echo on && exit 0
      stopped() { ps -o stat= -p "$pids" 2>/dev/null | head -1 | grep -q '^T'; }
      case "''${1:-toggle}" in
        status) stopped && echo off || echo on ;;
        toggle)
          if stopped; then
            kill -CONT $pids; echo on
          else
            kill -STOP $pids; echo off
          fi
          ;;
      esac
    '';
  };
  # Power actions as .desktop entries so they show up in Vicinae
  # (launcher), which the waybar power module opens on click.
  home.file.".local/share/applications/power-lock.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Power: Lock
      Comment=Lock the screen
      Exec=hyprlock
      Icon=system-lock-screen
      Categories=System;
      Terminal=false
    '';
  };
  home.file.".local/share/applications/power-logout.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Power: Logout
      Comment=End the Hyprland session
      Exec=hyprctl dispatch exit
      Icon=system-log-out
      Categories=System;
      Terminal=false
    '';
  };
  home.file.".local/share/applications/power-reboot.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Power: Reboot
      Comment=Restart the machine
      Exec=systemctl reboot
      Icon=system-reboot
      Categories=System;
      Terminal=false
    '';
  };
  home.file.".local/share/applications/power-shutdown.desktop" = {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Power: Shutdown
      Comment=Power off the machine
      Exec=systemctl poweroff
      Icon=system-shutdown
      Categories=System;
      Terminal=false
    '';
  };

  # ── Notifications ──
  services.swaync = {
    enable = true;
    # style.css is generated by matugen (see "Dynamic theming" above)
  };

  # ── Launcher ──
  # Vicinae (system, AUR vicinae-bin) is the launcher — the nix Qt build
  # can't init OpenGL on NVIDIA (same EGL wall as kitty). Config lives at
  # ~/.config/vicinae (managed outside HM for now).
  # NOTE: vicinae's extension host resolves `node` from PATH, which points at
  # the nix `nodejs` in home.packages — keep nodejs in the nix profile or
  # vicinae extensions (e.g. clipboard history) break without an obvious cause.

  # ── Lockscreen ──
  # hyprlock is system-provided (pacman); config managed here so the
  # nix build (NVIDIA EGL/GBM) isn't pulled in by home-manager.
  home.file.".config/hypr/hyprlock.conf" = {
    text = ''
      # colors come from matugen (hyprlock-colors.conf, regenerated per theme)
      source = ~/.config/hypr/hyprlock-colors.conf
      general {
          hide_cursor = true
      }
      background {
          path = screenshot
          blur_passes = 3
          blur_size = 8
      }
      input-field {
          size = 200, 50
          position = 0, -80
          monitor =
          dots_center = true
          fade_on_empty = false
          font_color = $font_color
          inner_color = $inner_color
          outer_color = $outer_color
          outline_thickness = 2
          placeholder_text = Password...
      }
      label {
          monitor =
          text = cmd[update:1000] echo $(date +"%H:%M")
          color = $text_color
          font_size = 90
          font_family = JetBrains Mono Nerd Font
          position = 0, 40
          halign = center
          valign = center
      }
    '';
  };

  # ── Idle management ──
  # hypridle is system-provided (pacman) and started via hyprland's
  # exec-once. Config lives at ~/.config/hypr/hypridle.conf.
  home.file.".config/hypr/hypridle.conf" = {
    text = ''
      general {
          after_sleep_cmd = hyprctl dispatch dpms on
          ignore_dbus_inhibit = false
      }
      listener {
          timeout = 300
          on-timeout = hyprctl dispatch dpms off
          on-resume = hyprctl dispatch dpms on
      }
      listener {
          timeout = 600
          on-timeout = hyprlock
      }
      listener {
          timeout = 900
          on-timeout = systemctl suspend
      }
    '';
  };

  # Clipboard history is vicinae-native (clipboard:history, Super+V);
  # no separate cliphist service.

  # ── Terminal — kitty (primary) ──
  # Using system kitty (pacman) instead of nix kitty — nix kitty's bundled
  # libglvnd crashes with NVIDIA EGL (segfault on display init).
  # Config is managed via home.file; kitty itself stays system-provided.
  home.file.".config/kitty/kitty.conf" = {
    text = ''
      font_family JetBrains Mono Nerd Font
      font_size 12
      shell nu
      shell_integration no-rc
      confirm_os_window_close 0
      window_padding_width 8
      background_opacity 0.8
      cursor_shape beam
      cursor_blink_interval 0.5
      enable_audio_bell no
      tab_bar_edge top
      tab_bar_style powerline
      # reload config when it changes (interval in seconds); allow runtime theme reload
      auto_reload_config 1
      allow_remote_control yes
      listen_on unix:/tmp/kitty
      # matugen-generated chrome (bg/fg/accent) + wallpaper-derived ANSI
      # palette (from kitty.toml templates, contrast-solved by palette.py);
      # reloads automatically via auto_reload_config above.
      include ~/.config/kitty/kitty-colors.conf
    '';
  };

  # ── Browser — Firefox ──
  programs.firefox = {
    enable = true;
    configPath = ".mozilla/firefox";
    profiles.roni = {
      settings = {
        "browser.disableResetPrompt" = true;
        "browser.download.panel.shown" = true;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.urlbar.suggest.quicksuggest" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        "layout.css.devPixelsPerPx" = "1.0";
        "media.ffmpeg.vaapi.enabled" = true;
        "widget.use-xdg-desktop-portal.file-picker" = 1;
        # MatugenFox userChrome/userContent injection needs this on
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
    };
  };

  # ── Gaming tools ──
  # programs.gamemode was removed from home-manager; the gamemode package
  # is installed by bootstrap.sh (cachyos-gaming-meta does NOT pull it in).
  # Config lives in ~/.config/gamemode.ini.
  home.file.".config/gamemode.ini" = {
    text = ''
      [general]
      renice=10
      desiredgov=performance
      [gpu]
      apply_gpu_optimisations=1
      gpu_device=0
    '';
  };

  # ── MangoHud overlay ──
  # mangohud is system-provided (pacman) — the nix build injects into
  # system Steam/game processes with its own libs (mismatch risk).
  # Config is managed via home.file.
  home.file.".config/mangohud/MangoHud.conf" = {
    text = ''
      fps=1
      frame_timing=1
      gpu_stats=1
      cpu_stats=1
      ram=1
      vram=1
      gpu_temp=1
      cpu_temp=1
      engine_version=1
      gamemode=1
      config_version=3
    '';
  };

  # ── Theming decision (was: Stylix) ──
  # System-wide theming is NOT Stylix: nix builds of GPU/GL apps abort on the
  # NVIDIA stack, so Hyprland/kitty/ghostty are system (pacman) builds and
  # theming is done by the matugen pipeline below (palette.py + templates:
  # hyprland/waybar/swaync/kitty/ghostty/btop/micro/nvim/helix/firefox/zed/
  # spotify/vesktop/steam). Runtime configs are matugen-owned and regenerated
  # from the templates in ./matugen/. This block is intentionally not enabled.

  # ── Icon theme (Papirus tinted to the matugen primary) ──
  home.file.".local/bin/apply-icons.sh" = {
    source = ./scripts/apply-icons.sh;
    executable = true;
  };

  # ── Theme apply helper ──
  # Regenerates the matugen palette for the given mode + wallpaper and reloads
  # every themed surface in place. Used by theme-toggle, set-wallpaper and the
  # login exec-once (so kitty/waybar/swaync start fresh with the right theme).
  home.file.".local/bin/apply-theme.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      mode="''${1:-dark}"
      wallpaper="''${2:-}"
      if [ -z "$wallpaper" ]; then
        if [ -f "$HOME/.cache/current-wallpaper" ]; then
          wallpaper=$(cat "$HOME/.cache/current-wallpaper")
        else
          wallpaper="$HOME/projects/fleek/profiles/wallpaper.jpg"
        fi
      fi
      python3 "$HOME/.config/matugen/palette.py" "$wallpaper" "$mode" || exit 1
      # tint the Papirus icon theme folders to the current matugen primary
      "$HOME/.local/bin/apply-icons.sh" "$mode"
      hyprctl reload
      # reload in place so active notifications survive
      pkill -USR2 -x .waybar-wrapped 2>/dev/null
      swaync-client -rs 2>/dev/null
      # reload kitty by targeting its control socket explicitly — `kitty @`
      # without --to needs a controlling tty (fails from Hyprland exec), but
      # with --to it works everywhere and uses the proper control protocol.
      sock=$(ls -t /tmp/kitty-* 2>/dev/null | head -1)
      if [ -n "$sock" ]; then
        kitty @ --to "unix:$sock" load-config 2>/dev/null
      fi
      # spicetify: re-theme Spotify only if it's already running (never launch
      # it on a theme switch). Restarting is needed to pick up color.ini.
      if pgrep -x spotify >/dev/null 2>&1; then
        pkill -x spotify 2>/dev/null
        sleep 1
        spicetify apply >/dev/null 2>&1
        spotify-launcher >/dev/null 2>&1 &
      fi
    '';
  };

  # ── Theme toggle script (light ↔ dark) ──
  # Super+T: flip the mode and re-generate the palette.
  home.file.".local/bin/theme-toggle" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      state="$HOME/.cache/theme-mode"
      mode=$(cat "$state" 2>/dev/null || echo dark)
      [ "$mode" = dark ] && new=light || new=dark
      echo "$new" > "$state"
      # drive system color-scheme (GTK/Qt follow it); vicinae theme is applied
      # automatically by matugen's post_hook (theme set matugen)
      if [ "$new" = light ]; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-light
      else
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark
      fi
      exec "$HOME/.local/bin/apply-theme.sh" "$new"
    '';
  };

  # ── Wallpaper + theme apply ──
  home.file.".local/bin/set-wallpaper" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      wallpaper="''${1:-$HOME/projects/fleek/profiles/wallpaper.jpg}"
      if [ -f "$wallpaper" ]; then
        awww img "$wallpaper" --transition-type wipe --transition-fps 60
        echo "$wallpaper" > "$HOME/.cache/current-wallpaper"
        mode=$(cat "$HOME/.cache/theme-mode" 2>/dev/null || echo dark)
        exec "$HOME/.local/bin/apply-theme.sh" "$mode" "$wallpaper"
      fi
    '';
  };
}
