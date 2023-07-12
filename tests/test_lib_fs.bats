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

    #
    #    actual
    #    expected
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
    
    . "$DIR/../lib/lib_fs.sh"
}

@test "fsDirectoryHasContent returns OK status when there is a subdir" {
    set -e
    declare tmpdir; tmpdir=$(mktemp -d)

    mkdir "$tmpdir/deleteme.dir"

    fsDirectoryHasContent "$tmpdir"

    rm -r "$tmpdir"
    set +e
}

@test "fsDirectoryHasContent returns OK status when there is a file" {
    set -e
    declare tmpdir; tmpdir=$(mktemp -d)

    touch "$tmpdir/deleteme.file"

    fsDirectoryHasContent "$tmpdir"

    rm -r "$tmpdir"
    set +e
}

@test "fsDirectoryHasContent returns error status when there is no content" {
    set -e
    declare tmpdir; tmpdir=$(mktemp -d)

    ! fsDirectoryHasContent "$tmpdir"

    rm -r "$tmpdir"
    set +e
}


@test "fsJoinPaths works" {
    declare out_path='/part1'

    fsJoinPaths out_path "part2" "part3"

    assert_equal "$out_path" "/part1/part2/part3"
}

@test "fsJoinPaths handles paths that end with slash correctly (path1/ + path2)" {
    declare out_path='/part1/'

    fsJoinPaths out_path "part2"

    assert_equal "$out_path" "/part1/part2"
}

@test "fsJoinPaths fails when join absolute path" {
    declare out_path='/part1'

    run fsJoinPaths out_path '/part2'

    [[ "$status" -ne 0 ]]
}
