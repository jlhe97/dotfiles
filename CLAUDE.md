# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests
bats tests/

# Run a single test file
bats tests/install.bats

# Run a single test by name
bats tests/install.bats --filter "backup_and_link creates symlink"

# Lint shell scripts
shellcheck install.sh uninstall.sh

# Install dotfiles (requires --name and --email)
./install.sh --name "Your Name" --email "you@example.com"

# Uninstall (skip interactive package removal prompt)
./uninstall.sh --skip-packages
```

## Architecture

### Install / uninstall flow

`install.sh` maintains two arrays near the top:

- **`FILES`** — individual files to symlink (`.tmux.conf`, `.vimrc`, `.zshrc`, `.slconfig`, neomutt configs, claude settings, etc.)
- **`DIRS`** — directories to symlink as a whole (`.config/nvim`, `.claude/skills`)

`main()` resolves identity (`--name`/`--email` flags → existing `.neomutt/local.rc` → interactive prompt), installs packages for the detected platform (Homebrew on macOS, apt/dnf/pacman on Linux), configures git and sapling identity, sets up oh-my-zsh, loops through `FILES`/`DIRS` calling `backup_and_link()`, then installs vim/nvim plugins.

`uninstall.sh` has a flat `TARGETS` array of absolute `$HOME/...` paths. Its loop only removes symlinks that point into `$DOTFILES_DIR` — regular files and foreign symlinks are left untouched with a warning.

**When adding a new dotfile**: add it to `FILES` in `install.sh`, add the corresponding `$HOME/...` path to `TARGETS` in `uninstall.sh`, add `touch "$FAKE_DOTFILES/<file>"` to the setup blocks in `tests/idempotency.bats` and `tests/uninstall_idempotency.bats`, and add `test -L "$HOME/<file>"` to all four e2e Dockerfiles and the macOS e2e step in `.github/workflows/test.yml`.

### `backup_and_link(src, dest)`

The core idempotency primitive:
- Already correct symlink → no-op
- Dangling or wrong symlink → replace without backup
- Real file or directory → move to `$BACKUP_DIR` (`.dotfiles_backup_YYYYMMDD_HHMMSS/`), then link
- Missing → create symlink

### Tests

Four BATS files under `tests/`:

| File | What it covers |
|------|---------------|
| `install.bats` | Unit tests for every helper function in `install.sh` |
| `uninstall.bats` | Unit tests for every helper function in `uninstall.sh` |
| `idempotency.bats` | End-to-end: runs `main()` 2–3× with all system ops stubbed, verifies no extra backups, stable symlinks, local.rc write-guard |
| `uninstall_idempotency.bats` | End-to-end: install → uninstall → reinstall round-trip, foreign symlink/real file safety |

**Sourcing trick** used by all test files: `set -e` and the `main` invocation are stripped from the script before sourcing so individual functions can be tested in isolation:

```bash
grep -v '^set -e' "$DOTFILES_DIR/install.sh" | grep -v '^main ' > "$tmpfile"
source "$tmpfile"
```

System operations that touch the real host (package managers, chsh, oh-my-zsh download) are replaced with no-op stubs in the idempotency tests. Unit tests use mock binaries placed in `$MOCK_BIN` with `PATH` manipulation.

### CI

`.github/workflows/test.yml` runs 8 jobs on every push:

- **Shellcheck** — lints `install.sh` and `uninstall.sh`
- **Ubuntu / Fedora** — BATS unit tests inside Docker
- **macOS** — BATS unit tests on `macos-latest`
- **E2E Ubuntu / Fedora / Arch** — full `install.sh` run inside Docker, then verifies packages and symlinks
- **E2E macOS** — full `install.sh` run on `macos-latest`, verifies packages, symlinks, and nvim plugin directory

### Package lists

`packages/apt.txt`, `packages/dnf.txt`, `packages/pacman.txt` — one package per line; blank lines and `#` comments are skipped. `install_via_packagefile()` auto-detects which file to use based on the available package manager.

### Identity & machine-specific config

`resolve_identity()` writes `$DOTFILES_DIR/.neomutt/local.rc` with IMAP/SMTP/GPG settings. The file is gitignored (machine-specific). `configure_git()` and `configure_sapling()` set `user.name`/`user.email` globally; both are idempotent (skip if already matching).

`.zshrc.local` is also gitignored and sourced by `.zshrc` for machine-specific shell config.
