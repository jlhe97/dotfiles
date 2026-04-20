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

  # Isolated fake dotfiles dir inside TEST_HOME so main() never touches
  # the real repository files.
  FAKE_DOTFILES="$TEST_HOME/fake_dotfiles"
  mkdir -p \
    "$FAKE_DOTFILES/.neomutt" \
    "$FAKE_DOTFILES/.config/nvim" \
    "$FAKE_DOTFILES/.claude/skills"
  for f in .tmux.conf .vimrc .vimrc.plug .zshrc .neomuttrc .zshrc.local; do
    touch "$FAKE_DOTFILES/$f"
  done
  touch \
    "$FAKE_DOTFILES/.neomutt/macos.rc" \
    "$FAKE_DOTFILES/.neomutt/linux.rc" \
    "$FAKE_DOTFILES/.claude/settings.local.json"

  # Source install functions without running main or set -e.
  local tmpfile
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$DOTFILES_DIR/install.sh" | grep -v '^main ' | grep -v '^# Run main' > "$tmpfile"
  # shellcheck disable=SC1090
  source "$tmpfile"
  rm -f "$tmpfile"

  # Point at the fake dotfiles dir.
  DOTFILES_DIR="$FAKE_DOTFILES"
  # BACKUP_DIR was set to $TEST_HOME/.dotfiles_backup_<ts> by the source — keep it.

  # Stub every operation that touches the real system.
  install_via_brewfile()    { :; }
  install_via_packagefile() { :; }
  install_ghostty()         { :; }
  install_sapling()         { :; }
  configure_sapling()       { :; }
  install_ohmyzsh()         { :; }
  set_default_shell()       { :; }
  install_vim_plugins()     { :; }
  install_nvim_plugins()    { :; }
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
  content="$(cat "$FAKE_DOTFILES/.neomutt/local.rc")"
  [[ "$content" == *"New User"* ]]
  [[ "$content" == *"new@example.com"* ]]
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
