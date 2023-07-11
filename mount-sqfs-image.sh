#!/usr/bin/env bash

set -u
set -e
# set -x

. lib/lib_core.sh
# . lib/lib_fs.sh
. lib/lib_input_args.sh
# . lib/lib_number_fn.sh
# . lib/lib_string_fn.sh
. lib/lib_ui.sh

script_name=$(basename "$0")

function usage {
    # shellcheck disable=SC2317
    echo2 "\
Usage:
    $script_name -i <image_file>
"
}

# getSqfsFileList
#    dir_path
#    out_files_arr
function getSqfsFileList {
    declare -r dir="$1"
    declare -n out_files=$2

    [[ ! -d $dir ]] && fail "'$dir' is not a directory."
    [[ ! -x $dir ]] && fail "'$dir' has no traverse access."

    declare -a files_img=()
    declare -a files_other=()

    declare file
    while IFS= read -r file; do
        case "$file" in
        *.img)
            files_img+=("$file")
            ;;
        *)
            files_other+=("$file")
            ;;
        esac
    done <<<"$(find "$dir" -type f)"

    # shellcheck disable=SC2034
    out_files=( "${files_img[@]}" "${files_other[@]}" )
}

declare sqfs_mount_dir
sqfs_mount_dir=$(mktemp -d)

# getImageToMount
#    list_files
#    out_selected_file
function getImageToMount {
    declare -rn list_files=$1
    declare -n out_selected_file=$2

    declare -ri file_count=${#list_files[@]}

    if [[ $file_count -eq 0 ]]; then
        fail "No files in sqfs"
    elif [[ $file_count -eq 1 ]]; then
        out_selected_file="${list_files[0]}"
    else
        declare -i selected_idx
        declare -a file_names
        echo2 "DIR: $sqfs_mount_dir"
        for file in "${list_files[@]}"; do
            declare name
            name=$(realpath --relative-to="$sqfs_mount_dir" "$file")
            file_names+=("$name")
        done

        uiListWithSelection selected_idx file_names 0 "Select image to mount"
        out_selected_file="${list_files[$selected_idx]}"
    fi
}

declare -i sqfs_mounted=0

main() {
    ensureCommands mktemp

    declare -A opts
    getInputArgs opts ':i:' "$@"

    declare -r image_file="${opts['i']:-''}"
    if [[ ! -f $image_file ]] || [[ ! -r $image_file ]]; then
        fail "Image file '$image_file' does not exist or has no read permission."
    fi

    # ? if luks-encrypted (have .enc.sqfs extension) - decrypt device
    # - mount sqfs image into temp dir
    mount -o loop --read-only "$image_file" "$sqfs_mount_dir"
    sqfs_mounted=1
    declare sqfs_loop_device
    sqfs_loop_device=$(losetup -j "$image_file")
    echo2 "Sqfs mounted to: $sqfs_loop_device"

    # - allow user to choose img file to mount
    declare -a sqfs_files
    getSqfsFileList "$sqfs_mount_dir" sqfs_files

    declare image_to_mount
    getImageToMount sqfs_files image_to_mount

    echo2 "Will mount '$image_to_mount'"
    # - mount selected img file from that dir using losetup -P for partition devices
    # - wait for termination
    # - on termination - unmount in reverse order.
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