#!/usr/bin/env bats

# Tests for bin/git-sl.
# Run with: bats tests/git-sl.bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
GIT_SL="$DOTFILES_DIR/bin/git-sl"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  # Keep the developer's own git config (aliases, pager, sl.public) out.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME="Test User" GIT_AUTHOR_EMAIL="tester@example.com"
  export GIT_COMMITTER_NAME="Test User" GIT_COMMITTER_EMAIL="tester@example.com"

  REPO="$TEST_HOME/repo"
  git init -q -b main "$REPO"
  cd "$REPO"
  git commit -q --allow-empty -m "public base"
  # A fake upstream: origin/main at the base, origin/HEAD pointing at it.
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Commit markers with the hash and graph stripped: "@ <author>" etc.
_markers() {
  "$GIT_SL" | awk '$2 ~ /^[0-9a-f]{10}$/ { print $1, $NF }'
}

@test "with no drafts it shows just HEAD, marked @" {
  run "$GIT_SL"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "@ "* ]]
  [[ "$output" == *"public base"* ]]
}

@test "a draft is marked @ and sits on its public base, marked o" {
  git commit -q --allow-empty -m "my draft"

  run "$GIT_SL"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "@ "* ]]
  [[ "${lines[1]}" == *"my draft" ]]
  [[ "$output" == *$'\n'"o "*"public base"* ]]
}

@test "another local branch's draft is shown too" {
  git switch -q -c side
  git commit -q --allow-empty -m "side work"
  git switch -q main
  git commit -q --allow-empty -m "main work"

  run "$GIT_SL"

  [[ "$output" == *"side work"* ]]
  [[ "$output" == *"main work"* ]]
}

# The kernel case: a maintainer's branch is upstream, not yours.
@test "sl.public globs mark other remotes' commits as public" {
  git commit -q --allow-empty -m "maintainer commit"
  git update-ref refs/remotes/axboe/for-next/io_uring HEAD
  git commit -q --allow-empty -m "my draft"

  run "$GIT_SL"
  [[ "$output" == *"public base"* ]]

  # Now the maintainer commit is the public base the draft sits on, and
  # nothing below it is shown.
  git config sl.public 'origin/* axboe/*'
  run "$GIT_SL"
  [[ "$output" == *"my draft"* ]]
  [[ "$output" == *"maintainer commit"* ]]
  [[ "$output" != *"public base"* ]]
}

@test "a subject starting with graph characters is left alone" {
  git commit -q --allow-empty -m "* not a graph | / \\"

  run "$GIT_SL"

  [[ "${lines[1]}" == *"* not a graph | / \\" ]]
}

@test "merge lines are drawn with box-drawing characters" {
  git switch -q -c side
  git commit -q --allow-empty -m "side work"
  git switch -q main
  git commit -q --allow-empty -m "main work"
  git merge -q --no-ff --no-edit side

  run "$GIT_SL"

  [[ "$output" == *"├╮"* ]]
  [[ "$output" == *"├╯"* ]]
  [[ "$output" != *"|"* ]]
}

@test "piped output has no color codes" {
  git commit -q --allow-empty -m "my draft"

  run "$GIT_SL"

  [[ "$output" != *$'\033'* ]]
}
