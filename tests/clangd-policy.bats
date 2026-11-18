#!/usr/bin/env bats

@test "clangd respects repository policies and keeps personal fallback isolated" {
  command -v nvim >/dev/null || skip "Neovim is not installed"
  nvim --headless -u NONE '+if !has("nvim-0.12") | cquit | endif' +qa \
    || skip "Neovim 0.12 is required"
  [ "$(uname -s)" = Linux ] || skip "clangd config isolation uses Linux XDG paths"
  run nvim --headless -u NONE -l "$BATS_TEST_DIRNAME/clangd-policy.lua"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
