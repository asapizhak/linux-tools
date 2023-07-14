#!/usr/bin/env bash

BATS_VERSION='1.9.0'

. .batsrc

declare -r file_to_run=${1:-}

echo >&2 "Building scripts"

if [[ $EUID -eq 0 && -n "$SUDO_USER" ]]; then # run build as normal user to avoid access problems
    su -c "/bin/bash ./run-build.sh" "$SUDO_USER"
else
    bash ./run-build.sh
fi

echo >&2 "Running tests inside docker container..."

if ! docker inspect --type image "bats/bats:$BATS_VERSION" >/dev/null 2>&1; then
    echo "BATS image does not exist locally."
    echo "Will now fetch, and run BATS internal tests. This is one-time action."
    docker run -it --rm "bats/bats:$BATS_VERSION" "/opt/bats/test"
fi

if [[ -n "$file_to_run" ]]; then
    docker run -it --rm -v "$BATS_WORKSPACE:/tests" -e BATS_WORKSPACE="$BATS_WORKSPACE" "bats/bats:$BATS_VERSION" -r "/tests/tests/$file_to_run"
else
    docker run -it --rm -v "$BATS_WORKSPACE:/tests" -e BATS_WORKSPACE="$BATS_WORKSPACE" "bats/bats:$BATS_VERSION" -r /tests/tests
fi
