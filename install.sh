#!/usr/bin/env bash
# Sets up zsh: Oh My Zsh + plugins + Starship + the configs in this repo.
# Safe to re-run: it skips what's already in place and updates the plugins.
#
#   curl -fsSL https://raw.githubusercontent.com/shawnwellner/zsh-configs/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/shawnwellner/zsh-configs/main/install.sh | bash -s -- --no-chsh
#   ~/.dotfiles/install.sh            # from a checkout
#
# Run with --help for the options and environment variables.
#
# Everything below the bash check sits inside functions and `main` runs on the last line,
# so a truncated download can't run half a script and nothing can swallow piped stdin.

# Plain sh up to here, so `curl ... | sh` explains itself instead of failing on bash syntax.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "install.sh needs bash. Run: curl -fsSL https://raw.githubusercontent.com/shawnwellner/zsh-configs/main/install.sh | bash" >&2
  exit 1
fi

set -euo pipefail
unset CDPATH   # otherwise `cd` inside $(...) can print the path and corrupt the result

DEFAULT_REPO="https://github.com/shawnwellner/zsh-configs.git"
DEFAULT_SSH_REPO="git@github.com:shawnwellner/zsh-configs.git"   # fallback for the default repo only
DOTFILES_REPO="${DOTFILES_REPO:-$DEFAULT_REPO}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
OMZ_DIR="$HOME/.oh-my-zsh"
OMZ_CUSTOM="$OMZ_DIR/custom"
BIN_DIR="$HOME/.local/bin"
BACKUP_NAME="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.dotfiles-backup/$BACKUP_NAME"

# Same package names on Debian/Ubuntu (apt) and Arch (pacman).
# net-tools: `netstat` for the `ports` alias. unzip: .zip files for the `extract` plugin.
PACKAGES=(zsh git curl ca-certificates net-tools unzip)

# path-under-$OMZ_CUSTOM  git-url
OMZ_ADDONS=(
  "plugins/zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions.git"
  "plugins/zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git"
  "plugins/zsh-completions         https://github.com/zsh-users/zsh-completions.git"
  "plugins/zsh-vi-mode             https://github.com/jeffreytse/zsh-vi-mode.git"
)

# repo file  ->  target under $HOME, symlinked (nothing but you edits these)
LINKS=(
  "config/starship.toml    .config/starship.toml"
)

# repo file  ->  target under $HOME that gets a small loader file instead of a symlink.
# Tool installers often append to ~/.zshrc; with a loader, those lines stay on the machine
# instead of landing in the repo.
LOADERS=(
  "zsh/.zshrc      .zshrc"
  "zsh/.zprofile   .zprofile"
)
LOADER_MARK="# zsh-configs loader"

DO_PACKAGES=1
DO_CHSH=1
WORK_DIR=""   # scratch space; removed by cleanup() on any exit
ME="${USER:-$(id -un)}"

if [[ -t 1 ]]; then
  c_blue=$'\e[1;34m' c_yellow=$'\e[1;33m' c_red=$'\e[1;31m' c_green=$'\e[1;32m' c_off=$'\e[0m'
else
  c_blue='' c_yellow='' c_red='' c_green='' c_off=''
fi
step() { printf '%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s!!%s  %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%sxx%s  %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

as_root() {
  if [[ $EUID -eq 0 ]]; then "$@"
  elif have sudo; then sudo "$@"
  else return 1
  fi
}

cleanup() {
  if [[ -n "$WORK_DIR" ]]; then rm -rf "$WORK_DIR"; fi
}

usage() {
  cat <<'EOF'
Usage: install.sh [options]
       curl -fsSL https://raw.githubusercontent.com/shawnwellner/zsh-configs/main/install.sh | bash -s -- [options]

Options:
  --no-packages    skip installing packages (zsh git curl ca-certificates net-tools unzip,
                   with apt on Debian/Ubuntu or pacman on Arch)
  --no-chsh        don't make zsh the login shell
  -h, --help       show this help

Environment:
  DOTFILES_DIR     where the repo is cloned   (default: ~/.dotfiles)
  DOTFILES_REPO    clone URL                  (default: https://github.com/shawnwellner/zsh-configs.git)
  DOTFILES_BRANCH  branch to check out        (default: main)
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --no-packages) DO_PACKAGES=0 ;;
      --no-chsh)     DO_CHSH=0 ;;
      -h|--help)     usage; exit 0 ;;
      *)             die "unknown option: $1 (try --help)" ;;
    esac
    shift
  done
}

