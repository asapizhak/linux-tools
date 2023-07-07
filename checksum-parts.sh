#!/usr/bin/env bash

# Makes checksumming of large files easier by checksumming their parts. Supports stopping/resuming.

set -u
set -e
# set -x

. lib/lib_fs.sh
. lib/lib_input_args.sh
. lib/lib_number_fn.sh
. lib/lib_string_fn.sh

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

    [[ ! -f "$file" ]] && fail "File does not exist, or is not a file '$file'"

    # shellcheck disable=SC2034
    f_out=$(tail -n 1 "$file")
}

function readOffsetFromFile {
    declare -r file="$1"
    declare -n f_out=$2

    declare last_line
    readLastFileLine "$file" last_line
    [[ -z "$last_line" ]] && fail "Failed to read offset: last line was empty"

    [[ ${last_line//[[:space:]]/} = 'end' ]] && {
        echo2 "Hashes are already calculated, exiting."
        exit 0
    }

    declare -r offset_str=$(echo "$last_line" | awk '{print $1}')
    if [[ "${offset_str//[[:space:]]/}" != "${last_line//[[:space:]]/}" ]]; then
        fail "Malformed file. Expected only offset on the last line, got '$last_line'. If hash was already calculated, just delete it from last line."
    fi
    if ! isPositiveIntString "$offset_str"; then
        fail "Malformed file. Offset expected at line start, got '$offset_str'."
    fi

    # shellcheck disable=SC2034
    printf -v f_out "%d" "$offset_str"
}

###############################################################################
### MAIN
main() {
    ensureCommands sudo tail awk stat blockdev dd

    declare -A opts
    getInputArgs opts ':fi:o:b:' "$@"

    declare -r input_file="${opts['i']:-''}"
    [[ ! -r $input_file ]] && fail "Input object '$input_file' does not exist or has no read permission."

    declare -r output_file="${opts['o']:-${input_file}.sums.txt}"
    [[ $output_file == -* ]] && fail "Invalid output file argument '$output_file'."

    declare overwrite_output_file=0
    [[ "${opts[f]+value}" ]] && overwrite_output_file=1

    declare -r part_size_blocks="${opts['b']:-'1024'}"
    if ! isPositiveIntString "$part_size_blocks"; then fail "Invalid block size specified '$part_size_blocks'."; fi

    declare -i input_size_bytes=-1
    getStorageObjectSize "$input_file" input_size_bytes
    echo2 "Input size: $input_size_bytes"

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
        fail "Output file exists but is not a file '$output_file'"
    fi

    echo2 "--- Begin ---"

    declare -ri block_size=$((1024 * 1024)) # 1MiB
    declare -ri part_size_bytes=$((block_size * part_size_blocks))
    # check if offset is multiply of block size
    if ((offset_bytes % block_size != 0)); then
        fail "Offset is not multiply of block size '$block_size'"
    fi

    declare -i upto=0
    declare -i finished_bytes=$offset_bytes
    declare done_percent
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
        echo2 "Range: $offset_bytes..$upto of $input_size_bytes"
        offset_blocks=$((offset_bytes / block_size))
        sum_out=$(
            dd if="${input_file}" bs="$block_size" skip="$offset_blocks" count="$part_size_blocks" |
                sha1sum -b |
                awk '{print $1}'
        )

        finished_bytes=$((upto - 1))
        if [[ $finished_bytes -gt $input_size_bytes ]]; then finished_bytes=$input_size_bytes; fi
        numPercentageFrac $((finished_bytes)) $input_size_bytes 2 done_percent
        echo2 "Hash: $sum_out, $done_percent% finished"
        printf ";%s" "$sum_out" >>"$output_file"
        echo2 "---"
        offset_bytes=$upto
    done

    printf "\nend" >>"$output_file"

    return 0
}

main "$@"
exit $?
