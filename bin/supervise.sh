#!/bin/bash

# XXX: this assumes that this script's realpath is in the root of the K8sDeputy
# project.  must be updated if we move to etc/ or bin/ or something.
#
# Also `realpath` may not be universally available so may want to figure out
# something more generic to follow symlinks and resolve relative paths etc.
project=$(realpath $0 | xargs dirname | xargs dirname)
# TODO: remove this sanity check when we're confident that it's working
echo "inferred project=$project" >&2

# TODO: printing this just to be able to know what to `kill`
echo "my PID is $$"

terminate_supervised()
{
    julia --project="$project" -e 'using K8sDeputy; graceful_terminate()'
    wait $child
    exit $?
}

# start background process
"$@" &
child=$!

trap "terminate_supervised" TERM INT

wait $child

echo "done"
