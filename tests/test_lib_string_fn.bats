#!/usr/bin/env bats

load testhelper.bash

function setup() {
    . "$BATS_WORKSPACE/build/lib/lib_string_fn.sh"

    testhelpGenericSetup
}

@test "smoke" {
    return 0
}

@test "strPadString pads left correctly" {
    declare out=
    strPadString 'lala' 6 out

    assert_equal "$out" "  lala"
}

@test "strPadString pads right correctly" {
    declare out=
    strPadString 'lala' -6 out

  echo ${#out}
    assert_equal "$out" "lala  "
}

@test "strPadString accepts lower max than string length" {
    declare out=
    strPadString 'lala' 0 out

    assert_equal "$out" "lala"
}

@test "isPositiveIntString returns ok on 1 digit positives" {
    isPositiveIntString 5
}

@test "isPositiveIntString returns ok on 2 digit positives" {
    isPositiveIntString 10
}

@test "isPositiveIntString returns ok on 3 digit positives" {
    isPositiveIntString 541
}

@test "isPositiveIntString fails on 1-digit negative numbers" {
    ! isPositiveIntString -3
}

@test "isPositiveIntString fails on 2-digit negative numbers" {
    ! isPositiveIntString -10
}
