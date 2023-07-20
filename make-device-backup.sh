#! /usr/bin/env bash

set -u
set -e
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/lib/lib_core.sh"
. "$SCRIPT_DIR/lib/lib_fs.sh"
. "$SCRIPT_DIR/lib/lib_input_args.sh"
. "$SCRIPT_DIR/lib/lib_packages.sh"
. "$SCRIPT_DIR/lib/lib_number_fn.sh"
. "$SCRIPT_DIR/lib/lib_ui.sh"

script_name=$(basename "$0")

function usage {
    # shellcheck disable=SC2317
    echo2 "\
Usage:
    $script_name -i <input_object> -n <friendly_device_name> -o <output_file_dir>

    -i                        Input file-, dir-, device path
    -n                        Friendly name of the backup. Sqfs and .img will
                              have this name. A-Za-z and -_ allowed.
    -o                        Output file will be created there. Should exist.
                              Will be PWD, if omitted.
    -s                        Sqfs only - skips LUKS file creation, SQFS will be
                              the output file then.

Exit codes:
    1                        Generic exit code
    $EXIT_CODE_NO_INPUT_ARGS                       No input arguments provided
"
}

#
#   opts
function normalizeValidateInputArgs {
    declare -n _opts=$1

    # input file
    if [[ -z ${_opts['i']:-} ]]; then coreFailExitWithUsage "Input object not set"; fi
    if [[ ! -e ${_opts['i']} ]]; then coreFailExit "Input object '${_opts['i']}' does not exist"; fi
    if [[ ! -r ${_opts['i']} ]]; then coreFailExit "Input object '${_opts['i']}' has no read access"; fi

    if [[ ! -f ${_opts['i']} && ! -b ${_opts['i']} && ! -d ${_opts['i']} ]]; then
        coreFailExit "Only block devices, dirs and files are supported as input. '${_opts['i']}' is neither."; fi

    # friendly name
    if [[ -z ${_opts['n']:-} ]]; then coreFailExitWithUsage "Friendly name not set"; fi

    _opts['n']="${_opts['n']:-"$(basename "${_opts['n']}")"}"
    _opts['n']="${_opts['n']// /_}" # replace spaces
    _opts['n']="${_opts['n']//[^a-zA-Z0-9_\-]/}" # remove illegal chars
    _opts['n']="${_opts['n']//__/_}" # not perfect but should be ok
    _opts['n']="${_opts['n']//--/-}" # not perfect but should be ok

    if [[ -z ${_opts['n']} ]]; then coreFailExitWithUsage "After stripping illegal chars - friendly name is empty"; fi

    # output dir
    # default to working dir, if not supplied
    if [[ -z ${_opts['o']:-} ]]; then _opts['o']="$PWD"; fi
    _opts['o']="$(realpath "${_opts['o']}")"

    if [[ ! -d ${_opts['o']:-} ]]; then coreFailExitWithUsage "-o should be an existing directory"; fi

    readonly -A _opts
}

declare temp_dir

