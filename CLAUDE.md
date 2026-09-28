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

# Lint shell scripts (same set CI lints)
shellcheck install.sh uninstall.sh bin/mail-pass bin/gpg-setup

# Install dotfiles (requires --name and --email)
./install.sh --name "Your Name" --email "you@example.com"

# Uninstall (skip interactive package removal prompt)
./uninstall.sh --skip-packages
```

## Architecture

### Install / uninstall flow

`install.sh` maintains two arrays near the top:

- **`FILES`** — committed files to symlink (`.tmux.conf`, `.vimrc`, `.zshrc`, `.slconfig`, `.ripgreprc`, neomutt platform rcs, `.gnupg/gpg.conf`)
- **`DIRS`** — directories to symlink as a whole (`.config/nvim`, `.config/clangd`, `bin`)
- **`GENERATED`** — absolute `$HOME` paths of the machine-specific files `main()` writes as **real files, never symlinks**: `.zshrc.local`, `.neomutt/local.rc`, `.mbsyncrc`, `.notmuch-config`, `.signature`, `.gnupg/gpg-agent.conf`

The `GENERATED` split exists because these files are gitignored: keeping them in the repo and symlinking meant the repo never actually carried them, while hiding them from anything that backs up `$HOME` (dotsync2 on a devserver stores the symlink, not its target, so a rebuilt host got dangling links). `materialize_local_file()` converts a leftover symlink into a real file on upgrade — without it every `>` redirect in the generation block would write through the link into `$DOTFILES_DIR`.

`main()` resolves identity (`--name`/`--email` flags → existing `.neomutt/local.rc` → interactive prompt), installs packages for the detected platform (Homebrew on macOS, apt/dnf/pacman on Linux), configures git and sapling identity, sets up oh-my-zsh, loops through `FILES`/`DIRS` calling `backup_and_link()`, then installs vim/nvim plugins.

`uninstall.sh` has a flat `TARGETS` array of absolute `$HOME/...` paths. Its loop only removes symlinks that point into `$DOTFILES_DIR` — regular files and foreign symlinks are left untouched with a warning. Its own `GENERATED` array mirrors install's: those paths are reported and never deleted when they are real files, since `.zshrc.local` and `.signature` are meant to be hand-edited. A `GENERATED` path that is still a repo symlink (pre-migration install) does get removed.

**When adding a new committed dotfile**: add it to `FILES` in `install.sh`, add the corresponding `$HOME/...` path to `TARGETS` in `uninstall.sh`, add `touch "$FAKE_DOTFILES/<file>"` to the setup blocks in `tests/idempotency.bats` and `tests/uninstall_idempotency.bats`, and add `test -L "$HOME/<file>"` to the three full-install e2e Dockerfiles (`ubuntu`, `fedora`, `arch`) and the macOS e2e step in `.github/workflows/test.yml`. `ubuntu-bridge-e2e` asserts only the bridge-specific output, so it needs nothing.

**When adding a new generated file**: add the `$HOME/...` path to `GENERATED` in both `install.sh` and `uninstall.sh`, write it in `main()` with a plain `>` redirect, add it to the `.gitignore` list, and add it to the loop in the "generated files are real files" e2e assertion. Do **not** add it to `FILES` — the loop would warn `Source file not found`.

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

`.github/workflows/test.yml` runs 9 jobs on every push:

- **Shellcheck** — lints `install.sh`, `uninstall.sh`, `bin/mail-pass`, `bin/gpg-setup`
- **Ubuntu / Fedora** — BATS unit tests inside Docker
- **macOS** — BATS unit tests on `macos-latest`
- **E2E Ubuntu / Fedora / Arch** — full `install.sh` run inside Docker, then verifies packages and symlinks
- **E2E Ubuntu bridge** — `install.sh` with `MAIL_MODE=bridge` against an unreachable proxy, asserting the generated stunnel conf, systemd unit, `.mbsyncrc` and `.msmtprc`
- **E2E macOS** — full `install.sh` run on `macos-latest`, verifies packages, symlinks, and nvim plugin directory, then exercises the launchd branch of `configure_mail_bridge`

### Package lists

`packages/apt.txt`, `packages/dnf.txt`, `packages/pacman.txt` — one package per line; blank lines and `#` comments are skipped. `install_via_packagefile()` auto-detects which file to use based on the available package manager.

### Identity & machine-specific config

`resolve_identity()` collects name/email (reading `$HOME/.neomutt/local.rc`, which works whether it is already a real file or still a repo symlink); `main()` then generates three machine-specific files from that identity directly in `$HOME`:

- `.neomutt/local.rc` — `imap_user`/`from`/`real_name`/`smtp_url`/`nm_default_url` (sourced by the platform rc; its write-guard requires all three of `real_name`, `imap_user`, `nm_default_url` to be present before skipping the rewrite).
- `.mbsyncrc` — mbsync IMAP→maildir config; password via `PassCmd "$HOME/bin/mail-pass"`.
- `.notmuch-config` — notmuch database path + identity.
- `.signature` — mail signature, just `$USER_NAME`. Unlike the three above it is written **only when missing or empty**, never regenerated: it is prose meant to be hand-edited. `.neomuttrc` points `$signature` at it and sets `sig_dashes`, so the `-- ` delimiter is not stored in the file.

`configure_git()` and `configure_sapling()` set `user.name`/`user.email` globally; both are idempotent (skip if already matching).

`~/.zshrc.local` is created empty if missing and sourced by `.zshrc` for machine-specific shell config.

### Mail architecture

Mail is **local**: `mbsync` (isync) pulls the configured provider into `$MAIL_DIR` (`~/Mail/<provider>`), `notmuch` indexes it for cross-folder threading, and neomutt reads the notmuch database (`virtual-mailboxes`). No live IMAP, no GPG in the mail path. The provider is defined in `bin/mail-provider` (defaults to Fastmail; override any value in `~/.config/dotfiles/mail.conf`, gitignored), and every other name — maildir, secret-store key, bridge unit — derives from it. The app password lives in the OS secret store and is read by `bin/mail-pass`, used by both mbsync and neomutt SMTP: macOS Keychain (`security`), or on Linux the first of `secret-tool` (libsecret), `systemd-creds` (host-key encrypted, the only option that survives a reboot) or `keyctl` (kernel keyring, lost on reboot) that returns a non-empty secret. (`pass` was dropped: it drags gpg-agent and a passphrase prompt into the mail path.) Store or rotate the secret with `mail-pass --store`, check it with `mail-pass --check`. `bin/mail-sync` runs `mbsync -a && notmuch new`; `bin/mutt` runs it before launching neomutt. `bin/mail-timer` installs a periodic-sync timer for the current OS (launchd LaunchAgent on macOS, systemd `--user` timer on Linux); run it once per machine.

### Patch signing & GnuPG

Kernel patches are sent with `git send-email`/`b4` through the provider's SMTP, and signed
with whichever OpenPGP secret key this machine holds for the configured identity —
`signing_key_fingerprint` resolves it at install time. Identity comes from `--name`/`--email`,
not from a committed file, and no key material or fingerprint is recorded in this repo.
Check what this machine resolved with `gpg-setup --check`.

`configure_patch_workflow()` in `install.sh` sets `sendemail.*`, installs a
**URL-scoped** credential helper (`credential.smtp://$MAIL_SMTP_HOST:$MAIL_SMTP_PORT.helper`)
that shells out to `bin/mail-pass`, and then calls `configure_patch_signing()`.
Scoped rather than global so the machine's normal helper still serves GitHub.
The helper has two values — an empty one first to reset anything inherited from a
broader scope, then the real one. `sendemail.smtppass` must stay **unset**: b4 only
falls back to `git credential fill` when it is empty.

**Signing is gated on the secret key being present locally.** `signing_key_fingerprint()`
looks for a secret key matching the identity; if there is none, no signing config is
written at all. That single condition is what makes `install.sh` safe to run in a
container or on a devserver, and the e2e Dockerfiles assert the negative case. An
explicitly set `user.signingKey` or `patatt.signingkey` is never clobbered.
`commit.gpgsign` is deliberately left alone — signing mailing-list patches is a
different decision from signing every commit on the machine.

Two config files land in `~/.gnupg`, and the directory is forced to mode 700:

- `.gnupg/gpg.conf` — committed, symlinked from the repo, identical everywhere.
- `.gnupg/gpg-agent.conf` — generated per machine as a real file, because the
  pinentry path is the one genuinely OS-specific piece: `pinentry-mac` on macOS, a
  graphical pinentry on a Linux desktop, `pinentry-curses` headless. `.zshrc` exports
  `GPG_TTY`, without which the curses prompt fails instead of prompting.

`bin/gpg-setup` covers what the installer cannot derive: `--check` (status of key,
agent, pinentry and publication), `--publish`, `--export`/`--import` for moving the
secret key between machines as an encrypted transfer file, `--enable-signing`, and
`--test`. `--publish` uses the keys.openpgp.org VKS **HTTPS** API rather than
`gpg --send-keys`, because the hkp/hkps transport is blocked on the corporate
network — it fails with "Invalid argument" while plain HTTPS to the same host works.
