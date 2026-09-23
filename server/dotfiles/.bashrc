# Modified alert that uses normal urgency, includes the error code on failed commands, and can also speak the message or play a sound (see notify-msg)
alert() {
    local e=$?
    local cmd=$(history|tail -n1|sed -E 's/^\s*[0-9]+\s*//; s/[;&|]\s*alert(-.*)?$//')
    local msg="$cmd"
    local opts=("$@")
    [ $e -ne 0 ] && { msg="$msg (Exit: $e)"; opts+=(--error); }
    notify-msg "${opts[@]}" "$msg"
}
alias alert-sound='alert --sound'
alias alert-tts='alert --speak'
alias bell='paplay /usr/share/sounds/freedesktop/stereo/complete.oga'