# apt for Debian/Ubuntu, pacman for Arch and Arch-based distros.
package_manager() {
  if have apt-get && have dpkg-query; then echo apt
  elif have pacman; then echo pacman
  fi
}

is_installed() {
  case "$1" in
    apt)    dpkg-query -W -f='${Status}' "$2" 2>/dev/null | grep -q 'install ok installed' ;;
    pacman) pacman -Q "$2" >/dev/null 2>&1 ;;
  esac
}

install_packages() {
  step "System packages"
  if ((!DO_PACKAGES)); then info "skipped (--no-packages)"; return; fi
  local pm missing=() p
  pm="$(package_manager)"
  if [[ -z "$pm" ]]; then
    warn "no apt or pacman here; install these yourself: ${PACKAGES[*]}"
    return
  fi
  for p in "${PACKAGES[@]}"; do
    is_installed "$pm" "$p" || missing+=("$p")
  done
  if ((${#missing[@]} == 0)); then info "all present ($pm): ${PACKAGES[*]}"; return; fi
  info "installing with $pm: ${missing[*]}"
  case "$pm" in
    apt)
      as_root apt-get update -qq </dev/null || die "apt-get update failed (need sudo?)"
      as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" </dev/null >/dev/null \
        || die "apt-get install failed"
      ;;
    pacman)
      # No -y: refreshing the package list without a full upgrade (-Sy) can leave Arch half-upgraded.
      as_root pacman -S --needed --noconfirm "${missing[@]}" </dev/null >/dev/null \
        || die "pacman couldn't install ${missing[*]} (need sudo? if the package list is stale, run: sudo pacman -Syu)"
      ;;
  esac
}

# Work out where the repo is: the checkout this script runs from, or clone/update $DOTFILES_DIR.
ensure_repo() {
  step "Dotfiles repo"
  have git || die "git is required (re-run without --no-packages, or install git)"
  local self_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -n "$self_dir" && -f "$self_dir/zsh/.zshrc" ]]; then
    DOTFILES_DIR="$self_dir"
    info "using checkout at $DOTFILES_DIR"
  elif [[ -e "$DOTFILES_DIR" ]]; then
    # Only reuse an existing folder if it's a checkout of this repo. ~/.dotfiles is a common
    # name, so never pull or link from somebody else's dotfiles.
    if [[ -d "$DOTFILES_DIR/.git" && -f "$DOTFILES_DIR/install.sh" && -f "$DOTFILES_DIR/zsh/.zshrc" ]]; then
      info "updating $DOTFILES_DIR"
      git -C "$DOTFILES_DIR" pull --ff-only -q </dev/null \
        || warn "couldn't fast-forward $DOTFILES_DIR (local changes?); using it as-is"
    else
      die "$DOTFILES_DIR already exists and isn't this repo. Move it aside, or install somewhere else:" \
        "curl -fsSL <install.sh URL> | DOTFILES_DIR=\$HOME/.zsh-configs bash"
    fi
  else
    info "cloning into $DOTFILES_DIR"
    # HTTPS first (works for a public repo with no keys). Only the default repo falls back to
    # SSH (for a private copy); a custom DOTFILES_REPO must never silently become another repo.
    if GIT_TERMINAL_PROMPT=0 git clone -q --branch "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$DOTFILES_DIR" </dev/null; then
      :
    elif [[ "$DOTFILES_REPO" == "$DEFAULT_REPO" ]] \
      && git clone -q --branch "$DOTFILES_BRANCH" "$DEFAULT_SSH_REPO" "$DOTFILES_DIR" </dev/null; then
      :
    else
      die "couldn't clone $DOTFILES_REPO"
    fi
  fi
  # Absolute path, so the links and loaders work even if DOTFILES_DIR was given as a relative path.
  DOTFILES_DIR="$(cd "$DOTFILES_DIR" && pwd)"
}

