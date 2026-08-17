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

# Regression: the loop feeds the package list in on stdin, so a package manager
# that reads stdin swallows the remainder of the list and the loop ends after
# the package that did it -- silently, since nothing returned non-zero. On
# Ubuntu 24.04 apt did exactly this, and everything after neovim in apt.txt was
# never attempted, with no warning to say so. The mock here reproduces that by
# draining stdin; every package must still be attempted.
@test "install_via_packagefile keeps going when the package manager reads stdin" {
  local log="$TEST_HOME/apt-slurp.log"
  cat > "$MOCK_BIN/sudo" << 'EOF'
#!/bin/bash
exec "$@"
EOF
  # Drain with a builtin loop, not `cat`: PATH is $MOCK_BIN only, so an
  # external command would not be found and stdin would survive, making this
  # test pass against the unfixed loop and guard nothing.
  # Only drain on `install`. install_via_packagefile also runs `apt update`
  # before the loop, and that call inherits the caller's stdin rather than the
  # package list -- draining there would block forever under bats.
  cat > "$MOCK_BIN/apt" << EOF
#!/bin/bash
echo "apt \$*" >> "$log"
if [ "\$1" = "install" ]; then
  while IFS= read -r _; do :; done   # drain stdin, as a real package manager may
fi
EOF
  chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/apt"

  local fake_dotfiles="$TEST_HOME/fake_dotfiles_slurp"
  mkdir -p "$fake_dotfiles/packages"
  printf 'tmux\nneovim\nneomutt\nzsh\n' > "$fake_dotfiles/packages/apt.txt"
  DOTFILES_DIR="$fake_dotfiles"

  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_via_packagefile

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  [ "$status" -eq 0 ]
  [[ "$(cat "$log")" == *"install -y tmux"* ]]
  [[ "$(cat "$log")" == *"install -y neovim"* ]]
  [[ "$(cat "$log")" == *"install -y neomutt"* ]]
  [[ "$(cat "$log")" == *"install -y zsh"* ]]
  [ "$(grep -c 'install -y' "$log")" -eq 4 ]
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

@test "install_via_packagefile installs each package from dnf.txt via dnf" {
  local log="$TEST_HOME/dnf.log"
  cat > "$MOCK_BIN/sudo" << 'EOF'
#!/bin/bash
exec "$@"
EOF
  cat > "$MOCK_BIN/dnf" << EOF
#!/bin/bash
echo "dnf \$*" >> "$log"
EOF
  chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/dnf"

  local fake_dotfiles="$TEST_HOME/fake_dotfiles"
  mkdir -p "$fake_dotfiles/packages"
  printf 'tmux\nneovim\n' > "$fake_dotfiles/packages/dnf.txt"
  DOTFILES_DIR="$fake_dotfiles"

  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_via_packagefile

  export PATH="$orig_path"
  DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

  [ "$status" -eq 0 ]
  [[ "$(cat "$log")" == *"install -y tmux"* ]]
  [[ "$(cat "$log")" == *"install -y neovim"* ]]
}

# ---------------------------------------------------------------------------
# install_via_brewfile
# ---------------------------------------------------------------------------

@test "install_via_brewfile warns and returns 1 when brew is not on PATH" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run install_via_brewfile

  export PATH="$orig_path"
  [ "$status" -eq 1 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"Homebrew not found"* ]]
}

@test "install_via_brewfile runs brew bundle when brew is available" {
  local log="$TEST_HOME/brew.log"
  cat > "$MOCK_BIN/brew" << EOF
#!/bin/bash
echo "brew \$*" >> "$log"
EOF
  chmod +x "$MOCK_BIN/brew"

  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run install_via_brewfile

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$(cat "$log")" == *"bundle install"* ]]
}

# ---------------------------------------------------------------------------
# set_default_shell
# ---------------------------------------------------------------------------

@test "set_default_shell skips when zsh is already the default shell" {
  cat > "$MOCK_BIN/zsh" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN/zsh"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"
  export SHELL="$MOCK_BIN/zsh"

  run set_default_shell

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already the default shell"* ]]
}

@test "set_default_shell calls chsh when a different shell is active" {
  local log="$TEST_HOME/chsh.log"
  cat > "$MOCK_BIN/zsh" << 'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$MOCK_BIN/chsh" << EOF
#!/bin/bash
echo "chsh \$*" >> "$log"
EOF
  # /etc/shells must contain zsh path for the grep check; stub it via a
  # temp file and override with a no-op grep that always succeeds.
  cat > "$MOCK_BIN/grep" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN/zsh" "$MOCK_BIN/chsh" "$MOCK_BIN/grep"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"
  export SHELL="/bin/bash"

  run set_default_shell

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Setting zsh as default shell"* ]]
  [[ "$(cat "$log")" == *"chsh"* ]]
}

