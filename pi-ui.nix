# pi-ui: pi-coding-agent 0.85.1 with the two local pi-patches applied, plus a
# `bin/pi` that launches the UNMINIFIED dist entry so the patches take effect.
#
# Why a runCommand copy instead of overrideAttrs/postPatch:
#   The shipped `bin/pi` runs dist/bundle/cli.js (minified), so the patch
#   scripts — which edit the human-readable dist — would be ignored. Also,
#   overrideAttrs/postPatch on the original derivation would force a full
#   tsgo + esbuild rebuild. Copying the substituted store path is ~207 MB of
#   file copies and a couple of in-place regex patches; cheap and cacheable.
#
# Reversible: delete this file and point `programs.pi.coding-agent.package`
# back at `piPkg` in pi.nix.
#
# Evaluate standalone:
#   nix build --impure --expr \
#     'let f = builtins.getFlake (toString ./.);
#      in import ./pi-ui.nix { pkgs = f.inputs.nixpkgs-pi.legacyPackages.x86_64-linux; inputs = f.inputs; }'
{ pkgs, inputs }:
let
  system = pkgs.stdenv.hostPlatform.system;
  # Source package comes from the targeted `nixpkgs-pi` input, independent of
  # whichever `pkgs` the caller passes for build tools.
  pi = inputs.nixpkgs-pi.legacyPackages.${system}.pi-coding-agent;

  # Build/runtime tools. `nodejs` here only needs to run .mjs patch scripts and
  # launch dist/cli.js; the version does not have to match pi's shebang node.
  inherit (pkgs) nodejs fd ripgrep;
in
pkgs.runCommand "pi-coding-agent-ui-${pi.version}"
{
  nativeBuildInputs = [ pkgs.coreutils ];
  meta = pi.meta // {
    description = "${pi.meta.description} (with pi-ui patches)";
  };
}
''
  # Fresh, writable copy of the substituted store path.
  cp -R ${pi}/. $out
  chmod -R u+w $out

  # The patches live in pi-patches/ and are owned by other tickets — only wired
  # here. Each is idempotent and exits nonzero if an anchor drifts.
  ${nodejs}/bin/node ${./pi-patches/transcript-seam.mjs} $out
  ${nodejs}/bin/node ${./pi-patches/pi-tui-backdrop.mjs} $out

  # Replace the makeWrapper-generated `pi` (which execs dist/bundle/cli.js, the
  # minified bundle) with one that preserves the original wrapper's guarantees
  # and execs the unminified dist entry instead.
  rm -f $out/bin/pi
  cat > $out/bin/pi <<'PI_UI_WRAPPER'
#!${pkgs.runtimeShell}
# Preserved from the original nix wrapper: pi's find/grep tools shell out to
# fd/ripgrep, and these suppress the update check and telemetry.
export PATH="${fd}/bin:${ripgrep}/bin:$PATH"
export PI_SKIP_VERSION_CHECK="''${PI_SKIP_VERSION_CHECK-1}"
export PI_TELEMETRY="''${PI_TELEMETRY-0}"
exec ${nodejs}/bin/node ${placeholder "out"}/lib/node_modules/pi-monorepo/dist/cli.js "$@"
PI_UI_WRAPPER
  chmod 755 $out/bin/pi
''