install_oh_my_zsh() {
  step "Oh My Zsh"
  if [[ -f "$OMZ_DIR/oh-my-zsh.sh" ]]; then info "already installed at $OMZ_DIR"; return; fi
  [[ -e "$OMZ_DIR" ]] && die "$OMZ_DIR exists but isn't an Oh My Zsh install; move it aside and re-run"
  # Same git settings the official installer uses, so `omz update` works afterwards.
  git clone -q --depth=1 --branch master \
    -c core.eol=lf -c core.autocrlf=false \
    -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore \
    -c receive.fsck.zeroPaddedFilemode=ignore \
    -c oh-my-zsh.remote=origin -c oh-my-zsh.branch=master \
    https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR" </dev/null \
    || die "couldn't download Oh My Zsh from GitHub"
  info "installed to $OMZ_DIR"
}

install_omz_addons() {
  step "Oh My Zsh plugins"
  local entry rel url dest
  for entry in "${OMZ_ADDONS[@]}"; do
    read -r rel url <<<"$entry"
    dest="$OMZ_CUSTOM/$rel"
    if [[ -d "$dest/.git" ]]; then
      if git -C "$dest" pull --ff-only -q </dev/null; then info "updated   ${rel#*/}"
      else warn "couldn't update ${rel#*/}; leaving it as-is"; fi
    elif [[ -e "$dest" ]]; then
      warn "${rel#*/} exists but isn't a git checkout; leaving it as-is"
    else
      mkdir -p "$(dirname "$dest")"
      git clone -q --depth=1 "$url" "$dest" </dev/null || die "couldn't download ${rel#*/} from $url"
      info "installed ${rel#*/}"
    fi
  done
}

install_starship() {
  step "Starship prompt"
  if have starship || [[ -x "$BIN_DIR/starship" ]]; then
    info "already installed ($("$(command -v starship || echo "$BIN_DIR/starship")" --version | head -1))"
    return
  fi
  mkdir -p "$BIN_DIR"
  # Starship's installer downloads its archive via `mktemp` and never deletes it, so point
  # its TMPDIR at a private folder. cleanup() also removes it if anything fails or is interrupted.
  WORK_DIR="$(mktemp -d)"
  curl -fsSL https://starship.rs/install.sh | TMPDIR="$WORK_DIR" sh -s -- --yes --bin-dir "$BIN_DIR" >/dev/null \
    || die "Starship install failed"
  cleanup
  WORK_DIR=""
  info "installed to $BIN_DIR/starship"
}

# Move an existing ~/<target> (file or symlink) into this run's backup folder, keeping its
# path relative to $HOME so `cp -a ~/.dotfiles-backup/<ts>/. ~/` restores it.
backup_existing() {
  local target="$1" dest="$HOME/$1"
  [[ -e "$dest" || -L "$dest" ]] || return 0
  mkdir -p "$(dirname "$BACKUP_DIR/$target")"
  mv "$dest" "$BACKUP_DIR/$target"
  info "backed up ~/$target -> ~/.dotfiles-backup/$BACKUP_NAME/$target"
}

link_dotfiles() {
  step "Linking configs"
  local entry rel target src dest
  for entry in "${LINKS[@]}"; do
    read -r rel target <<<"$entry"
    src="$DOTFILES_DIR/$rel"
    dest="$HOME/$target"
    [[ -f "$src" ]] || die "missing $src"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      info "ok        ~/$target"
      continue
    fi
    mkdir -p "$(dirname "$dest")"
    backup_existing "$target"
    ln -s "$src" "$dest"
    info "linked    ~/$target"
  done
}

