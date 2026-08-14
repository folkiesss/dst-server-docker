#!/usr/bin/env bash
set -euo pipefail

SHARD="${SHARD:-Master}"
CLUSTER_NAME="MyDediServer"
DATA_DIR="/data/DoNotStarveTogether/${CLUSTER_NAME}"
SHARD_DIR="${DATA_DIR}/${SHARD}"
TEMPLATES_DIR="/etc/dst-templates"

echo "================================================="
echo " Starting DST Dedicated Server Shard: ${SHARD}"
echo " Persistent Storage: ${DATA_DIR}"
echo "================================================="

mkdir -p "${DATA_DIR}" "${SHARD_DIR}"

# 0. Check and Install/Update Game Files in Shared Volume /dst
DST_BINARY="/dst/bin64/dontstarve_dedicated_server_nullrenderer_x64"
INSTALL_LOCK="/dst/.installing.lock"

if [ ! -f "${DST_BINARY}" ] || [ "${UPDATE_ON_START:-false}" = "true" ]; then
    if mkdir "${INSTALL_LOCK}" 2>/dev/null; then
        echo "================================================="
        echo " [Install] Downloading / Validating DST into volume /dst..."
        echo "================================================="
        DepotDownloader \
            -app 343050 \
            -dir /dst \
            -os linux \
            -validate

        chmod +x /dst/bin64/dontstarve_dedicated_server_nullrenderer_x64 2>/dev/null || true
        rmdir "${INSTALL_LOCK}" 2>/dev/null || true
        echo " [Install] DST Game Installation Complete!"
    else
        echo " [Install] Another shard is downloading/updating game files. Waiting for completion..."
        while [ -d "${INSTALL_LOCK}" ] || [ ! -f "${DST_BINARY}" ]; do
            sleep 2
        done
        echo " [Install] Game files ready. Continuing startup."
    fi
fi

# Helper function to update or insert ini key-value pairs safely
update_ini_setting() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    if [ -n "${value}" ] && [ -f "${file}" ]; then
        # Strip surrounding double or single quotes if present
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        # Safe update without sed delimiter/ampersand collision
        awk -v k="${key}" -v v="${value}" -v s="${section}" '
        BEGIN { in_target_section = 0; replaced = 0 }
        $0 ~ "^\\[" s "\\]" {
            in_target_section = 1
            print
            next
        }
        in_target_section && $0 ~ "^\\[" {
            if (!replaced) {
                print k " = " v
                replaced = 1
            }
            in_target_section = 0
            print
            next
        }
        in_target_section && $1 == k && ($2 == "=" || $0 ~ "^" k "[[:space:]]*=") {
            print k " = " v
            replaced = 1
            next
        }
        { print }
        END {
            if (in_target_section && !replaced) {
                print k " = " v
            }
        }
        ' "${file}" > "${file}.tmp" && mv -f "${file}.tmp" "${file}"
    fi
}

# 1. Seed default configuration from templates if missing or empty
CLUSTER_INI="${DATA_DIR}/cluster.ini"
if [ ! -s "${CLUSTER_INI}" ] && [ -f "${TEMPLATES_DIR}/cluster.ini" ]; then
    echo "[Config] cluster.ini not found or empty. Seeding from templates/cluster.ini..."
    cp -f "${TEMPLATES_DIR}/cluster.ini" "${CLUSTER_INI}"
fi

SERVER_INI="${SHARD_DIR}/server.ini"
if [ ! -s "${SERVER_INI}" ] && [ -f "${TEMPLATES_DIR}/${SHARD}/server.ini" ]; then
    echo "[Config] ${SHARD}/server.ini not found or empty. Seeding from template..."
    cp -f "${TEMPLATES_DIR}/${SHARD}/server.ini" "${SERVER_INI}"
fi

