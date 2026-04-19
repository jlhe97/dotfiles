#!/usr/bin/env bats

# Tests for functions defined in install.sh.
# Run with: bats tests/install.bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Source install.sh functions without triggering `set -e` or `main "$@"`.
  local tmpfile
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$DOTFILES_DIR/install.sh" | grep -v '^main ' | grep -v '^# Run main' > "$tmpfile"
  # shellcheck disable=SC1090
  source "$tmpfile"
  rm -f "$tmpfile"

  # Restore after source (install.sh resets DOTFILES_DIR to its own location,
  # which happens to be the same value — but be explicit).
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  MOCK_BIN="$TEST_HOME/mock_bin"
  mkdir -p "$MOCK_BIN"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

@test "info prints [INFO] tag and the message" {
  run info "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"hello world"* ]]
}

@test "warn prints [WARN] tag and the message" {
  run warn "a warning"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"a warning"* ]]
}

@test "error prints [ERROR] tag and the message" {
  run error "an error"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ERROR]"* ]]
  [[ "$output" == *"an error"* ]]
}

# ---------------------------------------------------------------------------
# backup_and_link
# ---------------------------------------------------------------------------

@test "backup_and_link creates symlink when destination does not exist" {
  local src dest
  src="$(mktemp)"
  dest="$TEST_HOME/target_file"

  backup_and_link "$src" "$dest"

  [ -L "$dest" ]
  [ "$(readlink "$dest")" = "$src" ]
  rm -f "$src"
}

@test "backup_and_link is a no-op when symlink already points to src" {
  local src dest
  src="$(mktemp)"
  dest="$TEST_HOME/target_file"
  ln -s "$src" "$dest"

  backup_and_link "$src" "$dest"

  [ -L "$dest" ]
  [ "$(readlink "$dest")" = "$src" ]
  # No backup directory should be created
  [ ! -d "$BACKUP_DIR" ]
  rm -f "$src"
}

@test "backup_and_link replaces dangling symlink without creating a backup" {
  local src dest
  src="$(mktemp)"
  dest="$TEST_HOME/target_file"
  ln -s "/nonexistent/dangling" "$dest"

  backup_and_link "$src" "$dest"

  [ -L "$dest" ]
  [ "$(readlink "$dest")" = "$src" ]
  [ ! -d "$BACKUP_DIR" ]
  rm -f "$src"
}

@test "backup_and_link replaces symlink pointing to a different file without backup" {
  local src dest other
  src="$(mktemp)"
  other="$(mktemp)"
  dest="$TEST_HOME/target_file"
  ln -s "$other" "$dest"

  backup_and_link "$src" "$dest"

  [ -L "$dest" ]
  [ "$(readlink "$dest")" = "$src" ]
  [ ! -d "$BACKUP_DIR" ]
  rm -f "$src" "$other"
}

@test "backup_and_link backs up an existing regular file before linking" {
  local src dest
  src="$(mktemp)"
  dest="$TEST_HOME/target_file"
  echo "original content" > "$dest"

  backup_and_link "$src" "$dest"

  [ -L "$dest" ]
  [ "$(readlink "$dest")" = "$src" ]
  [ -d "$BACKUP_DIR" ]
  [ -f "$BACKUP_DIR/target_file" ]
  rm -f "$src"
}

@test "backup_and_link backup preserves the original file's content" {
  local src dest
  src="$(mktemp)"
  dest="$TEST_HOME/precious_config"
  echo "my precious config" > "$dest"

  backup_and_link "$src" "$dest"

  [ "$(cat "$BACKUP_DIR/precious_config")" = "my precious config" ]
  rm -f "$src"
}

# ---------------------------------------------------------------------------
# resolve_identity
# ---------------------------------------------------------------------------

@test "resolve_identity uses --name/--email flag values without prompting" {
  USER_NAME="CI User"
  USER_EMAIL="ci@example.com"
  DOTFILES_DIR="$TEST_HOME"

  run resolve_identity

  [ "$status" -eq 0 ]
  [[ "$output" == *"Using provided identity"* ]]
  [[ "$output" == *"CI User"* ]]
}

