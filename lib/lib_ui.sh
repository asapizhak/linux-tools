#! /usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

ensureCommands read tput

#
#    array_ref
#    selection_index?
#    title?
function uiDisplayList {
    declare -rn list_to_display=$1
    declare -ri selection_idx=${2:--1}
    declare -r title=${3:-}

    echo2
    [[ -n $title ]] && printf2 "╔═ $title ═╗\n"

    for idx in "${!list_to_display[@]}"; do
        if [[ $idx -ge 0 && $idx -eq $selection_idx ]]; then
            tput rev
            printf2 -- "\e[1m- %s\e[0m\n" "${list_to_display[$idx]}"
            tput sgr0
        else
            printf2 -- "- %s\n" "${list_to_display[$idx]}"
        fi
    done
}

# uiListWithSelection
#    out_selected_index
#    ref_items_array
#    selection_index?
#    title?
function uiListWithSelection {
    declare -n out_selected_idx=$1
    declare -rn list_to_choose=$2
    declare -i selection_idx=${3:-0}
    declare title=${4:-}

    [[ -n $title ]] && title="$title ═ 'q' to quit" || title="q to quit"

    # man tput, man terminfo, https://tldp.org/HOWTO/Bash-Prompt-HOWTO/x405.html
    tput sc # save cursor pos before list
    tput civis
    uiDisplayList list_to_choose $selection_idx "$title"

    declare input
    while true; do
        IFS= read -rsN1 input
        [[ $input = $'\e' ]] && IFS= read -rsN2 input

        case $input in
        '[A') # arrow up
            selection_idx=$((selection_idx - 1))
            ;;
        '[B') # arrow down
            selection_idx=$((selection_idx + 1))
            ;;
        $'\n') # Enter
            # shellcheck disable=SC2034
            out_selected_idx=$selection_idx
            # clear selection list to lower log cluttering
            tput rc
            tput ed
            tput cnorm
            return 0
            ;;
        "q")
            tput cnorm
            echo2 Quit requested
            # shellcheck disable=SC2034
            out_selected_idx=
            return 1
            ;;
        *)
            echo2 "Unknown key: $input"
            ;;
        esac

        ((selection_idx < 0)) && selection_idx=0
        ((selection_idx >= ${#list_to_choose[@]})) && selection_idx=$((${#list_to_choose[@]} - 1))

        tput rc # restore cursor pos
        tput ed # clear to the end

        uiDisplayList list_to_choose $selection_idx "$title"
    done
}