WORLDGEN_FILE="${SHARD_DIR}/worldgenoverride.lua"
LEVELDATA_FILE="${SHARD_DIR}/leveldataoverride.lua"
if [ ! -s "${WORLDGEN_FILE}" ] && [ ! -s "${LEVELDATA_FILE}" ] && [ -f "${TEMPLATES_DIR}/${SHARD}/worldgenoverride.lua" ]; then
    echo "[Config] No world override found for ${SHARD}. Seeding default worldgenoverride.lua from template..."
    cp -f "${TEMPLATES_DIR}/${SHARD}/worldgenoverride.lua" "${WORLDGEN_FILE}"
fi

MODOVERRIDES_FILE="${SHARD_DIR}/modoverrides.lua"
if [ ! -s "${MODOVERRIDES_FILE}" ] && [ -f "${TEMPLATES_DIR}/${SHARD}/modoverrides.lua" ]; then
    echo "[Config] ${SHARD}/modoverrides.lua not found or empty. Seeding from template..."
    cp -f "${TEMPLATES_DIR}/${SHARD}/modoverrides.lua" "${MODOVERRIDES_FILE}"
fi

# 2. Handle Cluster Token
TOKEN_FILE="${DATA_DIR}/cluster_token.txt"
if [ -n "${DST_CLUSTER_TOKEN:-}" ]; then
    echo "Writing DST_CLUSTER_TOKEN to ${TOKEN_FILE}..."
    echo "${DST_CLUSTER_TOKEN}" > "${TOKEN_FILE}"
fi

if [ ! -f "${TOKEN_FILE}" ] || [ ! -s "${TOKEN_FILE}" ]; then
    echo "------------------------------------------------------------------------"
    echo " WARNING: No cluster_token.txt found in ${DATA_DIR}."
    echo " Set DST_CLUSTER_TOKEN env var or place token in cluster/cluster_token.txt."
    echo " Obtain one from: https://accounts.klei.com/account/game/servers?game=DST"
    echo "------------------------------------------------------------------------"
fi

# 3. Apply Environment Variable Overrides to cluster.ini
if [ -f "${CLUSTER_INI}" ]; then
    update_ini_setting "${CLUSTER_INI}" "NETWORK" "cluster_name" "${DST_CLUSTER_NAME:-}"
    update_ini_setting "${CLUSTER_INI}" "NETWORK" "cluster_description" "${DST_CLUSTER_DESCRIPTION:-}"
    update_ini_setting "${CLUSTER_INI}" "NETWORK" "cluster_password" "${DST_CLUSTER_PASSWORD:-}"
    update_ini_setting "${CLUSTER_INI}" "GAMEPLAY" "game_mode" "${DST_GAME_MODE:-}"
    update_ini_setting "${CLUSTER_INI}" "GAMEPLAY" "max_players" "${DST_MAX_PLAYERS:-}"
    update_ini_setting "${CLUSTER_INI}" "GAMEPLAY" "pvp" "${DST_PVP:-}"
    update_ini_setting "${CLUSTER_INI}" "GAMEPLAY" "pause_when_empty" "${DST_PAUSE_WHEN_EMPTY:-}"
    update_ini_setting "${CLUSTER_INI}" "MISC" "console_enabled" "${DST_ENABLE_CONSOLE:-}"
    update_ini_setting "${CLUSTER_INI}" "SHARD" "cluster_key" "${DST_CLUSTER_KEY:-}"
    update_ini_setting "${CLUSTER_INI}" "SHARD" "bind_ip" "0.0.0.0"
    update_ini_setting "${CLUSTER_INI}" "SHARD" "shard_enabled" "true"
    update_ini_setting "${CLUSTER_INI}" "SHARD" "master_ip" "${MASTER_HOST:-master}"
fi

# Ensure shard server_port matches container port configuration
if [ -n "${SERVER_PORT:-}" ] && [ -f "${SERVER_INI}" ]; then
    update_ini_setting "${SERVER_INI}" "NETWORK" "server_port" "${SERVER_PORT}"
fi

# 4. Sync and Auto-Detect Workshop Mods
mkdir -p /dst/mods
MODS_SETUP_DST="/dst/mods/dedicated_server_mods_setup.lua"
MODS_SETUP_CONFIG="/mods_config/dedicated_server_mods_setup.lua"

if [ -f "${MODS_SETUP_CONFIG}" ]; then
    cp -f "${MODS_SETUP_CONFIG}" "${MODS_SETUP_DST}"
