#!/bin/bash

# XXX: this assumes that this script's realpath is one subdirectory deep in the
# K8sDeputy project.  must be updated if we move it any deeper
#
# Also `realpath` may not be universally available so may want to figure out
# something more generic to follow symlinks and resolve relative paths etc.
project=$(realpath $0 | xargs dirname | xargs dirname)
# TODO: remove this sanity check when we're confident that it's working
echo "inferred project=$project"

# TODO: printing this just to be able to know what to `kill`
echo "my PID is $$"

terminate_supervised()
{
    echo "Superviser is terminating via K8sDeputy.graceful_terminate()..."
    # XXX: this load path injection only works if the active project _already
    # has_ K8sDeputy somewhere in its dependencies.  The purpose of this is to
    # make this all work _without_ requiring that K8sDeputy is explicitly
    # included in the project (i.e., to support use cases where it comes in as a
    # dependency of a bigger library that wraps it along with other features.)
    JULIA_LOAD_PATH="$project:$JULIA_LOAD_PATH" julia -e '@show Base.load_path(); using K8sDeputy; graceful_terminate()'
    wait $child
    exit $?
}

# TODO: set and validate load path before running?

# start background process
"$@" &
child=$!

trap "terminate_supervised" TERM INT

wait $child

echo "done"
