#!/bin/bash

# generate structured JSON logs with `timestamp`, `status`, and `message` fields.
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
                               # ms part of fractional seconds w/o leading 0.
                               ms: . | modf | .[0] | "\(.)" | .[2:5]
                           } |
                           "\(.datetime).\(.ms)Z",
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
    # this is already logged in get_pid()
    if [[ -z $SUPERVISED_PID ]]; then
        exit 1
    fi
    local SOCKET_PATH="${IPC_DIR}/graceful-terminator.${SUPERVISED_PID}.socket"
    # TODO: timeout.  not likely to be critical since we don't call this unitl termination
    # is requested
    # until [ -e "$SOCKET_PATH" ]; do
    #     sleep 0.1
    # done
    echo "using socket at $SOCKET_PATH" | logger debug

    # output
    echo "$SOCKET_PATH"
}

terminate_supervised()
{
    echo "TERM trapped, stopping" | logger

    # we parse these at termination time because they may not be ready at startup, and
    # because this matches the behavior of `K8sDeputy.graceful_terminate`
    local PID SOCKET_PATH
    PID="$(get_pid)"
    SOCKET_PATH="$(get_socket "$PID")"

    if [[ -S $SOCKET_PATH ]]; then
        # https://github.com/beacon-biosignals/K8sDeputy.jl/blob/b62e1858a4083ffc8f9f7b10fcb60a77896ae13e/src/graceful_termination.jl#L143-L144
        nc -U "$SOCKET_PATH" <<<"terminate"
    else
        echo "Expected socket at $SOCKET_PATH; got something else. $PID may be a zombie now. sending SIGTERM to $child instead" | logger warn
        kill -TERM $child
    fi

    wait -n $child

    local status=$?
    echo "PID $child completed with status $status" | logger debug
    exit $status
}

JQ=$(command -v jq)
if [[ -z $JQ ]]; then
    echo "logging works best with jq" | logger warn
fi

if ! command -v nc >/dev/null; then
    echo "supervise.sh requires netcat (nc)" | logger error
    exit 1
fi

echo "startup.sh shim running from $0" | logger debug

# start background process
"$@" &

# NOTE: the PID of the actual Julia application that creates the socket that K8sDeputy
# listens for termination on may not be the same as the PID of the immediate child process
# here, if the command passed to this script is another shim (like with `juliaup`) or
# otherwise launches Julia as a subprocess.
#
# Nevertheless we still want to _wait_ on this child.
child=$!

trap 'terminate_supervised' TERM

wait -n $child
