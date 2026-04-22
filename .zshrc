# ─── dotPi zshrc ──────────────────────────────────────────────────────────────

# ─── path ─────────────────────────────────────────────────────────────────────
typeset -U path PATH   # dedupe
path=(
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/.bun/bin"
    "/usr/local/bin"
    $path
)
export PATH

export BUN_INSTALL="$HOME/.bun"
export TERM="${TERM:-xterm-256color}"
export EDITOR="${EDITOR:-nvim}"
export VISUAL="$EDITOR"
export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"

# ─── zinit ────────────────────────────────────────────────────────────────────
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# ─── plugins (turbo mode — deferred, ~10× faster startup) ─────────────────────
zinit wait lucid light-mode for \
    atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
        zdharma-continuum/fast-syntax-highlighting \
    atload"_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    blockf atpull'zinit creinstall -q .' \
        zsh-users/zsh-completions \
    Aloxaf/fzf-tab

# OMZ snippets (eager — small, provide aliases used immediately)
zinit snippet OMZP::git
zinit snippet OMZP::sudo

# ─── completion styling ───────────────────────────────────────────────────────
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':completion:*' rehash true                       # pick up new binaries

# fzf-tab previews
zstyle ':fzf-tab:complete:cd:*'           fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*'   fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:git-checkout:*' fzf-preview 'git log --oneline --color=always -20 $word 2>/dev/null'
zstyle ':fzf-tab:complete:(kill|ps):*'    fzf-preview 'ps -p $word -o cmd --no-headers -w -w 2>/dev/null'
zstyle ':fzf-tab:*' use-fzf-default-opts yes

# ─── options ──────────────────────────────────────────────────────────────────
setopt auto_cd                # `foo` == `cd foo`
setopt interactive_comments   # allow `#` in interactive shell
setopt extended_glob          # powerful globs
setopt no_beep

# history
HISTSIZE=100000
SAVEHIST=$HISTSIZE
HISTFILE="$HOME/.zsh_history"
HISTDUP=erase
setopt inc_append_history     # write every command immediately
setopt share_history
setopt extended_history       # timestamp entries
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups
setopt hist_reduce_blanks
setopt hist_verify            # expand ! before executing

# ─── keybindings ──────────────────────────────────────────────────────────────
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region
bindkey '^[[1;5C' forward-word    # ctrl-right
bindkey '^[[1;5D' backward-word   # ctrl-left

# ─── aliases ──────────────────────────────────────────────────────────────────
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias v='nvim'
alias cl='clear'
alias la='tree'
alias op='code .'
alias ta='tmux attach || tmux new'

# dirs
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'

# git
alias gc='git commit -m'
alias gca='git commit -a -m'
alias gp='git push origin'
alias gpu='git pull origin'
alias gst='git status'
alias glog="git log --graph --topo-order --pretty='%w(100,0,6)%C(yellow)%h%C(bold)%C(black)%d %C(cyan)%ar %C(green)%an%n%C(bold)%C(white)%s %N' --abbrev-commit"
alias gdiff='git diff'
alias gco='git checkout'
alias gb='git branch'
alias gba='git branch -a'
alias gadd='git add'
alias ga='git add -p'
alias gcoall='git checkout -- .'
alias gr='git remote'
alias gre='git reset'

# modern replacements (conditional on install)
if command -v eza &>/dev/null; then
    alias l='eza -l --icons --git -a'
    alias lt='eza --tree --level=2 --long --icons --git'
    alias ll='eza -l --icons --git'
else
    alias l='ls -la'
    alias lt='tree -L 2'
    alias ll='ls -l'
fi

command -v yazi &>/dev/null && alias fs='yazi'
command -v bat  &>/dev/null && alias cat='bat --paging=never'
command -v btop &>/dev/null && alias top='btop'

# ─── functions ────────────────────────────────────────────────────────────────
cx() { cd "$@" && l; }

fcd() {
    local dir
    dir=$(find . -type d -not -path '*/.*' 2>/dev/null | fzf) && cd "$dir" && l
}

f() {
    local file
    file=$(find . -type f -not -path '*/.*' 2>/dev/null | fzf) || return
    if command -v xclip &>/dev/null; then
        printf '%s' "$file" | xclip -selection clipboard
        echo "copied: $file"
    elif command -v wl-copy &>/dev/null; then
        printf '%s' "$file" | wl-copy
        echo "copied: $file"
    else
        echo "$file"
    fi
}

fv() {
    local file
    file=$(find . -type f -not -path '*/.*' 2>/dev/null | fzf) && nvim "$file"
}

mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
    [[ ! -f "$1" ]] && { echo "not a file: $1" >&2; return 1; }
    case "$1" in
        *.tar.bz2|*.tbz2) tar xjf "$1"   ;;
        *.tar.gz|*.tgz)   tar xzf "$1"   ;;
        *.tar.xz)         tar xJf "$1"   ;;
        *.tar)            tar xf  "$1"   ;;
        *.bz2)            bunzip2 "$1"   ;;
        *.gz)             gunzip  "$1"   ;;
        *.zip)            unzip   "$1"   ;;
        *.rar)            unrar x "$1"   ;;
        *.7z)             7z x    "$1"   ;;
        *.xz)             unxz    "$1"   ;;
        *) echo "unsupported: $1" >&2; return 1 ;;
    esac
}

# ─── fzf ──────────────────────────────────────────────────────────────────────
# Catppuccin Mocha palette (matches starship + tmux theme)
export FZF_DEFAULT_OPTS="\
--height 40% --layout=reverse --border=rounded \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

# use fd if available (faster + respects .gitignore)
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

# ─── shell integrations ───────────────────────────────────────────────────────
command -v fzf      &>/dev/null && source <(fzf --zsh) 2>/dev/null
command -v zoxide   &>/dev/null && eval "$(zoxide init --cmd d zsh)"
command -v starship &>/dev/null && eval "$(starship init zsh)"
[[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"

# ─── local overrides ──────────────────────────────────────────────────────────
# machine-specific tweaks that shouldn't be tracked in git
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
