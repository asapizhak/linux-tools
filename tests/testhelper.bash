#! /usr/bin/env bash

load "../.batsrc"

bats_require_minimum_version 1.5.0

#
function testhelpGenericSetup {
    bats_load_library bats-support
    bats_load_library bats-assert

    batslib_decorate() { # workaround for expected/actual values can't be seen when test failing
        exec 1>&2
        echo
        echo "-- $1 --"
        cat -
        echo '--'
        echo
    }

    #
    #    actual
    #    expected
    #    message?
    assert_equal() {
        declare -r _msg=${3:-}

        if [[ $1 != "$2" ]]; then
            batslib_print_kv_single_or_multi 8 \
                'expected' "'$2'" \
                'actual' "'$1'" |
                batslib_decorate "assert_equal failed: $_msg" |
                fail
        fi
    }

    #
    #    actual
    #    expected
    #    message?
    assert_not_equal() {
        declare -r _msg=${3:-}

        if [[ $1 != "$2" ]]; then return 0; fi

        batslib_print_kv_single_or_multi 8 \
            'unexpected value' "'$2'" |
            batslib_decorate "assert_not_equal failed: $_msg" |
            fail
    }
}
