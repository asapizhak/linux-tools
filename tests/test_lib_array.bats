#!/usr/bin/env bats

DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
. "$DIR/testhelper.bash"

function setup() {
    . "$DIR/../lib/lib_array.sh"

    testhelpGenericSetup
}


@test "arrJoin works" {
    declare output=

    arrJoin output ";:;" "1" "22" "aka3"

    assert_equal "$output" "1;:;22;:;aka3"
}