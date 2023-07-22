#!/usr/bin/env bash

set -u
set -e
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/lib/lib_core.sh"
. "$SCRIPT_DIR/lib/lib_array.sh"
. "$SCRIPT_DIR/lib/lib_fs.sh"
. "$SCRIPT_DIR/lib/lib_input_args.sh"
. "$SCRIPT_DIR/lib/lib_number_fn.sh"
. "$SCRIPT_DIR/lib/lib_ui.sh"

script_name=$(basename "$0")

function usage {
    # shellcheck disable=SC2317
    echo2 "\
Usage:
    $script_name -i <input_object> -d <dir_for_partition_mount>

    -i                       specifies sqfs file or device that will be mounted
    -d                       specifies the directory in which subdirs
                             will be created for image partitions
Exit codes:
    1                        Generic exit code
    $EXIT_CODE_NO_INPUT_ARGS                       No input arguments provided
"
}

function validateInputArgs {
    declare -n _opts=$1

    # input object
    declare -r input_object="${_opts['i']}"
    [[ -z $input_object ]] && coreFailExitWithUsage
    if [[ ! -e $input_object ]]; then coreFailExit "Input object '$input_object' does not exist."; fi
    if [[ ! -r $input_object ]]; then coreFailExit "Input object '$input_object' has no read permission."; fi

    # dir for mounts
    declare -r dir_partition_mount="${_opts['d']}"
    if [[ -z "$dir_partition_mount" ]]; then
        coreFailExitWithUsage "Destination directory does not exist ($dir_partition_mount)"; fi
    if [[ ! -d "$dir_partition_mount" ]]; then
        coreFailExitWithUsage "Destination directory is not a directory ($dir_partition_mount)"; fi
    if [[ ! -w "$dir_partition_mount" ]]; then
        coreFailExit "Destination directory is not writable ($dir_partition_mount)"; fi
}

# getSqfsMountableFiles
#    dir_path
#    out_files_arr
function getSqfsMountableFiles {
    declare -r dir="$1"
    declare -n out_files=$2

    [[ ! -d $dir ]] && coreFailExit "'$dir' is not a directory."
    [[ ! -x $dir ]] && coreFailExit "'$dir' has no traverse access."

    out_files=()

    declare file is_blockdev_file
    while IFS= read -r file; do

        fsIsBlockDeviceFile "$file" is_blockdev_file

        if [[ $is_blockdev_file -eq 1 ]]; then
            out_files+=("$file")
        fi
    done <<<"$(find "$dir" -type f)"
}

declare sqfs_mount_dir
sqfs_mount_dir=$(mktemp -dt -- "mount-sqfs-backup-XXX")

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
        coreFailExit "No files in sqfs"
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
#    input_object
function mountImageFile {
    declare -r input_object="$1"

    image_mount_device=$(losetup --find --show -r -P "$input_object")
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
        coreFailExit "Dir to mount '$partition' does not exist or is not a directory ($dir_mount)"; fi

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
        echo2 "No partition will be mount."
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
    coreEnsureCommands mktemp losetup realpath blkid blockdev cut mountpoint

    coreEnsureRunByRoot "We need to be able to mount/unmount things"

    inputExitIfNoArguments "$@"

    declare -A opts
    getInputArgs opts ':i:d:' "$@"

    validateInputArgs opts

    declare -r input_object="${opts['i']}"
    declare -r dir_partition_mount=$"${opts['d']}"

    # ? if luks-encrypted (have .enc.sqfs extension) - decrypt device
    # - mount sqfs image into temp dir
    printf2 "Mounting input"
    if [[ -b $input_object ]]; then
        printf2 " device..."
        mount --read-only "$input_object" "$sqfs_mount_dir"
        sqfs_mounted=1
        F_COLOR=magenta echo2 " $sqfs_mount_dir"
    elif [[ -f $input_object ]]; then
        printf2 " file..."
        mount -o loop --read-only "$input_object" "$sqfs_mount_dir"
        sqfs_mounted=1
        declare sqfs_loop_device
        sqfs_loop_device=$(losetup -j "$input_object" | cut -d ':' -f 1)
        F_COLOR=magenta echo2 " $sqfs_loop_device $sqfs_mount_dir"
    else
        coreFailExit "This type of input object is not supported"
    fi

    # - allow user to choose img file to mount
    echo2 "Scanning files..."
    # shellcheck disable=SC2034
    declare -a sqfs_files
    getSqfsMountableFiles "$sqfs_mount_dir" sqfs_files

    declare image_to_mount
    getImageToMount sqfs_files image_to_mount

    # TODO: determine if selected image is a partition or has partition table, and mount accordingly.

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
    tput sc
    declare -i i=3
    while [[ $i -ne 0 ]]; do
        echo2 "Now do your work, then press any key $i times to unmount everything"
        read -rsN1
        ((i--))
        tput rc; tput ed
    done
    # - on termination - unmount in reverse order. - done in cleanup
}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    [[ $cleanup_run -ne 0 ]] && return 0

    tput cnorm # reset cursor to normal
    sleep 0.5 # slight delay in case devices were just created and are busy. Not 100% proof but usually enough.

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
}
trapWithSigname cleanup EXIT SIGINT SIGTERM

main "$@"