# ~/.zshrc and ~/.zprofile are small files of yours that load the repo's versions. They're not
# in git, so anything added to them (by you or by a tool installer) stays on this machine.
# A re-run keeps everything in them and only fixes the loader line if the repo moved.
write_loaders() {
  step "Loader files (not in git)"
  local entry rel target src dest ref line tmp
  for entry in "${LOADERS[@]}"; do
    read -r rel target <<<"$entry"
    src="$DOTFILES_DIR/$rel"
    dest="$HOME/$target"
    [[ -f "$src" ]] || die "missing $src"
    ref="$src"
    if [[ "$src" == "$HOME/"* ]]; then ref="\$HOME/${src#"$HOME"/}"; fi
    line="if [[ -r \"$ref\" ]]; then source \"$ref\"; else print -u2 \"zsh-configs: $ref not found\"; fi   $LOADER_MARK"
    if [[ -f "$dest" && ! -L "$dest" ]] && grep -qF "$LOADER_MARK" "$dest"; then
      if grep -qxF -- "$line" "$dest"; then
        info "ok        ~/$target"
      else
        tmp="$dest.zsh-configs.$$"
        NEW_LINE="$line" MARK="$LOADER_MARK" awk 'index($0, ENVIRON["MARK"]) { print ENVIRON["NEW_LINE"]; next } { print }' \
          "$dest" >"$tmp"
        mv "$tmp" "$dest"
        info "updated   ~/$target (repo path changed; the rest of the file is kept)"
      fi
      continue
    fi
    backup_existing "$target"
    {
      printf '# ~/%s: loads the shared config from zsh-configs (%s).\n' "$target" "$rel"
      printf '# This file is not in git: settings for this machine only go below the next line,\n'
      printf '# and tool installers that append to ~/%s stay here too.\n' "$target"
      printf '%s\n' "$line"
    } >"$dest"
    info "created   ~/$target (loads $rel)"
  done
}

# ~/.aliases and ~/.env belong to you; ~/.zshrc loads each one when present.
# ~/.aliases is created from the repo's starter only if it doesn't exist (copied, not linked),
# and is never edited or replaced after that. ~/.env is never created or touched.
# shellcheck disable=SC2088  # the "~/..." strings are for display, not paths
setup_private_files() {
  step "Your aliases and env"
  if [[ -e "$HOME/.aliases" || -L "$HOME/.aliases" ]]; then
    info "kept      ~/.aliases (already exists; never overwritten)"
  elif [[ -f "$DOTFILES_DIR/zsh/.aliases" ]]; then
    install -m 644 "$DOTFILES_DIR/zsh/.aliases" "$HOME/.aliases"
    info "created   ~/.aliases from the starter; edit it freely"
  else
    warn "no starter aliases in $DOTFILES_DIR (older copy of the repo?); skipped ~/.aliases"
  fi
  if [[ -f "$HOME/.env" ]]; then
    info "found     ~/.env"
  else
    info "not found ~/.env (optional: put secrets there as export NAME=value)"
  fi
  # -L: judge the real file, not a symlink's own (always 777) mode
  if [[ -f "$HOME/.env" ]] && [[ -n "$(find -L "$HOME/.env" -perm /077)" ]]; then
    warn "~/.env can be read by other users; run: chmod 600 ~/.env"
  fi
  if [[ -f "$HOME/.aliases" ]] && [[ -n "$(find -L "$HOME/.aliases" -perm /022)" ]]; then
    warn "~/.aliases can be changed by other users; run: chmod 644 ~/.aliases"
  fi
}

set_login_shell() {
  step "Login shell"
  if ((!DO_CHSH)); then info "skipped (--no-chsh)"; return; fi
  local zsh_path current
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then warn "zsh isn't installed; skipping"; return; fi
  current="$(getent passwd "$ME" | cut -d: -f7)"
  if [[ "$current" == "$zsh_path" ]]; then info "already $zsh_path"; return; fi
  grep -qx "$zsh_path" /etc/shells 2>/dev/null || warn "$zsh_path isn't listed in /etc/shells"
  if as_root chsh -s "$zsh_path" "$ME" </dev/null || chsh -s "$zsh_path"; then
    info "changed $current -> $zsh_path"
  else
    warn "couldn't change the login shell; run: chsh -s $zsh_path"
  fi
}

main() {
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  parse_args "$@"
  install_packages
  ensure_repo
  install_oh_my_zsh
  install_omz_addons
  install_starship
  link_dotfiles
  write_loaders
  setup_private_files
  set_login_shell
  printf '\n%sDone.%s Open a new terminal, or run: exec zsh\n' "$c_green" "$c_off"
  if [[ -d "$BACKUP_DIR" ]]; then info "Files it replaced are in ~/.dotfiles-backup/$BACKUP_NAME/"; fi
}

main "$@"
