# oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# EDITOR
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

export PATH="$HOME/bin:$HOME/.local/bin:$PATH"

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

# local overrides
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
