{ pkgs, lib, ... }: {
  # Work-specific program modules
  programs.claude-code.enable = true;

  # Route xdg-open URLs to the Windows default browser from WSL.
  home.sessionVariables.BROWSER = "wsl-open";

  # GPG + pass for aws-sso SecureStore backend
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    enableNushellIntegration = true;
    # Cache GPG passphrase for 8 hours so you only enter it once per work session
    defaultCacheTtl = 28800;
    maxCacheTtl = 28800;
    pinentry.package = pkgs.pinentry-curses;
    # Prevent gpg-agent from trying the D-Bus secret-service (unavailable in WSL)
    noAllowExternalCache = true;
    # Allow loopback pinentry so GPG_TTY-based prompts work in the terminal
    extraConfig = ''
      allow-loopback-pinentry
    '';
  };

  # GPG_TTY must be set so pinentry-curses knows which terminal to use.
  # The HM nushell integration sets $env.GPG_TTY but only works when nushell
  # is started interactively with a real TTY; we make it explicit here as well.
  programs.bash.initExtra = ''
    export GPG_TTY=$(tty)
  '';

  # Patch SecureStore: pass into the existing aws-sso config.
  # We use an activation script rather than xdg.configFile so we don't clobber
  # the rest of the config (SSOConfig, StartUrl, etc.) which is managed by
  # `aws-sso setup wizard` / manual edits.
  home.activation.awsSsoSecureStore =
    let
      yq = "${pkgs.yq-go}/bin/yq";
      cfg = "$HOME/.config/aws-sso/config.yaml";
    in
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      mkdir -p "$(dirname ${cfg})"
      if [ ! -f "${cfg}" ]; then
        echo "SecureStore: pass" > "${cfg}"
      else
        ${yq} -i '.SecureStore = "pass"' "${cfg}"
      fi
    '';

  # Work-specific packages (AWS SSO toolchain + GPG/pass + WSL utils)
  home.packages = with pkgs; [
    wsl-open
    aws-sso-cli
    pass
    gnupg
    # rtk (Rust Token Killer, https://github.com/rtk-ai/rtk) — CLI proxy that
    # condenses command output before it reaches Claude Code. Wired up via the
    # `rtk hook claude` PreToolUse hook in ~/.claude/settings.json. Not in
    # nixpkgs; install the static musl binary from the release tarball.
    # Bump version + sha256 to upgrade.
    (pkgs.stdenvNoCC.mkDerivation rec {
      pname = "rtk";
      version = "0.43.0";
      src = pkgs.fetchurl {
        url = "https://github.com/rtk-ai/rtk/releases/download/v${version}/rtk-x86_64-unknown-linux-musl.tar.gz";
        sha256 = "02d6lbz7ig0z7n4yal9yydnzzjcpvjhyqnm8j591fvj9crvix2pz";
      };
      dontUnpack = true;
      installPhase = ''
        tar -xzf $src
        install -Dm755 "$(find . -type f -name rtk | head -n1)" $out/bin/rtk
      '';
    })
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "Roman Weintraub";
      user.email = "roman.weintraub@gmail.com"; # Update this to your work email.
      alias = {
        pushall = "!git remote | xargs -L1 git push --all";
        graph = "log --decorate --oneline --graph";
        add-nowhitespace = "!git diff -U0 -w --no-color | git apply --cached --ignore-whitespace --unidiff-zero -";
      };
      feature.manyFiles = true;
      init.defaultBranch = "main";
      gpg.format = "ssh";
      credential.helper = "cache --timeout 86400";
    };

    signing = {
      key = "";
      signByDefault = builtins.stringLength "" > 0;
    };

    lfs.enable = true;
    ignores = [ ".direnv" "result" ];
  };
}
