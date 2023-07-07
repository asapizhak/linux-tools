#!/usr/bin/env bash

BATS_VERSION='1.9.0'

if ! docker inspect --type image "bats/bats:$BATS_VERSION" >/dev/null 2>&1; then
    echo "BATS image does not exist locally."
    echo "Will now fetch, and run BATS internal tests. This is one-time action."
    docker run -it --rm "bats/bats:$BATS_VERSION" "/opt/bats/test"
fi

docker run -it --rm -v "$PWD:/tests" "bats/bats:$BATS_VERSION" -r /tests/tests
