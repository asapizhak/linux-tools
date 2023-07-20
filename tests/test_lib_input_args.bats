#!/usr/bin/env bats

load testhelper.bash

function setup() {
    . "$BATS_WORKSPACE/build/lib/lib_input_args.sh"

    testhelpGenericSetup
}

@test "smoke" {
    return 0
}

@test "getInputArgs parses args without parameters" {
    declare -A opts
    getInputArgs opts ':t:wk' '-k' '-w' '-t' 110

    assert_equal "${#opts[@]}" 3 'opts count'
    assert_equal "${opts[w]}" '1' 'opt w'
    assert_equal "${opts[k]}" '1' 'opt k'
}

@test "getInputArgs parses args with parameters" {
    declare -A opts
    getInputArgs opts ':t:wks:' '-k' '-s' 120 '-w' '-t' 110

    assert_equal "${#opts[@]}" 4 'opts count'
    assert_equal "${opts[s]}" '120' 'opt s'
    assert_equal "${opts[t]}" '110' 'opt t'
}