# ---------------------------------------------------------------------------
# install_ghostty / install_sapling — already-installed fast paths
# ---------------------------------------------------------------------------

@test "install_ghostty skips when ghostty is already on PATH" {
  cat > "$MOCK_BIN/ghostty" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN/ghostty"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run install_ghostty

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "install_sapling skips when sl is already on PATH" {
  cat > "$MOCK_BIN/sl" << 'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$MOCK_BIN/sl"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run install_sapling

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

# The mock answers the `has("nvim-0.8")` probe rather than --version, because
# that is what nvim_meets_minimum actually reads; --version is only echoed back
# in the log line.
mock_nvim() {
  cat > "$MOCK_BIN/nvim" << EOF
#!/bin/bash
for arg in "\$@"; do
  case "\$arg" in
    *'io.write(vim.fn.has'*) printf '%s' '$1'; exit 0 ;;
  esac
done
echo "NVIM v$2"
EOF
  chmod +x "$MOCK_BIN/nvim"
}

@test "nvim_meets_minimum accepts a new enough nvim" {
  mock_nvim 1 "0.10.0"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run nvim_meets_minimum

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
}

@test "nvim_meets_minimum rejects an nvim older than 0.8" {
  mock_nvim 0 "0.6.1"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run nvim_meets_minimum

  export PATH="$orig_path"
  [ "$status" -ne 0 ]
}

@test "nvim_meets_minimum reports failure when nvim is not on PATH" {
  rm -f "$MOCK_BIN/nvim"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run nvim_meets_minimum

  export PATH="$orig_path"
  [ "$status" -ne 0 ]
}

@test "install_neovim skips when the installed nvim already meets the minimum" {
  mock_nvim 1 "0.10.0"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run install_neovim

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new enough"* ]]
}

@test "install_neovim warns instead of failing on an unsupported architecture" {
  mock_nvim 0 "0.6.1"
  cat > "$MOCK_BIN/uname" << 'EOF'
#!/bin/bash
[[ "$1" == "-m" ]] && echo "riscv64" || echo "Linux"
EOF
  chmod +x "$MOCK_BIN/uname"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run install_neovim

  export PATH="$orig_path"
  rm -f "$MOCK_BIN/uname"
  [ "$status" -eq 0 ]
  [[ "$output" == *"riscv64"* ]]
}

# ---------------------------------------------------------------------------
# pinentry_program
# ---------------------------------------------------------------------------

# Return the octal mode of $1 on both GNU and BSD stat.
_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %A "$1"
}

_mock_uname() {
  cat > "$MOCK_BIN/uname" << EOF
#!/bin/bash
[[ "\$1" == "-m" ]] && echo "x86_64" || echo "$1"
EOF
  chmod +x "$MOCK_BIN/uname"
}

# Narrow PATH to MOCK_BIN alone -- the way to prove a binary is absent when the
# host might have it installed -- while keeping the few utilities the function
# under test genuinely calls. Stripping PATH outright breaks mkdir/chmod/cat
# and fails the test for the wrong reason.
_isolate_path_with() {
  local u
  for u in "$@"; do
    ln -sf "$(command -v "$u")" "$MOCK_BIN/$u"
  done
  export PATH="$MOCK_BIN"
}

@test "pinentry_program prefers pinentry-mac on macOS" {
  _mock_uname Darwin
  printf '#!/bin/bash\n' > "$MOCK_BIN/pinentry-mac"
  printf '#!/bin/bash\n' > "$MOCK_BIN/pinentry-curses"
  chmod +x "$MOCK_BIN/pinentry-mac" "$MOCK_BIN/pinentry-curses"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run pinentry_program

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pinentry-mac" ]]
}

# The headless case is the one that matters: a devserver or container has no
# display, and a graphical pinentry there would hang instead of prompting.
@test "pinentry_program falls back to curses on Linux with no display" {
  _mock_uname Linux
  printf '#!/bin/bash\n' > "$MOCK_BIN/pinentry-curses"
  chmod +x "$MOCK_BIN/pinentry-curses"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"
  unset DISPLAY WAYLAND_DISPLAY

  run pinentry_program

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pinentry-curses" ]]
}

@test "pinentry_program prefers a graphical prompt when a display is present" {
  _mock_uname Linux
  printf '#!/bin/bash\n' > "$MOCK_BIN/pinentry-gnome3"
  printf '#!/bin/bash\n' > "$MOCK_BIN/pinentry-curses"
  chmod +x "$MOCK_BIN/pinentry-gnome3" "$MOCK_BIN/pinentry-curses"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"
  export DISPLAY=":0"

  run pinentry_program

  export PATH="$orig_path"
  unset DISPLAY
  [ "$status" -eq 0 ]
  [[ "$output" == *"pinentry-gnome3" ]]
}

