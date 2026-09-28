# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Commands

```bash
bats tests/                                          # all tests
bats tests/install.bats                              # one file
bats tests/install.bats --filter "backup_and_link"   # one test
shellcheck install.sh uninstall.sh bin/mail-pass bin/gpg-setup   # same set CI lints

./install.sh --name "Your Name" --email "you@example.com"   # both flags required
./uninstall.sh --skip-packages
```

## Conventions

**Comments earn their place.** Only write one when the code below it is not
self-evident *and* getting it wrong matters: a platform quirk, an ordering
constraint, a deliberate non-obvious choice. Never restate what the next line
says. Keep them to one or two lines — the rationale belongs in the commit
message, not the source.

## Install / uninstall

`install.sh` has three arrays at the top:

| Array | Contents |
|---|---|
| `FILES` | committed files to symlink, paths relative to the repo |
| `DIRS` | directories symlinked whole: `.config/nvim`, `.config/clangd`, `bin` |
| `GENERATED` | absolute `$HOME` paths written as **real files, never symlinks** |

`GENERATED` holds `.zshrc.local`, `.neomutt/local.rc`, `.mbsyncrc`,
`.notmuch-config`, `.signature`, `.gnupg/gpg-agent.conf`. They are gitignored,
so symlinking them into the repo meant nothing carried them — and hid them from
anything backing up `$HOME` (dotsync2 stores a symlink, not its target, so a
rebuilt devserver got dangling links). `materialize_local_file()` converts a
leftover symlink to a real file on upgrade; without it every `>` in the
generation block would write through the link into `$DOTFILES_DIR`.

`main()`: resolve identity (`--name`/`--email` → existing `~/.neomutt/local.rc`
→ prompt) → packages (Brewfile on macOS, package list on Linux) → git/sapling
identity → gnupg → patch workflow → oh-my-zsh → generate the `GENERATED` files
→ `backup_and_link()` over `FILES`/`DIRS` → vim/nvim plugins.

`uninstall.sh` mirrors the split: `TARGETS` removes only symlinks pointing into
`$DOTFILES_DIR`; its `GENERATED` array is reported and never deleted when real
(`.zshrc.local` and `.signature` are hand-edited), but a leftover repo symlink
at those paths is removed.

**Adding a committed dotfile**: `FILES` in `install.sh`, `TARGETS` in
`uninstall.sh`, `touch "$FAKE_DOTFILES/<file>"` in both idempotency test setups,
`test -L "$HOME/<file>"` in the three e2e Dockerfiles and the macOS e2e step.

**Adding a generated file**: `GENERATED` in both scripts, write it with a plain
`>` in `main()`, add to `.gitignore`, add to the "generated files are real
files" e2e loop. Not in `FILES` — that loop warns `Source file not found`.

### `backup_and_link(src, dest)`

Correct symlink → no-op. Dangling or wrong symlink → replace, no backup. Real
file or dir → move to `$BACKUP_DIR` (`.dotfiles_backup_YYYYMMDD_HHMMSS/`), then
link. Missing → link.

## Tests

| File | Covers |
|---|---|
| `install.bats` | every helper in `install.sh` |
| `uninstall.bats` | every helper in `uninstall.sh` |
| `idempotency.bats` | `main()` 2–3× with system ops stubbed: no extra backups, stable symlinks, local.rc write-guard, symlink→real-file migration |
| `uninstall_idempotency.bats` | install → uninstall → reinstall, foreign-symlink and real-file safety |

All four source the script with `set -e` and the `main` call stripped, so
functions can be tested in isolation:

```bash
grep -v '^set -e' "$DOTFILES_DIR/install.sh" | grep -v '^main ' > "$tmpfile"
source "$tmpfile"
```

Idempotency tests stub anything touching the host (package managers, chsh,
oh-my-zsh). Unit tests use mock binaries in `$MOCK_BIN` with `PATH` ahead of it.

## CI

`.github/workflows/test.yml` — 5 job definitions, 9 runs after matrix
expansion: `shellcheck`; `test-linux` (Ubuntu, Fedora in Docker); `test-macos`;
`e2e` (Ubuntu, Fedora, Arch, Ubuntu bridge); `e2e-macos`. The bridge run uses
`MAIL_MODE=bridge` against an unreachable proxy and asserts the generated
stunnel conf, systemd unit, `.mbsyncrc` and `.msmtprc`.

