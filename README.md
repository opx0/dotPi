# dotPi

Automated dotfiles for Raspberry Pi / VPS / Debian-family servers. Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## One-liner install

```bash
curl -fsSL https://raw.githubusercontent.com/opx0/dotPi/main/setup.sh | bash
```

Or, if you prefer to clone first:

```bash
git clone https://github.com/opx0/dotPi ~/dotPi && ~/dotPi/setup.sh
```

Both run the same script — it auto-clones to `~/dotPi` when piped.

**Dry-run first** (no changes, just prints what would happen):

```bash
~/dotPi/setup.sh --dry-run
```

**Other flags:**

```bash
~/dotPi/setup.sh --skip-shell   # don't run chsh
~/dotPi/setup.sh --help         # print full usage
```

## What the bootstrap does

| Step | What | How |
|---|---|---|
| 1 | Preflight | refuses root, caches sudo, waits for apt lock, generates UTF-8 locale |
| 2 | APT packages | `stow fzf neovim tmux zsh tree xclip curl wget git unzip gpg ca-certificates locales bat fd-find btop` |
| 3 | [starship](https://starship.rs) | official installer → `/usr/local/bin` |
| 4 | [zoxide](https://github.com/ajeetdsouza/zoxide) | official installer → `/usr/local/bin` |
| 5 | [eza](https://github.com/eza-community/eza) | `deb.gierens.de` apt repo (amd64 / arm64 / armhf) |
| 6 | [yazi](https://github.com/sxyazi/yazi) | official `.deb` release (amd64 / arm64) |
| 7 | [tailscale](https://tailscale.com) | official `install.sh` → installs + enables `tailscaled`; `tailscale up` (login) is deferred |
| 8 | [GitHub CLI](https://cli.github.com) | `cli.github.com` apt repo (amd64 / arm64) |
| 9 | [TPM](https://github.com/tmux-plugins/tpm) | `git clone` → `~/.config/tmux/plugins/tpm` |
| 10 | Dotfiles | backs up conflicting files, then `stow --restow .` |
| 11 | Default shell | `sudo chsh -s zsh` (bypasses PAM prompt) |
| 12 | GitHub auth | git identity (`GIT_USER_NAME`/`GIT_USER_EMAIL` or prompt) + `gh auth login` (or `GH_TOKEN`) + `gh auth setup-git` — optional/deferred |

Everything is **idempotent**: re-running only does work that's not already done.

## Robustness features

- `set -euo pipefail` + `IFS=$'\n\t'`
- `ERR` / `EXIT` traps with line-number reporting and tempdir cleanup
- Full log tee'd to `~/.dotpi.log`
- Backs up existing `.zshrc` / `.bashrc` to `~/.dotpi-backup-<timestamp>/` before stowing
- Waits for `apt` lock (avoids clashes with `unattended-upgrades` on fresh Ubuntu)
- Sudo keepalive so the whole run is one prompt
- `DEBIAN_FRONTEND=noninteractive` + `--force-confold` — no blocking dialogs
- `--dry-run` flag prints every action without touching the system

## Architecture support

| Arch | apt pkgs | starship | zoxide | eza | yazi | tailscale |
|---|---|---|---|---|---|---|
| `x86_64` (VPS) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `aarch64` (Pi 4/5, Pi Zero 2, 64-bit VPS) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `armv7l` (Pi 3 / 32-bit Pi OS) | ✓ | ✓ | ✓ | ✓ | ✗ (no upstream binary) | ✓ |

## What's included

| File | Purpose |
|---|---|
| [`.zshrc`](.zshrc) | Zsh — zinit plugins, fzf-tab, zoxide (`d`), aliases, nav functions |
| [`.config/starship/starship.toml`](.config/starship/starship.toml) | Starship — Catppuccin Mocha, powerline segments |
| [`.config/tmux/tmux.conf`](.config/tmux/tmux.conf) | Tmux — vim keys, tokyo-night theme, TPM (XDG path) |

## After setup

```bash
exec zsh              # reload shell
sudo tailscale up     # log in to Tailscale (prints an auth URL to open)
gh auth login         # finish GitHub login if the bootstrap deferred it (non-interactive run)
tmux                  # open tmux
# then press C-Space + I  to install tmux plugins
```

## Key bindings

**Tmux** — prefix `C-Space`

| Key | Action |
|---|---|
| `h j k l` | Move between panes |
| `"` / `%` | Split (inherits cwd) |
| `S-←/→` or `M-H/L` | Switch windows |
| `M-←/↑/→/↓` | Switch panes (no prefix) |
| `C-Space + I` | Install plugins |
| `v` / `y` (copy-mode) | Begin selection / yank |

**Zsh**

| Key / Command | Action |
|---|---|
| `^p` / `^n` | History search back / forward |
| `d <path>` | Jump (zoxide) |
| `fcd` | Fuzzy cd |
| `fv` | Fuzzy open in nvim |
| `f` | Fuzzy find → copy path to clipboard |
| `l` / `lt` / `ll` | `eza -l` / `eza --tree` / `eza -l` (no hidden) |
| `cat` | `bat --paging=never` (when available; auto-handles Debian's `batcat`) |
| `top` | `btop` (when available) |
| `fs` | `yazi` (when available) |

## Environment overrides

The one-liner installer respects these variables:

| Var | Default | Purpose |
|---|---|---|
| `DOTPI_REPO` | `https://github.com/opx0/dotPi` | fork URL |
| `DOTPI_DIR` | `$HOME/dotPi` | clone target |
| `DOTPI_BRANCH` | `main` | branch/tag to check out |
| `GH_TOKEN` / `GITHUB_TOKEN` | _(unset)_ | GitHub token. Used for GitHub API calls (yazi release lookup, dodges the 60/hr anon limit on shared IPs) **and** for non-interactive `gh auth login` on fresh machines |
| `GIT_USER_NAME` | _(unset)_ | git `user.name` to set; prompts when interactive if unset |
| `GIT_USER_EMAIL` | _(unset)_ | git `user.email` to set; prompts when interactive if unset |

Example:

```bash
DOTPI_DIR=~/src/dotPi curl -fsSL .../install.sh | bash
```

## Troubleshooting

- **Script failed** — check `~/.dotpi.log` for the full transcript.
- **Stow conflicts** — displaced files are moved to `~/.dotpi-backup-<timestamp>/`, not deleted. Diff them against `$HOME` to recover anything you want.
- **TPM plugins didn't install** — open tmux and press `C-Space + I` (the one step that needs interactive tmux).
- **Shell didn't change** — run `sudo chsh -s $(which zsh) $USER` manually, then re-login.
