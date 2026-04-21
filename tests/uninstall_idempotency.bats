#!/usr/bin/env bats

# End-to-end idempotency tests for uninstall.sh.
# Each test installs first (via main() from install.sh) to create real
# symlinks, then exercises uninstall.sh's main() with system operations
# stubbed and --skip-packages to avoid the interactive prompt.

REAL_DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  FAKE_DOTFILES="$TEST_HOME/fake_dotfiles"
  mkdir -p \
    "$FAKE_DOTFILES/.neomutt" \
    "$FAKE_DOTFILES/.config/nvim" \
    "$FAKE_DOTFILES/.claude/skills"
  for f in .tmux.conf .vimrc .vimrc.plug .zshrc .neomuttrc .zshrc.local .slconfig; do
    touch "$FAKE_DOTFILES/$f"
  done
  touch \
    "$FAKE_DOTFILES/.neomutt/macos.rc" \
    "$FAKE_DOTFILES/.neomutt/linux.rc" \
    "$FAKE_DOTFILES/.claude/settings.local.json"

  # --- Source install.sh and run it to lay down symlinks ---
  local tmpfile
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$REAL_DOTFILES_DIR/install.sh" | grep -v '^main ' | grep -v '^# Run main' > "$tmpfile"
  # shellcheck disable=SC1090
  source "$tmpfile"
  rm -f "$tmpfile"

  DOTFILES_DIR="$FAKE_DOTFILES"

  install_via_brewfile()    { :; }
  install_via_packagefile() { :; }
  install_ghostty()         { :; }
  install_sapling()         { :; }
  configure_git()           { :; }
  configure_sapling()       { :; }
  install_ohmyzsh()         { :; }
  set_default_shell()       { :; }
  install_vim_plugins()     { :; }
  install_nvim_plugins()    { :; }

  main --name "Test User" --email "test@example.com" >/dev/null

  # --- Source uninstall.sh (overwrites shared helpers like info/warn) ---
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$REAL_DOTFILES_DIR/uninstall.sh" | grep -v '^main ' > "$tmpfile"
  # shellcheck disable=SC1090
  source "$tmpfile"
  rm -f "$tmpfile"

  DOTFILES_DIR="$FAKE_DOTFILES"

  uninstall_via_packagefile() { :; }
  uninstall_ghostty()         { :; }
  uninstall_ohmyzsh()         { :; }
  restore_default_shell()     { :; }
}

teardown() {
  rm -rf "$TEST_HOME"
}

_uninstall() {
  main --skip-packages
}

# ---------------------------------------------------------------------------

@test "uninstall removes dotfile symlinks from HOME" {
  _uninstall

  [ ! -e "$TEST_HOME/.tmux.conf" ]
  [ ! -e "$TEST_HOME/.vimrc" ]
  [ ! -e "$TEST_HOME/.vimrc.plug" ]
  [ ! -e "$TEST_HOME/.zshrc" ]
  [ ! -e "$TEST_HOME/.neomuttrc" ]
  [ ! -e "$TEST_HOME/.slconfig" ]
  [ ! -e "$TEST_HOME/.neomutt/macos.rc" ]
  [ ! -e "$TEST_HOME/.neomutt/linux.rc" ]
}

@test "uninstall removes the .config/nvim and .claude/skills symlinks" {
  _uninstall
  [ ! -e "$TEST_HOME/.config/nvim" ]
  [ ! -e "$TEST_HOME/.claude/skills" ]
}

@test "second uninstall exits cleanly" {
  main --skip-packages >/dev/null
  # If this exits non-zero BATS will fail the test
  main --skip-packages >/dev/null
}

@test "second uninstall warns about missing targets rather than erroring" {
  main --skip-packages >/dev/null
  local output
  output="$(main --skip-packages 2>&1)"
  [[ "$output" == *"does not exist"* ]]
}

@test "uninstall leaves a symlink pointing outside DOTFILES_DIR untouched" {
  # Plant a foreign symlink at one of the TARGETS paths
  local foreign
  foreign="$(mktemp)"
  ln -sf "$foreign" "$TEST_HOME/.vimrc"

  _uninstall

  # The foreign symlink should still be there
  [ -L "$TEST_HOME/.vimrc" ]
  rm -f "$foreign"
}

@test "uninstall leaves regular files (not symlinks) untouched" {
  # Replace the installed symlink with a real file
  rm "$TEST_HOME/.tmux.conf"
  echo "hand-crafted config" > "$TEST_HOME/.tmux.conf"

  _uninstall

  [ -f "$TEST_HOME/.tmux.conf" ]
  [ "$(cat "$TEST_HOME/.tmux.conf")" = "hand-crafted config" ]
}

@test "full round-trip: install → uninstall → reinstall leaves symlinks intact" {
  # uninstall (install already ran in setup)
  main --skip-packages >/dev/null

  # reinstall — source install functions again
  local tmpfile
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$REAL_DOTFILES_DIR/install.sh" | grep -v '^main ' | grep -v '^# Run main' > "$tmpfile"
  # shellcheck disable=SC1090
  source "$tmpfile"
  rm -f "$tmpfile"

  DOTFILES_DIR="$FAKE_DOTFILES"
  install_via_brewfile()    { :; }
  install_via_packagefile() { :; }
  install_ghostty()         { :; }
  install_sapling()         { :; }
  configure_git()           { :; }
  configure_sapling()       { :; }
  install_ohmyzsh()         { :; }
  set_default_shell()       { :; }
  install_vim_plugins()     { :; }
  install_nvim_plugins()    { :; }

  main --name "Test User" --email "test@example.com" >/dev/null

  [ -L "$TEST_HOME/.tmux.conf" ]
  [ -L "$TEST_HOME/.vimrc" ]
  [ -L "$TEST_HOME/.zshrc" ]
  [ "$(readlink "$TEST_HOME/.tmux.conf")" = "$FAKE_DOTFILES/.tmux.conf" ]
}
