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
    $script_name -i <image_file> -d <dir_for_partition_mount>

    -i                       specifies sqfs file that will be mounted
    -d                       specifies the directory in which subdirs
                             will be created for image partitions
"
}

function validateInputArgs {
    declare -r image_file=$1
    declare -r dir_partition_mount=$2

    if [[ ! -f $image_file ]] || [[ ! -r $image_file ]]; then
        fail "Image file '$image_file' does not exist or has no read permission."
    fi

    if [[ -z "$dir_partition_mount" ]]; then
        failWithUsage "Destination directory does not exist ($dir_partition_mount)"; fi
    if [[ ! -d "$dir_partition_mount" ]]; then
        failWithUsage "Destination directory is not a directory ($dir_partition_mount)"; fi
    if [[ ! -w "$dir_partition_mount" ]]; then
        fail "Destination directory is not writable ($dir_partition_mount)"; fi
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
    uiPushColor2 'green'
    echo2 "Image mounted to $image_mount_device"
    uiPopColor2
}

#
#    device
#    out_partitions
function getPartitions {
    declare -r device=$1
    declare -n out_partitions=$2

    for part in "$device"*; do
        if [[ $part = "$image_mount_device" ]]; then continue; fi

        out_partitions+=("$part")
    done
}

#
#    part_name
#    out_info ['name', 'label', 'type']
function getPartitionInfo {
    declare -r part_name=$1
    declare -n out_info=$2

    out_info['name']="$part"
    out_info['label']=$(blkid -o value -s LABEL "$part_name")
    out_info['type']=$(blkid -o value -s TYPE "$part_name")

    getStorageObjectSize "$part" size
    declare size_display; numDisplayAsSize "$size" size_display

    # shellcheck disable=SC2034
    out_info['size']=$size_display
}