#
#    _input_object
#    _img_name_wo_ext
#    _sqfs_basename
function dumpToSqfs {
    declare -r _input_object="$1"
    declare -r _img_name_wo_ext="$2"
    declare -r _sqfs_basename="$3"

    # check free space
    declare -i input_size; declare input_size_display
    getStorageObjectSize "$_input_object" input_size
    numDisplayAsSizeEx $input_size input_size_display
    echo2 "Input size: $input_size_display"

    # calculate free space using size of original input.
    # Sqfs file would usually be smaller but we don't know beforehand.
    declare -i free_space_diff
    fsIsEnoughFreeSpace "$PWD" $input_size free_space_diff

    if [[ $free_space_diff -le 0 ]]; then
        F_COLOR='yellow' echo2 "WARN: Low free space! Operation will possible fail."
        F_COLOR='yellow' echo2 "      Continue at your own risk."; fi

    # different mksquashfs versions allow different syntax
    declare mksquashfs_version
    mksquashfs_version="$(mksquashfs -version | grep 'mksquashfs version' | awk '{print $3}' )"

    declare -i is_ver_lessthan_4p5=0
    pkgAreEqualVersionStrings is_ver_lessthan_4p5 "$mksquashfs_version" 'lt' '4.5'

    declare -r img_basename="${_img_name_wo_ext}.img"
    echo2 "Will create $_sqfs_basename"
    sleep 1

    # take block device and read it into .img file in sqfs container (temp file), with default zstd compression
    declare -r common_args="-all-root -comp zstd -Xcompression-level 16"

    if [[ $is_ver_lessthan_4p5 -eq 1 ]]; then
        echo2 "Found mksquashfs version $mksquashfs_version (older than 4.5)"
        declare _rootdir="sqfsroot"
        mkdir "$_rootdir"
        # shellcheck disable=SC2086
        mksquashfs "$_rootdir" "$_sqfs_basename" $common_args \
            -p "$img_basename f 444 root root dd 2>/dev/null if=$_input_object bs=1M"
        rm -r "$_rootdir"
    else
        echo2 "Found mksquashfs version $mksquashfs_version"
        # shellcheck disable=SC2086
        mksquashfs - "$_sqfs_basename" $common_args \
            -p '/ d 644 0 0' \
            -p "$img_basename f 444 root root dd if=$_input_object bs=1M"
    fi

    declare -i sqfs_size
    getStorageObjectSize "$_sqfs_basename" sqfs_size

    declare sqfs_size_display; numDisplayAsSize $sqfs_size sqfs_size_display
    declare _size_percent; numPercentageFrac _size_percent $sqfs_size $input_size
    declare reduction; numDivFrac $input_size $sqfs_size reduction 2

    echo2
    printf2 "Created "
    F_COLOR=magenta printf2 "'%s'" "$_sqfs_basename"
    printf2 " of size "
    F_COLOR=magenta printf2 "%s" "$sqfs_size_display"
    printf2 " ("
    F_COLOR=magenta printf2 "%s%%" "$_size_percent"
    printf2 " of input, "
    F_COLOR=magenta printf2 "%sx" "$reduction"
    echo2 " reduction)"
}

########################################
# main
########################################
main() {
    coreEnsureCommands blkid mksquashfs cryptsetup

    inputExitIfNoArguments "$@"

    declare -A opts
    getInputArgs opts ':i:o:n:' "$@"

    normalizeValidateInputArgs opts

    declare -r input_object="${opts['i']:-}"
    declare -r friendly_device_name="${opts['n']}"
    declare output_luks_file="${opts['o']}"

    temp_dir="$(mktemp -dt -- "make-device-backup-XXX")"
    chmod a+rx "$temp_dir"
    pushd "$temp_dir" >/dev/null
    F_COLOR=gray echo2 "Temp dir is $temp_dir"

    declare cur_date; cur_date="$(date +"%Y%m%d_%H%M")"

    # input can be
    #   - a block device to backup (input -> img -> sqfs -> luks)
    #   - an sqfs file (input -> luks) # not implemented yet
    declare temp_sqfs_filename="${friendly_device_name}_$cur_date.sqfs"
    if [[ -b $input_object ]]; then
        echo2 "Input is a block device. Dumping to SQFS..."
        dumpToSqfs "$input_object" "$friendly_device_name" "$temp_sqfs_filename"
    elif [[ -d $input_object ]]; then
        echo2 "Input is a directory. Dumping to SQFS..."
        dumpToSqfs "$input_object" "$friendly_device_name" "$temp_sqfs_filename"

    elif [[ -f $input_object ]]; then
        declare file_type; file_type="$(file -bE "$input_object" | awk -F ',' '{print $1}')"
        printf2 "Input is a file or type"; F_COLOR=magenta echo2 " $file_type"

        # if input is already sqfs file, take it.
        if [[ $file_type == *"Squashfs filesystem"* ]]; then
            temp_sqfs_filename="$input_object"
            echo2 "Already an sqfs file."

        # if input is already LUKS container, skip.
        elif [[ $file_type == *"LUKS encrypted file"* ]]; then
            coreFailExit "Already a LUKS container. Aborting."

        else # input is a regular file, dump it to sqfs
            dumpToSqfs "$input_object" "$friendly_device_name" "$temp_sqfs_filename"
        fi
    else coreFailExit "Unsupported input type."
    fi

    ########################################
    # At this moment we should have SQFS file ready.
    declare -r sqfs_filename="$PWD/$temp_sqfs_filename"

}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    if [[ $cleanup_run -ne 0 ]]; then return 0; else cleanup_run=1; fi

    tput cnorm || true # reset cursor to normal

    if [[ ${temp_dir:-} == /tmp/* ]]; then
        printf2 "Removing temp dir..."
        rm -r "$temp_dir" && echo2 " Removed.";
    fi

    F_COLOR=cyan echo2 "Done."
}
trapWithSigname cleanup EXIT SIGINT SIGTERM

main "$@"
