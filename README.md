# Home Manager Flake

Nix Home Manager configuration for WSL2 Ubuntu 24.04 development environments and the CachyOS gaming PC.

## What this repo contains

- Shared modules: `home.nix`, `programs.nix`, `path.nix`, `shell.nix`, `user.nix`
- User identity modules: `users/roni.nix`, `users/nixos.nix`
- Environment modules: `profiles/work.nix`, `profiles/private.nix`, `profiles/gaming.nix`
- Flake entrypoint: `flake.nix`
- Bootstrap scripts: `install.sh` (WSL), `bootstrap.sh` (CachyOS gaming PC — see `ROADMAP.md`)

### Home Manager targets

| Target | User | Profile |
|---|---|---|
| `roni@work` | roni | work |
| `nixos@work` | nixos | work |
| `roni@private` | roni | private |
| `roni@gaming` | roni | gaming (CachyOS + Hyprland; see `ROADMAP.md` and `docs/sanity-handoff.md`) |

### Shared packages (home.nix)

`helix`, `neovim`, `fd`, `ripgrep`, `bat`, `fzf`, `jq`, `jtc`, `lazygit`, `glow`, `tree`, `wget`, `curl`, `zip`, `unzip`, `cheat`, `usbutils`, `wslu`, `wsl-open`, `tilt`, `kubectl`, `kubectx`, `helm`, `krew`, `dive`, `devbox`, `go`, `awscli2`

### Work profile packages (profiles/work.nix)

`aws-sso-cli`, `pass`, `gnupg`, `claude-code`

Work profile also configures:
- GPG agent with `pinentry-curses` (8h passphrase cache, loopback pinentry for WSL)
- `pass` as the SecureStore backend for `aws-sso` (enforced via activation script)
- Git identity (`Roman Weintraub`) with LFS enabled

## Fresh machine bootstrap

Use `install.sh` on a fresh Ubuntu instance. It installs Nix, Docker CE, applies the iptables-legacy fix (WSL2), clones this repo, and runs Home Manager:

```bash
curl -fsSL https://raw.githubusercontent.com/Roni1993/fleek/main/install.sh | bash -s -- work
# or
bash install.sh private
```

After running, a few manual steps remain:
1. Start a new shell (or `source ~/.nix-profile/etc/profile.d/nix.sh`)
2. Work profile: generate/import a GPG key and run `pass init <KEY-ID>`
3. If you saw the docker group warning: `newgrp docker`
4. Run `aws-sso login` to authenticate

## Applying changes

```bash
nix run .#apply-current          # prompts for work/private
nix run .#apply-current -- work  # non-interactive
nix run .#apply-work
nix run .#apply-private
```

Or using `home-manager` directly if already on `$PATH`:

```bash
home-manager switch --flake .#roni@work
```

If evaluation fails:

```bash
nix run .#apply-current -- --show-trace
```

## Apply without cloning

```bash
nix run github:Roni1993/fleek              # prompts for work/private
nix run github:Roni1993/fleek#apply-work
nix run github:Roni1993/fleek#apply-private
```

## Flake apps

| App | Description |
|---|---|
| `default` / `apply-current` | Prompts for environment, resolves target from `$USER` |
| `apply-work` | Applies work profile for current user |
| `apply-private` | Applies private profile for current user |
| `hm` | Runs the pinned `home-manager` binary directly |

## Where to edit

| What | Where |
|---|---|
| Shared packages / options | `home.nix`, `programs.nix` |
| Shell config | `shell.nix` |
| PATH entries | `path.nix` |
| Nushell, starship, git aliases | `user.nix` |
| Work-specific config | `profiles/work.nix` |
| Private-specific config | `profiles/private.nix` |
| Username / home directory | `users/roni.nix`, `users/nixos.nix` |
| Flake inputs / target wiring | `flake.nix` |

## WSL2 Docker networking workaround

Ubuntu 24.04 defaults to the `iptables-nft` backend, which breaks Docker's bridge networking on WSL2 (containers start but have no internet access, inter-container routing fails).

The fix applied in `install.sh` switches the system to `iptables-legacy`:

```bash
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
```

This runs automatically as part of `install.sh` before starting Docker. No changes to `daemon.json` are required.

**Why not Podman or containerd?** Rootless Podman avoids iptables entirely via userspace networking (`slirp4netns`/`pasta`) and is a clean alternative, but switching would require aliasing the `docker` CLI and adjusting Compose workflows. The `iptables-legacy` shim is lower-friction for an existing Docker-based workflow.

**Why not `"firewall-backend": "nftables"` in `daemon.json`?** Docker 29+ supports this, but it is still experimental and requires manually enabling IP forwarding. Not suitable for production use yet.

Relevant upstream issues: `moby/moby#46127`, `docker/for-linux#1472`, `microsoft/WSL#4133`.

## Daily workflow

```bash
# Edit files, then apply
nix run .#apply-current
git --no-pager diff
```

## References

- [Home Manager manual](https://nix-community.github.io/home-manager/)
- [Home Manager options](https://nix-community.github.io/home-manager/options.html)
