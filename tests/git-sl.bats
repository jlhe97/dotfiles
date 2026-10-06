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

@test "a draft is marked @, drawn off to the side and joined into its base" {
  git commit -q --allow-empty -m "my draft"

  run "$GIT_SL"

  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "  @ "* ]]
  [[ "${lines[1]}" == "╭─╯ my draft" ]]
  [ "${lines[2]}" = "│" ]
  [[ "${lines[3]}" == "o "* ]]
  [[ "${lines[4]}" == *"public base" ]]
}

# The case that motivated the spine: HEAD sits on the upstream tip, which is
# public, while another branch has work based further down.
@test "HEAD on the upstream tip is shown above another branch's stack" {
  git switch -q -c feature
  git commit -q --allow-empty -m "feature work"
  git switch -q main
  git commit -q --allow-empty -m "upstream moved on"
  git update-ref refs/remotes/origin/main HEAD

  run "$GIT_SL"

  # The tip's parent is the stack's base: a solid line, joined with ├.
  [[ "${lines[0]}" == "@ "*"origin/main"* ]]
  [[ "${lines[3]}" == "│ o "*"(feature)" ]]
  [[ "${lines[4]}" == "├─╯ feature work" ]]
  [[ "$output" == *"public base"* ]]
}

@test "public history between the upstream tip and a stack's base is elided" {
  git switch -q -c feature
  git commit -q --allow-empty -m "feature work"
  git switch -q main
  git commit -q --allow-empty -m "hidden public 1"
  git commit -q --allow-empty -m "hidden public 2"
  git update-ref refs/remotes/origin/main HEAD

  run "$GIT_SL"

  [[ "$output" != *"hidden public 1"* ]]
  [[ "${lines[1]}" == "╷ hidden public 2" ]]
  [ "${lines[${#lines[@]}-1]}" != "~" ]
}

@test "older history below the lowest base is marked ~, but not past a root" {
  git switch -q -c feature
  git commit -q --allow-empty -m "feature work"
  git switch -q main
  run "$GIT_SL"
  [ "${lines[${#lines[@]}-1]}" != "~" ]

  git commit -q --allow-empty -m "second public"
  git switch -q -c later
  git commit -q --allow-empty -m "later work"
  git switch -q main
  git commit -q --allow-empty -m "third public"
  git update-ref refs/remotes/origin/main HEAD
  git branch -q -D feature
  run "$GIT_SL"
  [[ "${lines[${#lines[@]}-4]}" == "o "*  ]]
  [[ "${lines[${#lines[@]}-3]}" == "│ second public" ]]
  [ "${lines[${#lines[@]}-1]}" = "~" ]
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

  # By default the maintainer commit is part of the draft stack.
  run "$GIT_SL"
  [[ "${lines[3]}" == "  o "*"(axboe/for-next/io_uring)" ]]

  # Public, it becomes the base the draft joins into.
  git config sl.public 'origin/* axboe/*'
  run "$GIT_SL"
  [[ "${lines[1]}" == "╭─╯ my draft" ]]
  [[ "${lines[3]}" == "o "*"(axboe/for-next/io_uring)" ]]
}

# The kernel case: a maintainer tree and the main upstream are unrelated
# lines, and each keeps its own commits together.
@test "an ancestor is drawn under its descendant, not after an unrelated line" {
  git config sl.public 'origin/* axboe/*'
  git switch -q -c maint
  git commit -q --allow-empty -m "maint older"
  git commit -q --allow-empty -m "maint newer"
  git update-ref refs/remotes/axboe/for-next HEAD
  git switch -q -c d1
  git commit -q --allow-empty -m "draft on newer"
  git switch -q -c d2 maint~1
  git commit -q --allow-empty -m "draft on older"
  git switch -q main
  git commit -q --allow-empty -m "unrelated upstream"
  git update-ref refs/remotes/origin/main HEAD

  run "$GIT_SL"

  local between
  between="$(printf '%s\n' "$output" | sed -n '/maint newer/,/maint older/p')"
  [[ "$between" == *"draft on older"* ]]
  [[ "$between" != *"unrelated upstream"* ]]
  [[ "$between" != *$'\n'"~"$'\n'* ]]
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
