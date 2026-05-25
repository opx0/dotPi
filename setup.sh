#!/usr/bin/env bash
# dotPi — one-shot bootstrap for Raspberry Pi / Debian / Ubuntu VPS
#
# Two ways to run (both work):
#   1. curl -fsSL https://raw.githubusercontent.com/opx0/dotPi/main/setup.sh | bash
#   2. git clone https://github.com/opx0/dotPi ~/dotPi && ~/dotPi/setup.sh
#
# Safe to re-run. Supports: x86_64, aarch64, armv7l (eza only).

set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true   # bash 4.4+: errexit into $( )
IFS=$'\n\t'

# ── bootstrap: clone repo if piped via curl|bash ──────────────────────────────
DOTPI_REPO="${DOTPI_REPO:-https://github.com/opx0/dotPi}"
DOTPI_DIR="${DOTPI_DIR:-$HOME/dotPi}"
DOTPI_BRANCH="${DOTPI_BRANCH:-main}"

# If BASH_SOURCE[0] points at a real file inside a dotPi checkout (has packages.txt
# alongside), we're running from the repo. Otherwise we're piped — clone + re-exec.
_src="${BASH_SOURCE[0]:-}"
if [[ -n "$_src" && -f "$_src" && -f "$(dirname "$_src")/packages.txt" ]]; then
  DOTFILES_DIR="$(cd "$(dirname "$_src")" && pwd)"
else
  echo "dotPi: bootstrapping via clone..."
  command -v git >/dev/null 2>&1 || {
    echo "git is required. Install first (as root): apt install git" >&2
    exit 1
  }
  if [[ -d "$DOTPI_DIR/.git" ]]; then
    echo "  repo exists at $DOTPI_DIR — pulling latest"
    git -C "$DOTPI_DIR" pull --ff-only 2>/dev/null || echo "  (pull skipped: local changes)"
  else
    echo "  cloning $DOTPI_REPO → $DOTPI_DIR"
    git clone --depth=1 --branch "$DOTPI_BRANCH" "$DOTPI_REPO" "$DOTPI_DIR"
  fi
  exec bash "$DOTPI_DIR/setup.sh" "$@"
fi

# ── config ────────────────────────────────────────────────────────────────────
ARCH="$(uname -m)"
LOGFILE="$HOME/.dotpi.log"
BACKUP_DIR="$HOME/.dotpi-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
SKIP_SHELL=0
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

