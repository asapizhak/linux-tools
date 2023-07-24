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
. "$SCRIPT_DIR/lib/lib_string_fn.sh"
. "$SCRIPT_DIR/lib/lib_ui.sh"

script_name=$(basename "$0")

function usage {
    # shellcheck disable=SC2317
    echo2 "\
Usage:
    $script_name -i <input_object> -n <friendly_backup_name> -o <output_file_dir>

    -i                        Input file-, dir-, device path
    -n                        Friendly name of the backup. Sqfs and .img will
                              have this name. A-Za-z and -_ allowed.
    -o                        Output file will be created there. Should exist.
                              Will be PWD, if omitted.
    -s                        Sqfs only - skips LUKS file creation, SQFS will be
                              the output file then.
    -p <amount>               Adds <amount> of recovery data, in integer
                              percents. To skip recovery generation, use -p 0
                              If not supplied, 10 percent of recovery data
                              will be added.

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

    # parity amount
    _opts['p']="${_opts['p']:-10}"
    if ! isPositiveIntString "${_opts['p']}"; then coreFailExitWithUsage "-p argument wrong value: ${_opts['p']}"; fi

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

    declare -i is_ver_less_than_4p4=0
    declare -i is_ver_lessthan_4p5=0

    pkgAreEqualVersionStrings is_ver_less_than_4p4 "$mksquashfs_version" 'lt' '4.4'
    pkgAreEqualVersionStrings is_ver_lessthan_4p5 "$mksquashfs_version" 'lt' '4.5'

    echo2 "Will create $_sqfs_file"
    uiPressEnterToContinue

    # shellcheck disable=SC2034
    declare -r img_basename="${_img_name_wo_ext}.img"

    declare _source=
    declare compressor=zstd
    declare -a compressor_opts=('-Xcompression-level' '16')
    declare -a _rootdir_definition=()
    declare -a _pseudofile=("-p" "$img_basename f 444 root root dd 2>/dev/null if=$_input_object bs=1M")

    if [[ -d $_input_object ]]; then
        _source="$_input_object"
        _pseudofile=()
    fi

    if [[ $is_ver_less_than_4p4 -eq 1 ]]; then
        F_COLOR=gray echo2 "Found old mksquashfs version $mksquashfs_version (older than 4.4)"
        [[ -z $_source ]] && {
            _source="sqfsroot"
            mkdir "$_source"
        }
        compressor=xz
        compressor_opts=()
    elif [[ $is_ver_lessthan_4p5 -eq 1 ]]; then
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

    declare -a common_opts=('-all-root' '-comp' "$compressor" "${compressor_opts[@]}")

    declare -a args=("$_source" "$_sqfs_file" "${common_opts[@]}" "${_rootdir_definition[@]}" "${_pseudofile[@]}")
    mksquashfs "${args[@]}"
}

#
#    sqfs_file_path
#    sqfs_size
function showSqfsSizeSummary {
    declare -r _sqfs_file_path="$1"
    declare -ri _sqfs_size="$2"

    declare sqfs_size_display; numDisplayAsSize $_sqfs_size sqfs_size_display
    declare _input_size_percent; numPercentageFrac _input_size_percent $_sqfs_size $input_size
    declare reduction; numDivFrac $input_size $_sqfs_size reduction 2

    F_COLOR=magenta printf2 "'%s'" "$_sqfs_file_path"
    printf2 " of size "
    F_COLOR=magenta printf2 "%s" "$sqfs_size_display"
    printf2 " ("
    F_COLOR=magenta printf2 "%s%%" "$_input_size_percent"
    printf2 " of input, "
    F_COLOR=magenta printf2 "%sx" "$reduction"
    echo2 " reduction)"
}

declare luks_file_created
declare luks_container_loop_dev
declare luks_mapped_device
declare -i backup_succeeded

function closeLuksDevice {
    if [[ -n ${luks_mapped_device:-} ]]; then
        printf2 "Closing LUKS device $luks_mapped_device..."
        cryptsetup close "$luks_mapped_device" && luks_mapped_device=
        F_COLOR=cyan echo2 " Done."
    fi
}

function unmountLuksFile {
    if [[ -n ${luks_container_loop_dev:-} ]]; then
        printf2 "Unmounting LUKS file from $luks_container_loop_dev..."
        losetup -d "$luks_container_loop_dev" && luks_container_loop_dev=
        F_COLOR=cyan echo2 " Done."
    fi
}

declare -r par2_cmd="par2"

