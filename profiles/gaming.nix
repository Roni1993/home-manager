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

    # Terminal multiplexer — session persistence across reboots
    # (serializes sessions to ~/.cache/zellij; `zellij attach -c` resurrects)
    zellij
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
  home.file.".config/hypr/hyprland.lua" = {
    text = ''
      -- Managed by home-manager (profiles/gaming.nix). Do not edit.
      -- Hyprland 0.56 Lua config: hyprlang `.conf` support is removed in 0.57.
      local mod = "SUPER"

      -- Palette: matugen writes ~/.config/hypr/hyprland-colors.lua at runtime.
      -- require() is re-executed on every hyprctl reload, so theme switches
      -- apply live. Defaults keep Hyprland alive before the first theme run.
      local pal = {
        primary = "rgba(ffffffff)",
        secondary = "rgba(ffffffff)",
        outline_variant = "rgba(ffffffff)",
      }
      local ok, generated = pcall(require, "hyprland-colors")
      if ok and type(generated) == "table" then
        for key, value in pairs(generated) do
          pal[key] = value
        end
      end

      -- ── Environment ──
      hl.env("XCURSOR_SIZE", "24")
      hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
      hl.env("XDG_SESSION_TYPE", "wayland")
      hl.env("XDG_SESSION_DESKTOP", "Hyprland")
      hl.env("QT_QPA_PLATFORM", "wayland;xcb")
      hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
      hl.env("SDL_VIDEODRIVER", "wayland")
      hl.env("MOZ_ENABLE_WAYLAND", "1")
      -- NVIDIA VA-API hw decode for the nix Firefox: select the system
      -- libva-nvidia-driver and let the RDD process open /dev/nvidia*.
      hl.env("LIBVA_DRIVER_NAME", "nvidia")
      hl.env("LIBVA_DRIVERS_PATH", "/usr/lib/dri")
      hl.env("NVD_BACKEND", "direct")
      hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
      hl.env("GDK_BACKEND", "wayland,x11")

      -- ── Autostart (fires once at session start, the exec-once equivalent) ──
      hl.on("hyprland.start", function()
        hl.exec_cmd("/usr/bin/dbus-update-activation-environment --systemd DISPLAY HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE")
        hl.exec_cmd("awww-daemon")
        hl.exec_cmd("hypridle")
        -- Respawn vicinae on crash (it ABRTs occasionally); stop on clean
        -- exit/SIGTERM (logout). Restarts appended to the state log.
        hl.exec_cmd([==[while true; do vicinae server; c=$?; [ "$c" -eq 0 ] && exit 0; echo "$(date +%FT%T) vicinae server exited with code $c — respawning" >> ~/.local/state/vicinae-respawn.log; sleep 2; done]==])
        -- graphical-session.target never activates under system Hyprland
        -- (RefuseManualStart), so the HM units WantedBy it — waybar, swaync,
        -- opencode-idle-guard — are never pulled in. Push the Wayland env into
        -- the systemd user manager, then start them directly. waybar's unit
        -- waits for the socket and retries (see systemd.user.services.waybar).
        hl.exec_cmd("systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user start waybar.service swaync.service opencode-idle-guard.service")
        -- Re-apply the theme after login so all matugen outputs match the
        -- persisted mode/wallpaper (kitty etc. read them fresh at startup).
        hl.exec_cmd([==[sleep 3; ~/.local/bin/apply-theme.sh "$(cat ~/.cache/theme-mode 2>/dev/null || echo dark)"]==])
        -- clipboard history is vicinae-native (Super+V); no cliphist.
        hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent")
      end)

      -- ── Monitor ──
      hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

      -- ── Look and feel ──
      hl.config({
        general = {
          gaps_in = 5,
          gaps_out = 10,
          border_size = 2,
          col = {
            active_border = { colors = { pal.primary, pal.secondary }, angle = 45 },
            inactive_border = pal.outline_variant,
          },
          layout = "dwindle",
        },
        decoration = {
          rounding = 10,
          blur = {
            enabled = true,
            size = 3,
            passes = 1,
            new_optimizations = true,
          },
          shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)",
          },
        },
        animations = { enabled = true },
        misc = {
          disable_hyprland_logo = true,
          disable_splash_rendering = true,
        },
        render = { direct_scanout = 1 },
        dwindle = { preserve_split = true },
        master = { new_on_top = true },
        input = {
          kb_layout = "us",
          follow_mouse = 1,
          touchpad = { natural_scroll = true },
        },
      })

      hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
      hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
      hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
      hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
      hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
      hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
      hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

      -- ── Keybinds ──
      hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd("kitty"))
      hl.bind(mod .. " + Q", hl.dsp.window.close())
      hl.bind(mod .. " + M", hl.dsp.exit())
      hl.bind(mod .. " + E", hl.dsp.exec_cmd("nautilus"))
      hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
      hl.bind(mod .. " + SHIFT + SPACE", hl.dsp.window.float({ action = "toggle" }))
      hl.bind(mod .. " + R", hl.dsp.exec_cmd("vicinae toggle"))
      hl.bind(mod .. " + P", hl.dsp.window.pseudo())
      hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd("vicinae toggle"))
      hl.bind(mod .. " + L", hl.dsp.exec_cmd("hyprlock"))
      hl.bind(mod .. " + T", hl.dsp.exec_cmd("~/.local/bin/theme-toggle"))
      hl.bind(mod .. " + W", hl.dsp.exec_cmd("~/.local/bin/rotate-wallpaper.sh"))
      -- clipboard history (Super+V → vicinae clipboard:history)
      hl.bind(mod .. " + V", hl.dsp.exec_cmd("vicinae cmd launch clipboard:history"))

      hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m region"))
      hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd("hyprshot -m region"))
      hl.bind(mod .. " + PRINT", hl.dsp.exec_cmd("hyprshot -m output"))
      hl.bind(mod .. " + N", hl.dsp.exec_cmd("swaync-client -t"))

      for i = 1, 10 do
        local key = i % 10
        hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
        hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
      end

      hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
      hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

      hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +5%"), { repeating = true })
      hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -5%"), { repeating = true })
      hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"), { repeating = true })

      hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
      hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

      hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
      hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

      -- Fullscreen every `*.exe` (Proton/Wine games).
      hl.window_rule({ name = "fullscreen-exe", match = { class = "^(.*\\.exe)$" }, fullscreen = true })
    '';
  };

  # ── Dynamic theming — matugen + palette.py (custom scheme) ──
  # palette.py dumps matugen's scheme-expressive Material palette (UI chrome)
  # then injects six ANSI hues sampled from the wallpaper's actual hue
  # distribution (Material fixed hues as fallback for empty slots), and renders
  # config.toml + kitty.toml. HM manages matugen's config + templates; the
  # generated files (~/.config/hypr/hyprland-colors.lua etc.) are matugen-owned
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
      input_path = "~/.config/matugen/templates/hyprland-colors.lua"
      output_path = "~/.config/hypr/hyprland-colors.lua"

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
  home.file.".config/matugen/templates/hyprland-colors.lua" = {
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
  # idle-guard plugin: signals real agent activity to opencode-idle-guard.
  # Touches ~/.cache/opencode/active on tool exec / message stream; clears it
  # only once the whole session tree is idle. The parent session goes idle while
  # background delegations keep running, so a plain session.idle clear dropped
  # the hypridle inhibitor mid-run (the same premature-idle bug notify.ts fixes
  # via child statuses). The guard holds the inhibitor only while this marker is
  # fresh — so an idle-but-open TUI does NOT block the lockscreen.
  home.file.".config/opencode/plugins/idle-guard.ts" = {
    text = ''
      import * as fs from "node:fs/promises"
      import * as path from "node:path"
      import * as os from "node:os"
      import type { Plugin } from "@opencode-ai/plugin"
      import type { Event, OpencodeClient } from "@opencode-ai/sdk"

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

      // The marker is global, so keep it while ANY session is still working.
      // This also covers a delegated child going idle while its siblings run,
      // which a per-session children check would miss.
      async function anySessionWorking(client: OpencodeClient): Promise<boolean> {
        try {
          const result = await client.session.status({})
          const statuses = (result.data ?? {}) as Record<string, { type: string }>
          return Object.values(statuses).some((s) => s.type !== "idle")
        } catch {
          return true
        }
      }

      export const IdleGuardPlugin: Plugin = async ({ client }) => {
        return {
          "tool.execute.before": async () => {
            await markActive()
          },
          event: async ({ event }: { event: Event }) => {
            const e = event as { type: string }
            if (e.type === "message.part.updated") {
              await markActive()
            } else if (e.type === "session.idle") {
              if (await anySessionWorking(client as OpencodeClient)) return
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

  # Hardening for the HM waybar systemd unit.
  # At login graphical-session.target can start waybar before Hyprland's
  # Wayland socket exists; waybar then exits with "cannot open display",
  # burns its 5 on-failure retries in <10s, and stays dead via
  # start-limit-hit. Wait for the socket, retry patiently, never give up.
  systemd.user.services.waybar = {
    Unit.StartLimitIntervalSec = 0;
    Service = {
      Restart = lib.mkForce "always";
      RestartSec = 2;
      ExecStartPre = "${pkgs.writeShellScript "wait-wayland" ''
        for _ in $(seq 1 50); do
          [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && exit 0
          sleep 0.2
        done
        exit 1
      ''}";
    };
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

  # ── Gamescope session switching + auto-restore (DEPRECATED) ──
  # Kept as safety net only: if the gamescope-session desktop is ever used
  # again, the restore hook prevents a Game-Mode autologin loop on Steam
  # quit. The Game Mode path itself was scrapped — flicker (fixed via HDR
  # strip) plus an unresolvable latency/fps-cap left Big Picture run from
  # the Hyprland desktop as the chosen route (see ROADMAP). switch-session
  # still works for any plasmalogin session flip.
  # root helper /usr/local/bin/fleek-set-session (installed by bootstrap.sh,
  # NOPASSWD via /etc/sudoers.d/fleek-session) rewrites /etc/plasmalogin.conf
  # autologin and can restart the DM. switch-session is the user-side entry
  # point: from Hyprland for `flip the next boot into Game Mode`.
  # NOTE: it restarts the display manager -> kills this terminal's session.
  home.file.".local/bin/switch-session" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      name="''${1:-}"
      if [ -z "$name" ]; then
        echo "usage: switch-session <session> (hyprland | gamescope-session | plasma)" >&2
        exit 1
      fi
      sudo -n /usr/local/bin/fleek-set-session "$name"
    '';
  };
  # When Steam/Game Mode exits, gamescope-session.service stops with it.
  # ExecStopPost hooks that moment headlessly (no polkit/display needed):
  # point autologin back at Hyprland BEFORE the display manager restarts,
  # otherwise the greeter autologins straight back into Game Mode.
  home.file.".config/systemd/user/gamescope-session.service.d/10-restore-desktop.conf" = {
    text = ''
      [Service]
      # gamescope must run in DRM session mode, not nested-on-wayland: the
      # user manager inherits WAYLAND_DISPLAY=wayland-1 from the Hyprland
      # session, and gamescope then aborts ("Failed to connect to wayland
      # socket: wayland-1"). Unset it so session/DRI mode is chosen.
      UnsetEnvironment=WAYLAND_DISPLAY
      ExecStopPost=/usr/bin/sudo -n /usr/local/bin/fleek-set-session hyprland --no-restart
    '';
  };

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
      # launch (or resurrect) the main zellij workspace in a new window
      map ctrl+shift+enter launch --cwd=current zellij attach -c main
    '';
  };

  # ── Terminal multiplexer — zellij ──
  # Session persistence: zellij serializes live sessions (tabs/panes/cwds/
  # commands) to ~/.cache/zellij by default (~1 min interval);
  # `zellij attach -c <name>` creates a session if missing and resurrects an
  # exited one, so a terminal workspace survives a reboot by re-attaching
  # after login. Chrome theme is the builtin base16 one-dark (same palette
  # family as the nushell prompts; arrows between status/tab segments render
  # automatically). Terminal colors stay matugen-driven via kitty.
  # Keybinds: zellij's "Unlock-First (non-colliding)" preset (0.41+), inlined
  # so home-manager owns it. Zellij starts LOCKED, so no Ctrl+<key> is stolen
  # from apps in panes (this is what blocked opencode's Ctrl+P). Press Ctrl+g
  # to unlock, then a mode key: p pane, t tab, n resize, s scroll, m move,
  # o session; Enter/Esc re-locks. Alt+h/j/k/l etc. work without unlocking.
  # Exact preset zellij 0.44.3 generates (Session -> c -> Change Mode Behavior).
  home.file.".config/zellij/config.kdl" = {
    text = ''
      theme "onedark"
      default_mode "locked"
      keybinds clear-defaults=true {
          normal {
          }
          locked {
              bind "Ctrl g" { SwitchToMode "Normal"; }
          }
          resize {
              bind "r" { SwitchToMode "Normal"; }
              bind "h" "Left" { Resize "Increase Left"; }
              bind "j" "Down" { Resize "Increase Down"; }
              bind "k" "Up" { Resize "Increase Up"; }
              bind "l" "Right" { Resize "Increase Right"; }
              bind "H" { Resize "Decrease Left"; }
              bind "J" { Resize "Decrease Down"; }
              bind "K" { Resize "Decrease Up"; }
              bind "L" { Resize "Decrease Right"; }
              bind "=" "+" { Resize "Increase"; }
              bind "-" { Resize "Decrease"; }
          }
          pane {
              bind "p" { SwitchToMode "Normal"; }
              bind "h" "Left" { MoveFocus "Left"; }
              bind "l" "Right" { MoveFocus "Right"; }
              bind "j" "Down" { MoveFocus "Down"; }
              bind "k" "Up" { MoveFocus "Up"; }
              bind "Tab" { SwitchFocus; }
              bind "n" { NewPane; SwitchToMode "Locked"; }
              bind "d" { NewPane "Down"; SwitchToMode "Locked"; }
              bind "r" { NewPane "Right"; SwitchToMode "Locked"; }
              bind "s" { NewPane "stacked"; SwitchToMode "Locked"; }
              bind "x" { CloseFocus; SwitchToMode "Locked"; }
              bind "f" { ToggleFocusFullscreen; SwitchToMode "Locked"; }
              bind "z" { TogglePaneFrames; SwitchToMode "Locked"; }
              bind "w" { ToggleFloatingPanes; SwitchToMode "Locked"; }
              bind "e" { TogglePaneEmbedOrFloating; SwitchToMode "Locked"; }
              bind "c" { SwitchToMode "RenamePane"; PaneNameInput 0;}
              bind "i" { TogglePanePinned; SwitchToMode "Locked"; }
          }
          move {
              bind "m" { SwitchToMode "Normal"; }
              bind "n" "Tab" { MovePane; }
              bind "p" { MovePaneBackwards; }
              bind "h" "Left" { MovePane "Left"; }
              bind "j" "Down" { MovePane "Down"; }
              bind "k" "Up" { MovePane "Up"; }
              bind "l" "Right" { MovePane "Right"; }
          }
          tab {
              bind "t" { SwitchToMode "Normal"; }
              bind "r" { SwitchToMode "RenameTab"; TabNameInput 0; }
              bind "h" "Left" "Up" "k" { GoToPreviousTab; }
              bind "l" "Right" "Down" "j" { GoToNextTab; }
              bind "n" { NewTab; SwitchToMode "Locked"; }
              bind "x" { CloseTab; SwitchToMode "Locked"; }
              bind "s" { ToggleActiveSyncTab; SwitchToMode "Locked"; }
              bind "b" { BreakPane; SwitchToMode "Locked"; }
              bind "]" { BreakPaneRight; SwitchToMode "Locked"; }
              bind "[" { BreakPaneLeft; SwitchToMode "Locked"; }
              bind "1" { GoToTab 1; SwitchToMode "Locked"; }
              bind "2" { GoToTab 2; SwitchToMode "Locked"; }
              bind "3" { GoToTab 3; SwitchToMode "Locked"; }
              bind "4" { GoToTab 4; SwitchToMode "Locked"; }
              bind "5" { GoToTab 5; SwitchToMode "Locked"; }
              bind "6" { GoToTab 6; SwitchToMode "Locked"; }
              bind "7" { GoToTab 7; SwitchToMode "Locked"; }
              bind "8" { GoToTab 8; SwitchToMode "Locked"; }
              bind "9" { GoToTab 9; SwitchToMode "Locked"; }
              bind "Tab" { ToggleTab; }
          }
          scroll {
              bind "s" { SwitchToMode "Normal"; }
              bind "e" { EditScrollback; SwitchToMode "Locked"; }
              bind "f" { SwitchToMode "EnterSearch"; SearchInput 0; }
              bind "Ctrl c" { ScrollToBottom; SwitchToMode "Locked"; }
              bind "j" "Down" { ScrollDown; }
              bind "k" "Up" { ScrollUp; }
              bind "Ctrl f" "PageDown" "Right" "l" { PageScrollDown; }
              bind "Ctrl b" "PageUp" "Left" "h" { PageScrollUp; }
              bind "d" { HalfPageScrollDown; }
              bind "u" { HalfPageScrollUp; }
              bind "Alt left" { MoveFocusOrTab "left"; SwitchToMode "locked"; }
              bind "Alt down" { MoveFocus "down"; SwitchToMode "locked"; }
              bind "Alt up" { MoveFocus "up"; SwitchToMode "locked"; }
              bind "Alt right" { MoveFocusOrTab "right"; SwitchToMode "locked"; }
              bind "Alt h" { MoveFocusOrTab "left"; SwitchToMode "locked"; }
              bind "Alt j" { MoveFocus "down"; SwitchToMode "locked"; }
              bind "Alt k" { MoveFocus "up"; SwitchToMode "locked"; }
              bind "Alt l" { MoveFocusOrTab "right"; SwitchToMode "locked"; }
          }
          search {
              bind "Ctrl c" { ScrollToBottom; SwitchToMode "Locked"; }
              bind "j" "Down" { ScrollDown; }
              bind "k" "Up" { ScrollUp; }
              bind "Ctrl f" "PageDown" "Right" "l" { PageScrollDown; }
              bind "Ctrl b" "PageUp" "Left" "h" { PageScrollUp; }
              bind "d" { HalfPageScrollDown; }
              bind "u" { HalfPageScrollUp; }
              bind "n" { Search "down"; }
              bind "p" { Search "up"; }
              bind "c" { SearchToggleOption "CaseSensitivity"; }
              bind "w" { SearchToggleOption "Wrap"; }
              bind "o" { SearchToggleOption "WholeWord"; }
          }
          entersearch {
              bind "Ctrl c" "Esc" { SwitchToMode "Scroll"; }
              bind "Enter" { SwitchToMode "Search"; }
          }
          renametab {
              bind "Ctrl c" "Enter" { SwitchToMode "Locked"; }
              bind "Esc" { UndoRenameTab; SwitchToMode "Tab"; }
          }
          renamepane {
              bind "Ctrl c" "Enter" { SwitchToMode "Locked"; }
              bind "Esc" { UndoRenamePane; SwitchToMode "Pane"; }
          }
          session {
              bind "o" { SwitchToMode "Normal"; }
              bind "d" { Detach; }
              bind "w" {
                  LaunchOrFocusPlugin "session-manager" {
                      floating true
                      move_to_focused_tab true
                  };
                  SwitchToMode "Locked"
              }
              bind "c" {
                  LaunchOrFocusPlugin "configuration" {
                      floating true
                      move_to_focused_tab true
                  };
                  SwitchToMode "Locked"
              }
              bind "p" {
                  LaunchOrFocusPlugin "plugin-manager" {
                      floating true
                      move_to_focused_tab true
                  };
                  SwitchToMode "Locked"
              }
              bind "a" {
                  LaunchOrFocusPlugin "zellij:about" {
                      floating true
                      move_to_focused_tab true
                  };
                  SwitchToMode "Locked"
              }
              bind "s" {
                  LaunchOrFocusPlugin "zellij:share" {
                      floating true
                      move_to_focused_tab true
                  };
                  SwitchToMode "Locked"
              }
              bind "l" {
                  LaunchOrFocusPlugin "zellij:layout-manager" {
                      floating true
                      move_to_focused_tab true
                  };
                  SwitchToMode "Locked"
              }
          }
          shared_except "locked" "renametab" "renamepane" {
              bind "Ctrl g" { SwitchToMode "Locked"; }
              bind "Ctrl q" { Quit; }
          }
          shared_except "renamepane" "renametab" "entersearch" "locked" {
              bind "esc" { SwitchToMode "locked"; }
          }
          shared_among "normal" "locked" {
              bind "Alt n" { NewPane; }
              bind "Alt f" { ToggleFloatingPanes; }
              bind "Alt i" { MoveTab "Left"; }
              bind "Alt o" { MoveTab "Right"; }
              bind "Alt h" "Alt Left" { MoveFocusOrTab "Left"; }
              bind "Alt l" "Alt Right" { MoveFocusOrTab "Right"; }
              bind "Alt j" "Alt Down" { MoveFocus "Down"; }
              bind "Alt k" "Alt Up" { MoveFocus "Up"; }
              bind "Alt =" "Alt +" { Resize "Increase"; }
              bind "Alt -" { Resize "Decrease"; }
              bind "Alt [" { PreviousSwapLayout; }
              bind "Alt ]" { NextSwapLayout; }
              bind "Alt p" { TogglePaneInGroup; }
              bind "Alt Shift p" { ToggleGroupMarking; }
          }
          shared_except "locked" "renametab" "renamepane" {
              bind "Enter" { SwitchToMode "Locked"; }
          }
          shared_except "pane" "locked" "renametab" "renamepane" "entersearch" {
              bind "p" { SwitchToMode "Pane"; }
          }
          shared_except "resize" "locked" "renametab" "renamepane" "entersearch" {
              bind "r" { SwitchToMode "Resize"; }
          }
          shared_except "scroll" "locked" "renametab" "renamepane" "entersearch" {
              bind "s" { SwitchToMode "Scroll"; }
          }
          shared_except "session" "locked" "renametab" "renamepane" "entersearch" {
              bind "o" { SwitchToMode "Session"; }
          }
          shared_except "tab" "locked" "renametab" "renamepane" "entersearch" {
              bind "t" { SwitchToMode "Tab"; }
          }
          shared_except "move" "locked" "renametab" "renamepane" "entersearch" {
              bind "m" { SwitchToMode "Move"; }
          }
      }
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
