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
        coreFailExit "Only block devices, dirs and files are supported as input. '${_opts['i']}' is neither."
    fi

    declare real_input_path; real_input_path="$(realpath "${_opts['i']}")"
    if [[ ! $real_input_path == "${_opts['i']}" ]]; then
        _opts['i']="$real_input_path"
    fi

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

    # skip LUKS
    _opts['s']="${_opts['s']:-0}"

    readonly -A _opts
}

declare -A luks_overhead_metadata=()

#
#    out_overhead_size (in bytes)
function calculateLuksOverhead {
    declare -n out_overhead=$1

    echo2 "Calculating LUKS overhead..."

    declare -ir test_file_size_blocks=$((100*1024*1024/512)) # 100Mb in 512 blocks
    uiPushColor2 gray

    luks_overhead_metadata['test_file']=$(mktemp)
    dd if=/dev/zero of="${luks_overhead_metadata['test_file']}" bs=512 count=1 seek=$((test_file_size_blocks-1)) 2>/dev/null
    printf2 "+Temp-file."

    luks_overhead_metadata['file_dev']=$(losetup -f --show "${luks_overhead_metadata['test_file']}")
    printf2 " +Mounted."

    declare -r temp_pass="123"
    printf2 " LuksFormat, this may take some time.."
    cryptsetup luksFormat --type luks2 --key-file=- "${luks_overhead_metadata['file_dev']}" <<< "$temp_pass"
    printf2 " Done."

    printf2 " +Mapping.."
    luks_overhead_metadata['part_name']="overhead_test"
    cryptsetup open --type luks \
        --key-file=- "${luks_overhead_metadata['file_dev']}" "${luks_overhead_metadata['part_name']}" <<< "$temp_pass"

    declare -ir size_dev=$(blockdev --getsz "${luks_overhead_metadata['file_dev']}")
    declare -ir size_mapped=$(blockdev --getsz "/dev/mapper/${luks_overhead_metadata['part_name']}")

    declare -ri overhead="$(( size_dev - size_mapped ))"
    # shellcheck disable=SC2034
    out_overhead=$((overhead * 512))

    echo2 " Done."
    uiPopColor2
}

# shellcheck disable=SC2317
function calculateLuksOverheadCleanup {
    uiPushColor2 gray
    printf2 "Calculate LUKS overhead cleanup:"
    if [[ -n "${luks_overhead_metadata['part_name']:-}" ]]; then
        cryptsetup close "${luks_overhead_metadata['part_name']}"; luks_overhead_metadata['part_name']=''
        printf2 " -Mapping."; fi
    if [[ -n "${luks_overhead_metadata['file_dev']:-}" ]]; then
        losetup -d "${luks_overhead_metadata['file_dev']}"; luks_overhead_metadata['file_dev']=''
        printf2 " -Mount"; fi
    if [[ -n "${luks_overhead_metadata['test_file']:-}" ]]; then
        rm "${luks_overhead_metadata['test_file']}"; luks_overhead_metadata['test_file']=''
        printf2 " -Temp-file"; fi

    echo2 " Done."
    uiPopColor2

    return 0
}

declare temp_dir
declare -i input_size
declare input_size_display