@test "pinentry_program fails when no pinentry is installed" {
  _mock_uname Linux
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"
  unset DISPLAY WAYLAND_DISPLAY

  run pinentry_program

  export PATH="$orig_path"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# configure_gnupg
# ---------------------------------------------------------------------------

_setup_gnupg_fixture() {
  DOTFILES_DIR="$TEST_HOME/fake_dotfiles"
  mkdir -p "$DOTFILES_DIR"
  _mock_uname Linux
  printf '#!/bin/bash\n' > "$MOCK_BIN/pinentry-curses"
  chmod +x "$MOCK_BIN/pinentry-curses"
  unset DISPLAY WAYLAND_DISPLAY
}

@test "configure_gnupg creates ~/.gnupg with 700 permissions" {
  _setup_gnupg_fixture
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_gnupg

  export PATH="$orig_path"
  [ -d "$TEST_HOME/.gnupg" ]
  [ "$(_mode "$TEST_HOME/.gnupg")" = "700" ]
}

# A pre-existing directory created with the umask default must be tightened,
# not left as it was — gpg refuses to use a world-readable homedir.
@test "configure_gnupg tightens an already-loose ~/.gnupg" {
  _setup_gnupg_fixture
  mkdir -p "$TEST_HOME/.gnupg"
  chmod 755 "$TEST_HOME/.gnupg"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_gnupg

  export PATH="$orig_path"
  [ "$(_mode "$TEST_HOME/.gnupg")" = "700" ]
}

@test "configure_gnupg writes gpg-agent.conf naming the resolved pinentry" {
  _setup_gnupg_fixture
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_gnupg

  export PATH="$orig_path"
  local conf="$DOTFILES_DIR/.gnupg/gpg-agent.conf"
  [ -f "$conf" ]
  [[ "$(cat "$conf")" == *"pinentry-program"*"pinentry-curses"* ]]
  [[ "$(cat "$conf")" == *"default-cache-ttl 3600"* ]]
}

@test "configure_gnupg is a no-op on the second run" {
  _setup_gnupg_fixture
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_gnupg
  run configure_gnupg

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
}

@test "configure_gnupg warns but still writes a conf when no pinentry exists" {
  _setup_gnupg_fixture
  rm -f "$MOCK_BIN/pinentry-curses"
  local orig_path="$PATH"
  _isolate_path_with mkdir chmod cat

  run configure_gnupg

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no pinentry binary found"* ]]
  [ -f "$DOTFILES_DIR/.gnupg/gpg-agent.conf" ]
}

# ---------------------------------------------------------------------------
# signing_key_fingerprint
# ---------------------------------------------------------------------------

# Emit the colon-delimited records gpg would produce for a key. $1 non-empty
# means "this identity has a secret key".
_mock_gpg_with_key() {
  cat > "$MOCK_BIN/gpg" << 'EOF'
#!/bin/bash
if [[ "$*" == *"--list-secret-keys"* ]]; then
  echo "sec:u:255:22:6FF739276A6BB0D9:1775692800:::u:::scESC:::+:::23::0:"
  echo "fpr:::::::::48E9148428957881DD2558116FF739276A6BB0D9:"
  echo "uid:u::::1775692800::ABC::Test User <test@example.com>::::::::::0:"
fi
exit 0
EOF
  chmod +x "$MOCK_BIN/gpg"
}

_mock_gpg_no_key() {
  printf '#!/bin/bash\nexit 2\n' > "$MOCK_BIN/gpg"
  chmod +x "$MOCK_BIN/gpg"
}

@test "signing_key_fingerprint returns nothing when gpg is not installed" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run signing_key_fingerprint "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "signing_key_fingerprint returns nothing when the identity has no key" {
  _mock_gpg_no_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run signing_key_fingerprint "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "signing_key_fingerprint extracts the full fingerprint from --with-colons" {
  _mock_gpg_with_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run signing_key_fingerprint "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ "$output" = "48E9148428957881DD2558116FF739276A6BB0D9" ]
}

# ---------------------------------------------------------------------------
# configure_patch_workflow / configure_patch_signing
#
# These use the real git against a throwaway HOME rather than a mock: the
# behaviour under test is what actually lands in the config file, including
# the two-value credential helper, which a mock would not reproduce faithfully.
# ---------------------------------------------------------------------------

_setup_git_fixture() {
  : > "$TEST_HOME/.gitconfig"
  export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"
}

