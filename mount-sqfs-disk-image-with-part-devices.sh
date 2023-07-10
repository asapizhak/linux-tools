#!/usr/bin/env bash

set -u
set -e
# set -x

. lib/lib_core.sh
# . lib/lib_fs.sh
. lib/lib_input_args.sh
# . lib/lib_number_fn.sh
# . lib/lib_string_fn.sh

script_name=$(basename "$0")

function usage {
    # shellcheck disable=SC2317
    echo2 "\
Usage:
    $script_name -i <image_file>
"
}

function getImagesToMount {
    declare -r dir="$1"
    declare -n f_out=$2

    [[ ! -d $dir ]] && fail "'$dir' is not a directory."
    [[ ! -x $dir ]] && fail "'$dir' has no traverse access."


    declare -a files_img=()
    declare -a files_other=()

    while IFS= read -r file; do
        case "$file" in
        *.img)
            files_img+=("$file")
            ;;
        *)
            files_other+=("$file")
            ;;
        esac
    done <<< "$(find "$dir" -type f)"

    f_out+=( "${files_img[@]}" "${files_other[@]}" )
}

declare sqfs_mount_dir
sqfs_mount_dir=$(mktemp -d)

declare -i sqfs_mounted=0

main() {
    ensureCommands mktemp

    declare -A opts
    getInputArgs opts ':i:' "$@"

    declare -r image_file="${opts['i']:-''}"
    if [[ ! -f $image_file ]] || [[ ! -r $image_file ]]; then
        fail "Image file '$image_file' does not exist or has no read permission."
    fi

    # 0. if luks-encrypted (have .enc.sqfs extension) - decrypt device
    # mount sqfs image into temp dir
    mount -o loop --read-only "$image_file" "$sqfs_mount_dir"
    sqfs_mounted=1
    declare sqfs_loop_device
    # losetup --find --show "$image_file"
    sqfs_loop_device=$(losetup -j "$image_file")
    echo2 "Sqfs mounted to: $sqfs_loop_device"
    # show indexed list of image files + other files
    declare -a files
    getImagesToMount "$sqfs_mount_dir" files

    # if there is one image file - mount it. Else, give user the aility to select right file
    # todo:
    for file in "${files[@]}"; do
        echo "F:> $(realpath --relative-to="$sqfs_mount_dir" "$file")"
    done
    # allow user to choose img file to mount
    # mount img file from that dir using losetup -P for partitions check
    # wait for termination
    # on termination - unmount in reverse order.

}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    [[ $cleanup_run -ne 0 ]] && return 0

    # revert mount operations
    [[ $sqfs_mounted -eq 1 ]] && {
        umount "$sqfs_mount_dir"
        sqfs_mounted=0
    }
    # clear temp stuff
    [[ -d $sqfs_mount_dir ]] && {
        rm -r "$sqfs_mount_dir"
        sqfs_mount_dir=''
    }

    cleanup_run=1
    echo2 "Cleanup done (${1})"
}
trapWithSigname cleanup EXIT SIGINT SIGTERM

main "$@"
