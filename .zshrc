# oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
PROMPT='%F{yellow}%n@%m%f %F{cyan}%c%f $(git_prompt_info)'

# EDITOR
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export EDITOR="$HOME/bin/dotfiles-editor"
export VISUAL="$EDITOR"

# C/C++: make every CMake build emit compile_commands.json so clangd works
# out of the box (the Cargo-style "just works" experience). For Make projects
# use `bear -- make`; for the kernel use `make compile_commands.json`.
export CMAKE_EXPORT_COMPILE_COMMANDS=ON
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# LESS text coloring
case "${LESS-}" in
  *R*) ;;
  *) export LESS="-FRX${LESS:+ $LESS}" ;;
esac

# Panes
DISABLE_AUTO_TITLE=true
autoload -Uz add-zsh-hook

dotfiles_pane_title() {
  print -Pn '\e]2;(%n@%m)\a'
}

add-zsh-hook precmd dotfiles_pane_title
add-zsh-hook preexec dotfiles_pane_title

# local overrides
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
