#!/bin/bash

logger()
{
    local level=${1:-info}
    if [[ -n $JQ ]]; then
        jq --raw-input --raw-output --compact-output \
           --arg status "$level" \
           '{
                # theres no jq way I can find to format timestamp w/ subsecond precision
                # so here we are, rolling our own!
                timestamp: now |
                           {
                               # just the date-time stamp w/o Z
                               datetime: . | strftime("%Y-%m-%dT%H:%M:%S"),
                               # ms part of fractional seconds w/o leading 0
                               ms: . | modf | .[0] | "\(.)" | .[1:5]
                           } |
                           "\(.datetime)\(.ms)Z",
                status: $status,
                message: .
            }' >&2
    else
        # provide a _very_ minimal fallback here
        read -r message
        echo "{\"status\":\"$level\",\"message\":\"$message\"}" >&2
    fi
}

# https://github.com/beacon-biosignals/K8sDeputy.jl/blob/b62e1858a4083ffc8f9f7b10fcb60a77896ae13e/src/graceful_termination.jl#L14
IPC_DIR="${DEPUTY_IPC_DIR:-/run}"

# https://github.com/beacon-biosignals/K8sDeputy.jl/blob/b62e1858a4083ffc8f9f7b10fcb60a77896ae13e/src/graceful_termination.jl#L21-L29
get_pid()
{
    local PID_FILE="${IPC_DIR}/julia-entrypoint.pid"
    # TODO: timeout.  not likely to be critical since we don't call this unitl termination
    # is requested
    # until [ -f "${PID_FILE}" ]; do
    #     sleep 0.1
    # done
    if [[ ! -f $PID_FILE ]]; then
        echo "Failed to find PID file at $PID_FILE" | logger error
        exit 1
    fi
    echo "reading PID from $PID_FILE" | logger debug
    local SUPERVISED_PID
    read -r SUPERVISED_PID <"${IPC_DIR}/julia-entrypoint.pid"
    if [[ ! $SUPERVISED_PID =~ ^[0-9]+$ ]]; then
        echo "PID file $PID_FILE does not contain a numeric PID: $SUPERVISED_PID" | logger error
        exit 1
    fi
    echo "supervised process has PID $SUPERVISED_PID" | logger debug

    # output
    echo "$SUPERVISED_PID"
}

# https://github.com/beacon-biosignals/K8sDeputy.jl/blob/b62e1858a4083ffc8f9f7b10fcb60a77896ae13e/src/graceful_termination.jl#L16-L19
get_socket()
{
    local SUPERVISED_PID=${1}
    local SOCKET_PATH="${IPC_DIR}/graceful-terminator.${SUPERVISED_PID}.socket"
    # TODO: timeout.  not likely to be critical since we don't call this unitl termination
    # is requested
    # until [ -e "$SOCKET_PATH" ]; do
    #     sleep 0.1
    # done
    if [[ ! -S $SOCKET_PATH ]]; then
        echo "Expected socket at $SOCKET_PATH; got something else. $SUPERVISED_PID may be a zombie now" | logger error
        exit 1
    fi
    echo "using socket at $SOCKET_PATH" | logger debug

    # output
    echo "$SOCKET_PATH"
}

terminate_supervised()
{
    echo "TERM trapped, stopping" | logger
    # we parse these at termination time because they may not be ready at startup, and
    # because this matches the behavior of `K8sDeputy.graceful_terminate`
    local PID="$(get_pid)"
    local SOCKET_PATH="$(get_socket $PID)"
    # https://github.com/beacon-biosignals/K8sDeputy.jl/blob/b62e1858a4083ffc8f9f7b10fcb60a77896ae13e/src/graceful_termination.jl#L143-L144
    nc -U "$SOCKET_PATH" <<<"terminate"
    wait $child
    exit $?
}

JQ=$(command -v jq)
if [[ -z $JQ ]]; then
    echo "logging works best with jq" | logger warn
fi

if ! command -v nc >/dev/null; then
    echo "supervise.sh requires netcat (nc)" | logger error
    exit 1
fi

# start background process
"$@" &
child=$!

trap "terminate_supervised" TERM

wait $child
