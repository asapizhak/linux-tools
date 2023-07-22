#!/usr/bin/env bash

###############################################################################
# no external command calls here, only pure bash!
###############################################################################
if [[ ${core__inited:-0} -ne 1 ]]; then
    declare -gir core__inited=1

    # shellcheck disable=SC2034
    declare -ri EXIT_CODE_NO_INPUT_ARGS=55
    # shellcheck disable=SC2034
    declare -ri EXIT_CODE_PREREQUISITE_FAILED=57

    if declare -p COLOR >/dev/null 2>&1; then
        echo >&2 "Variable 'COLOR' was already defined!"
        exit 1
    fi
    # Color variables
    declare -gA COLOR=()
    COLOR['default']='\033[0m'
    COLOR['red']='\033[0;31m'
    COLOR['green']='\033[0;32m'
    COLOR['yellow']='\033[0;33m'
    COLOR['blue']='\033[0;34m'
    COLOR['magenta']='\033[0;35m'
    COLOR['cyan']='\033[0;36m'
    COLOR['white']='\033[0;37m'
    COLOR['gray']='\033[90m'
    readonly -A COLOR

    declare -ag core_color_names_stack=()
fi

function coreFailExit {
    declare -r msg=${1:-""}
    declare -ri code=$(( "${2:-1}" ))

    [ -n "$msg" ] && printf >&2 "Error: ${COLOR['red']}%s${COLOR['default']}\n" "$msg"

    if [[ $code -ne 0 ]]; then
        exit $code
    else
        printf >&2 "${COLOR['red']}Failed to coreFailExit with success code 0${COLOR['default']}"
        exit 1
    fi
}

function coreFailExitWithUsage {
    if [[ $(type -t usage) = 'function' ]]; then
        usage
    fi
    coreFailExit "$@"
}

function coreCommandsArePresent {
    declare suppress_echo=$1

    if [[ $suppress_echo =~ ^[0-9]+$ ]]; then
        shift
        [[ $suppress_echo -ne 0 ]] && suppress_echo=1
    else
        suppress_echo=0
    fi

    ret=0
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            [[ $suppress_echo -eq 0 ]] && echo "Command '$cmd' was not found." >&2
            ret=1
        fi
    done
    return $ret
}

function coreEnsureCommands {
    if ! coreCommandsArePresent "$@"; then coreFailExit "Missing required commands"; fi
}

function coreIsNameNotTaken {
    declare -r name=$1

    if coreCommandsArePresent 1 "$name" || type -t "$name" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Use F_COLOR with color name for colored output
function echo2 {
    declare color_enabled=0

    if declare -p F_COLOR >/dev/null 2>&1 && [[ -n "$F_COLOR" ]]; then
        color_enabled=1
        declare -r color="${COLOR[$F_COLOR]}"
        # shellcheck disable=SC2059
        printf >&2 "$color"
        core_color_names_stack+=("$color")
    fi

    echo >&2 "$@"

    if [[ $color_enabled -eq 1 ]]; then
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            unset 'core_color_names_stack[-1]'
        fi
        declare ret_color_name=default
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            ret_color_name="${core_color_names_stack[-1]}"
        fi
        # shellcheck disable=SC2059
        printf >&2 "${COLOR[$ret_color_name]}"
    fi
}

function echo2success {
    F_COLOR=green echo2 "$@"
}

function echo2warn {
    F_COLOR=yellow echo2 "$@"
}

function echo2fail {
    F_COLOR=red echo2 "$@"
}

# Use F_COLOR with color name for colored output
function printf2 {
    declare color_enabled=0

    if declare -p F_COLOR >/dev/null 2>&1 && [[ -n "$F_COLOR" ]]; then
        color_enabled=1
        declare -r color="${COLOR[$F_COLOR]}"
        # shellcheck disable=SC2059
        printf >&2 "$color"
        core_color_names_stack+=("$color")
    fi

    # shellcheck disable=SC2059
    printf >&2 "$@"

    if [[ $color_enabled -eq 1 ]]; then
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            unset 'core_color_names_stack[-1]'
        fi
        declare ret_color_name=default
        if [[ ${#core_color_names_stack[@]} -gt 0 ]]; then
            ret_color_name="${core_color_names_stack[-1]}"
        fi
        # shellcheck disable=SC2059
        printf >&2 "${COLOR[$ret_color_name]}"
    fi
}

function printf2success {
    F_COLOR=green printf2 "$@"
}

function printf2warn {
    F_COLOR=yellow printf2 "$@"
}

function printf2fail {
    F_COLOR=red printf2 "$@"
}

function trapWithSigname { # https://stackoverflow.com/a/2183063
    declare -r func="$1"
    shift

    # shellcheck disable=SC2317
    function f_proxy {
        declare -r f=$1
        shift

        echo2
        F_COLOR='cyan' echo2 "┌ Running cleanup ($1)..."
        if "$f" "$@"; then
            F_COLOR='cyan' echo2 "└ Cleanup finished."
        else
            F_COLOR='cyan' echo2 "└ Cleanup failed."
        fi
    }

    for sig; do
        # shellcheck disable=SC2064
        trap "f_proxy $func $sig" "$sig"
    done
}

#
#    explanation?
function coreEnsureRunByRoot {
    declare -r explanation="${1:-}"

    printf2 "Checking if run by root..."
    if [[ $EUID -eq 0 ]]; then
        echo2success " OK"
        return 0
    else
        echo2error " Fail"
        if [[ -n $explanation ]]; then coreFailExit "Script need to be run by root user - $explanation"
        else coreFailExit "Script need to be run by root user"
        fi
    fi
}
