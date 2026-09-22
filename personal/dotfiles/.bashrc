# Modified alert that uses normal urgency, includes the error code on failed commands and an extension that can play a sound
alert() {
    local e=$?
    local cmd=$(history|tail -n1|sed -E 's/^\s*[0-9]+\s*//; s/[;&|]\s*alert(-.*)?$//')
    local msg="$cmd"
    [ $e -ne 0 ] && msg="$msg (Exit: $e)"
    notify-send --urgency=normal -i "$([ $e = 0 ] && echo terminal || echo error)" "$msg"
}
alias bell='paplay /usr/share/sounds/freedesktop/stereo/complete.oga'
alias alert-sound='alert;bell;sleep 1;bell'
