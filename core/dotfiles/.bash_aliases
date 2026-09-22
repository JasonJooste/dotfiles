### Useful little functions
calc() {
    echo "scale=3;$@" | bc -l
}
# Add key binding for copying the current command to the clipboard
if [[ -n $DISPLAY ]]; then
  copy_line_to_x_clipboard () {
    printf %s "$READLINE_LINE" | xclip -selection CLIPBOARD
  }
  bind -x '"\C-y": copy_line_to_x_clipboard' # bound to ctrl-y
fi

alias cp='cp -i'
alias cxclip="xclip -rmlastnl -selection C"
