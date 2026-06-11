# dotfiles

Managed with [chezmoi](https://chezmoi.io). Provisions a new Mac in one command:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply srichards2103
```

## What happens on a fresh machine

1. chezmoi installs itself, clones this repo, and writes all dotfiles
   (zsh, tmux, nvim, hammerspoon, ghostty, git, codex, claude, wasteos tooling).
2. `run_once_before_00-install-homebrew` installs Homebrew if missing.
3. `run_onchange_after_10-brew-bundle` runs `brew bundle install --global`
   against `~/.Brewfile`: all CLI formulae, GUI apps (Docker Desktop, Ghostty,
   Cursor, browsers, Office, ...), npm globals, Cursor/VS Code extensions,
   and Xcode via `mas` (sign in to the App Store first for that one).
4. `run_once_after_20-cli-installers` installs claude, opencode, and
   cursor-agent via their official curl installers.

`brew bundle` uses `cask_args adopt: true`, so it is safe on a machine where
some apps were already installed manually.

## Manual steps (not automated)

- Sign in to the Mac App Store before/after first apply (needed for Xcode via mas).
- Copy `~/.config/wasteos/shipfeat.env` from another machine — it contains
  credentials and is deliberately NOT in this repo.
- `~/.codex/auth.json`, ssh keys, and other credentials: not in this repo;
  log in to each tool once (claude, codex, gh auth login, glab auth login).
- No Homebrew cask exists for: Cluely, Cisco AnyConnect, Microsoft Defender.
