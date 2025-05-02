#!/bin/bash

get_pid()
{
    PID_FILE="${IPC_DIR}/julia-entrypoint.pid"
    until [ -f "${PID_FILE}" ]; do
        sleep 1
    done
    read -r SUPERVISED_PID <"${IPC_DIR}/julia-entrypoint.pid"    
    echo "supervising $SUPERVISED_PID"
}

get_socket()
{
    SOCKET_PATH="${IPC_DIR}/graceful-terminator.${SUPERVISED_PID}.socket"
    until [ -e "$SOCKET_PATH" ]; do
        sleep 1
    done

    if [ ! -S "$SOCKET_PATH" ]; then
        echo "Expected socket at $SOCKET_PATH; got something else. $SUPERVISED_PID is a zombie now" >&2
        exit 1
    fi
    echo "using socket at $SOCKET_PATH"
}

terminate_supervised()
{
    echo "Gently terminating $SUPERVISED_PID"
    nc -U "$SOCKET_PATH" <<<"terminate"
    wait
    STATUS=$?
    echo "$SUPERVISED_PID exited with $STATUS"
    exit $STATUS
}

echo "my PID is $$"

# create a separate IPC dir for this invocation because there can be a race with the PID file with 
IPC_DIR="${DEPUTY_IPC_DIR:-/run}/supervise-$$"
echo "IPC_DIR=$IPC_DIR"
mkdir -p "$IPC_DIR"

# start background process
DEPUTY_IPC_DIR=$IPC_DIR "$@" &

get_pid
get_socket

# TODO: check that nc is available before starting
# trap TERM to write "terminate" to socket with nc
trap "terminate_supervised" TERM INT

wait

echo "done"
