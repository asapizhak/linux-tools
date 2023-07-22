#!/usr/bin/env bash

set -u
set -e
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/lib/lib_core.sh"
# . "$SCRIPT_DIR/lib/lib_array.sh"
# . "$SCRIPT_DIR/lib/lib_fs.sh"
. "$SCRIPT_DIR/lib/lib_input_args.sh"
# . "$SCRIPT_DIR/lib/lib_number_fn.sh"
# . "$SCRIPT_DIR/lib/lib_ui.sh"

script_name=$(basename "$0")

function usage {
    # shellcheck disable=SC2317
    echo2 "\
Usage:
    $script_name -i <image_file> -d <dir_for_mount>

    -i                                  Input LUKS file to mount
    -d                                  Directory to mount to
    -v                                  Don't mount, verify sha1 and parity if exists

Exit codes:
    1                        Generic exit code
    $EXIT_CODE_NO_INPUT_ARGS                       No input arguments provided
"
}

function normalizeValidateInputArgs {
    declare -n _opts=$1

    # input file
    if [[ -z ${_opts['i']:-} ]]; then coreFailExitWithUsage "Input object not set"; fi
    if [[ ! -e ${_opts['i']} ]]; then coreFailExit "Input object '${_opts['i']}' does not exist"; fi
    if [[ ! -r ${_opts['i']} ]]; then coreFailExit "Input object '${_opts['i']}' has no read access"; fi

    # output dir
    if [[ -z ${_opts['d']:-} ]]; then coreFailExitWithUsage "Output dir not set"; fi
    if [[ ! -e ${_opts['d']} ]]; then coreFailExit "Output dir '${_opts['d']}' does not exist"; fi

    # verify
    _opts['v']="${_opts['v']:-0}"
}

declare luks_mapped_device

function closeLuksDevice {
    if [[ -n ${luks_mapped_device:-} ]]; then
        printf2 "Closing LUKS device $luks_mapped_device..."
        cryptsetup close "$luks_mapped_device" && luks_mapped_device=
        F_COLOR=cyan echo2 " Done."
    fi
}

declare -r par2_cmd=par2

# args
declare input_file
declare mount_dir
declare -i verify_only
#
declare input_file_dir

