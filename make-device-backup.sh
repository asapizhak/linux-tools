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
    $script_name -i <input_object> -o <luks_file_path> -n <friendly_device_name>

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

    # output file
    if [[ -z ${_opts['o']:-} ]]; then _opts['o']="$PWD/${_opts['n']}"; fi
    _opts['o']="$(realpath "${_opts['o']}")"
    if [[ ${_opts['o']} != *.img.luks ]]; then _opts['o']="${_opts['o']}.img.luks"; fi

    if [[ -e ${_opts['o']} ]]; then coreFailExit "Output file already exists (${_opts['o']})"; fi
    if [[ ! -e "$(dirname "${_opts['o']}")" ]]; then
        coreFailExit "Output file directory $(dirname "${_opts['o']}") does not exist"
    fi

    readonly -A _opts
}

declare temp_dir

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
