#!/bin/bash

project=$(realpath $0 | xargs dirname)

echo "script is running from $project"
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
