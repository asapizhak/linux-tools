#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib_core.sh"


# returns package name using command name or full executable path
#    cmd - name or path
#    out_pkg_name
function pkgGetCommandPackage {
    coreEnsureCommands dpkg-query
    declare -r cmd="$1"
    declare -n out_pkg_name=$2

    declare cmd_full=
    if [[ $cmd == /* ]]; then cmd_full="$cmd"; else cmd_full=$(which "$cmd"); fi

    # shellcheck disable=SC2034
    out_pkg_name="$(dpkg-query -S "$cmd_full" | cut -d ':' -f 1)"
}

#    pkg - package name
#    out_version
function pkgGetPackageVersion {
    declare -r pkg="$1"
    declare -n out_version=$2

    # shellcheck disable=SC2034
    out_version="$(dpkg-query -f '${Version}' -W "$pkg")"
}

# Compare version numbers, where op is a binary operator. There are two groups of operators,
#  which differ in how they treat  an  empty ver1  or ver2.
#  These treat an empty version as earlier than any version: lt le eq ne ge gt.
#  These treat an empty version as later than any version: lt-nl le-nl ge-nl gt-nl.
#  These are provided only for compatibility: <  <<  <=  =  >= >> >.
#  The < and > operators are obsolete and should not be used, due to confusing semantics.
#  To illustrate: 0.1 < 0.1 evaluates to true.
#
#    out_equal - 1 if true, 0 if false
#    v1
#    op
#    v2
function pkgAreEqualVersionStrings {
    coreEnsureCommands dpkg
    declare -n out_equal=$1
    declare -r v1=$2
    declare -r op=$3
    declare -r v2=$4

    out_equal=$(set +e; dpkg --compare-versions "$v1" "$op" "$v2"; echo $?)
    if [[ $out_equal -eq 0 ]]; then out_equal=1; else out_equal=0; fi
}
