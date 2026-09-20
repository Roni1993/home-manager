{ pkgs, lib, inputs, ... }:
let
  # pi-coding-agent 0.85.1 from the targeted `nixpkgs-pi` input (see flake.nix),
  # not the main nixpkgs pin, with the two local pi-ui patches applied and a
  # `bin/pi` that launches the unminified entry (see pi-ui.nix). Delete that
  # import to fall back to the unpatched package.
  piPkg = import ./pi-ui.nix { inherit pkgs inputs; };
in
{
  # Pi runtime via the pi.nix flake's Home Manager module. pi-workflow
  # (github.com/Roni1993/pi-workflow) is a Pi *package* — extensions + skills,
  # no binary — so it installs into Pi's own package store rather than Nix.
  #
  # package = the nixpkgs build (substituted from cache.nixos.org) instead of
  # pi.nix's own npm/bun build, so no extra binary cache is required.
  imports = [ inputs.pi.homeModules.default ];

  programs.pi.coding-agent = {
    enable = true;
    # Pi 0.85.1 via the targeted `nixpkgs-pi` input (bump done; see flake.nix).
    package = piPkg;
    # jail.enable = true;  # available via pi.nix; off because pi-workflow
    # spawns host tmux + jj agents, which the default jail would not reach.
  };

  # Install the workflow + ponytail packages once. Guarded so offline switches
  # don't fail and idempotent with `pi list`. Upgrade with `pi update <pkg>`.
  home.activation.piPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Pi shells out to npm/git to install packages; the activation PATH does
    # not include the profile, so add them explicitly.
    export PATH="${pkgs.nodejs}/bin:${pkgs.git}/bin:$PATH"
    for src in \
      "git:github.com/Roni1993/pi-workflow" \
      "npm:@dietrichgebert/ponytail" \
      "npm:@quintinshaw/pi-dynamic-workflows"; do
      if ! ${piPkg}/bin/pi list 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "$src"; then
        run ${piPkg}/bin/pi install "$src"
      fi
    done
  '';
}
