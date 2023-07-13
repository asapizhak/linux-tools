#!/usr/bin/env bats

DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
. "$DIR/testhelper.bash"

function setup() {
    . "$DIR/../lib/lib_core_stack.sh"

    testhelpGenericSetup
}

@test "smoke" {
    return 0
}

@test "stackPush works" {
    declare -a stack=()

    stackPush stack "557a"
    stackPush stack "kb4"

    assert_equal "${#stack[@]}" 2 "stack size" && \
    assert_equal "${stack[0]}" "557a" "first element" && \
    assert_equal "${stack[1]}" "kb4" "second element"
}

@test "stackPop works" {
    declare -a stack=("557a" "kb4")
    declare elem

    assert_equal "${#stack[@]}" 2 "stack size before test"

    stackPop stack elem

    assert_equal "${#stack[@]}" 1 "stack size" && \
    assert_equal "${stack[0]}" "557a" "first element"
}

@test "stackPop handles stack with 0 elements" {
    declare -a stack=()
    declare elem

    assert_equal "${#stack[@]}" 0 "stack size before test"

    stackPop stack elem

    assert_equal "${#stack[@]}" 0 "stack size" && \
    [[ -z $elem ]]
}

@test "stackPop returns but not removes last element in peek mode" {
    declare -a stack=("557a" "kb4")
    declare elem

    assert_equal "${#stack[@]}" 2 "stack size before test"

    stackPop stack elem 1

    assert_equal "$elem" "kb4" && \
    assert_equal "${#stack[@]}" 2 "stack size" && \
    assert_equal "${stack[0]}" "557a" "first element" && \
    assert_equal "${stack[1]}" "kb4" "second element"
}