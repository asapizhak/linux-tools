#!/usr/bin/env bats

function setup() {
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

    assert_equal() {
    if [[ $1 != "$2" ]]; then
        batslib_print_kv_single_or_multi 8 \
        'expected' "'$2'" \
        'actual'   "'$1'" \
        | batslib_decorate 'values do not equal' \
        | fail
    fi
  }

    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    
    . "$DIR/../lib/lib_string_fn.sh"
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