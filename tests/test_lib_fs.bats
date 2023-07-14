#!/usr/bin/env bats

load testhelper.bash

function setup() {
    . "$BATS_WORKSPACE/build/lib/lib_fs.sh"

    testhelpGenericSetup
}

@test "smoke" {
    return 0
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

@test "fsJoinPaths fails when joining absolute path" {
    declare out_path='/part1'

    # somehow "run !" does not work here, just passes ok
    run fsJoinPaths out_path '/part2'

    assert_not_equal "$status" 0 "Status code"
}

@test "fsJoinPaths don't fail when out var is empty and first path is absolute path" {
    declare out_path=''

    fsJoinPaths out_path '/part1' 'part2' && assert_equal "$out_path" "/part1/part2"
}