#
#    out_selected_part
function selectImagePartitionToMount {
    declare -n parts=$1
    declare -n out_selected_part=$2

    declare -a parts_with_info=()

    for part in "${parts[@]}"; do
        declare -A part_info=(); getPartitionInfo "$part" part_info

        declare info_str; arrJoin info_str '; ' "${part_info[@]}"
        parts_with_info+=("$part; $info_str")
    done

    declare -r placeholder_empty="None found."
    declare -r placeholder_skip="Don't mount partition"

    if [[ ${#parts_with_info[@]} -eq 0 ]]; then
        parts_with_info+=("$placeholder_empty")
        echo2 "Partitions not found."
    else
        echo2 "Partitions found:"
        uiPushColor2 'magenta'
        for p in "${parts[@]}"; do
            echo2 "  - $p"
        done
        uiPopColor2
        parts_with_info+=("$placeholder_skip")
    fi

    declare -i selected_idx
    uiListWithSelection selected_idx parts_with_info 0 "Select partition to mount"

    declare -r user_selection="${parts_with_info[$selected_idx]}"
    if [[ $user_selection = "$placeholder_empty" || $user_selection = "$placeholder_skip" ]]; then
        out_selected_part=
    else
        # shellcheck disable=SC2034
        out_selected_part="${parts[$selected_idx]}"
    fi
}

declare -i sqfs_mounted=0
declare -a dirs_created=()
declare -a dirs_mounted=()

function mountPartitionToDir {
    declare -r partition=$1
    declare -r dir_mount=$2

    if [[ ! -d "$dir_mount" ]]; then
        fail "Dir to mount '$partition' does not exist or is not a directory ($dir_mount)"; fi

    if [[ -b $partition ]]; then
        mount --read-only "$partition" "$dir_mount"
    else
        mount -o loop --read-only "$partition" "$dir_mount"
    fi

    dirs_mounted+=("$dir_mount")

    uiPushColor2 'green'
    printf2 "Partition '"
    uiPushColor2 'magenta'
    printf2 "%s" "$partition"
    uiPopColor2
    echo2 "' mounted to '$dir_mount'"
    uiPopColor2
}

function checkAndMountPartitionToSubdir {
    declare -r partition=$1

    if [[ -z $partition ]]; then
        echo2 "No partition, will not mount."
        return 0
    fi

    declare basename_partition; basename_partition=$(basename "$partition")
    if [[ -z "$basename_partition" ]]; then
        echo2 "Error: empty basename"
        return 0
    fi

    declare -r subdir="$basename_partition"
    declare partition_dir=
    fsJoinPaths partition_dir "$dir_partition_mount" "$subdir"

    if [[ ! -e "$partition_dir" ]]; then
        mkdir -v "$partition_dir"
        dirs_created+=("$partition_dir")
    else
        echo2 "Partition dir '$partition_dir' already exist"
        [[ ! -d "$partition_dir" ]] && echo2 "Partition dir '$partition_dir' is not a directory, won't mount"
        if mountpoint -q "$partition_dir"; then
            echo2 "Partition dir '$partition_dir' is already a mount point, won't mount"
            return 0
        fi
    fi
    mountPartitionToDir "$partition" "$partition_dir"
}

main() {
    ensureCommands mktemp losetup realpath blkid blockdev cut mountpoint

    declare -A opts
    getInputArgs opts ':i:d:' "$@"

    declare -r image_file="${opts['i']:-}"
    declare -r dir_partition_mount=$"${opts['d']:-}"
    validateInputArgs "$image_file" "$dir_partition_mount"

    # ? if luks-encrypted (have .enc.sqfs extension) - decrypt device
    # - mount sqfs image into temp dir
    mount -o loop --read-only "$image_file" "$sqfs_mount_dir"
    sqfs_mounted=1
    declare sqfs_loop_device
    sqfs_loop_device=$(losetup -j "$image_file" | cut -d ':' -f 1)
    uiPushColor2 'green'
    echo2 "Sqfs mounted to $sqfs_loop_device, $sqfs_mount_dir"
    uiPopColor2

    # - allow user to choose img file to mount
    # shellcheck disable=SC2034
    declare -a sqfs_files
    getSqfsFileList "$sqfs_mount_dir" sqfs_files

    declare image_to_mount
    getImageToMount sqfs_files image_to_mount

    echo2 "Will mount '$(getSqfsRelativePath "$image_to_mount")'"
    # - mount selected img file from that dir using losetup -P for partition devices
    mountImageFile "$image_to_mount"

    # shellcheck disable=SC2034
    declare -a dev_partitions=()
    getPartitions "$image_mount_device" dev_partitions

    declare selected_partition
    selectImagePartitionToMount dev_partitions selected_partition

    # mount selected partition into subdir of mount directory
    checkAndMountPartitionToSubdir "$selected_partition"

    # - wait for termination
    echo2 "Now do your work, then press any key 3 times to unmount everything"
    declare -i i=3
    printf2 "%d" $i
    while [[ $i -ne 0 ]]; do
        read -rsN1
        ((i--))
        printf2 "\b%d" $i
    done
    printf2 "\b"
    # - on termination - unmount in reverse order. - done in cleanup
}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    [[ $cleanup_run -ne 0 ]] && return 0

    tput cnorm # reset cursor to normal
    sleep 0.5 # slight delay in case devices were just created and are busy. Not 100% proof but usually enough.
    uiPushColor2 'cyan'
    echo2 "Running cleanup."
    uiPopColor2
    # revert mount operations
    ## unmount partitions
    for d in "${dirs_mounted[@]}"; do
        if ! umount "$d"; then echo2 "Failed to unmount '$d', do it manually!"
        else echo2 "Unmounted partition from '$d'"
        fi
    done
    ## delete partition mount dirs
    for d in "${dirs_created[@]}"; do
        if ! fsDirectoryHasContent "$d"; then printf2 "Removing empty dir '%s'..." "$d"; rm -r "$d" && echo2 " Removed."
        else echo2 "Dir '$d' is not empty, check and remove manually after script run" ; fi
    done
    ## unmount image file from device
    [[ -n $image_mount_device ]] && {
        losetup -d "$image_mount_device"
        echo2 "Unmounted image from $image_mount_device."
        image_mount_device=''
    }
    ## unmount squashfs image
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