#
#    _input_object
#    _img_name_wo_ext
#    _sqfs_file
function dumpToSqfs {
    declare -r _input_object="$1"
    declare -r _img_name_wo_ext="$2"
    declare -r _sqfs_file="$3"

    # check free space
    # calculate free space using size of original input.
    # Sqfs file would usually be smaller but we don't know beforehand.
    declare -i free_space_diff
    fsIsEnoughFreeSpace "$PWD" $input_size free_space_diff

    if [[ $free_space_diff -le 0 ]]; then
        F_COLOR='yellow' echo2 "WARN: Low free space! Operation will likely fail."
        F_COLOR='yellow' echo2 "      Continue at your own risk."; fi

    # different mksquashfs versions allow different syntax
    declare mksquashfs_version
    mksquashfs_version="$(mksquashfs -version | grep 'mksquashfs version' | awk '{print $3}' )"

    declare -i is_ver_lessthan_4p5=0
    pkgAreEqualVersionStrings is_ver_lessthan_4p5 "$mksquashfs_version" 'lt' '4.5'

    echo2 "Will create $_sqfs_file"
    uiPressEnterToContinue

    # shellcheck disable=SC2034
    declare -r img_basename="${_img_name_wo_ext}.img"

    declare _source=
    declare -a _rootdir_definition=()
    declare -a _pseudofile=("-p" "$img_basename f 444 root root dd 2>/dev/null if=$_input_object bs=1M")

    if [[ -d $_input_object ]]; then
        _source="$_input_object"
        _pseudofile=()
    fi

    if [[ $is_ver_lessthan_4p5 -eq 1 ]]; then
        F_COLOR=gray echo2 "Found mksquashfs version $mksquashfs_version (older than 4.5)"
        [[ -z $_source ]] && {
            _source="sqfsroot"
            mkdir "$_source"
        }
    else # 4.5+
        F_COLOR=gray echo2 "Found mksquashfs version $mksquashfs_version"
        [[ -z $_source ]] && {
            _source='-'
        }
        _rootdir_definition=("-p" "d 644 0 0")
    fi

    declare -a common_opts=('-comp' 'zstd' '-all-root' '-Xcompression-level' '16')

    declare -a args=("$_source" "$_sqfs_file" "${common_opts[@]}" "${_rootdir_definition[@]}" "${_pseudofile[@]}")
    mksquashfs "${args[@]}"
}

#
#    sqfs_file_path
#    input_size
function showSqfsSizeSummary {
    declare -r _sqfs_file_path="$1"

    declare -i sqfs_size
    getStorageObjectSize "$_sqfs_file_path" sqfs_size

    declare sqfs_size_display; numDisplayAsSize $sqfs_size sqfs_size_display
    declare _input_size_percent; numPercentageFrac _input_size_percent $sqfs_size $input_size
    declare reduction; numDivFrac $input_size $sqfs_size reduction 2

    echo2
    printf2 "Created "
    F_COLOR=magenta printf2 "'%s'" "$_sqfs_file_path"
    printf2 " of size "
    F_COLOR=magenta printf2 "%s" "$sqfs_size_display"
    printf2 " ("
    F_COLOR=magenta printf2 "%s%%" "$_input_size_percent"
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
    getInputArgs opts ':i:o:n:s' "$@"

    normalizeValidateInputArgs opts

    declare -r input_object="${opts['i']}"
    declare -r friendly_device_name="${opts['n']}"
    declare -r output_dir="${opts['o']}"
    declare -ri skip_luks="${opts['s']}"

    if [[ $skip_luks -eq 1 ]]; then
        F_COLOR=yellow echo2 "LUKS creation skip was requested. Writing sqfs to output dir."
        pushd "$output_dir" >/dev/null
    else
    temp_dir="$(mktemp -dt -- "make-device-backup-XXX")"
    chmod a+rx "$temp_dir"
    pushd "$temp_dir" >/dev/null
    fi

    F_COLOR=gray echo2 "Current dir is $PWD"

    # Store input size
    getStorageObjectSize "$input_object" input_size
    numDisplayAsSizeEx $input_size input_size_display
    echo2 "Input size: $input_size_display"

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
    declare -r sqfs_file="$PWD/$temp_sqfs_filename"

    if [[ $skip_luks -eq 1 ]]; then
        F_COLOR=green
        echo2 "Done."
        exit 0
    fi

    showSqfsSizeSummary "$sqfs_file"

    # Create LUKS container and copy sqfs file into it
    echo2
    echo2 "Creating LUKS container"

    declare -i luks_overhead
    calculateLuksOverhead luks_overhead

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
