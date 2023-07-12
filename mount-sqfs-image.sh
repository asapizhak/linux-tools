#!/usr/bin/env bash

set -u
set -e
# set -x

. lib/lib_core.sh
. lib/lib_array.sh
. lib/lib_fs.sh
. lib/lib_input_args.sh
. lib/lib_number_fn.sh
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

#
#    path
function getSqfsRelativePath {
    declare -r path=$1

    if [[ -n $sqfs_mount_dir ]];then
        printf "%s" "$(realpath --relative-to="$sqfs_mount_dir" "$path")"
    else
        printf "%s" "$path"
    fi
}

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

        for file in "${list_files[@]}"; do
            declare name
            name=$(realpath --relative-to="$sqfs_mount_dir" "$file")
            file_names+=("$name")
        done

        uiListWithSelection selected_idx file_names 0 "Select image to mount"
        # shellcheck disable=SC2034
        out_selected_file="${list_files[$selected_idx]}"
    fi
}

declare image_mount_device=''

#
#    image_file
function mountImageFile {
    declare -r image_file="$1"

    image_mount_device=$(losetup --find --show -r -P "$image_file")
    echo2 "Image mounted to $image_mount_device"
}

#
#    out_selected_part
function selectImagePartitionToMount {
    declare -n out_selected_part=$1

    declare -a parts=()
    for part in "$image_mount_device"*; do
        [[ $part != "$image_mount_device" ]] && {
            declare -A part_info
            part_info['label']=$(blkid -o value -s LABEL "$part")
            part_info['type']=$(blkid -o value -s TYPE "$part")
            getStorageObjectSize "$part" size
            declare size_display; numDisplayAsSize "$size" size_display
            part_info['size']=$size_display
            declare info_str
            arrJoinWith info_str ' ; ' "${part_info[@]}"
            parts+=("$part ; $info_str")
        }
    done

    declare placeholder_empty="None found. Select to quit"

    if [[ ${#parts[@]} -eq 0 ]]; then
        parts+=("$placeholder_empty")
        echo2 "Partitions not found."
    else
        echo2 "Partitions found: ${#parts[@]}"
    fi

    declare -i selected_idx
    uiListWithSelection selected_idx parts 0 "Select partition to mount"

    if [[ ${parts[$selected_idx]} = "$placeholder_empty" ]]; then
        out_selected_part=''
    else
        # shellcheck disable=SC2034
        out_selected_part="${parts[$selected_idx]}"
    fi
}

declare -i sqfs_mounted=0

main() {
    ensureCommands mktemp losetup realpath blkid blockdev cut

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
    sqfs_loop_device=$(losetup -j "$image_file" | cut -d ':' -f 1)
    echo2 "Sqfs mounted to: $sqfs_loop_device, $sqfs_mount_dir"

    # - allow user to choose img file to mount
    # shellcheck disable=SC2034
    declare -a sqfs_files
    getSqfsFileList "$sqfs_mount_dir" sqfs_files

    declare image_to_mount
    getImageToMount sqfs_files image_to_mount

    echo2 "Will mount '$(getSqfsRelativePath "$image_to_mount")'"
    # - mount selected img file from that dir using losetup -P for partition devices
    mountImageFile "$image_to_mount"

    declare selected_partition
    selectImagePartitionToMount selected_partition
    echo2 "PART: $selected_partition"
    # - wait for termination
    # - on termination - unmount in reverse order.
}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    [[ $cleanup_run -ne 0 ]] && return 0

    tput cnorm # reset cursor to normal
    sleep 0.5 # slight delay in case devices were just created and are busy. Not 100% proof but usually enough.
    echo2 "Running cleanup."
    # revert mount operations
    [[ -n $image_mount_device ]] && {
        losetup -d "$image_mount_device"
        echo2 "Unmounted image from $image_mount_device."
        image_mount_device=''
    }

    [[ $sqfs_mounted -eq 1 ]] && {
        umount "$sqfs_mount_dir"
        echo2 "Unmounted squashfs."
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
