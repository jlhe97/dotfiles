#!/usr/bin/env bats

# Tests for functions defined in uninstall.sh.
# Run with: bats tests/uninstall.bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Source uninstall.sh functions without triggering `set -e` or `main "$@"`.
  # head -n -1 drops the trailing main call.
  local tmpfile
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$DOTFILES_DIR/uninstall.sh" | head -n -1 > "$tmpfile"
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
