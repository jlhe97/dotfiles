#!/usr/bin/env bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  export MAIL_SYNC_TEST_LOG="$TEST_HOME/operations"
  MOCK_BIN="$TEST_HOME/mock-bin"
  mkdir -p "$MOCK_BIN"
  cat > "$MOCK_BIN/mbsync" <<'EOF'
#!/bin/bash
echo "mbsync:$*" >> "$MAIL_SYNC_TEST_LOG"
exit "${MAIL_SYNC_TEST_STATUS:-0}"
EOF
  cat > "$MOCK_BIN/notmuch" <<'EOF'
#!/bin/bash
if [ "$*" = "config get database.path" ]; then
  sed -n 's/^path=//p' "$HOME/.notmuch-config"
  exit 0
fi
echo "notmuch:$*" >> "$MAIL_SYNC_TEST_LOG"
exit "${NOTMUCH_TEST_STATUS:-0}"
EOF
  chmod +x "$MOCK_BIN/mbsync" "$MOCK_BIN/notmuch"
  export PATH="$MOCK_BIN:$PATH"
  write_mail_config fastmail "$HOME/Mail/fastmail-kernel"
}

teardown() {
  rm -rf "$TEST_HOME"
}

write_mail_config() {
  local provider="$1" mail_dir="$2"
  cat > "$HOME/.mbsyncrc" <<EOF
Group $provider
Channels $provider-inbox $provider-sent
Path $mail_dir/
EOF
  cat > "$HOME/.notmuch-config" <<EOF
[database]
path=$mail_dir
EOF
}

@test "mail-sync runs only the kernel group and then indexes" {
  run "$DOTFILES_DIR/bin/mail-sync"
  [ "$status" -eq 0 ]
  [ "$(cat "$MAIL_SYNC_TEST_LOG")" = $'mbsync:fastmail\nnotmuch:new' ]
  [ -d "$TEST_HOME/Mail/fastmail-kernel" ]
  [ ! -e "$TEST_HOME/Mail/fastmail" ]
}

@test "mail-sync selects the configured provider rather than all channels" {
  mkdir -p "$TEST_HOME/.config/dotfiles"
  echo 'MAIL_PROVIDER=posteo' > "$TEST_HOME/.config/dotfiles/mail.conf"
  write_mail_config posteo "$HOME/Mail/posteo-kernel"
  run "$DOTFILES_DIR/bin/mail-sync"
  [ "$status" -eq 0 ]
  [ "$(cat "$MAIL_SYNC_TEST_LOG")" = $'mbsync:posteo\nnotmuch:new' ]
  [ -d "$TEST_HOME/Mail/posteo-kernel" ]
}

@test "mail-sync indexes partial results and preserves the sync failure status" {
  export MAIL_SYNC_TEST_STATUS=7
  run "$DOTFILES_DIR/bin/mail-sync"
  [ "$status" -eq 7 ]
  [ "$(cat "$MAIL_SYNC_TEST_LOG")" = $'mbsync:fastmail\nnotmuch:new' ]
  [[ "$output" == *"continuing to index"* ]]
}

@test "mail-sync reports an indexing failure" {
  export NOTMUCH_TEST_STATUS=9
  run "$DOTFILES_DIR/bin/mail-sync"
  [ "$status" -eq 9 ]
}

@test "mail-sync refuses legacy whole-account config without syncing or indexing" {
  cat > "$HOME/.mbsyncrc" <<EOF
Channel fastmail
Patterns *
EOF
  run "$DOTFILES_DIR/bin/mail-sync"
  [ "$status" -ne 0 ]
  [[ "$output" == *"re-run the dotfiles installer"* ]]
  [ ! -e "$MAIL_SYNC_TEST_LOG" ]
}

@test "mail-sync refuses a sync store that disagrees with MAIL_DIR" {
  cat > "$HOME/.mbsyncrc" <<EOF
Group fastmail
Channels fastmail-inbox fastmail-sent
Path $HOME/Mail/fastmail/
EOF
  run "$DOTFILES_DIR/bin/mail-sync"
  [ "$status" -ne 0 ]
  [ ! -e "$MAIL_SYNC_TEST_LOG" ]
}

@test "mail-sync refuses a notmuch index still pointing at personal mail" {
  cat > "$HOME/.notmuch-config" <<EOF
[database]
path=$HOME/Mail/fastmail
EOF
  run "$DOTFILES_DIR/bin/mail-sync"
  [ "$status" -ne 0 ]
  [[ "$output" == *"notmuch must index"* ]]
  [ ! -e "$MAIL_SYNC_TEST_LOG" ]
}
