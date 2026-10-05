# oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh

# Preferred editor for local and remote sessions. Over ssh the box may be one
# where the nvim config's 0.8 floor isn't met; stock vim always is.
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export TERM=xterm-256color

# C/C++: make every CMake build emit compile_commands.json so clangd works
# out of the box (the Cargo-style "just works" experience). For Make projects
# use `bear -- make`; for the kernel use `make compile_commands.json`.
export CMAKE_EXPORT_COMPILE_COMMANDS=ON
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# Source local overrides (not committed to public dotfiles)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
