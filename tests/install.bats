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
# configure_git
# ---------------------------------------------------------------------------

@test "configure_git returns 0 silently when git is not on PATH" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run configure_git "Test User" "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "configure_git sets identity when not yet configured" {
  cat > "$MOCK_BIN/git" << 'EOF'
#!/bin/bash
if [[ "$1 $2" == "config --global" && "$3" == "user.name" && $# -eq 3 ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "$MOCK_BIN/git"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run configure_git "Test User" "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git identity set to"* ]]
}

@test "configure_git skips when identity already matches" {
  cat > "$MOCK_BIN/git" << 'EOF'
#!/bin/bash
case "$3" in
  user.name)  echo "Test User" ;;
  user.email) echo "test@example.com" ;;
esac
exit 0
EOF
  chmod +x "$MOCK_BIN/git"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run configure_git "Test User" "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already set"* ]]
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
# install_vim_plugins / install_nvim_plugins
# ---------------------------------------------------------------------------

@test "install_vim_plugins skips gracefully when vim is not on PATH" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_vim_plugins

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "install_nvim_plugins skips gracefully when nvim is not on PATH" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_nvim_plugins

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "install_vim_plugins bootstraps vim-plug when it is missing" {
  # curl mock: parse -fLo <dest> and create the destination file
  cat > "$MOCK_BIN/curl" << 'EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -fLo|-Lo|-o) shift; dest="$1" ;;
  esac
  shift
done
mkdir -p "$(dirname "$dest")" && touch "$dest"
EOF
  cat > "$MOCK_BIN/vim" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/vim"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run install_vim_plugins

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrapping"* ]]
}

@test "install_nvim_plugins bootstraps vim-plug when it is missing" {
  cat > "$MOCK_BIN/curl" << 'EOF'
#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -fLo|-Lo|-o) shift; dest="$1" ;;
  esac
  shift
done
mkdir -p "$(dirname "$dest")" && touch "$dest"
EOF
  cat > "$MOCK_BIN/nvim" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/nvim"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run install_nvim_plugins

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrapping"* ]]
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

# ---------------------------------------------------------------------------
# install_via_packagefile
# ---------------------------------------------------------------------------

@test "install_via_packagefile installs each package from apt.txt via apt" {
  local log="$TEST_HOME/apt.log"
  cat > "$MOCK_BIN/sudo" << 'EOF'
#!/bin/bash
exec "$@"
EOF
  cat > "$MOCK_BIN/apt" << EOF
#!/bin/bash
echo "apt \$*" >> "$log"
EOF
  chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/apt"

  # minimal package list in a temp dotfiles dir
  local fake_dotfiles="$TEST_HOME/fake_dotfiles"
  mkdir -p "$fake_dotfiles/packages"
  printf 'tmux\n# a comment\n\nzsh\n' > "$fake_dotfiles/packages/apt.txt"
  DOTFILES_DIR="$fake_dotfiles"

  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_via_packagefile

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  [ "$status" -eq 0 ]
  [[ "$(cat "$log")" == *"install -y tmux"* ]]
  [[ "$(cat "$log")" == *"install -y zsh"* ]]
  [[ "$(cat "$log")" != *"a comment"* ]]
}

@test "install_via_packagefile installs each package from pacman.txt via pacman" {
  local log="$TEST_HOME/pacman.log"
  cat > "$MOCK_BIN/sudo" << 'EOF'
#!/bin/bash
exec "$@"
EOF
  cat > "$MOCK_BIN/pacman" << EOF
#!/bin/bash
echo "pacman \$*" >> "$log"
EOF
  chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/pacman"

  local fake_dotfiles="$TEST_HOME/fake_dotfiles"
  mkdir -p "$fake_dotfiles/packages"
  printf 'tmux\nghostty\n' > "$fake_dotfiles/packages/pacman.txt"
  DOTFILES_DIR="$fake_dotfiles"

  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_via_packagefile

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  [ "$status" -eq 0 ]
  [[ "$(cat "$log")" == *"-S --noconfirm tmux"* ]]
  [[ "$(cat "$log")" == *"-S --noconfirm ghostty"* ]]
}

@test "install_via_packagefile returns 1 when the package file is missing" {
  local log="$TEST_HOME/apt.log"
  cat > "$MOCK_BIN/sudo" << 'EOF'
#!/bin/bash
exec "$@"
EOF
  cat > "$MOCK_BIN/apt" << EOF
#!/bin/bash
echo "apt \$*" >> "$log"
EOF
  chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/apt"

  # DOTFILES_DIR with no packages/ subdirectory
  DOTFILES_DIR="$TEST_HOME/empty_dotfiles"
  mkdir -p "$DOTFILES_DIR"

  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_via_packagefile

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
}

@test "install_via_packagefile returns 1 when no package manager is found" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_via_packagefile

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
}

# ---------------------------------------------------------------------------
# ERR trap — mid-function failure detail
# ---------------------------------------------------------------------------

@test "install_via_packagefile emits command-failed detail when the package manager command fails" {
  local fake_dotfiles="$TEST_HOME/fake_dotfiles"
  mkdir -p "$fake_dotfiles/packages"
  printf 'tmux\n' > "$fake_dotfiles/packages/apt.txt"

  printf '#!/bin/bash\nexec "$@"\n'        > "$MOCK_BIN/sudo"
  printf '#!/bin/bash\nexit 1\n'           > "$MOCK_BIN/apt"
  chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/apt"

  DOTFILES_DIR="$fake_dotfiles"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  local captured
  set +e
  captured="$(install_via_packagefile 2>&1)"
  set -e

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  [[ "$captured" == *"command failed"* ]]
}
