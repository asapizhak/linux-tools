#!/usr/bin/env bash

# Makes checksumming of large files easier by checksumming their parts. Supports stopping/resuming.

set -u
set -e
# set -x

. lib/lib_string_fn.sh
. lib/lib_number_fn.sh
. lib/lib_fs.sh

script_name=$(basename "$0")

function usage {
    echo2 "Usage:"
    echo2 "    $script_name <input_file>"
}

function readLastFileLine {
    file=$1
    [[ "$1" == "${!#}" ]] && fail "Missing last argument."

    [[ ! -f "$file" ]] && fail "File does not exist, or is not a file '$file'"

    last_line=$(tail -n 1 "$file")
    # [[ -z "$last_line" ]] && last_line=$(tail -n 2 "$file" | head -n 1)
}

function readOffsetFromFile {
    file=$1

    last_line=
    readLastFileLine "$file" last_line
    [[ -z "$last_line" ]] && fail "Failed to read offset: last line was empty"

    [[ ${last_line//[[:space:]]/} = 'end' ]] && {
        echo2 "Hashes are already calculated, exiting."
        exit 0
    }

    offset_str=$(echo "$last_line" | awk '{print $1}')
    if [[ "${offset_str//[[:space:]]/}" != "${last_line//[[:space:]]/}" ]]; then
        fail "Malformed file. Expected only offset on the last line, got '$last_line'"
    fi
    if ! isPositiveIntString "$offset_str"; then
        fail "Malformed file. Offset expected at line start, got '$offset_str'."
    fi

    printf -v ${!#} "%d" "$offset_str"
}

function appendOffsetToFile {
    offset=$1
    file=$2

    str=''
    padStr "$offset" 14 str
    printf "%s" "$str" >>"$file"
}

# offset_bytes=$((offset_str))
# check if offset is a multiple of a part size
# if (( offset_bytes % part_size_bytes != 0 )); then
#     fail "Offset '$offset_bytes' is not multiple of part size '$part_size_bytes'"
# fi

###############################################################################
### MAIN
main() {
    [ $# -ne 1 ] && usage && fail
    if ! commandsArePresent sudo tail awk stat blockdev dd; then fail; fi

    input_file="$1"

    input_size_bytes=-1
    getStorageObjectSize "$input_file" input_size_bytes
    echo "Input size: $input_size_bytes"

    output_file="${input_file}.sums.txt"

    offset_bytes=-1
    if [[ ! -e "$output_file" ]]; then
        printf "" >"$output_file"
        appendOffsetToFile 0 "$output_file"
        offset_bytes=0
        echo2 "Output file was not present, starting from scratch."
    elif [[ -f "$output_file" ]]; then
        echo2 "Output file exists, looking for offset."
        readOffsetFromFile "$output_file" offset_bytes
        echo2 "Starting offset: $offset_bytes"
    else
        fail "Output file exists but is not a file '$output_file'"
    fi

    ###
    echo2 "--- Begin ---"

    block_size=$((1024 * 1024)) # 1MiB
    part_size_blocks=100
    part_size_bytes=$((block_size * part_size_blocks))
    # check if offset is multiply of block size
    if ((offset_bytes % block_size != 0)); then
        fail "Offset is not multiply of block size '$block_size'"
    fi

    upto=0
    is_start_iteration=1

    while [[ $offset_bytes -lt $input_size_bytes ]]; do
        if [[ $is_start_iteration -eq 0 ]]; then
            offset_str=''
            padStr $offset_bytes 14 offset_str
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

        echo2 "HASH:$sum_out"
        printf " %s" "$sum_out" >>"$output_file"
        echo2 "---"
        offset_bytes=$upto
    done

    printf "\nend" >>"$output_file"

    return 0
}

main "$@"
exit $?