@test "resolve_identity reads existing local.rc silently when no flags set" {
  DOTFILES_DIR="$TEST_HOME"
  mkdir -p "$TEST_HOME/.neomutt"
  printf 'set imap_user = "existing@example.com"\nset real_name = "Existing User"\n' \
    > "$TEST_HOME/.neomutt/local.rc"
  USER_NAME=""
  USER_EMAIL=""

  resolve_identity

  [ "$USER_NAME" = "Existing User" ]
  [ "$USER_EMAIL" = "existing@example.com" ]
}

@test "resolve_identity flags override an existing local.rc identity" {
  DOTFILES_DIR="$TEST_HOME"
  mkdir -p "$TEST_HOME/.neomutt"
  printf 'set imap_user = "old@example.com"\nset real_name = "Old User"\n' \
    > "$TEST_HOME/.neomutt/local.rc"
  USER_NAME="New User"
  USER_EMAIL="new@example.com"

  resolve_identity

  [ "$USER_NAME" = "New User" ]
  [ "$USER_EMAIL" = "new@example.com" ]
}

# ---------------------------------------------------------------------------
# configure_sapling
# ---------------------------------------------------------------------------

@test "configure_sapling returns 0 silently when sl is not on PATH" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run configure_sapling "Test User" "user@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "configure_sapling sets identity when sl exists but none is configured" {
  # Fake sl: empty output for 'config ui.username' → no identity set
  cat > "$MOCK_BIN/sl" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN/sl"
  export PATH="$MOCK_BIN:$PATH"

  run configure_sapling "Test User" "user@example.com"

  [ "$status" -eq 0 ]
  [[ "$output" == *"sapling identity set to"* ]]
  [[ "$output" == *"Test User"* ]]
}

@test "configure_sapling skips when identity is already configured" {
  # Fake sl: non-empty output for 'config ui.username' → identity exists
  cat > "$MOCK_BIN/sl" <<'EOF'
#!/bin/bash
echo "Existing User <existing@example.com>"
EOF
  chmod +x "$MOCK_BIN/sl"
  export PATH="$MOCK_BIN:$PATH"

  run configure_sapling "Test User" "user@example.com"

  [ "$status" -eq 0 ]
  [[ "$output" == *"already set"* ]]
}

# ---------------------------------------------------------------------------
# install_ohmyzsh
# ---------------------------------------------------------------------------

@test "install_ohmyzsh skips download when oh-my-zsh directory already exists" {
  mkdir -p "$TEST_HOME/.oh-my-zsh"

  run install_ohmyzsh

  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

# ---------------------------------------------------------------------------
# install_* failure handling
# ---------------------------------------------------------------------------

@test "install_tmux returns 1 (not exit) when no package manager is found" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"  # empty bin: no apt/dnf/pacman/brew/tmux

  run install_tmux

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
}

@test "install_neovim returns 1 (not exit) when no package manager is found" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_neovim

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
}

@test "install_neomutt returns 1 (not exit) when no package manager is found" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_neomutt

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
}

@test "install_zsh returns 1 (not exit) when no package manager is found" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_zsh

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
}

# ---------------------------------------------------------------------------
# ERR trap — mid-function failure detail
# ---------------------------------------------------------------------------

@test "install_tmux emits command-failed detail when the package manager command fails" {
  # apt smart stub: "update" succeeds so && continues; "install" fails → ERR trap fires.
  # set +e so non-zero return doesn't exit the test; no || wrapper so trap isn't suppressed.
  printf '#!/bin/bash\nexec "$@"\n'                                  > "$MOCK_BIN/sudo"
  printf '#!/bin/bash\n[[ "$1" == "install" ]] && exit 1\nexit 0\n' > "$MOCK_BIN/apt"
  chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/apt"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  local captured
  set +e
  captured="$(install_tmux 2>&1)"
  set -e

  export PATH="$orig_path"
  [[ "$captured" == *"command failed"* ]]
}