# returns an error when checksum is not correct.
# If not able to verify, returns ok but sets the correspondent variable
#    out_able_to_verify (0,1)
function verifySha {
    declare -n out_able_to_verify=$1

    echo2 "Verifying sha"

    declare input_file_basename; input_file_basename="$(basename "$input_file")"
    declare -a sha_files=()
    readarray -t sha_files < <(find "$input_file_dir" -maxdepth 1 -type f -name "${input_file_basename}.sha*")
    if [[ -z "${sha_files:-}" ]]; then sha_files=(); fi
    echo2 "Found ${#sha_files[@]} sha files for input file"

    if [[ ${#sha_files[@]} -lt 1 ]]; then
        echo2warn "No sha files, cannot verify"
        out_able_to_verify=0
        return 0
    fi

    declare sha_file='' sha_cmd=''

    for f in "${sha_files[@]}"; do
        printf2 "Checking $(basename "$f") command..."
        declare ext="${f##*.}"
        declare cmd="${ext}sum"
        if coreCommandsArePresent 1 "$cmd"; then
            sha_file="$f"
            sha_cmd="$cmd"
            echo2success " Found."
            break
        else
            echo2warn " Not found."
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

    declare par_file; par_file="${input_file}.par2"

    echo2 "Verifying parity"

    printf2 "Checking $par2_cmd command..."
    if ! coreCommandsArePresent "$par2_cmd"; then
        echo2warn " Not found. Cannot verify parity."
        out_able_verify_par=0
        return 0
    fi
    echo2success " Done."

    printf2 "Checking par file..."
    if [[ -z $par_file ]]; then
        echo2warn " Not found ($par_file)."
        out_able_verify_par=0
        return 0
    fi
    echo2success " Found."

    declare exit_code=0
    if [[ -f $par_file ]]; then
        set +e
        $par2_cmd verify -- "$par_file"
        exit_code=$?
        set -e
        if [[ $exit_code -eq 0 ]]; then
            out_able_verify_par=1
            echo2success "Successfully verified parity data."
            return 0
        else
            coreFailExit "$par2_cmd returned $exit_code. Parity verification failed."
        fi

    elif [[ -d $par_file ]]; then
        pushd "$par_file" >/dev/null
        set +e
        $par2_cmd verify "$(basename "$par_file")" "$input_file"
        exit_code=$?
        set -e
        popd >/dev/null
        if [[ $exit_code -eq 0 ]]; then
            # shellcheck disable=SC2034
            out_able_verify_par=1
            echo2success "Successfully verified parity data."
            return 0
        else
            coreFailExit "$par2_cmd returned $exit_code. Parity verification failed."
        fi
    fi
}

main() {
    coreEnsureCommands realpath basename cryptsetup

    coreEnsureRunByRoot "We need to be able to mount/unmount things"

    if ! coreCommandsArePresent "$par2_cmd"; then
        F_COLOR=yellow echo2 "$par2_cmd command not found. Recovery data won't be checked."
    fi

    inputExitIfNoArguments "$@"

    declare -A opts
    getInputArgs opts ':i:d:v' "$@"

    normalizeValidateInputArgs opts

    input_file="$(realpath "${opts['i']}")"
    mount_dir="$(realpath "${opts['d']}")"
    verify_only="${opts['v']}"
    input_file_dir="$(dirname "$input_file")"
    readonly input_file mount_dir verify_only input_file_dir

    pushd "$input_file_dir" >/dev/null || exit 0
    echo2 "Switched to dir $input_file_dir"

    # Verify only
    if [[ $verify_only -eq 1 ]]; then
        echo2 "Verification requested, not mounting."
        declare -i able_verify_sha=1 able_verify_par=1

        verifySha able_verify_sha
        sleep 3
        echo2
        verifyPar able_verify_par

        if [[ $able_verify_sha -ne 1 && $able_verify_par -ne 1 ]]; then
            coreFailExit "Failed to verify integrity."
        fi

        exit 0
    fi

    # Mount LUKS
    declare slug; slug="$(basename "$input_file")"
    slug="${slug%.luks}"
    slug="${slug%.sqfs}"
    slug="${slug%.squashfs}"
    
    slug="${slug// /_}" # replace spaces
    slug="${slug//[^a-zA-Z0-9_\-]/}" # remove illegal chars

    if [[ -f $input_file ]]; then printf2 "Opening input file..."
    elif [[ -b $input_file ]]; then printf2 "Opening input device..."
    fi

    tput sc
    echo2
    cryptsetup open --type luks --readonly "$input_file" "$slug"
    luks_mapped_device="$(cryptsetup status "$slug" | head -n 1 | awk '{print $1}'; true)"
    tput rc; tput ed
    printf2success " Mapped to"
    F_COLOR=magenta echo2 " $luks_mapped_device"

    read -rp "Press Enter"
    # now mount it as sqfs backup
    declare -r mount_script_name=mount-sqfs-backup
    echo2 "Running $mount_script_name -i $luks_mapped_device -d $mount_dir"
    sleep 2
    echo2
    bash "$SCRIPT_DIR/$mount_script_name.sh" -i "$luks_mapped_device" -d "$mount_dir"
}

declare -i cleanup_run=0
# shellcheck disable=SC2317
function cleanup {
    [[ $cleanup_run -ne 0 ]] && return 0

    tput cnorm # reset cursor to normal
    sleep 0.5 # slight delay in case devices were just created and are busy. Not 100% proof but usually enough.

    closeLuksDevice

    cleanup_run=1
}
trapWithSigname cleanup EXIT SIGINT SIGTERM

main "$@"