elif [ ! -f "${MODS_SETUP_DST}" ]; then
    touch "${MODS_SETUP_DST}"
fi

NEW_MODS_FOUND=0
for modoverride_file in "${DATA_DIR}"/*/modoverrides.lua; do
    if [ -f "${modoverride_file}" ]; then
        for mod_id in $(grep -oE 'workshop-[0-9]+' "${modoverride_file}" | sed 's/workshop-//' | sort -u); do
            if [ -n "${mod_id}" ] && ! grep -q "ServerModSetup(\"${mod_id}\")" "${MODS_SETUP_DST}" 2>/dev/null; then
                echo "[Mods] Auto-detected workshop mod ${mod_id} from ${modoverride_file}"
                echo "ServerModSetup(\"${mod_id}\")" >> "${MODS_SETUP_DST}"
                NEW_MODS_FOUND=1
            fi
        done
    fi
done

if [ "${NEW_MODS_FOUND}" -eq 1 ] && [ -w "/mods_config" ]; then
    echo "[Mods] Syncing auto-detected mods back to mods/dedicated_server_mods_setup.lua"
    cp -f "${MODS_SETUP_DST}" "${MODS_SETUP_CONFIG}" 2>/dev/null || true
fi

# 5. Configure shard settings in server.ini
if [ "${SHARD}" = "Master" ]; then
    update_ini_setting "${SERVER_INI}" "SHARD" "is_master" "true"
    update_ini_setting "${SERVER_INI}" "SHARD" "name" "Master"
    update_ini_setting "${SERVER_INI}" "SHARD" "id" "1"
else
    MASTER_HOST="${MASTER_HOST:-master}"
    echo "Setting Master host '${MASTER_HOST}' for slave shard '${SHARD}'..."
    update_ini_setting "${SERVER_INI}" "SHARD" "is_master" "false"
    update_ini_setting "${SERVER_INI}" "SHARD" "master_ip" "${MASTER_HOST}"
fi

# 6. Launch server with FIFO input for c_shutdown() trap
FIFO_PATH="/tmp/dst_${SHARD}.fifo"
rm -f "${FIFO_PATH}"
mkfifo "${FIFO_PATH}"

# Keep FIFO open on FD 3 so writing commands does not close the stream
exec 3<> "${FIFO_PATH}"

cd /dst/bin64
./dontstarve_dedicated_server_nullrenderer_x64 \
    -console \
    -cluster "${CLUSTER_NAME}" \
    -shard "${SHARD}" \
    -persistent_storage_root /data \
    -conf_dir DoNotStarveTogether < "${FIFO_PATH}" &
srv=$!

shutdown_handler() {
    echo "Caught termination signal. Triggering graceful DST world save via c_shutdown()..."
    echo "c_shutdown()" >&3 2>/dev/null || true
    exec 3>&- 2>/dev/null || true

    echo "Waiting for shard '${SHARD}' (PID ${srv}) to finish saving and exit..."
    # Poll up to 8 seconds for DST to finish saving and Lua shutdown
    for i in $(seq 1 16); do
        if ! kill -0 "${srv}" 2>/dev/null; then
            break
        fi
        sleep 0.5
    done

    # If DST completed save and is lingering on network/stdin threads, terminate immediately
    if kill -0 "${srv}" 2>/dev/null; then
        echo "DST world saved. Finalizing process termination (PID ${srv})..."
        kill -TERM "${srv}" 2>/dev/null || true
        sleep 0.5
        kill -KILL "${srv}" 2>/dev/null || true
    fi

    echo "Shard '${SHARD}' shutdown complete."
    rm -f "${FIFO_PATH}"
    exit 0
}

trap shutdown_handler TERM INT

# While DST is running, wait on short background sleeps so bash traps (SIGTERM/SIGINT) trigger immediately
while kill -0 "${srv}" 2>/dev/null; do
    sleep 1 &
    wait $! 2>/dev/null || true
done

exec 3>&- 2>/dev/null || true
rm -f "${FIFO_PATH}"