usage() {
  cat <<EOF
dotPi — one-shot bootstrap for Raspberry Pi / Debian / Ubuntu VPS

Usage: $0 [--dry-run] [--skip-shell] [-h|--help]

Flags:
  --dry-run      Print every action without touching the system.
  --skip-shell   Skip the chsh step (don't change the default shell).
  -h, --help     Show this help.

Env overrides honored when piped via curl|bash:
  DOTPI_REPO     fork URL                (default: https://github.com/opx0/dotPi)
  DOTPI_DIR      clone target            (default: \$HOME/dotPi)
  DOTPI_BRANCH   branch/tag to check out (default: main)
  GH_TOKEN       GitHub token — API calls + non-interactive 'gh auth login'
  GITHUB_TOKEN   alias for GH_TOKEN (either is accepted by gh)
  GIT_USER_NAME  git user.name to set    (else prompt when interactive)
  GIT_USER_EMAIL git user.email to set   (else prompt when interactive)
EOF
}

# parse flags
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-shell) SKIP_SHELL=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

# ── logging ───────────────────────────────────────────────────────────────────
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'
log()  { echo -e "${BLUE}[dotPi]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  !${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*" >&2; }
run()  { if [[ $DRY_RUN -eq 1 ]]; then echo -e "${DIM}    [dry] $*${NC}"; else eval "$@"; fi; }

exec > >(tee -a "$LOGFILE") 2>&1

# ── traps ─────────────────────────────────────────────────────────────────────
TMPDIRS=()
mktmp() { local d; d=$(mktemp -d); TMPDIRS+=("$d"); echo "$d"; }
cleanup() {
  local rc=$?
  for d in "${TMPDIRS[@]:-}"; do [[ -d "$d" ]] && rm -rf "$d"; done
  [[ $rc -ne 0 ]] && err "setup failed (exit $rc) — see $LOGFILE"
  exit $rc
}
on_error() { err "failed at line $1: $2"; }
trap 'on_error $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

# ── preflight ─────────────────────────────────────────────────────────────────
preflight() {
  log "Preflight checks..."

  # must not be root (sudo is used explicitly)
  if [[ $EUID -eq 0 ]]; then
    err "Run as a regular user, not root. sudo will be invoked where needed."
    exit 1
  fi

  # sudo present?
  if ! command -v sudo &>/dev/null; then
    err "sudo is not installed. Install it as root first:  apt install sudo"
    exit 1
  fi

  # sudo — prefer NOPASSWD; if a password is needed, warn clearly before prompting
  if sudo -n true 2>/dev/null; then
    ok "sudo (passwordless)"
  else
    log "sudo requires your password — you'll be asked ONCE, then cached for the run."
    log "(if your user has no password, reset it via the Azure Portal or set NOPASSWD in /etc/sudoers.d/)"
    if ! sudo -v; then
      err "sudo authentication failed — cannot proceed without sudo"
      exit 1
    fi
  fi
  ( while true; do sudo -n true 2>/dev/null || exit; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true; cleanup' EXIT

  # wait for any apt lock (unattended-upgrades on fresh Ubuntu)
  local waited=0
  while sudo fuser /var/lib/dpkg/lock-frontend &>/dev/null; do
    [[ $waited -eq 0 ]] && log "Waiting for apt lock (unattended-upgrades?)..."
    sleep 3; waited=$((waited+3))
    [[ $waited -gt 300 ]] && { err "apt lock held >5min, giving up"; exit 1; }
  done

  # locale — prevent perl warning cascade
  if ! locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$'; then
    log "Generating en_US.UTF-8 locale..."
    run "sudo apt-get install -y -qq locales"
    run "sudo locale-gen en_US.UTF-8"
  fi

  ok "preflight OK (arch=$ARCH)"
}

# ── apt packages ──────────────────────────────────────────────────────────────
pkg_installed() {
  # Robust: status field must start with "install ok installed".
  local s
  s=$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null || true)
  [[ "$s" == "installed" ]]
}

install_apt_packages() {
  log "Installing apt packages..."
  run "sudo apt-get update -y -qq"
  local pkgs=()
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    # strip leading/trailing whitespace, then skip blank/comment lines
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"
    pkg="${pkg%"${pkg##*[![:space:]]}"}"
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    if pkg_installed "$pkg"; then
      ok "$pkg"
    else
      pkgs+=("$pkg")
    fi
  done < "$DOTFILES_DIR/packages.txt"

  if [[ ${#pkgs[@]} -gt 0 ]]; then
    # Use a space-joined string for display; IFS=$'\n\t' means "${pkgs[*]}" would newline-join.
    local pkg_list
    pkg_list="$(printf '%s ' "${pkgs[@]}")"
    log "Installing: ${pkg_list% }"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo -e "${DIM}    [dry] sudo apt-get install ${pkg_list% }${NC}"
    else
      # "${pkgs[@]}" expands each element as its own argv word regardless of IFS — correct way.
      sudo apt-get install -y -qq -o Dpkg::Options::=--force-confold "${pkgs[@]}"
    fi
    for p in "${pkgs[@]}"; do ok "$p"; done
  fi
}

# ── starship ──────────────────────────────────────────────────────────────────
install_starship() {
  log "Installing starship..."
  if command -v starship &>/dev/null; then ok "starship $(starship --version | head -1)"; return; fi
  run "curl -fsSL https://starship.rs/install.sh | sudo sh -s -- --yes --bin-dir /usr/local/bin"
  ok "starship"
}

# ── zoxide ────────────────────────────────────────────────────────────────────
install_zoxide() {
  log "Installing zoxide..."
  if command -v zoxide &>/dev/null; then ok "zoxide $(zoxide --version)"; return; fi
  run "curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sudo bash -s -- --bin-dir /usr/local/bin"
  ok "zoxide"
}

# ── eza (via gierens apt repo) ────────────────────────────────────────────────
install_eza() {
  log "Installing eza..."
  if command -v eza &>/dev/null; then ok "eza $(eza --version | head -1)"; return; fi

  if [[ ! -f /etc/apt/sources.list.d/gierens.list ]]; then
    run "sudo mkdir -p /etc/apt/keyrings"
    run "curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg"
    run "echo 'deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main' | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null"
    run "sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list"
    run "sudo apt-get update -y -qq"
  fi
  run "sudo apt-get install -y -qq eza"
  ok "eza"
}

# Wrapper for GitHub API calls — honors GH_TOKEN to avoid the 60/hr anon limit.
gh_api() {
  local url="$1"
  if [[ -n "${GH_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer $GH_TOKEN" "$url"
  else
    curl -fsSL "$url"
  fi
}

# ── yazi (via .deb from GitHub releases) ──────────────────────────────────────
install_yazi() {
  log "Installing yazi..."
  if command -v yazi &>/dev/null; then ok "yazi $(yazi --version)"; return; fi

  local target
  case "$ARCH" in
    x86_64)  target="x86_64-unknown-linux-gnu" ;;
    aarch64) target="aarch64-unknown-linux-gnu" ;;
    *) warn "yazi: no prebuilt binary for $ARCH, skipping"; return ;;
  esac

  local url
  url=$(gh_api "https://api.github.com/repos/sxyazi/yazi/releases/latest" \
        | grep "browser_download_url.*yazi-${target}\.deb\"" \
        | cut -d '"' -f4 | head -1)

  if [[ -z "$url" ]]; then
    warn "yazi: could not resolve .deb release URL, falling back to zip"
    install_yazi_zip "$target"
    return
  fi

  local tmp; tmp=$(mktmp)
  run "curl -fsSL '$url' -o '$tmp/yazi.deb'"
  run "sudo apt-get install -y -qq '$tmp/yazi.deb'"
  ok "yazi (+ ya helper)"
}

install_yazi_zip() {
  local target="$1"
  local musl_target="${target/-gnu/-musl}"
  local url
  url=$(gh_api "https://api.github.com/repos/sxyazi/yazi/releases/latest" \
        | grep "browser_download_url.*yazi-${musl_target}\.zip\"" \
        | cut -d '"' -f4 | head -1)
  [[ -z "$url" ]] && { err "yazi: no zip release for $musl_target"; return; }

  local tmp; tmp=$(mktmp)
  run "curl -fsSL '$url' -o '$tmp/yazi.zip'"
  run "unzip -q '$tmp/yazi.zip' -d '$tmp'"
  run "sudo install -m 755 '$tmp/yazi-${musl_target}/yazi' /usr/local/bin/yazi"
  [[ -f "$tmp/yazi-${musl_target}/ya" ]] && run "sudo install -m 755 '$tmp/yazi-${musl_target}/ya' /usr/local/bin/ya"
  ok "yazi (zip)"
}

# ── tailscale ───────────────────────────────────────────────────────────────
install_tailscale() {
  log "Installing tailscale..."
  if command -v tailscale &>/dev/null; then
    ok "tailscale $(tailscale version | head -1)"
  else
    # official installer auto-detects distro + arch and enables the daemon
    run "curl -fsSL https://tailscale.com/install.sh | sh"
    ok "tailscale"
  fi

  # ensure tailscaled is enabled + running (idempotent — the installer already
  # does this on systemd, but a re-run repairs a disabled/stopped daemon)
  if command -v systemctl &>/dev/null; then
    run "sudo systemctl enable --now tailscaled"
  fi

  # auth is interactive and intentionally deferred — point at the finishing step
  if [[ $DRY_RUN -eq 0 ]] && command -v tailscale &>/dev/null && ! tailscale status &>/dev/null; then
    warn "tailscale installed but not logged in — finish with:  sudo tailscale up"
  fi
}

# ── GitHub CLI (gh, via official apt repo) ────────────────────────────────────
install_gh() {
  log "Installing GitHub CLI (gh)..."
  if command -v gh &>/dev/null; then ok "gh $(gh --version | head -1)"; return; fi

  if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
    local deb_arch; deb_arch="$(dpkg --print-architecture)"
    run "sudo mkdir -p /etc/apt/keyrings"
    # this keyring is already dearmored (binary gpg) — write it as-is, no --dearmor
    run "curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null"
    run "sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg"
    run "echo 'deb [arch=$deb_arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main' | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null"
    run "sudo apt-get update -y -qq"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "${DIM}    [dry] sudo apt-get install -y -qq gh${NC}"
  elif sudo apt-get install -y -qq gh; then
    ok "gh"
  else
    warn "gh: no package for $ARCH? install manually — https://github.com/cli/cli#installation"
  fi
}

# ── TPM ───────────────────────────────────────────────────────────────────────
install_tpm() {
  log "Installing TPM..."
  local tpm_dir="$HOME/.config/tmux/plugins/tpm"
  if [[ -d "$tpm_dir/.git" ]]; then
    ok "tpm (already present)"
    return
  fi
  run "mkdir -p '$HOME/.config/tmux/plugins'"
  run "git clone -q --depth=1 https://github.com/tmux-plugins/tpm '$tpm_dir'"
  ok "tpm"
}

# ── stow dotfiles (with conflict backup) ──────────────────────────────────────
stow_dotfiles() {
  log "Symlinking dotfiles..."
  cd "$DOTFILES_DIR"

  # detect conflicts first
  local conflicts
  conflicts=$(stow -n --verbose=2 . 2>&1 | grep -oP '(?<=existing target is neither a link nor a directory: ).*' || true)

  if [[ -n "$conflicts" ]]; then
    warn "backing up conflicting files to $BACKUP_DIR"
    run "mkdir -p '$BACKUP_DIR'"
    while IFS= read -r rel; do
      local src="$HOME/$rel"
      [[ -e "$src" ]] && {
        run "mkdir -p \"$BACKUP_DIR/\$(dirname '$rel')\""
        run "mv '$src' '$BACKUP_DIR/$rel'"
        ok "backed up $rel"
      }
    done <<< "$conflicts"
  fi

  run "stow --restow --target='$HOME' ."
  ok "dotfiles symlinked"
}

# ── default shell ─────────────────────────────────────────────────────────────
set_zsh_default() {
  if [[ $SKIP_SHELL -eq 1 ]]; then
    log "Skipping shell change (--skip-shell)"
    return
  fi
  log "Setting zsh as default shell..."
  local zsh_path; zsh_path=$(command -v zsh)
  [[ -z "$zsh_path" ]] && { err "zsh not found in PATH"; return; }

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    ok "zsh already default"
    return
  fi

  # ensure zsh is in /etc/shells
  if ! grep -qxF "$zsh_path" /etc/shells; then
    run "echo '$zsh_path' | sudo tee -a /etc/shells >/dev/null"
  fi

  # use sudo chsh to avoid PAM password prompt on fresh SSH sessions
  if run "sudo chsh -s '$zsh_path' '$USER'"; then
    ok "shell → zsh (re-login to apply)"
  else
    warn "chsh failed — run manually:  sudo chsh -s $zsh_path $USER"
  fi
}

# ── GitHub: git identity + gh auth ────────────────────────────────────────────
configure_git_identity() {
  local cur_name cur_email
  cur_name="$(git config --global user.name 2>/dev/null || true)"
  cur_email="$(git config --global user.email 2>/dev/null || true)"
  if [[ -n "$cur_name" && -n "$cur_email" ]]; then
    ok "git identity already set ($cur_name <$cur_email>)"
    return
  fi

  # env wins; otherwise prompt, but only with a real TTY (skips piped curl|bash)
  local name="${GIT_USER_NAME:-$cur_name}"
  local email="${GIT_USER_EMAIL:-$cur_email}"
  if [[ $DRY_RUN -eq 0 && -t 0 && -t 1 ]]; then
    [[ -z "$name"  ]] && { read -rp "  git user.name  (blank to skip): " name  || true; }
    [[ -z "$email" ]] && { read -rp "  git user.email (blank to skip): " email || true; }
  fi

  [[ -n "$name"  ]] && { run "git config --global user.name '$name'";   ok "user.name = $name"; }
  [[ -n "$email" ]] && { run "git config --global user.email '$email'"; ok "user.email = $email"; }
  [[ -z "$name" && -z "$email" ]] && warn "git identity unset — set later or pass GIT_USER_NAME / GIT_USER_EMAIL"
}

setup_github() {
  log "Configuring GitHub..."
  configure_git_identity

  if ! command -v gh &>/dev/null; then
    warn "gh not installed — skipping GitHub auth"
    return
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "${DIM}    [dry] gh auth login  (token if \$GH_TOKEN/\$GITHUB_TOKEN set, else interactive)${NC}"
    echo -e "${DIM}    [dry] gh auth setup-git${NC}"
    return
  fi

  if gh auth status &>/dev/null; then
    ok "gh already authenticated"
  else
    # token never goes through run/eval (the whole run is tee'd to the logfile)
    local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    if [[ -n "$token" ]]; then
      if printf '%s' "$token" | gh auth login --with-token; then
        ok "gh authenticated (token)"
      else
        warn "token auth failed — finish later:  gh auth login"; return
      fi
    elif [[ -t 0 && -t 1 ]]; then
      log "Launching 'gh auth login' (pick SSH to match this repo's git@ remotes)..."
      if ! gh auth login; then
        warn "gh auth login cancelled — finish later:  gh auth login"; return
      fi
    else
      warn "no TTY and no \$GH_TOKEN/\$GITHUB_TOKEN — GitHub login deferred. Finish with:  gh auth login"
      return
    fi
  fi

  # wire git to use gh's credentials (HTTPS helper; harmless for SSH remotes)
  if gh auth setup-git; then ok "git wired to GitHub (gh auth setup-git)"; else warn "gh auth setup-git failed"; fi
}

# ── verify ────────────────────────────────────────────────────────────────────
verify() {
  log "Verifying installed tools..."
  local missing=0
  for cmd in stow fzf nvim tmux zsh tree git starship zoxide eza tailscale gh; do
    if command -v "$cmd" &>/dev/null; then
      ok "$cmd"
    else
      warn "$cmd not on PATH"
      missing=$((missing+1))
    fi
  done
  # yazi is optional (armv7l skip)
  if command -v yazi &>/dev/null; then ok "yazi"; else warn "yazi not on PATH (expected on armv7l)"; fi
  [[ $missing -eq 0 ]] || warn "$missing required tool(s) missing — check $LOGFILE"
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BLUE}╔════════════════════════════╗${NC}"
  echo -e "${BLUE}║        dotPi setup         ║${NC}"
  echo -e "${BLUE}╚════════════════════════════╝${NC}"
  [[ $DRY_RUN -eq 1 ]] && warn "DRY-RUN mode — no changes will be made"
  echo ""

  preflight
  install_apt_packages
  install_starship
  install_zoxide
  install_eza
  install_yazi
  install_tailscale
  install_gh
  install_tpm
  stow_dotfiles
  set_zsh_default
  setup_github
  [[ $DRY_RUN -eq 0 ]] && verify

  echo ""
  ok "All done!"
  echo ""
  echo "  Log: $LOGFILE"
  [[ -d "$BACKUP_DIR" ]] && echo "  Backups of displaced files: $BACKUP_DIR"
  echo ""

  # drop user straight into zsh if running interactively — otherwise print instruction
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [[ $DRY_RUN -eq 0 ]] && [[ -n "$zsh_path" ]] && [[ -t 0 && -t 1 ]] && [[ "${SHELL:-}" != "$zsh_path" ]]; then
    log "Starting zsh now..."
    # kill sudo-keepalive so we don't orphan it (trap will try, but exec replaces us)
    kill "${SUDO_KEEPALIVE:-0}" 2>/dev/null || true
    exec "$zsh_path" -l
  else
    echo "  Start zsh:  exec zsh -l"
  fi
}

main "$@"
