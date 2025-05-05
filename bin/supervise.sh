#!/bin/bash

# https://github.com/beacon-biosignals/K8sDeputy.jl/blob/ff1548eba0eb84f463971fafc4839694df004cba/src/graceful_termination.jl#L14
IPC_DIR="${DEPUTY_IPC_DIR:-/run}"

# https://github.com/beacon-biosignals/K8sDeputy.jl/blob/ff1548eba0eb84f463971fafc4839694df004cba/src/graceful_termination.jl#L21-L29
get_pid()
{
    PID_FILE="${DEPUTY_IPC_DIR}/julia-entrypoint.pid"
    # TODO: timeout.  not likely to be critical since we don't call this unitl termination
    # is requested
    # until [ -f "${PID_FILE}" ]; do
    #     sleep 0.1
    # done
    if [[ ! -f $PID_FILE ]]; then
        echo "Failed to find PID file at $PID_FILE" >&2
        exit 1
    fi
    read -r SUPERVISED_PID <"${DEPUTY_IPC_DIR}/julia-entrypoint.pid"
    if [[ ! SUPERVISED_PID ~= ^[0-9]+$ ]]; then
        echo "PID file $PID_FILE does not contain a numeric PID: $SUPERVISED_PID" >&2
        exit 1
    fi
}

# https://github.com/beacon-biosignals/K8sDeputy.jl/blob/ff1548eba0eb84f463971fafc4839694df004cba/src/graceful_termination.jl#L16-L19
get_socket()
{
    SOCKET_PATH="${DEPUTY_IPC_DIR}/graceful-terminator.${SUPERVISED_PID}.socket"
    # TODO: timeout.  not likely to be critical since we don't call this unitl termination
    # is requested
    # until [ -e "$SOCKET_PATH" ]; do
    #     sleep 0.1
    # done
    if [[ ! -S $SOCKET_PATH ]]; then
        echo "Expected socket at $SOCKET_PATH; got something else. $SUPERVISED_PID may be a zombie now" >&2
        exit 1
    fi
    echo "using socket at $SOCKET_PATH"
}

terminate_supervised()
{
    # we parse these at termination time because they may not be ready at startup, and
    # because this matches the behavior of `K8sDeputy.graceful_terminate`
    get_pid
    get_socket
    echo "Gently terminating $SUPERVISED_PID"
    # https://github.com/beacon-biosignals/K8sDeputy.jl/blob/ff1548eba0eb84f463971fafc4839694df004cba/src/graceful_termination.jl#L143-L144
    nc -U "$SOCKET_PATH" <<<"terminate"
    wait $child
    exit $?
}

# start background process
"$@" &
child=$!

trap "terminate_supervised" TERM

wait $child

echo "done"
