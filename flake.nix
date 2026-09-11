{
  description = "Home Manager Configuration";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home manager
    home-manager.url = "https://flakehub.com/f/nix-community/home-manager/0.1.tar.gz";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Theming — used by gaming profile.
    # Kept intentionally but NOT enabled: nix GPU/GL builds abort on NVIDIA, so
    # theming is the matugen pipeline instead (see profiles/gaming.nix).
    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      homeManagerBin = "${home-manager.packages.${system}.home-manager}/bin/home-manager";
      repoPath = self.outPath;
      sharedModules = [
        ./home.nix
        ./path.nix
        ./shell.nix
        ./user.nix
        ./programs.nix
  ];
       mkHome = modules:
         home-manager.lib.homeManagerConfiguration {
           inherit pkgs;
           extraSpecialArgs = { inherit inputs; };
           inherit modules;
         };
       mkProfile = modules: mkHome (sharedModules ++ modules ++ [ { nixpkgs.overlays = []; } ]);
       applyCurrentScript = pkgs.writeShellScript "apply-current" ''
         set -euo pipefail

         environment=""
         case "''${1:-}" in
           work|w|WORK|Work|private|p|PRIVATE|Private|gaming|g|GAMING|Gaming)
             environment="$1"
             shift
             ;;
         esac

         if [ -z "$environment" ]; then
           printf "Environment [work/private/gaming]: " >&2
           read -r environment
         fi

         case "$environment" in
           work|w|WORK|Work)
             environment="work"
             ;;
           private|p|PRIVATE|Private)
             environment="private"
             ;;
           gaming|g|GAMING|Gaming)
             environment="gaming"
             ;;
           *)
             echo "Please choose 'work', 'private', or 'gaming'." >&2
             exit 1
             ;;
         esac

         case "$USER:$environment" in
           "roni:work")
             target="roni@work"
             ;;
           "roni:private")
             target="roni@private"
             ;;
           "roni:gaming")
             target="roni@gaming"
             ;;
           "nixos:work")
             target="nixos@work"
             ;;
           "nixos:private")
             echo "No private profile exists for user nixos." >&2
             exit 1
             ;;
           *)
             echo "No home configuration found for user '$USER' in environment '$environment'." >&2
             echo "Available targets:" >&2
             echo "  roni@private" >&2
             echo "  roni@work" >&2
             echo "  roni@gaming" >&2
             echo "  nixos@work" >&2
             exit 1
             ;;
         esac

        exec ${homeManagerBin} switch --flake "${repoPath}#''${target}" "$@"
      '';
      mkEnvironmentApp = environment:
        let
          script = pkgs.writeShellScript "apply-${environment}" ''
            set -euo pipefail
            exec ${applyCurrentScript} ${environment} "$@"
          '';
        in {
          type = "app";
          program = "${script}";
        };
    in {
      apps.${system} = {
        default = {
          type = "app";
          program = "${applyCurrentScript}";
        };
        hm = {
          type = "app";
          program = homeManagerBin;
        };
        apply-current = {
          type = "app";
          program = "${applyCurrentScript}";
        };
        apply-work = mkEnvironmentApp "work";
        apply-private = mkEnvironmentApp "private";
        apply-gaming = mkEnvironmentApp "gaming";
        agent = {
          type = "app";
          program = "${pkgs.writeShellScript "fleek-agent" ''
            set -euo pipefail
            # `nix run .#agent` opens fleek; `nix run .#agent -- <name>` opens
            # ~/projects/<name>. e.g. nix run .#agent -- homelab
            project="''${1:-fleek}"
            [ $# -gt 0 ] && shift
            dir="$HOME/projects/$project"
            [ -d "$dir" ] || { echo "no project at $dir — run bootstrap to clone it, or check the name." >&2; exit 1; }
            cd "$dir"
            exec opencode "$@"
          ''}";
        };
      };

      homeConfigurations = {
        "roni@work" = mkProfile [
          ./users/roni.nix
          ./profiles/work.nix
        ];

        "nixos@work" = mkProfile [
          ./users/nixos.nix
          ./profiles/work.nix
        ];

        "roni@private" = mkProfile [
          ./users/roni.nix
          ./profiles/private.nix
        ];

        "roni@gaming" = mkHome (sharedModules ++ [
          inputs.stylix.homeModules.stylix
          ./users/roni.nix
          ./profiles/gaming.nix
        ] ++ [ { nixpkgs.overlays = []; } ]);
      };
    };
}
