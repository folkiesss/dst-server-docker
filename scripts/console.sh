#!/usr/bin/env bash
set -euo pipefail

# Helper to send console commands directly to a running DST shard container
# Usage: ./scripts/console.sh <master|caves> <lua-command>
# Example: ./scripts/console.sh master "c_announce('Server restart in 5 minutes')"
# Example: ./scripts/console.sh master "c_save()"

TARGET="${1:-}"
shift || true
COMMAND="$*"

if [ -z "${TARGET}" ] || [ -z "${COMMAND}" ]; then
    echo "Usage: $0 <master|caves> <command>"
    echo "Example: $0 master \"c_announce('Hello World')\""
    echo "Example: $0 master \"c_save()\""
    exit 1
fi

case "${TARGET}" in
    master|Master)
        CONTAINER="dst-master"
        SHARD="Master"
        ;;
    caves|Caves)
        CONTAINER="dst-caves"
        SHARD="Caves"
        ;;
    *)
        echo "Error: Target must be 'master' or 'caves'"
        exit 1
        ;;
esac

echo "Sending command to ${CONTAINER} (${SHARD}): ${COMMAND}"
docker compose exec "${TARGET}" sh -c "echo \"${COMMAND}\" > /tmp/dst_${SHARD}.fifo"
echo "Command dispatched."
