#!/usr/bin/env bats

# End-to-end idempotency tests: run main() multiple times and verify
# the resulting state (symlinks, backups, local.rc) is stable.
#
# All package-install and shell-change operations are stubbed so the tests
# do not require sudo or any real package manager.

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export MAIL_MODE=direct

  # Isolated fake dotfiles dir inside TEST_HOME so main() never touches
  # the real repository files.
  FAKE_DOTFILES="$TEST_HOME/fake_dotfiles"
  mkdir -p \
    "$FAKE_DOTFILES/.neomutt" \
    "$FAKE_DOTFILES/.config/nvim" \
    "$FAKE_DOTFILES/.config/clangd" \
    "$FAKE_DOTFILES/.config/git" \
    "$FAKE_DOTFILES/bin"
  for f in .tmux.conf .vimrc .vimrc.plug .zshrc .neomuttrc .ripgreprc; do
    touch "$FAKE_DOTFILES/$f"
  done
  touch \
    "$FAKE_DOTFILES/.neomutt/macos.rc" \
    "$FAKE_DOTFILES/.neomutt/linux.rc" \
    "$FAKE_DOTFILES/.config/git/config" \
    "$FAKE_DOTFILES/.config/git/kernel.config" \
    "$FAKE_DOTFILES/.config/git/kernel-commit-template"

  # Source install functions without running main or set -e.
  local tmpfile
  export MAIL_PROVIDER_FILE="$DOTFILES_DIR/bin/mail-provider"
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$DOTFILES_DIR/install.sh" | grep -v '^main ' > "$tmpfile"
  # shellcheck disable=SC1090
  source "$tmpfile"
  rm -f "$tmpfile"

  # Point at the fake dotfiles dir.
  DOTFILES_DIR="$FAKE_DOTFILES"
  # BACKUP_DIR was set to $TEST_HOME/.dotfiles_backup_<ts> by the source — keep it.

  # Stub every operation that touches the real system.
  #
  # configure_patch_workflow is stubbed for the same reason as configure_git:
  # it writes global git config, and with XDG_CONFIG_HOME inherited from the
  # real environment that can land outside the faked HOME.
  install_via_brewfile()      { :; }
  install_via_packagefile()   { :; }
  install_ghostty()           { :; }
  configure_git()             { :; }
  configure_patch_workflow()  { :; }
  install_ohmyzsh()           { :; }
  set_default_shell()         { :; }
  install_vim_plugins()       { :; }
  install_nvim_plugins()      { :; }
}

teardown() {
  rm -rf "$TEST_HOME"
}

_install() {
  main --name "Test User" --email "test@example.com"
}

# ---------------------------------------------------------------------------

@test "first run creates expected symlinks in HOME" {
  _install

  [ -L "$TEST_HOME/.tmux.conf" ]
  [ -L "$TEST_HOME/.vimrc" ]
  [ -L "$TEST_HOME/.zshrc" ]
  [ -L "$TEST_HOME/.neomuttrc" ]
}

@test "second run creates no new backup directories" {
  _install
  local count_first
  count_first="$(find "$TEST_HOME" -maxdepth 1 -name '.dotfiles_backup*' -type d | wc -l)"

  _install
  local count_second
  count_second="$(find "$TEST_HOME" -maxdepth 1 -name '.dotfiles_backup*' -type d | wc -l)"

  [ "$count_first" -eq "$count_second" ]
}

@test "third run is also a no-op (no new backups)" {
  _install
  _install
  local count_after_second
  count_after_second="$(find "$TEST_HOME" -maxdepth 1 -name '.dotfiles_backup*' -type d | wc -l)"

  _install
  local count_after_third
  count_after_third="$(find "$TEST_HOME" -maxdepth 1 -name '.dotfiles_backup*' -type d | wc -l)"

  [ "$count_after_second" -eq "$count_after_third" ]
}

