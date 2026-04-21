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
# uninstall_via_packagefile
# ---------------------------------------------------------------------------

@test "uninstall_via_packagefile returns 1 when no package manager is found" {
  mkdir -p "$TEST_HOME/empty_bin"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/empty_bin"

  run uninstall_via_packagefile

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
}

@test "uninstall_via_packagefile removes each package from apt.txt via apt" {
  local log="$TEST_HOME/apt.log"
  local empty_bin="$TEST_HOME/empty_bin"
  mkdir -p "$empty_bin"
  printf '#!/bin/bash\nexec "$@"\n'          > "$empty_bin/sudo"
  printf '#!/bin/bash\necho "apt $*" >> "%s"\n' "$log" > "$empty_bin/apt"
  chmod +x "$empty_bin/sudo" "$empty_bin/apt"

  local fake_dotfiles="$TEST_HOME/fake_dotfiles"
  mkdir -p "$fake_dotfiles/packages"
  printf 'tmux\nzsh\n' > "$fake_dotfiles/packages/apt.txt"
  DOTFILES_DIR="$fake_dotfiles"

  local orig_path="$PATH"
  export PATH="$empty_bin"

  run uninstall_via_packagefile

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  [ "$status" -eq 0 ]
  [[ "$(cat "$log")" == *"remove -y tmux"* ]]
  [[ "$(cat "$log")" == *"remove -y zsh"* ]]
}

# ---------------------------------------------------------------------------
# restore_default_shell
# ---------------------------------------------------------------------------

@test "restore_default_shell skips when bash is already the default shell" {
  local mock_bash="$TEST_HOME/mock_bin/bash"
  mkdir -p "$TEST_HOME/mock_bin"
  printf '#!/bin/bash\nexit 0\n' > "$mock_bash"
  printf "#!/bin/bash\necho '%s'\n" "$mock_bash" > "$TEST_HOME/mock_bin/which"
  chmod +x "$mock_bash" "$TEST_HOME/mock_bin/which"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/mock_bin:$PATH"
  export SHELL="$mock_bash"

  run restore_default_shell

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already the default shell"* ]]
}

@test "restore_default_shell calls chsh when shell differs from bash" {
  local chsh_log="$TEST_HOME/chsh.log"
  local mock_bash="$TEST_HOME/mock_bin/bash"
  mkdir -p "$TEST_HOME/mock_bin"
  printf '#!/bin/bash\nexit 0\n'                             > "$mock_bash"
  printf "#!/bin/bash\necho '%s'\n" "$mock_bash"             > "$TEST_HOME/mock_bin/which"
  printf '#!/bin/bash\necho "chsh $*" >> "%s"\n' "$chsh_log" > "$TEST_HOME/mock_bin/chsh"
  chmod +x "$mock_bash" "$TEST_HOME/mock_bin/which" "$TEST_HOME/mock_bin/chsh"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/mock_bin:$PATH"
  export SHELL="/bin/zsh"

  run restore_default_shell

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restoring bash"* ]]
  [[ "$(cat "$chsh_log")" == *"$mock_bash"* ]]
}

# ---------------------------------------------------------------------------
# uninstall_ghostty
# ---------------------------------------------------------------------------

@test "uninstall_ghostty exits cleanly when ghostty is not on PATH" {
  mkdir -p "$TEST_HOME/empty_bin"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/empty_bin"

  run uninstall_ghostty

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed"* ]]
}

@test "uninstall_ghostty uses brew when ghostty and brew are available" {
  local brew_log="$TEST_HOME/brew.log"
  mkdir -p "$TEST_HOME/mock_bin"
  printf '#!/bin/bash\nexit 0\n'                              > "$TEST_HOME/mock_bin/ghostty"
  printf '#!/bin/bash\necho "brew $*" >> "%s"\n' "$brew_log" > "$TEST_HOME/mock_bin/brew"
  chmod +x "$TEST_HOME/mock_bin/ghostty" "$TEST_HOME/mock_bin/brew"
  local orig_path="$PATH"
  export PATH="$TEST_HOME/mock_bin:$PATH"

  run uninstall_ghostty

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$(cat "$brew_log")" == *"uninstall ghostty"* ]]
}

# ---------------------------------------------------------------------------
# ERR trap — mid-function failure detail
# ---------------------------------------------------------------------------

@test "uninstall_via_packagefile emits command-failed detail when the package manager command fails" {
  local empty_bin="$TEST_HOME/empty_bin"
  mkdir -p "$empty_bin"
  printf '#!/bin/bash\nexec "$@"\n' > "$empty_bin/sudo"
  printf '#!/bin/bash\nexit 1\n'    > "$empty_bin/apt"
  chmod +x "$empty_bin/sudo" "$empty_bin/apt"

  local fake_dotfiles="$TEST_HOME/fake_dotfiles"
  mkdir -p "$fake_dotfiles/packages"
  printf 'tmux\n' > "$fake_dotfiles/packages/apt.txt"
  DOTFILES_DIR="$fake_dotfiles"

  local orig_path="$PATH"
  export PATH="$empty_bin"

  local captured
  set +e
  captured="$(uninstall_via_packagefile 2>&1)"
  set -e

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  [[ "$captured" == *"command failed"* ]]
}
