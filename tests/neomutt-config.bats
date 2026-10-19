#!/usr/bin/env bats

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
NEOMUTTRC="$DOTFILES_DIR/.neomuttrc"

body_color_regex() {
  local color="$1"
  sed -n "/^color body $color default / { s/^color body $color default \"//; s/\"$//; p; }" "$NEOMUTTRC"
}

quote_regex() {
  sed -n '/^set quote_regex = / { s/^set quote_regex = "//; s/"$//; p; }' "$NEOMUTTRC"
}

regex_matches() {
  printf '%s\n' "$2" | grep -Eq -- "$1"
}

@test "errno-style prose is not colored as a diff deletion" {
  local regex
  regex="$(body_color_regex red)"

  ! regex_matches "$regex" '-EAGAIN'
  ! regex_matches "$regex" '-ENOBUF or another transient error'
  regex_matches "$regex" '-static int example;'
  regex_matches "$regex" $'-\treturn -EINVAL;'
}

@test "patch context includes are not detected as email quotes" {
  local regex
  regex="$(quote_regex)"

  ! regex_matches "$regex" ' #include <linux/errno.h>'
  ! regex_matches "$regex" '#include <linux/cleanup.h>'
  regex_matches "$regex" '> quoted reply'
  regex_matches "$regex" '  >> nested reply'
}

@test "thread branches use sender dates rather than delivery order" {
  grep -qx 'set sort_aux = last-date' "$NEOMUTTRC"
}
