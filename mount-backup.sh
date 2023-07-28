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
    -v                                  Don't mount, verify sha1 and parity if exists
Exit codes:
    1                        Generic exit code
    $EXIT_CODE_NO_INPUT_ARGS                       No input arguments provided
"
}

function normalizeValidateInputArgs {
    declare -n _opts=$1

    # input object
    declare -r input_object="${_opts['i']}"
    [[ -z $input_object ]] && coreFailExitWithUsage
    if [[ ! -e $input_object ]]; then coreFailExit "Input object '$input_object' does not exist."; fi
    if [[ ! -r $input_object ]]; then coreFailExit "Input object '$input_object' has no read permission."; fi

    # dir for mounts
    declare -r mount_dir="${_opts['d']}"
    if [[ -z "$mount_dir" ]]; then
        coreFailExitWithUsage "Destination directory does not exist ($mount_dir)"; fi
    if [[ ! -d "$mount_dir" ]]; then
        coreFailExitWithUsage "Destination directory is not a directory ($mount_dir)"; fi
    # todo: remove this check. It doesn't have to be writable to mount something there (I guess, needs checking)
    if [[ ! -w "$mount_dir" ]]; then
        coreFailExit "Destination directory is not writable ($mount_dir)"; fi

    # verify
    _opts['v']="${_opts['v']:-0}"
}

declare -r PAR2_CMD=par2

# input args
declare arg_input_object
declare arg_mount_dir
declare -i verify_only

