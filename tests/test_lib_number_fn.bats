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
    
    . "$DIR/../lib/lib_number_fn.sh"
}

@test "numDivFrac works" {
    declare out
    numDivFrac 10 3 out

    assert_equal "$out" '3.333333'
}

### >
@test "numCompFrac > when a > b" {
    numCompFrac 5 '>' 2
}

@test "numCompFrac > when a !> b" {
    ! numCompFrac 3 '>' 4
}

@test "numCompFrac > when a == b" {
    ! numCompFrac 3 '>' 3
}

### >=
@test "numCompFrac >= when a > b" {
    numCompFrac 5 '>=' 2
}

@test "numCompFrac >= when a !> b" {
    ! numCompFrac 3 '>=' 4
}

@test "numCompFrac >= when a == b" {
    numCompFrac 3 '>=' 3
}

### <
@test "numCompFrac < when a < b" {
    numCompFrac 2 '<' 3
}

@test "numCompFrac < when a !< b" {
    ! numCompFrac 4168 '<' 365
}

@test "numCompFrac < when a == b" {
    ! numCompFrac 6375 '<' 6375
}

### <=
@test "numCompFrac <= when a < b" {
    numCompFrac 2 '<=' 3
}

@test "numCompFrac <= when a !< b" {
    ! numCompFrac 4168 '<=' 365
}

@test "numCompFrac <= when a == b" {
    numCompFrac 6375 '<=' 6375
}

@test "numDisplayAsSize bytes" {
    declare out
    numDisplayAsSize 120 out
    
    assert_equal "$out" '120B'
}

@test "numDisplayAsSize KB" {
    declare out
    numDisplayAsSize 184320 out
    
    assert_equal "$out" '180KiB'
}

@test "numDisplayAsSize MB" {
    declare out
    numDisplayAsSize 536870912 out
    
    assert_equal "$out" '512MiB'
}

@test "numDisplayAsSize GB" {
    declare out
    numDisplayAsSize 21474836480 out
    
    assert_equal "$out" '20GiB'
}

@test "numDisplayAsSize TB" {
    declare out
    numDisplayAsSize $((1610612736 * 1024)) out

    assert_equal "$out" '1.5TiB'
}

@test "numPercentageFrac default precision" {
    declare out
    numPercentageFrac out 5.123456 10

    assert_equal "$out" '51.23'
}

@test "numPercentageFrac with precision" {
    declare out
    numPercentageFrac out 5.123456 10 3

    assert_equal "$out" '51.234'
}
