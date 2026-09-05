{ lib, pkgs, ... }:
let
  pluginsDir = ./opencode/plugins;
  filesOf = dirName:
    lib.mapAttrsToList (name: _: dirName + name)
      (lib.filterAttrs (_: type: type == "regular")
        (builtins.readDir "${toString pluginsDir}/${dirName}"));
  pluginFilePaths = filesOf "" ++ filesOf "notify/" ++ filesOf "kdco-primitives/";
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
    ".config/opencode/opencode.jsonc" = {
      text = ''
        {
          "$schema": "https://opencode.ai/config.json",
          "plugin": [
            "opencode-chrome-devtools",
            "opencode-pty"
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
  } // lib.listToAttrs (map (f: {
    name = ".config/opencode/plugins/${f}";
    value = { source = "${pluginsDir}/${f}"; };
  }) pluginFilePaths);
}