# returns an error when checksum is not correct.
# If not able to verify, returns ok but sets the correspondent variable
#    out_able_to_verify (0,1)
function verifySha {
    declare -n out_able_to_verify=$1

    echo2 "Verifying sha"

    if [[ ! -f $arg_input_object ]]; then
        # shaXXXsum alone will help here.
        coreFailExit "Cannot verify sha for device - no way to determine sha file name."
    fi

    declare -r input_file="$arg_input_object"
    declare input_file_basename; input_file_basename="$(basename "$input_file")"
    declare input_file_dir; input_file_dir="$(dirname "$input_file")"

    # find sha files for input file
    declare -a sha_files=()
    readarray -t sha_files < <(find "$input_file_dir" -maxdepth 1 -type f -name "${input_file_basename}.sha*")
    if [[ -z "${sha_files:-}" ]]; then sha_files=(); fi
    echo2 "Found ${#sha_files[@]} sha files for input file"

    if [[ ${#sha_files[@]} -lt 1 ]]; then
        echo2warn "No sha files, cannot verify"
        out_able_to_verify=0
        return 0
    fi

    # find first sha command for found files
    declare sha_file='' sha_cmd=''
    for f in "${sha_files[@]}"; do
        printf2 "Checking $(basename "$f") command... "
        declare ext="${f##*.}"
        declare cmd="${ext}sum"
        if coreCommandsArePresent 1 "$cmd"; then
            sha_file="$f"
            sha_cmd="$cmd"
            echo2success "Found."
            break
        else
            echo2warn "Not found."
        fi
    done

    if [[ -z "$sha_cmd" ]]; then
        out_able_to_verify=0
        echo2warn "No commands found to verify the files"
        return 0
    fi

    echo2 "Verifying checksum (this may take some time, depending on input size)..."
    if $sha_cmd -c --status "$sha_file"; then
        echo2success "${sha_file##*.} sum OK"
        # shellcheck disable=SC2034
        out_able_to_verify=1
        return 0
    else
        coreFailExit "${sha_file##*.} sum does not match!"
    fi
}

# returns an error when parity data is not verified correctly.
# If not able to verify, returns ok but sets the correspondent variable
#    out_able_to_verify (0,1)
function verifyPar {
    declare -n out_able_verify_par=$1

    if [[ ! -f $arg_input_object ]]; then
        # par2 v will help in custom cituations
        coreFailExit "Parity can be verified automatically only for file - no way to determine par2 file name."
        # todo: low priority - add ability to specify sha/par2 files
    fi

    declare -r input_file="$arg_input_object"
    declare par_file; par_file="${input_file}.par2"

    echo2 "Verifying parity"

    printf2 "Checking $PAR2_CMD command... "
    if ! coreCommandsArePresent "$PAR2_CMD"; then
        echo2warn "Not found. Cannot verify parity."
        out_able_verify_par=0
        return 0
    fi
    echo2success "Done."

    printf2 "Checking par file... "
    if [[ -z $par_file || ! -e $par_file ]]; then
        echo2 "Not found ($par_file)."
        echo2warn "No par2 files, cannot verify"
        out_able_verify_par=0
        return 0
    fi
    echo2success "Found."

    declare exit_code=0
    if [[ -f $par_file ]]; then
        set +e
        $PAR2_CMD verify -- "$par_file"
        exit_code=$?
        set -e
        if [[ $exit_code -eq 0 ]]; then
            out_able_verify_par=1
            echo2success "Successfully verified parity data."
            return 0
        else
            coreFailExit "$PAR2_CMD returned $exit_code. Parity verification failed."
        fi

    elif [[ -d $par_file ]]; then
        pushd "$par_file" >/dev/null
        set +e
        $PAR2_CMD verify "$(basename "$par_file")" "$input_file"
        exit_code=$?
        set -e
        popd >/dev/null
        if [[ $exit_code -eq 0 ]]; then
            # shellcheck disable=SC2034
            out_able_verify_par=1
            echo2success "Successfully verified parity data."
            return 0
        else
            coreFailExit "$PAR2_CMD returned $exit_code. Parity verification failed."
        fi
    else
        coreFailExit "$par_file - invalid object type. Expected file or dir."
    fi
}

declare luks_mapped_device

# shellcheck disable=SC2317
function closeLuksDevice {
    if [[ -n ${luks_mapped_device:-} ]]; then
        printf2 "Closing LUKS decrypted device $luks_mapped_device... "
        cryptsetup close "$luks_mapped_device" && luks_mapped_device=
        F_COLOR=cyan echo2 "Done."
    fi
}

declare sqfs_mountpoint

# shellcheck disable=SC2317
function unmountSqfsMountpoint {
    [[ -n ${sqfs_mountpoint:-} ]] && {
        printf2 "Unmounting squashfs... "
        umount "$sqfs_mountpoint"
        F_COLOR=cyan echo2 "Done."
        printf2 "Deleting mountpoint... "
        rm -r "$sqfs_mountpoint"
        sqfs_mountpoint=
        F_COLOR=cyan echo2 "Done."
    }
}

# getMountableFiles
#    dir_path
#    out_files_arr
# shellcheck disable=SC2317
function getMountableFiles {
    declare -r dir="$1"
    declare -n out_files=$2

    [[ ! -d $dir ]] && coreFailExit "'$dir' is not a directory."
    [[ ! -x $dir ]] && coreFailExit "'$dir' has no x permission, cannot traverse."

    out_files=()

    declare file
    declare -A attrs

    coreProgressStart
    while IFS= read -r file; do
        coreProgressIncrement
        fsGetBlockDeviceAttrs "$file" attrs
        if [[ ${attrs['USAGE']:-} == 'filesystem' || -n ${attrs['PTTYPE']:-} ]]; then
            out_files+=("$file")
        fi
    done < <(find "$dir" -type f)
    coreProgressEnd
}

#
#    path
function getSqfsRelativePath {
    declare -r path=$1
    declare -n out_path=$2

    if [[ -n $sqfs_mountpoint ]];then
        printf -v out_path "%s" "$(realpath --relative-to="$sqfs_mountpoint" "$path")"
    else
        # shellcheck disable=SC2034
        printf -v out_path "%s" "$path"
    fi
}

#
#   file
#   out_display
function getDisplayFromFile {
    declare -r _file=$1
    declare -n out_display=$2

    declare -A attrs
    fsGetBlockDeviceAttrs "$_file" attrs
    declare name
    getSqfsRelativePath "$_file" name

    # shellcheck disable=SC2034
    out_display="$name (${attrs['TYPE']:-N/A})"
}

#
#    list_files
#    display_fn  --  a function that takes file as $1 and returns display value as out $2
#    out_selected_file
function selectFileToMount {
    declare -rn list_files=$1
    declare display_fn=$2
    declare -n out_selected_file=$3

    declare -ri file_count=${#list_files[@]}

    if [[ $file_count -eq 0 ]]; then
        coreFailExit "No files to choose from"
    elif [[ $file_count -eq 1 ]]; then
        out_selected_file="${list_files[0]}"
    else
        declare -i selected_idx
        declare -a file_names

        declare display
        for file in "${list_files[@]}"; do
            $display_fn "$file" display
            file_names+=("$display")
        done

        uiListWithSelection selected_idx file_names 0 "Select image to mount"
        # shellcheck disable=SC2034
        out_selected_file="${list_files[$selected_idx]}"
    fi
}

declare image_mount_device=''

# shellcheck disable=SC2317
function unmountImageLoopDevice {
    [[ -n ${image_mount_device:-} ]] && {
        printf2 "Unmounting image from $image_mount_device... "
        losetup -d "$image_mount_device"
        image_mount_device=''
        F_COLOR=cyan echo2 "Done."
    }
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

    # out_info['name']="$part_name"
    out_info['label']=$(blkid --probe -o value -s LABEL "$part_name")
    out_info['type']=$(blkid --probe -o value -s TYPE "$part_name")

    getStorageObjectSize "$part" size
    declare size_display; numDisplayAsSize "$size" size_display

    # shellcheck disable=SC2034
    out_info['size']=$size_display
}

#
#    out_selected_part
function selectPartitionToMount {
    declare -n parts=$1
    declare -n out_selected_part=$2

    declare -a parts_with_info=()

    for part in "${parts[@]}"; do
        declare -A part_info=(); getPartitionInfo "$part" part_info

        declare info_str; arrJoin info_str '; ' "${part_info[@]}"
        parts_with_info+=("$part; $info_str")
    done

    declare -r placeholder_skip="Don't mount partition"

    parts_with_info+=("$placeholder_skip")

    declare -i selected_idx
    uiListWithSelection selected_idx parts_with_info 0 "Select partition to mount"

    declare -r user_selection="${parts_with_info[$selected_idx]}"
    if [[ $user_selection = "$placeholder_skip" ]]; then
        out_selected_part=
    else
        # shellcheck disable=SC2034
        out_selected_part="${parts[$selected_idx]}"
    fi
}

declare -i mount_dir_mounted=0

main() {
    coreEnsureCommands mktemp losetup realpath blkid blockdev cut mountpoint
    inputExitIfNoArguments "$@"
    coreEnsureRunByRoot "We need to be able to mount/unmount things"

    declare -A opts
    getInputArgs opts ':i:d:v' "$@"
    normalizeValidateInputArgs opts

    arg_input_object="${opts['i']}"
    arg_input_object="$(realpath "$arg_input_object")"
    arg_mount_dir=$"${opts['d']}"
    arg_mount_dir="$(realpath "$arg_mount_dir")"
    verify_only="${opts['v']}"

    readonly arg_input_object arg_mount_dir verify_only

    ###############
    # Verify only #
    ###############
    if [[ $verify_only -eq 1 ]]; then
        echo2 "Verification requested, not mounting."
        declare -i able_verify_sha=1 able_verify_par=1

        verifySha able_verify_sha
        sleep 1.5
        echo2
        verifyPar able_verify_par
        sleep 1.5

        if [[ $able_verify_sha -ne 1 && $able_verify_par -ne 1 ]]; then
            coreFailExit "Failed to verify integrity."
        fi

        exit 0
    fi

    declare sqfs_object="$arg_input_object"

    #################################################
    # if input is luks-encrypted - decrypt it first #
    #################################################
    if fsIsLuksContainer "$arg_input_object"; then # todo: fix line
        printf2 "Input is a LUKS container"
        coreEnsureCommands cryptsetup
        # Mount LUKS
        declare slug; slug="$(basename "$arg_input_object")"
        slug="${slug%.luks}"
        slug="${slug%.sqfs}"
        slug="${slug%.squashfs}" # remove extensions
        
        slug="${slug// /_}" # replace spaces
        slug="${slug//[^a-zA-Z0-9_\-]/}" # remove illegal chars

        F_COLOR=gray echo2 " '$slug'"

        if [[ -f $arg_input_object ]]; then echo2 "Decrypting input file..."
        elif [[ -b $arg_input_object ]]; then echo2 "Decrypting input device..."
        fi

        cryptsetup open --type luks --readonly "$arg_input_object" "$slug"
        luks_mapped_device="$(cryptsetup status "$slug" | head -n 1 | awk '{print $1}'; true)"
        printf2success "Decrypted as"
        F_COLOR=magenta echo2 " $luks_mapped_device"

        sleep 1.5
        # read -rp "Press Enter"

        sqfs_object="$luks_mapped_device"
    fi

    ####################################
    # - mount sqfs image into temp dir #
    ####################################
    # check if it's sqfs
    if ! fsIsSqfsContainer "$sqfs_object"; then
        echo2error "$sqfs_object is not an sqfs container, cannot proceed with mounts."
        uiPressEnterToContinue
        exit 1
    fi

    printf2 "Mounting sqfs"
    if [[ -b $sqfs_object ]]; then
        printf2 " device... "
        sqfs_mountpoint=$(mktemp -dt -- "mount-backup-mountpoint-XXX")
        mount --read-only "$sqfs_object" "$sqfs_mountpoint"
        F_COLOR=magenta echo2 "$sqfs_mountpoint"
    elif [[ -f $sqfs_object ]]; then
        printf2 " file... "
        sqfs_mountpoint=$(mktemp -dt -- "mount-backup-mountpoint-XXX")
        mount -o loop --read-only "$sqfs_object" "$sqfs_mountpoint"
        declare sqfs_loop_device
        sqfs_loop_device=$(losetup -j "$sqfs_object" | cut -d ':' -f 1)
        F_COLOR=magenta echo2 "$sqfs_loop_device, $sqfs_mountpoint"
    else
        coreFailExit "Sqfs object is neither file nor block device. Unknown type."
    fi
    sleep 1.5

    ################################
    # - choose image file to mount #
    ################################
    printf2 "Scanning files in sqfs... "
    # shellcheck disable=SC2034
    declare -a mountable_files
    getMountableFiles "$sqfs_mountpoint" mountable_files
    echo2success "Done."

    declare file_to_mount
    selectFileToMount mountable_files getDisplayFromFile file_to_mount

    declare file_to_mount_rel_path
    # getDisplayFromFile "$file_to_mount" file_to_mount_rel_path
    getSqfsRelativePath "$file_to_mount" file_to_mount_rel_path

    #######################################################################
    # - mount selected image file using losetup -P for partition scanning #
    #######################################################################
    declare file_type
    file_type="$(file -b "$file_to_mount" | awk -F';' '{print $1}' || true)"
    printf2 "Mounting "
    F_COLOR=magenta printf2 "'$file_to_mount_rel_path'"
    printf2 " (${file_type:-})... "
    image_mount_device=$(losetup --find --show -r -P "$file_to_mount")
    echo2success "$image_mount_device"
    sleep 1.5

    declare -a partitions=()
    getPartitions "$image_mount_device" partitions

    declare mount_object="$image_mount_device"

    if [[ ${#partitions[@]} -gt 0 ]]; then
        echo2 "Image has ${#partitions[@]} partitions"

        declare selected_partition
        selectPartitionToMount partitions selected_partition
        if [[ -n $selected_partition ]]; then
            mount_object="$selected_partition"
        else
            F_COLOR=gray echo2 "Selection canceled"
        fi
    fi

    #################################
    # mount selection to output dir #
    #################################
    printf2 "Mounting $mount_object... "
    declare -A attrs
    fsGetBlockDeviceAttrs "$mount_object" attrs
    if [[ ${attrs['USAGE']:-} == 'filesystem' ]]; then
        mount -o ro "$mount_object" "$arg_mount_dir"
        mount_dir_mounted=1
        echo2success "Done."
    else
        echo2warn "Cannot mount object to directory - not a filesystem."
    fi

    ##########################
    # - wait for termination #
    ##########################
    echo2
    tput sc
    declare -i i=3
    declare is_busy
    while [[ $i -ne 0 ]]; do
        if [[ $mount_dir_mounted -ne 0 ]]; then
            echo2 -e "Now do your work in ${COLOR['magenta']}${arg_mount_dir}${COLOR['default']}"
        else
            echo2 "Do your work while everything's mounted:"
            printf2 "SQFS at ${COLOR['magenta']}%s${COLOR['default']}, image at ${COLOR['magenta']}%s${COLOR['default']})\n" \
                "$sqfs_mountpoint" "$image_mount_device"
        fi
        printf2 "Then press any key $i times to unmount everything "
        read -rsN1
        is_busy=0
        if [[ $mount_dir_mounted -ne 0 ]]; then
            if fuser -m "$arg_mount_dir" >/dev/null 2>&1; then is_busy=1; fi
        fi
        if [[ $is_busy -eq 0 ]]; then
            ((i--))
        else
            echo2warn "Output dir is busy"
            sleep 0.2
        fi
        tput rc; tput ed
    done
}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    [[ $cleanup_run -ne 0 ]] && return 0

    tput cnorm # reset cursor to normal
    sleep 0.5 # slight delay in case devices were just created and are busy. Not 100% proof but usually enough.

    # Undo mount operations in reverse order
    if [[ $mount_dir_mounted -ne 0 ]]; then
        printf2 "Unmounting output directory... "
        umount "$arg_mount_dir"
        mount_dir_mounted=0
        F_COLOR=cyan echo2 "Done."
    fi
    unmountImageLoopDevice
    unmountSqfsMountpoint
    closeLuksDevice

    cleanup_run=1
}
trapWithSigname cleanup EXIT SIGINT SIGTERM

main "$@"
