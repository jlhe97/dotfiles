#!/usr/bin/env bats

# Tests for .config/git/config: the commit template each kind of repo gets.
# Run with: bats tests/git-config.bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  unset XDG_CONFIG_HOME
  # A system template is exactly what the config must override, so stand one
  # in rather than depending on whether this host has one.
  printf 'SYSTEM TEMPLATE\n' > "$TEST_HOME/system-template"
  printf '[commit]\n\ttemplate = %s\n' "$TEST_HOME/system-template" > "$TEST_HOME/system-gitconfig"
  export GIT_CONFIG_SYSTEM="$TEST_HOME/system-gitconfig"
  export GIT_AUTHOR_NAME="Test User" GIT_AUTHOR_EMAIL="tester@example.com"
  export GIT_COMMITTER_NAME="Test User" GIT_COMMITTER_EMAIL="tester@example.com"

  # Linked file by file, as install.sh does: the include path resolves
  # relative to the link, not to the repo.
  mkdir -p "$HOME/.config/git"
  local f
  for f in config kernel.config kernel-commit-template; do
    ln -s "$DOTFILES_DIR/.config/git/$f" "$HOME/.config/git/$f"
  done

  REPO="$TEST_HOME/repo"
  git init -q "$REPO"
  cd "$REPO"
}

teardown() {
  rm -rf "$TEST_HOME"
}

# Commit through an editor that saves what git pre-filled, then writes a
# subject so the commit goes through.
_commit_capturing_template() {
  GIT_EDITOR="sh -c 'cp \"\$1\" \"$TEST_HOME/prefilled\"; echo subject > \"\$1\"' --" \
    git commit -q --allow-empty
}

@test "a non-kernel repo gets no template, not the system one" {
  git remote add origin https://github.com/example/dotfiles.git

  run _commit_capturing_template

  [ "$status" -eq 0 ]
  ! grep -q 'SYSTEM TEMPLATE' "$TEST_HOME/prefilled"
  ! grep -q '<subsystem>' "$TEST_HOME/prefilled"
}

@test "a repo with a git.kernel.org remote gets the kernel template" {
  git remote add origin https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git

  run _commit_capturing_template

  [ "$status" -eq 0 ]
  grep -q '<subsystem>' "$TEST_HOME/prefilled"
  [ "$(git log -1 --format=%s)" = "subject" ]
}

# A kernel tree is often cloned from a personal fork, with the maintainer's
# tree added as a second remote.
@test "a kernel.org remote that is not origin still counts" {
  git remote add origin https://github.com/example/linux.git
  git remote add axboe https://git.kernel.org/pub/scm/linux/kernel/git/axboe/linux.git

  run _commit_capturing_template

  [ "$status" -eq 0 ]
  grep -q '<subsystem>' "$TEST_HOME/prefilled"
}

@test "the kernel template is all comments, so it never reaches a commit" {
  git remote add origin https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git

  run _commit_capturing_template

  [ "$(git log -1 --format=%B)" = "subject" ]
}

# A repo's own setting -- a project shipping its own template -- wins.
@test "a repo-local commit.template overrides both" {
  git remote add origin https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git
  printf 'PROJECT TEMPLATE\n' > "$TEST_HOME/project-template"
  git config commit.template "$TEST_HOME/project-template"

  run _commit_capturing_template

  grep -q 'PROJECT TEMPLATE' "$TEST_HOME/prefilled"
}