Package lists are `packages/{apt,dnf,pacman}.txt`, one per line, `#` and blanks
skipped; `install_via_packagefile()` picks by available package manager.

## Identity

`resolve_identity()` reads `$HOME/.neomutt/local.rc` (works whether it is a real
file or a pre-migration symlink). `main()` then writes into `$HOME`:

- `.neomutt/local.rc` — `imap_user`/`from`/`real_name`/`smtp_url`/`nm_default_url`.
  Its write-guard needs all of `real_name`, `imap_user`, `nm_default_url` present
  before it skips a rewrite.
- `.mbsyncrc` — IMAP→maildir; password via `PassCmd "$HOME/bin/mail-pass"`.
- `.notmuch-config` — database path + identity.
- `.signature` — written **only when missing or empty**, never regenerated: it
  is prose meant to be hand-edited. `.neomuttrc` sets `sig_dashes`, so the
  `-- ` delimiter is not stored in the file.

`configure_git()` / `configure_sapling()` set `user.name`/`user.email` globally,
both idempotent. `~/.zshrc.local` is created empty if missing.

## Mail

Local only: `mbsync` pulls into `$MAIL_DIR` (`~/Mail/<provider>`), `notmuch`
indexes for cross-folder threading, neomutt reads the notmuch database via
`virtual-mailboxes`. No live IMAP, no GPG in the mail path.

`bin/mail-provider` is the single source of truth (Fastmail by default;
override in `~/.config/dotfiles/mail.conf`). Maildir, secret-store key and
bridge unit names all derive from it.

The app password lives in the OS secret store, read only by `bin/mail-pass`:

| Platform | Store |
|---|---|
| macOS | Keychain (`security`) |
| Linux | first non-empty of `secret-tool` (libsecret), `systemd-creds` (host-key encrypted — the only one surviving a reboot), `keyctl` (kernel keyring, lost on reboot) |

`pass` was dropped: it drags gpg-agent and a passphrase prompt into the mail
path. `mail-pass --store` / `--check`. `bin/mail-sync` = `mbsync -a && notmuch
new`; `bin/mutt` syncs, opens neomutt, syncs again. `bin/mail-timer` installs a
periodic-sync timer (launchd or systemd `--user`), once per machine.

When the provider is unreachable directly, `install.sh` detects it and writes
an stunnel bridge on loopback plus `~/.msmtprc`. Those land in
`~/.config/systemd/user/` and are **not** covered by `uninstall.sh`'s arrays —
`remove_mail_services()` handles them.

## Patch signing

Patches go out via `git send-email`/`b4` through the provider's SMTP, signed
with whichever OpenPGP key this machine holds for the configured identity.
Identity comes from `--name`/`--email`; no key material or fingerprint is in
this repo. `gpg-setup --check` shows what a machine resolved.

`configure_patch_workflow()` sets `sendemail.*` and a **URL-scoped** credential
helper (`credential.smtp://$MAIL_SMTP_HOST:$MAIL_SMTP_PORT.helper`) shelling out
to `bin/mail-pass` — scoped, not global, so the machine's normal helper still
serves GitHub. It has two values: an empty one to reset anything inherited from
a broader scope, then the real one. `sendemail.smtppass` must stay **unset**;
b4 only falls back to `git credential fill` when it is empty.

**Signing is gated on the key being present locally.** `signing_key_fingerprint()`
finds nothing → no signing config at all. That single condition is what makes
`install.sh` safe in a container or on a fresh devserver, and the e2e
Dockerfiles assert the negative case. An explicit `user.signingKey` or
`patatt.signingkey` is never clobbered. `commit.gpgsign` is left alone: signing
list patches is a different decision from signing every commit on the machine.

`~/.gnupg` is forced to 700 and holds two config files:

- `gpg.conf` — committed, symlinked, identical everywhere.
- `gpg-agent.conf` — generated per machine as a real file, because the pinentry
  path is the one genuinely OS-specific piece (`pinentry-mac`, a graphical
  pinentry, or `pinentry-curses` headless). `.zshrc` exports `GPG_TTY`, without
  which the curses prompt fails instead of prompting.

`bin/gpg-setup` covers what the installer cannot derive: `--check`, `--publish`,
`--export`/`--import` (encrypted transfer file), `--enable-signing`, `--test`.
`--publish` uses the keys.openpgp.org VKS **HTTPS** API rather than
`gpg --send-keys`, because hkp/hkps is blocked on the corporate network — it
fails with "Invalid argument" while plain HTTPS to the same host works.
