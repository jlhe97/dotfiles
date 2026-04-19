#!/usr/bin/env bats

# Tests for functions defined in install.sh.
# Run with: bats tests/install.bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Source install.sh functions without triggering `set -e` or `main "$@"`.
  # head -n -2 drops the trailing comment + main call.
  local tmpfile
  tmpfile="$(mktemp)"
  grep -v '^set -e' "$DOTFILES_DIR/install.sh" | head -n -2 > "$tmpfile"
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
