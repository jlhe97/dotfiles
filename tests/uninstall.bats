#!/usr/bin/env bats

# Tests for functions defined in uninstall.sh.
# Run with: bats tests/uninstall.bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Source uninstall.sh functions without triggering `set -e` or `main "$@"`.
  local tmpfile
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$DOTFILES_DIR/uninstall.sh" | grep -v '^main ' > "$tmpfile"
  # shellcheck disable=SC1090
  source "$tmpfile"
  rm -f "$tmpfile"

  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

@test "info prints [INFO] tag and the message" {
  run info "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "warn prints [WARN] tag and the message" {
  run warn "watch out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"watch out"* ]]
}

# ---------------------------------------------------------------------------
# --skip-packages flag
# ---------------------------------------------------------------------------

@test "--skip-packages skips the prompt and package uninstallation" {
  ln -s "$DOTFILES_DIR/.tmux.conf" "$TEST_HOME/.tmux.conf"

  run main --skip-packages

  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping package uninstallation"* ]]
}

@test "unknown option exits with error" {
  run main --bad-flag

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

# ---------------------------------------------------------------------------
# uninstall_ohmyzsh
# ---------------------------------------------------------------------------

@test "uninstall_ohmyzsh removes the oh-my-zsh directory when present" {
  mkdir -p "$TEST_HOME/.oh-my-zsh"
  # Put a file inside so the directory is non-empty
  touch "$TEST_HOME/.oh-my-zsh/oh-my-zsh.sh"

  uninstall_ohmyzsh

  [ ! -d "$TEST_HOME/.oh-my-zsh" ]
}

@test "uninstall_ohmyzsh reports not installed when directory is absent" {
  run uninstall_ohmyzsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed"* ]]
}

# ---------------------------------------------------------------------------
# Symlink removal logic (tested via a helper that replicates main's loop)
# ---------------------------------------------------------------------------

# Extracts the symlink-removal logic from main() into a testable wrapper so
# we can verify the safety check (only remove symlinks pointing into DOTFILES_DIR).
remove_dotfile_symlinks() {
  local targets=("$@")
  for target in "${targets[@]}"; do
    if [ -L "$target" ]; then
      local link_dest
      link_dest="$(readlink "$target")"
      if [[ "$link_dest" == "$DOTFILES_DIR"* ]]; then
        rm "$target"
        info "Removed symlink: $target"
      else
        warn "Skipping $target - symlink points elsewhere: $link_dest"
      fi
    elif [ -e "$target" ]; then
      warn "Skipping $target - not a symlink"
    else
      warn "Skipping $target - does not exist"
    fi
  done
}

@test "symlink removal deletes link pointing into DOTFILES_DIR" {
  local target="$TEST_HOME/.tmux.conf"
  ln -s "$DOTFILES_DIR/.tmux.conf" "$target"

  remove_dotfile_symlinks "$target"

  [ ! -e "$target" ]
}

@test "symlink removal leaves link pointing outside DOTFILES_DIR untouched" {
  local target="$TEST_HOME/.tmux.conf"
  local other
  other="$(mktemp)"
  ln -s "$other" "$target"

  remove_dotfile_symlinks "$target"

  [ -L "$target" ]
  rm -f "$other"
}

@test "symlink removal warns and skips a regular file" {
  local target="$TEST_HOME/.tmux.conf"
  echo "real file" > "$target"

  run remove_dotfile_symlinks "$target"

  [ "$status" -eq 0 ]
  [[ "$output" == *"not a symlink"* ]]
  [ -f "$target" ]
}

@test "symlink removal warns and skips a non-existent path" {
  local target="$TEST_HOME/.does_not_exist"

  run remove_dotfile_symlinks "$target"

  [ "$status" -eq 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# ---------------------------------------------------------------------------
# uninstall_* failure handling
# ---------------------------------------------------------------------------

@test "uninstall_tmux returns 1 with a warning when no package manager is found" {
  # Create the fake bin and stub tmux BEFORE overriding PATH
  mkdir -p "$TEST_HOME/empty_bin"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_HOME/empty_bin/tmux"
  chmod +x "$TEST_HOME/empty_bin/tmux"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/empty_bin"

  run uninstall_tmux

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" != *"tmux uninstalled"* ]]
}

@test "uninstall_neovim returns 1 with a warning when no package manager is found" {
  mkdir -p "$TEST_HOME/empty_bin"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_HOME/empty_bin/nvim"
  chmod +x "$TEST_HOME/empty_bin/nvim"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/empty_bin"

  run uninstall_neovim

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" != *"neovim uninstalled"* ]]
}

@test "uninstall_zsh returns 1 with a warning when no package manager is found" {
  mkdir -p "$TEST_HOME/empty_bin"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_HOME/empty_bin/zsh"
  chmod +x "$TEST_HOME/empty_bin/zsh"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/empty_bin"

  run uninstall_zsh

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" != *"zsh uninstalled"* ]]
}

# ---------------------------------------------------------------------------
# ERR trap — mid-function failure detail
# ---------------------------------------------------------------------------

@test "uninstall_tmux emits command-failed detail when the package manager command fails" {
  # set +e so non-zero return doesn't exit the test; no || wrapper so trap isn't suppressed.
  mkdir -p "$TEST_HOME/empty_bin"
  printf '#!/bin/bash\nexec "$@"\n' > "$TEST_HOME/empty_bin/sudo"
  printf '#!/bin/bash\nexit 1\n'    > "$TEST_HOME/empty_bin/apt"
  printf '#!/bin/bash\nexit 0\n'    > "$TEST_HOME/empty_bin/tmux"
  chmod +x "$TEST_HOME/empty_bin/sudo" "$TEST_HOME/empty_bin/apt" "$TEST_HOME/empty_bin/tmux"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/empty_bin"

  local captured
  set +e
  captured="$(uninstall_tmux 2>&1)"
  set -e

  export PATH="$orig_path"
  [[ "$captured" == *"command failed"* ]]
}
