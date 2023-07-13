#!/usr/bin/env bash

###############################################################################
# no external command calls here, only pure bash!
###############################################################################

# Pushes element to the end of array as if it was a steck
#    ref_stack
#    element
stackPush() {
    declare -n ref_stack=$1
    declare -r element=$2

    ref_stack+=("$element")
}

# Pops the last element from array as if it was a stack
#    ref_stack
#    out_element
#    peek=0 - if 1, returns the last element as out, without removing
stackPop() {
    declare -n ref_stack=$1
    declare -n out_element=$2
    declare -ri peek=${3:-0}

    if [ ${#ref_stack[@]} -gt 0 ]; then
        declare -r top=${ref_stack[-1]}
        [[ $peek -ne 1 ]] && unset 'ref_stack[-1]'
        out_element="$top"
    else
        # shellcheck disable=SC2034
        out_element=
    fi
}
