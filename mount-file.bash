#!/usr/bin/env bash

set -o nounset            # Fail on use of unset variable.
set -o errexit            # Exit on command failure.
set -o pipefail           # Exit on failure of any command in a pipeline.
set -o errtrace           # Trap errors in functions and subshells.
shopt -s inherit_errexit  # Inherit the errexit option status in subshells.

# Print a useful trace when an error occurs
trap 'echo Error when executing ${BASH_COMMAND} at line ${LINENO}! >&2' ERR

export PATH="@coreutils@:$PATH"

# Get inputs from command line arguments
if [[ $# != 4 ]]; then
    echo "Error: 'mount-file.bash' requires *four* args." >&2
    exit 1
fi

mountPoint="$1"
targetFile="$2"
method="$3"
debug="$4"

trace() {
    if (( debug )); then
      echo "$@"
    fi
}
if (( debug )); then
    set -o xtrace
fi

mountTargetFile() {
    if [[ $method == "auto" && -e $targetFile ]] || [[ $method == "reconcile" ]]; then
        touch "$mountPoint"
        mount -o bind "$targetFile" "$mountPoint"
    else
        ln -s "$targetFile" "$mountPoint"
    fi
}

if [[ -L $mountPoint && $(readlink -f "$mountPoint") == "$targetFile" ]]; then
    trace "$mountPoint already links to $targetFile, ignoring"
elif findmnt "$mountPoint" >/dev/null; then
    trace "mount already exists at $mountPoint, ignoring"
elif [[ $method == "reconcile" && -e $mountPoint ]]; then
    mkdir -p "$(dirname "$targetFile")"

    if [[ ! -e $targetFile ]]; then
        trace "moving existing $mountPoint to $targetFile"
        mv "$mountPoint" "$targetFile"
    elif cmp -s -- "$mountPoint" "$targetFile"; then
        trace "$mountPoint already matches $targetFile, replacing with persisted mount"
        rm -f "$mountPoint"
    else
        echo "Refusing to replace conflicting file at $mountPoint; $targetFile already exists with different contents." >&2
        exit 1
    fi

    mountTargetFile
elif [[ -s $mountPoint ]]; then
    echo "A file already exists at $mountPoint!" >&2
    exit 1
elif [[ $method == "auto" && -e $targetFile ]] || [[ $method == "reconcile" && -e $targetFile ]]; then
    mountTargetFile
elif [[ $method == "auto" && $mountPoint == "/etc/machine-id" ]] || [[ $method == "reconcile" && $mountPoint == "/etc/machine-id" ]]; then
    # Work around an issue with persisting /etc/machine-id. For more
    # details, see https://github.com/nix-community/impermanence/pull/242
    echo "Creating initial /etc/machine-id"
    echo "uninitialized" > "$targetFile"
    mountTargetFile
else
    mountTargetFile
fi
