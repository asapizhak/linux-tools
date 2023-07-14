#!/usr/bin/env bats

load testhelper.bash

function setup() {
    . "$BATS_WORKSPACE/build/lib/lib_array.sh"

    testhelpGenericSetup
}

@test "smoke" {
    return 0
}

@test "arrJoin works" {
    declare output=

    arrJoin output ";:;" "1" "22" "aka3"

    assert_equal "$output" "1;:;22;:;aka3"
}