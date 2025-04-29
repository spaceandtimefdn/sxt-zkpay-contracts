#!/usr/bin/env bash
set -euo pipefail
JOBS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $JOBS_DIR/..

percentage=$(forge clean > /dev/null && forge build > /dev/null && forge coverage | grep -o "[0-9\.]*%" | uniq | tr -d '\n')
if [ "$percentage" != "%100.00%" ]; then
    >&2 echo "missing test coverage!"
    exit 1
fi
echo "100% test coverage!"