#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"

###############################################################################
# no external command calls here, only pure bash!
###############################################################################

# set -x

# usage:
#   declare -A opts
#   getInputArgs ':o:i:f' opts "$@"
#       optstring should start with ":", also if parameter needs argument, it should be followed by ":"
#   for parameters expecting no value, sets 1 as value if they are present.
function getInputArgs {
    declare -n f_out=$1
    declare -r argspec="$2"
    shift 2

    declare OPTIND opt

    while getopts "$argspec" opt; do
        case $opt in
        :) # missing option argument
            coreFailExitWithUsage "Missing argument for -$OPTARG"
            ;;
        \?) # unknown option
            coreFailExitWithUsage "Unknown option '$OPTARG'"
            ;;
        *)
            # shellcheck disable=SC2034
            f_out["$opt"]=${OPTARG:-1}
            ;;
        esac
    done
}

# Call this with single "$@" argument
# 
function inputExitIfNoArguments {

    if [ "$#" -eq 0 ]; then
        coreFailExitWithUsage '' $EXIT_CODE_NO_INPUT_ARGS; return $EXIT_CODE_NO_INPUT_ARGS
    fi
}