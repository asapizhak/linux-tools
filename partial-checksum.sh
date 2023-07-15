#!/usr/bin/env bash

# Makes checksumming of large files easier by checksumming their parts. Supports stopping/resuming.

set -u
set -e
# set -x

. lib/lib_fs.sh
. lib/lib_input_args.sh
. lib/lib_number_fn.sh
. lib/lib_string_fn.sh
. lib/lib_ui.sh

script_name=$(basename "$0")

function usage {
    # shellcheck disable=SC2317
    echo2 "\
Usage:
    $script_name -i <input_file> -o <output_file>[ -f][ -b NNNN]

    -i <file>                input file or block device
    -o <file>                path to output file
    -f                       force overwriting of output file.
    -b <size>                set hashable block size (in MiBs)
"
}

function readLastFileLine {
    declare -r file=$1
    declare -n f_out=$2

    [[ ! -f "$file" ]] && coreFailExit "File does not exist, or is not a file '$file'"

    # shellcheck disable=SC2034
    f_out=$(tail -n 1 "$file")
}

function readOffsetFromFile {
    declare -r file="$1"
    declare -n f_out=$2

    declare last_line
    readLastFileLine "$file" last_line
    [[ -z "$last_line" ]] && coreFailExit "Failed to read offset: last line was empty"

    [[ ${last_line//[[:space:]]/} = 'end' ]] && {
        echo2 "Hashes are already calculated, exiting."
        exit 0
    }

    declare -r offset_str=$(echo "$last_line" | awk '{print $1}')
    if [[ "${offset_str//[[:space:]]/}" != "${last_line//[[:space:]]/}" ]]; then
        coreFailExit "Malformed file. Expected only offset on the last line, got '$last_line'. If hash was already calculated, just delete it from last line."
    fi
    if ! isPositiveIntString "$offset_str"; then
        coreFailExit "Malformed file. Offset expected at line start, got '$offset_str'."
    fi

    # shellcheck disable=SC2034
    printf -v f_out "%d" "$offset_str"
}

declare sum_err_file
sum_err_file=$(mktemp)
declare sum_out_file
sum_out_file=$(mktemp)

# TODO: show the output file location on start
# TODO: deal with situation when dir to output file does not exist
# TODO: maybe, ask not for output file name, but for the object name (external-lin-home, etc),
#       and place a file into ./out/ e.g., or a separate option for output dir.
main() {
    ensureCommands sudo tail awk stat blockdev dd mktemp

    declare -A opts
    getInputArgs opts ':fi:o:b:' "$@"

    declare -r input_file="${opts['i']:-}"
    [[ -z $input_file ]] && coreFailExitWithUsage
    [[ ! -r $input_file ]] && coreFailExitWithUsage "Input object '$input_file' does not exist or has no read permission."

    declare -r output_file="${opts['o']:-${input_file}.sums.txt}"
    [[ $output_file == -* ]] && coreFailExitWithUsage "Invalid output file argument '$output_file'."

    declare overwrite_output_file=0
    [[ "${opts[f]+value}" ]] && overwrite_output_file=1

    declare -r part_size_blocks="${opts['b']:-1024}"
    if ! isPositiveIntString "$part_size_blocks"; then coreFailExit "Invalid block size specified '$part_size_blocks'."; fi

    declare -i input_size_bytes=-1
    getStorageObjectSize "$input_file" input_size_bytes
    declare -ri input_size_padding=${#input_size_bytes}
    echo2 "Input size: $input_size_bytes bytes"

    if [[ $overwrite_output_file -eq 1 ]] && [[ -e $output_file ]]; then
        echo2 "Output file exists and force overwrite is requested."
        rm -i "$output_file"
    fi

    declare -i offset_bytes=-1
    if [[ ! -e "$output_file" ]]; then
        printf "" >"$output_file"
        declare offset_str=
        strPadString "0" 14 offset_str
        printf "%s" "$offset_str" >>"$output_file"
        offset_bytes=0
        echo2 "Output file was not present, starting from scratch."
    elif [[ -f "$output_file" ]]; then
        echo2 "Output file exists, looking for offset."
        readOffsetFromFile "$output_file" offset_bytes
        echo2 "Starting offset: $offset_bytes"
    else
        coreFailExit "Output file exists but is not a file '$output_file'"
    fi

    echo2

    declare -ri block_size=$((1024 * 1024)) # 1MiB
    declare -ri part_size_bytes=$((block_size * part_size_blocks))
    # check if offset is multiply of block size
    if ((offset_bytes % block_size != 0)); then
        coreFailExit "Offset is not multiply of block size '$block_size'"
    fi

    declare -i upto
    declare -i finished_bytes=$offset_bytes
    declare percent_done
    is_start_iteration=1

    while [[ $offset_bytes -lt $input_size_bytes ]]; do
        if [[ $is_start_iteration -eq 0 ]]; then
            offset_str=''
            strPadString $offset_bytes 14 offset_str
            printf "\n%s" "$offset_str" >>"$output_file"
        else
            is_start_iteration=0
        fi
        upto=$((offset_bytes + part_size_bytes))
        offset_blocks=$((offset_bytes / block_size))
        # echo2 "Processing range: $offset_bytes..$upto of $input_size_bytes"
        printf2 "%${input_size_padding}s..%-${input_size_padding}d" $offset_bytes $upto

        dd if="${input_file}" bs="$block_size" skip="$offset_blocks" count="$part_size_blocks" 2>"$sum_err_file" | \
            sha1sum -b 2>"$sum_err_file" | \
            awk '{print $1}' > "$sum_out_file" 2>"$sum_err_file"

        for errlevel in "${PIPESTATUS[@]}"; do
            if [[ $errlevel -ne 0 ]]; then
                echo2 "!!! Checksumming error: !!!"
                cat <"$sum_err_file" >&2
                fail
            fi
        done

        declare sum_out
        read -r sum_out <"$sum_out_file"
        printf ";%s" "$sum_out" >>"$output_file"
        F_COLOR='magenta' printf2 " %s" "$sum_out"

        finished_bytes=$((upto - 1))
        if [[ $finished_bytes -gt $input_size_bytes ]]; then finished_bytes=$input_size_bytes; fi
        numPercentageFrac percent_done $((finished_bytes)) $input_size_bytes 2
        echo2 " finished $percent_done%"
        offset_bytes=$upto
    done

    printf "\nend" >>"$output_file"

    return 0
}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    [[ $cleanup_run -ne 0 ]] && return 0
    [[ -n $sum_err_file ]] && { rm "$sum_err_file"; sum_err_file=''; }
    [[ -n $sum_out_file ]] && { rm "$sum_out_file"; sum_out_file=''; }
    cleanup_run=1
}
trapWithSigname cleanup EXIT SIGINT SIGTERM

main "$@"
exit $?