@test "second run leaves all symlink targets unchanged" {
  _install
  local links_first
  links_first="$(find "$TEST_HOME" -maxdepth 4 -type l \
    -not -path "$TEST_HOME/fake_dotfiles/*" | sort | \
    while IFS= read -r l; do readlink "$l"; done)"

  _install
  local links_second
  links_second="$(find "$TEST_HOME" -maxdepth 4 -type l \
    -not -path "$TEST_HOME/fake_dotfiles/*" | sort | \
    while IFS= read -r l; do readlink "$l"; done)"

  [ "$links_first" = "$links_second" ]
}

@test "local.rc is not rewritten on second run with the same identity" {
  _install
  # Capture output of the second run; the write-guard should fire.
  local second_out
  second_out="$(_install 2>&1)"
  [[ "$second_out" == *"already up to date"* ]]
}

@test "local.rc is updated when identity changes via flags" {
  _install
  main --name "New User" --email "new@example.com"

  local content
  content="$(cat "$TEST_HOME/.neomutt/local.rc")"
  [[ "$content" == *"New User"* ]]
  [[ "$content" == *"new@example.com"* ]]
}

@test "mail sync selects only Kernel and Kernel/Sent with stable local names" {
  _install

  local config="$TEST_HOME/.mbsyncrc"
  [ "$(grep -c '^Channel ' "$config")" -eq 2 ]
  [ "$(grep -c '^Far ' "$config")" -eq 2 ]
  grep -qxF 'Far ":fastmail-remote:Kernel"' "$config"
  grep -qxF 'Far ":fastmail-remote:Kernel/Sent"' "$config"
  grep -qxF 'Near :fastmail-local:INBOX' "$config"
  grep -qxF 'Near :fastmail-local:Sent' "$config"
  grep -qxF 'Group fastmail' "$config"
  grep -qxF 'Channels fastmail-inbox fastmail-sent' "$config"
  ! grep -q '^Patterns\? ' "$config"
  [ -d "$TEST_HOME/Mail/fastmail-kernel/Sent/cur" ]
  [ -d "$TEST_HOME/Mail/fastmail-kernel/Sent/new" ]
  [ -d "$TEST_HOME/Mail/fastmail-kernel/Sent/tmp" ]
}

@test "real mbsync maps only kernel mail and bootstraps the dedicated sent folder" {
  command -v mbsync >/dev/null || skip "isync is not installed"
  _install

  local remote="$TEST_HOME/remote"
  local folder
  for folder in INBOX Sent Kernel; do
    mkdir -p "$remote/$folder/cur" "$remote/$folder/new" "$remote/$folder/tmp"
    cat > "$remote/$folder/cur/fixture:2,S" <<EOF
From: test@example.com
To: test@example.com
Subject: fixture
Message-ID: <$folder@example.com>

Test fixture.
EOF
  done

  local config="$TEST_HOME/local-sync.conf"
  cat > "$config" <<EOF
MaildirStore fastmail-remote
Path $remote/
Inbox $remote/INBOX
Subfolders Verbatim

MaildirStore fastmail-local
Path $MAIL_DIR/
Inbox $MAIL_DIR/INBOX
Subfolders Verbatim

EOF
  sed -n '/^Channel /,$p' "$TEST_HOME/.mbsyncrc" >> "$config"

  run mbsync -c "$config" fastmail
  [ "$status" -eq 0 ]
  [ -d "$remote/Kernel/Sent/cur" ]
  [ "$(find "$MAIL_DIR/INBOX/cur" -type f | wc -l)" -eq 1 ]
  [ "$(find "$MAIL_DIR/Sent/cur" -type f | wc -l)" -eq 0 ]
  [ -f "$remote/INBOX/cur/fixture:2,S" ]
  [ -f "$remote/Sent/cur/fixture:2,S" ]
  [ ! -e "$MAIL_DIR/Kernel" ]

  cat > "$MAIL_DIR/Sent/cur/outgoing:2,S" <<'EOF'
From: test@example.com
To: list@example.com
Subject: sent fixture
Message-ID: <outgoing@example.com>

Test fixture.
EOF
  run mbsync -c "$config" fastmail
  [ "$status" -eq 0 ]
  [ "$(find "$remote/Kernel/Sent/cur" -type f | wc -l)" -eq 1 ]
  [ "$(find "$remote/Sent/cur" -type f | wc -l)" -eq 1 ]
}

@test "mail paths and notmuch index are isolated from old whole-account mail" {
  mkdir -p "$TEST_HOME/Mail/fastmail/INBOX/cur"
  echo 'old personal mail' > "$TEST_HOME/Mail/fastmail/INBOX/cur/personal"
  _install

  grep -qxF "Path $TEST_HOME/Mail/fastmail-kernel/" "$TEST_HOME/.mbsyncrc"
  grep -qxF "path=$TEST_HOME/Mail/fastmail-kernel" "$TEST_HOME/.notmuch-config"
  grep -qxF "set my_maildir = \"$TEST_HOME/Mail/fastmail-kernel\"" "$TEST_HOME/.neomutt/local.rc"
  grep -qxF "set nm_default_url = \"notmuch://$TEST_HOME/Mail/fastmail-kernel\"" "$TEST_HOME/.neomutt/local.rc"
  [ "$(cat "$TEST_HOME/Mail/fastmail/INBOX/cur/personal")" = "old personal mail" ]
}

@test "reinstall migrates legacy local.rc paths even with the same identity" {
  mkdir -p "$TEST_HOME/.neomutt"
  cat > "$TEST_HOME/.neomutt/local.rc" <<EOF
set imap_user = "test@example.com"
set real_name = "Test User"
set my_maildir = "$TEST_HOME/Mail/fastmail"
set nm_default_url = "notmuch://$TEST_HOME/Mail/fastmail"
EOF

  _install

  grep -qxF "set nm_default_url = \"notmuch://$TEST_HOME/Mail/fastmail-kernel\"" "$TEST_HOME/.neomutt/local.rc"
  local second_out
  second_out="$(_install 2>&1)"
  [[ "$second_out" == *"already up to date"* ]]
}

@test "folder overrides stay exact mappings, including spaces" {
  MAIL_FOLDER="Kernel Work"
  MAIL_SENT_FOLDER="Kernel Work/Sent Patches"
  _install

  grep -qxF 'Far ":fastmail-remote:Kernel Work"' "$TEST_HOME/.mbsyncrc"
  grep -qxF 'Far ":fastmail-remote:Kernel Work/Sent Patches"' "$TEST_HOME/.mbsyncrc"
  ! grep -q '^Patterns\? ' "$TEST_HOME/.mbsyncrc"
}

@test "reinstall updates local.rc when a custom mail path changes" {
  _install
  MAIL_DIR="$TEST_HOME/Mail/custom-kernel"
  _install

  grep -qxF "set my_maildir = \"$MAIL_DIR\"" "$TEST_HOME/.neomutt/local.rc"
  grep -qxF "set nm_default_url = \"notmuch://$MAIL_DIR\"" "$TEST_HOME/.neomutt/local.rc"
  grep -qxF "path=$MAIL_DIR" "$TEST_HOME/.notmuch-config"
}

@test "signature is created from the installed name as a real file" {
  _install

  [ "$(cat "$TEST_HOME/.signature")" = "Test User" ]
  [ -f "$TEST_HOME/.signature" ]
  [ ! -L "$TEST_HOME/.signature" ]
}

@test "an edited signature survives a reinstall" {
  _install
  printf 'Test User\nhttps://example.com\n' > "$TEST_HOME/.signature"

  main --name "New User" --email "new@example.com"

  # Prose, not generated config: the new identity must not clobber the edits.
  [ "$(cat "$TEST_HOME/.signature")" = "$(printf 'Test User\nhttps://example.com')" ]
}

@test "an empty signature file is filled in rather than left blank" {
  : > "$TEST_HOME/.signature"

  _install

  [ "$(cat "$TEST_HOME/.signature")" = "Test User" ]
}

@test "generated files are real files, not symlinks into the repo" {
  _install

  for f in .zshrc.local .neomutt/local.rc .mbsyncrc .notmuch-config .signature; do
    [ -f "$TEST_HOME/$f" ]
    [ ! -L "$TEST_HOME/$f" ]
    [ ! -e "$FAKE_DOTFILES/$f" ]
  done
}

@test "a leftover repo symlink is migrated to a real file keeping its content" {
  mkdir -p "$FAKE_DOTFILES/.neomutt"
  printf 'hand written\n' > "$FAKE_DOTFILES/.signature"
  ln -s "$FAKE_DOTFILES/.signature" "$TEST_HOME/.signature"
  printf 'export FOO=1\n' > "$FAKE_DOTFILES/.zshrc.local"
  ln -s "$FAKE_DOTFILES/.zshrc.local" "$TEST_HOME/.zshrc.local"

  _install

  [ ! -L "$TEST_HOME/.signature" ]
  [ "$(cat "$TEST_HOME/.signature")" = "hand written" ]
  [ ! -L "$TEST_HOME/.zshrc.local" ]
  [ "$(cat "$TEST_HOME/.zshrc.local")" = "export FOO=1" ]
}

@test "a dangling repo symlink is replaced rather than written through" {
  ln -s "$FAKE_DOTFILES/.mbsyncrc" "$TEST_HOME/.mbsyncrc"

  _install

  [ ! -L "$TEST_HOME/.mbsyncrc" ]
  [ ! -e "$FAKE_DOTFILES/.mbsyncrc" ]
  grep -q '^IMAPAccount' "$TEST_HOME/.mbsyncrc"
}

@test "install continues and creates symlinks even when a tool install fails" {
  install_via_packagefile() { return 1; }

  _install

  # Symlinks for other files should still be created
  [ -L "$TEST_HOME/.vimrc" ]
  [ -L "$TEST_HOME/.zshrc" ]
  [ -L "$TEST_HOME/.neomuttrc" ]
}

@test "pre-existing file is backed up on first run then left alone on second" {
  echo "my old tmux config" > "$TEST_HOME/.tmux.conf"

  _install
  # Original file should now be a symlink (backed up, replaced)
  [ -L "$TEST_HOME/.tmux.conf" ]
  local count_after_first
  count_after_first="$(find "$TEST_HOME" -maxdepth 1 -name '.dotfiles_backup*' -type d | wc -l)"

  _install
  # Second run: symlink already correct, no new backup
  local count_after_second
  count_after_second="$(find "$TEST_HOME" -maxdepth 1 -name '.dotfiles_backup*' -type d | wc -l)"

  [ "$count_after_first" -eq "$count_after_second" ]
}
