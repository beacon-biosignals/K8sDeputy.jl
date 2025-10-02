#!/usr/bin/env bash

timestamp()
{
    if [[ -z "$TIMESTAMP_MODE" ]]; then
        if ! command -v date >/dev/null; then
            echo 'supervise.sh requires `date`' >&2
            exit 1
        fi

        if [[ "$(date +%3N)" =~ ^[0-9]{3}$ ]]; then
            TIMESTAMP_MODE="date_ns"
        elif command -v adjtimex >/dev/null && command -v awk >/dev/null; then
            TIMESTAMP_MODE="adjtimex"
        else
            TIMESTAMP_MODE="date_s"
        fi
    fi

    case "$TIMESTAMP_MODE" in
        date_ns)
            date -u +"%Y-%m-%dT%H:%M:%S.%3NZ"
            ;;
        adjtimex)
            local timestamp_us="$(adjtimex | awk '/(time.tv_sec|time.tv_usec)/ { printf("%06d", $2) }')"
            local ms="${timestamp_us: -6:3}"
            local timestamp_s="${timestamp_us::-6}"
            date -u -d "@$timestamp_s" +"%Y-%m-%dT%H:%M:%S.${ms}Z"
            ;;
        date_s)
            date -u +"%Y-%m-%dT%H:%M:%SZ"
            ;;
    esac
}

# generate structured JSON logs with `timestamp`, `status`, and `message` fields.
logger()
{
    local level=${1:-info}
    read -r message
    echo "{\"timestamp\":\"$(timestamp)\",\"status\":\"$level\",\"message\":\"$message\"}" >&2
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
    signal=${1:-TERM}
    echo "$signal trapped, stopping" | logger

    # we parse these at termination time because they may not be ready at startup, and
    # because this matches the behavior of `K8sDeputy.graceful_terminate`
    local PID SOCKET_PATH
    PID="$(get_pid)"
    SOCKET_PATH="$(get_socket "$PID")"

    if [[ -S $SOCKET_PATH ]]; then
        # https://github.com/beacon-biosignals/K8sDeputy.jl/blob/b62e1858a4083ffc8f9f7b10fcb60a77896ae13e/src/graceful_termination.jl#L143-L144
        nc -U "$SOCKET_PATH" <<<"terminate"
    else
        echo "Expected socket at $SOCKET_PATH; got something else. $PID may be a zombie now. sending SIG${signal} to $child instead" | logger warn
        kill "-$signal" $child
    fi

    wait $child

    local status=$?
    echo "PID $child completed with status $status" | logger debug
    exit $status
}

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

trap 'terminate_supervised TERM' TERM
trap 'terminate_supervised INT' INT

wait $child