@test "configure_patch_workflow returns 0 silently when git is not on PATH" {
  local orig_path="$PATH"
  export PATH="$MOCK_BIN"

  run configure_patch_workflow "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "configure_patch_workflow sets the Fastmail sendemail keys" {
  _setup_git_fixture
  _mock_gpg_no_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_patch_workflow "test@example.com"

  export PATH="$orig_path"
  [ "$(git config --global --get sendemail.smtpserver)" = "smtp.fastmail.com" ]
  [ "$(git config --global --get sendemail.smtpserverport)" = "587" ]
  [ "$(git config --global --get sendemail.smtpencryption)" = "tls" ]
  [ "$(git config --global --get sendemail.smtpuser)" = "test@example.com" ]
}

# b4 only consults `git credential fill` -- and so bin/mail-pass -- when
# sendemail.smtppass is empty. A value left here silently pins a stale second
# copy of the password, which is the bug this whole design removed.
@test "configure_patch_workflow removes a lingering sendemail.smtppass" {
  _setup_git_fixture
  _mock_gpg_no_key
  git config --global sendemail.smtppass "stale-password"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run configure_patch_workflow "test@example.com"

  export PATH="$orig_path"
  [[ "$output" == *"removed sendemail.smtppass"* ]]
  [ -z "$(git config --global --get sendemail.smtppass || true)" ]
}

@test "configure_patch_workflow installs the scoped credential helper with its reset" {
  _setup_git_fixture
  _mock_gpg_no_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_patch_workflow "test@example.com"

  export PATH="$orig_path"
  local values
  values="$(git config --global --get-all 'credential.smtp://smtp.fastmail.com:587.helper')"
  # Two values: the empty reset that drops any inherited helper, then ours.
  [ "$(echo "$values" | wc -l | tr -d ' ')" = "2" ]
  [[ "$values" == *"mail-pass"* ]]
}

@test "configure_patch_workflow does not duplicate the helper on a second run" {
  _setup_git_fixture
  _mock_gpg_no_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_patch_workflow "test@example.com"
  run configure_patch_workflow "test@example.com"

  export PATH="$orig_path"
  [[ "$output" == *"already configured"* ]]
  local count
  count="$(git config --global --get-all 'credential.smtp://smtp.fastmail.com:587.helper' | wc -l | tr -d ' ')"
  [ "$count" = "2" ]
}

# The gate that makes the installer safe everywhere: no local secret key means
# no signing config at all, so a container or devserver never ends up trying
# to sign with a key it does not have.
@test "configure_patch_signing leaves signing off when there is no secret key" {
  _setup_git_fixture
  _mock_gpg_no_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run configure_patch_signing "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [[ "$output" == *"leaving patch signing off"* ]]
  [ -z "$(git config --global --get patatt.signingkey || true)" ]
  [ -z "$(git config --global --get user.signingKey || true)" ]
}

@test "configure_patch_signing enables signing when the secret key is present" {
  _setup_git_fixture
  _mock_gpg_with_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run configure_patch_signing "test@example.com"

  export PATH="$orig_path"
  [ "$status" -eq 0 ]
  [ "$(git config --global --get user.signingKey)" = "48E9148428957881DD2558116FF739276A6BB0D9" ]
  [ "$(git config --global --get patatt.signingkey)" = "openpgp:48E9148428957881DD2558116FF739276A6BB0D9" ]
}

@test "configure_patch_signing clears the historical b4 no-sign opt-out" {
  _setup_git_fixture
  _mock_gpg_with_key
  git config --global b4.send-no-patatt-sign true
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_patch_signing "test@example.com"

  export PATH="$orig_path"
  [ -z "$(git config --global --get b4.send-no-patatt-sign || true)" ]
}

# Someone who pointed these at a different key -- a work key, a hardware
# token -- meant to. The installer must not quietly take it over.
@test "configure_patch_signing does not clobber an explicit signing key" {
  _setup_git_fixture
  _mock_gpg_with_key
  git config --global user.signingKey "DEADBEEFDEADBEEF"
  git config --global patatt.signingkey "openpgp:DEADBEEFDEADBEEF"
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  run configure_patch_signing "test@example.com"

  export PATH="$orig_path"
  [[ "$output" == *"already set"* ]]
  [ "$(git config --global --get user.signingKey)" = "DEADBEEFDEADBEEF" ]
  [ "$(git config --global --get patatt.signingkey)" = "openpgp:DEADBEEFDEADBEEF" ]
}

@test "configure_patch_signing is idempotent across runs" {
  _setup_git_fixture
  _mock_gpg_with_key
  local orig_path="$PATH"
  export PATH="$MOCK_BIN:$PATH"

  configure_patch_signing "test@example.com"
  configure_patch_signing "test@example.com"

  export PATH="$orig_path"
  [ "$(git config --global --get-all user.signingKey | wc -l | tr -d ' ')" = "1" ]
  [ "$(git config --global --get patatt.signingkey)" = "openpgp:48E9148428957881DD2558116FF739276A6BB0D9" ]
}
