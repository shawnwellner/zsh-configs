# zsh-configs: shared login-shell setup. ~/.zprofile is a small file the installer creates
# (not in git) that loads this one.
# Read ~/.profile the way bash does, so PATH and exports set there (e.g. ~/.local/bin,
# tool env vars) carry over to zsh.
[[ -f ~/.profile ]] && emulate sh -c '. ~/.profile'