########################################
# main
########################################
main() {
    coreEnsureCommands blkid mksquashfs

    inputExitIfNoArguments "$@"

    declare -A opts
    getInputArgs opts ':i:o:n:sp:' "$@"

    normalizeValidateInputArgs opts

    declare -r input_object="${opts['i']}"
    declare -r friendly_device_name="${opts['n']}"
    declare -r output_dir="${opts['o']}"
    declare -ri skip_luks="${opts['s']}"

    declare -ri parity_amount="${opts['p']}"

    if [[ $skip_luks -ne 1 ]]; then
        coreEnsureCommands cryptsetup
    fi

    if ! coreCommandsArePresent "$par2_cmd"; then
        F_COLOR=yellow echo2 "$par2_cmd command not found. Recovery data will not be generated."
        uiPressEnterToContinue
    fi

    declare cur_date; cur_date="$(date +"%Y%m%d_%H%M")"
    declare -r sqfs_basename="${friendly_device_name}_$cur_date.sqfs"

    declare output_file
    if [[ $skip_luks -ne 1 ]]; then
        output_file="$output_dir/$sqfs_basename.luks"
    else
        output_file="$output_dir/$sqfs_basename"
    fi
    readonly output_file
    [[ ! $output_file == /* ]] && coreFailExit "Output file is not absolute path ($output_file)"


    # Fail if output file already exists
    if [[ -e $output_file ]]; then coreFailExit "Cannot create $output_dir/$sqfs_basename - file already exist"; fi

    temp_dir="$(mktemp -dt -- "make-device-backup-XXX")"
    chmod a+rx "$temp_dir"
    pushd "$temp_dir" >/dev/null

    declare sqfs_file="$temp_dir/$sqfs_basename"

    if [[ $skip_luks -eq 1 ]]; then
        sqfs_file="$output_dir/$sqfs_basename"
    fi

    declare -i input_is_sqfs=0

    # Store input size
    getStorageObjectSize "$input_object" input_size
    numDisplayAsSizeEx $input_size input_size_display

    ########################################
    # Determine input type
    if [[ -b $input_object ]]; then
        echo2 "Input is a block device of size $input_size_display"
    elif [[ -d $input_object ]]; then
        echo2 "Input is a directory of size $input_size_display"
    elif [[ -f $input_object ]]; then
        declare file_type; file_type="$(file -bE "$input_object" | awk -F ',' '{print $1}')"
        printf2 "Input is a file of size $input_size_display and type"; F_COLOR=magenta echo2 " $file_type"

        # if input is already sqfs file, take it.
        if [[ $file_type == *"Squashfs filesystem"* ]]; then
            sqfs_file="$input_object"
            input_is_sqfs=1
            echo2 "Already an sqfs file."

        # if input is already LUKS container, skip.
        elif [[ $file_type == *"LUKS encrypted file"* ]]; then
            coreFailExit "Already a LUKS container. Aborting."
        fi
    else coreFailExit "Unsupported input type."
    fi
    readonly sqfs_file
    readonly input_is_sqfs

    [[ ! $sqfs_file == /* ]] && coreFailExit "Sqfs file is not absolute path ($sqfs_file)"

    if [[ $input_is_sqfs -eq 0 ]]; then
        echo2 "Dumping to SQFS..."
        # sanity check before writing sqfs file
        if [[ -e $sqfs_file ]]; then
            coreFailExit "$sqfs_file: Sqfs file already exists. Won't overwrite!"
        fi

        dumpToSqfs "$input_object" "$friendly_device_name" "$sqfs_file"
    fi

    declare -i sqfs_size
    getStorageObjectSize "$sqfs_file" sqfs_size

    echo2
    if [[ $input_is_sqfs -eq 0 ]]; then printf2 "Created "; fi
    showSqfsSizeSummary "$sqfs_file" $sqfs_size
    sleep 1

    ########################################
    # At this moment we should have SQFS file ready.
    if [[ $skip_luks -eq 1 && $input_is_sqfs -eq 1 ]]; then
        F_COLOR=yellow echo2 "LUKS creation skipped and input is an sqfs file"
        F_COLOR=green echo2 "Doing nothing."
        exit 0
    fi

    if [[ $skip_luks -eq 1 ]]; then # sqfs is the output, copy it to output dir
        echo2 "LUKS creation skipped"
        echo2 "Copying sqfs file to the output dir..."

        # another sanity check before writing there with dd
        if [[ -e $output_file ]]; then
            coreFailExit "$output_file: Output file already exists. This should be caught earlier!"
        fi
        dd if="$sqfs_file" of="$output_file" bs=1M
        echo2 "Done."
        printf2 "Output file is "; F_COLOR=magenta printf2 "$output_file"
        exit 0
    fi

    # Create LUKS container and copy sqfs file into it
    echo2
    declare -i luks_overhead
    calculateLuksOverhead luks_overhead

    # round size up so it's aligned by 512 bytes
    declare -ri luks_file_size=$(( (sqfs_size + luks_overhead + 511) / 512 * 512 ))

    # check free space for LUKS file
    declare -i free_space_diff
    fsIsEnoughFreeSpace "$output_dir" $luks_file_size free_space_diff

    if [[ $free_space_diff -lt 0 ]]; then
        declare space_needed=$((0-free_space_diff))
        declare space_needed_display
        numDisplayAsSizeEx $space_needed space_needed_display
        F_COLOR='red' echo2 "Not enough free space to create LUKS container. Free $space_needed_display."
        exit 1
    fi

    # make LUKS file
    # another sanity check before writing there with dd
    if [[ -e $output_file ]]; then
        coreFailExit "$output_file: Output file already exists. This should be caught earlier!"
    fi

    # create (sparce) file
    printf2 "Creating LUKS file"; F_COLOR=magenta printf2 " '$output_file'"; printf2 "... "
    tput sc
    echo2
    uiPressEnterToContinue

    dd if=/dev/zero of="$output_file" bs=512 count=1 seek="$(( (luks_file_size / 512) - 1))" 2>/dev/null
    luks_file_created="$output_file"
    tput rc; tput ed
    F_COLOR='green' echo2 "Done."

    printf2 "Mounting file to..."
    luks_container_loop_dev=$(losetup -f --show "$output_file")
    printf2 "\b\b\b ${COLOR['magenta']}$luks_container_loop_dev${COLOR['default']}..."
    F_COLOR='green' echo2 " Done."

    printf2 "Formatting LUKS partition..."
    tput sc
    echo2
    cryptsetup -y luksFormat --type luks2 "$luks_container_loop_dev"
    tput rc; tput ed
    F_COLOR='green' echo2 'Done.'

    printf2 "Opening LUKS partition..."
    tput sc
    echo2
    cryptsetup open --type luks "$luks_container_loop_dev" "$friendly_device_name"
    luks_mapped_device="$(cryptsetup status "$friendly_device_name" | head -n 1 | awk '{print $1}'; true)"
    tput rc; tput ed
    F_COLOR='green' printf2 " Done as ${COLOR['magenta']}$luks_mapped_device${COLOR['default']}\n"

    # confirm partition has enough free space for sqfs
    declare -ir partition_size=$(blockdev --getsize64 "/dev/mapper/$friendly_device_name")
    declare -ir excessive_size=$((partition_size-sqfs_size))

    if [[ $excessive_size -eq 0 ]]; then
        echo2 "LUKS partition size is equal to sqfs file size."
    elif [[ $excessive_size -gt 0 ]]; then
        F_COLOR=yellow echo2 "LUKS partition size is greater than sqfs file size by $excessive_size bytes."
        F_COLOR=yellow echo2 "This may be suboptimal."
    else
        echo2 "Error: LUKS partition is smaller than sqfs file for ${excessive_size//-/} bytes."
        coreFailExit "       This is probably due to overhead calculation error."
    fi

    # copying sqfs filesystem to LUKS partition
    printf2 "Copying sqfs filesystem to LUKS partition..."
    tput sc
    echo2
    dd if="$sqfs_file" of="$luks_mapped_device" bs=1M status=progress
    tput rc; tput ed
    F_COLOR=green printf2 "Done."

    echo2
    echo2 "Verifying sqfs and LUKS checksums (they should match)"
    declare sha_sqfs; sha_sqfs="$(sha1sum -b "$sqfs_file" | awk 'print $1')"
    declare sha_device; sha_device="$(sha1sum -b "$luks_mapped_device" | awk 'print $1')"

    echo2 "$sha_sqfs $sqfs_file"
    if [[ $sha_sqfs == "$sha_device" ]]; then
        echo2success "$sha_device $luks_mapped_device"
        sleep 2
    else
        echo2error "$sha_device $luks_mapped_device"
        echo2error "Checksums don't match, the backup is likely not correct!"
        uiPressEnterToContinue
    fi

    printf2 "Calculation sha sum for output file..."
    sha1sum -b "$output_file" > "$output_file.sha1"
    echo2success " Done"

    printf2 "LUKS backup saved as "; F_COLOR=magenta echo2 "$output_file"
    backup_succeeded=1

    closeLuksDevice
    unmountLuksFile

    if [[ parity_amount -gt 0 ]]; then
        echo2
        echo2 "Will now add recovery data"
        uiPressEnterToContinue

        if coreCommandsArePresent "$par2_cmd"; then
            $par2_cmd create -r$parity_amount -m32 -- "$output_file"
            $par2_cmd verify -- "$output_file.par2"
        else
            echo2 "$par2_cmd command not found. Skipping recovery data generation."
        fi
    else
        echo2 "Recovery data generation skipped."
    fi

    echo2
    printf2success "Backup finished:"
    F_COLOR=magenta echo2 " $output_file"

    uiPressEnterToContinue

    return 0
}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    if [[ $cleanup_run -ne 0 ]]; then return 0; else cleanup_run=1; fi

    tput cnorm || true # reset cursor to normal

    closeLuksDevice
    unmountLuksFile

    if [[ -n ${luks_file_created:-} && ${backup_succeeded:-0} -eq 0 ]]; then
        printf2 "Removing LUKS file $luks_file_created..."
        rm "$luks_file_created" && luks_file_created=
        F_COLOR=cyan echo2 " Done."
    fi

    if [[ ${temp_dir:-} == /tmp/* ]]; then
        printf2 "Removing temp dir..."
        rm -r "$temp_dir" && temp_dir= && echo2 " Removed.";
    fi

    calculateLuksOverheadCleanup

    F_COLOR=cyan echo2 "│ Done."
}
trapWithSigname cleanup EXIT SIGINT SIGTERM

main "$@"
