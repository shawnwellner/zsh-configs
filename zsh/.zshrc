# zsh-configs: the shared zsh setup. ~/.zshrc is a small file the installer creates (not in
# git) that loads this one. Change this file for every machine; settings for one machine go in
# ~/.zshrc below its loader line, your aliases in ~/.aliases and secrets in ~/.env.

export PATH="$HOME/.local/bin:$PATH"
typeset -U path PATH   # drop duplicate PATH entries

# ---------------------------------------------------------------------------
# Oh My Zsh
# ---------------------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""   # the prompt comes from Starship (below)

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-vi-mode
)

# zsh-completions only works from fpath (not as a plugin) — it must be added before
# oh-my-zsh runs compinit. See https://github.com/zsh-users/zsh-completions#oh-my-zsh
fpath+=("${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src")

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  print -u2 "zsh-configs: Oh My Zsh isn't installed at $ZSH; re-run install.sh from zsh-configs"
fi

# ---------------------------------------------------------------------------
# Your files, loaded only if present. The repo never overwrites them (the installer only
# creates ~/.aliases from a starter when it's missing). Plain sh syntax, so bash can load them too.
# ---------------------------------------------------------------------------
[[ -f ~/.env ]]     && source ~/.env       # secrets: export NAME=value
[[ -f ~/.aliases ]] && source ~/.aliases   # your aliases

# ---------------------------------------------------------------------------
# Terminal title: hostname + distro + cwd. Only for terminals that understand title
# escapes (not the Linux console, TERM=dumb or Emacs). The text is printed raw, never
# prompt-expanded, so a folder name like '$(cmd)' can't run anything.
# ---------------------------------------------------------------------------
if [[ -z "$INSIDE_EMACS" ]]; then
  case "$TERM" in
    xterm*|rxvt*|screen*|tmux*|alacritty*|wezterm*|foot*|kitty*|konsole*|putty*|st|st-*|contour*|mlterm*|cygwin|ansi)
      if [[ -r /etc/os-release ]]; then
        _TITLE_OS="$(. /etc/os-release && print -r -- "$PRETTY_NAME")"   # e.g. "Ubuntu 26.04.1 LTS"
      else
        _TITLE_OS="Linux $(uname -r)"
      fi
      _set_terminal_title() {
        print -rn -- $'\e]1;'"${HOST}"$'\a'                                    # tab
        print -rn -- $'\e]2;'"${HOST} — ${_TITLE_OS} — ${PWD/#$HOME/~}"$'\a'   # window
      }
      autoload -Uz add-zsh-hook
      add-zsh-hook precmd _set_terminal_title
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Prompt: Starship (config: ~/.config/starship.toml)
# ---------------------------------------------------------------------------
if (( $+commands[starship] )); then
  _starship_init="$(starship init zsh --print-full-init)"
  eval "$_starship_init"
  # zsh-vi-mode rebinds keys when it initialises; re-apply Starship's setup after it
  # (from the saved script, so no second starship process).
  typeset -ga zvm_after_init_commands
  zvm_after_init_commands+=('eval "$_starship_init"')
fi
