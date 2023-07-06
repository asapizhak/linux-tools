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
function getInputArgs {
    declare argspec=$1
    declare -n out=$2
    shift 2

    declare OPTIND opt

    while getopts "$argspec" opt; do
        case $opt in
        :) # missing option argument
            failWithUsage "Missing argument for -$OPTARG"
            ;;
        \?) # unknown option
            failWithUsage "Unknown option '$OPTARG'"
            ;;
        *)
            # shellcheck disable=SC2034
            out["$opt"]=${OPTARG:-""}
            ;;
        esac
    done
}
