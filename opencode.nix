{ lib, pkgs, ... }:
let
  pluginsDir = ./opencode/plugins;
  agentsDir = ./opencode/agents;
  filesOf = base: dirName:
    lib.mapAttrsToList (name: _: dirName + name)
      (lib.filterAttrs (_: type: type == "regular")
        (builtins.readDir "${toString base}/${dirName}"));
  pluginFilePaths = filesOf pluginsDir "" ++ filesOf pluginsDir "notify/" ++ filesOf pluginsDir "kdco-primitives/";
  agentFilePaths = filesOf agentsDir "";

in {
  # opencode shared config (all profiles). Gaming-specific bits (idle-guard,
  # hypridle inhibitor) stay in profiles/gaming.nix.

  # ocx: OpenCode extension manager (kdcokenny/ocx) — makes the kdco registry
  # (~/.config/opencode/ocx.jsonc) usable on every machine. Bump version +
  # sha256 together.
  home.packages = [
    (pkgs.stdenvNoCC.mkDerivation rec {
      pname = "ocx";
      version = "2.0.15";
      src = pkgs.fetchurl {
        url = "https://github.com/kdcokenny/ocx/releases/download/v${version}/ocx-linux-x64";
        sha256 = "8e5b578e45beebc379d26c2418f60b1ab6bdeb3e83e6218f59bc5c5210416148";
      };
      dontUnpack = true;
      installPhase = ''
        install -Dm755 $src $out/bin/ocx
      '';
    })
  ];

  home.file = {
    ".config/opencode/AGENTS.md".source = ./opencode/global-rules.md;

    ".config/opencode/opencode.jsonc" = {
      text = ''{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "opencode-chrome-devtools",
    "opencode-pty",
    "opencode-cmd-provider"
  ],
  "references": {
    "fleek-docs": {
      "path": "~/projects/fleek/docs",
      "description": "fleek repo docs: ADRs, agent/issue conventions, domain model, and research notes"
    }
  }
}
      '';
    };

    ".config/opencode/tui.json" = {
      text = ''
        {
          "$schema": "https://opencode.ai/tui.json",
          "plugin": [
            "opencode-cmd-provider"
          ],
          "theme": "matugen"
        }
      '';
    };
  } // lib.listToAttrs (map (f: {
    name = ".config/opencode/plugins/${f}";
    value = { source = "${pluginsDir}/${f}"; };
  }) pluginFilePaths)
    // lib.listToAttrs (map (f: {
      name = ".config/opencode/agent/${f}";
      value = { source = "${agentsDir}/${f}"; };
    }) agentFilePaths);
}
