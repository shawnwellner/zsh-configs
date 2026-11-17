# zsh-configs

A zsh setup: Oh My Zsh, four community plugins, and a Kali-style [Starship](https://starship.rs)
prompt. Works on Ubuntu/Debian (apt) and Arch-based systems (pacman), including WSL.

It also turns on some of Oh My Zsh's built-in plugins, which need no install:

- `git` and `docker`: completions and shortcuts (`docker` stays idle where Docker isn't installed)
- `sudo`: press Esc twice to put `sudo` in front of the current or last command
- `extract`: `extract <archive>` (or `x`) unpacks any archive type
- `z`: `z <part of a path>` jumps to a folder you've visited before

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/shawnwellner/zsh-configs/main/install.sh | bash
```

Pipe it to `bash`, not `sh`. This clones the repo to `~/.dotfiles` and then:

1. installs anything missing from `zsh git curl ca-certificates net-tools unzip`, using apt or pacman,
   whichever the machine has (asks for sudo). On Arch it never refreshes the package list on its
   own, because that can leave the system half-upgraded; if the list is stale, it asks you to run
   `sudo pacman -Syu` first
2. installs Oh My Zsh to `~/.oh-my-zsh`
3. installs or updates the plugins: zsh-autosuggestions, zsh-syntax-highlighting,
   zsh-completions, zsh-vi-mode
4. installs Starship to `~/.local/bin`
5. creates small `~/.zshrc` and `~/.zprofile` files that load the repo's versions, and symlinks
   `~/.config/starship.toml` (see [How it's wired](#how-its-wired)). Any existing files are moved to
   `~/.dotfiles-backup/<timestamp>/` at the same paths, e.g. `~/.dotfiles-backup/<timestamp>/.zshrc`
6. creates `~/.aliases` from a starter if you don't have one. An existing `~/.aliases` is never
   overwritten. It also warns if `~/.env` or `~/.aliases` has unsafe permissions (see [Your files](#your-files))
7. makes zsh your login shell

It's safe to run again. A re-run skips what's already in place, keeps anything you added to
`~/.zshrc` or `~/.zprofile`, and pulls plugin updates.

Options go after `bash -s --`, e.g. `curl -fsSL …/install.sh | bash -s -- --no-chsh`:

| Option          | Effect                                   |
|-----------------|------------------------------------------|
| `--no-packages` | skip the package step                    |
| `--no-chsh`     | leave the login shell alone              |
| `-h`, `--help`  | show the options                         |

`DOTFILES_DIR`, `DOTFILES_REPO` and `DOTFILES_BRANCH` override the clone location, URL and branch.
If `~/.dotfiles` already exists and isn't this repo, the installer stops before changing anything in your home folder.
Move that folder aside, or install somewhere else with `curl -fsSL …/install.sh | DOTFILES_DIR=$HOME/.zsh-configs bash`.
If the repo is private, the raw URL above won't work. Clone it over SSH and run it from the checkout:

```bash
git clone git@github.com:shawnwellner/zsh-configs.git ~/.dotfiles && ~/.dotfiles/install.sh
```

## How it's wired

| In your home folder       | What it is                                                         |
|---------------------------|--------------------------------------------------------------------|
| `~/.zshrc`                | a small loader for [`zsh/.zshrc`](zsh/.zshrc); not in git           |
| `~/.zprofile`             | a small loader for [`zsh/.zprofile`](zsh/.zprofile); not in git     |
| `~/.config/starship.toml` | a symlink to [`config/starship.toml`](config/starship.toml)        |
| `~/.aliases`              | a copy of [`zsh/.aliases`](zsh/.aliases), only if you had none      |

**Changes for every machine** go in the repo. Edit `~/.dotfiles/zsh/.zshrc` (or the other repo
files), commit and push. Then `git -C ~/.dotfiles pull` on the other machines and open a new shell.

**Changes for one machine** go in `~/.zshrc`, below the loader line. Tool installers that append
to `~/.zshrc` or `~/.zprofile` (nvm, conda and the like) land there too, so their lines never end
up in the repo.

`~/.zshrc` and `~/.zprofile` are loaders rather than symlinks for exactly that reason: with a
symlink, anything a tool appended would be written into the repo's own file.

## Your files

`~/.zshrc` loads two more files of yours, each only if it exists:

- **`~/.aliases`** holds your aliases. The first install creates it from
  [`zsh/.aliases`](zsh/.aliases), a small starter set, but only if you don't already have one.
  After that it's yours: the installer never edits or replaces it, and later changes to the
  starter don't reach it.
- **`~/.env`** holds secrets and tokens as `export NAME=value` lines. Keep it `chmod 600`.
  The installer never creates or touches it. Keep the real copy somewhere safe, such as a
  password manager or an encrypted backup.

The names have no `zsh` in them, and both use plain `sh` syntax, so bash can load the same files
on machines without zsh. Add this to `~/.bashrc`:

```bash
[ -f ~/.env ] && . ~/.env
[ -f ~/.aliases ] && . ~/.aliases
```

`.gitignore` blocks `.env` files anywhere in the repo folder, and a `.aliases` at the top, in case a
real one gets copied there by mistake.

Some tools search parent folders for a `.env` file. For example, `load_dotenv()` from Python's
python-dotenv does. A project under your home folder with no `.env` of its own can pick up `~/.env`.

## What it leaves on disk

| Path                              | What it is                                   | Safe to delete?                        |
|-----------------------------------|----------------------------------------------|----------------------------------------|
| `~/.dotfiles`                     | this repo                                    | No. The loaders and symlink point into it. |
| `~/.zshrc`, `~/.zprofile`         | the small loaders, plus anything you added   | Only to uninstall                      |
| `~/.oh-my-zsh`                    | Oh My Zsh, with plugins in `custom/plugins/` | Only to uninstall                      |
| `~/.local/bin/starship`           | the Starship binary                          | Only to uninstall                      |
| `~/.aliases`                      | the starter aliases, if you had none         | It's yours; edit or delete it          |
| `~/.dotfiles-backup/<timestamp>/` | files the installer replaced                 | Yes, once you don't need them          |

A backup folder only appears when the installer replaced something, and old ones are never pruned.
Packages it installed stay installed.

Nothing is left in `/tmp`. Starship's own installer leaves its download behind, so the script
gives it a private temp folder and deletes that folder on exit, including after an error or Ctrl-C.

## Uninstall

There's no uninstall script. First copy out anything you added below the loader line in
`~/.zshrc` or `~/.zprofile` that you want to keep. Then:

```bash
chsh -s /bin/bash                                     # 1. switch back to bash
rm ~/.zshrc ~/.zprofile ~/.config/starship.toml       # 2. remove the loaders and the symlink
cp -a ~/.dotfiles-backup/<timestamp>/. ~/             # 3. restore your old files, if there's a backup
rm -rf ~/.oh-my-zsh ~/.local/bin/starship ~/.dotfiles # 4. remove what was installed
```

For step 3, if there are several backup folders, the oldest one has your original files.

To remove the packages too: `sudo apt remove zsh net-tools unzip`, or on Arch
`sudo pacman -R zsh net-tools unzip`. Leave `git`, `curl` and `ca-certificates`, since other tools need them.
Skip `unzip` if anything else on the machine uses it.

None of this touches `~/.env`, `~/.aliases` or `~/.zsh_history`. If your `~/.aliases` is
still just the starter and you don't want it, delete it too.
