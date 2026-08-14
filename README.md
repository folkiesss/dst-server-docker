# Don't Starve Together (DST) Dedicated Server

A lightweight, multi-shard (Master + Caves) Don't Starve Together dedicated server in Docker with automatic Workshop mod management and clean `.env` configuration.

---

## 🚀 Quick Start

### 1. Get a Klei Cluster Token
1. Log in to the [Klei Account Server Portal](https://accounts.klei.com/account/game/servers?game=DST).
2. Generate a token for server name `MyDediServer`.
3. Copy your token string.

### 2. Configure `.env`
Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

Set your token and server options in `.env`:
```dotenv
# Klei authentication token
DST_CLUSTER_TOKEN=pds-g^KU_...

# Server settings
DST_CLUSTER_NAME=My Awesome DST Server
DST_CLUSTER_PASSWORD=secretpassword
DST_GAME_MODE=survival
DST_MAX_PLAYERS=16
DST_PVP=false
DST_PAUSE_WHEN_EMPTY=true
```

### 3. Start the Server
```bash
docker compose up -d
```
Game files will automatically download on first run, after which both Master and Caves shards will start up.

View live logs:
```bash
docker compose logs -f
```

---

## 📂 Using Existing Saves & Worlds

To load an existing world or a world created in the game client:

1. Copy your **`Master/`** and **`Caves/`** folders into the `cluster/` directory:
   ```text
   cluster/
   ├── Master/
   │   ├── save/
   │   ├── server.ini
   │   └── modoverrides.lua
   └── Caves/
       ├── save/
       ├── server.ini
       └── modoverrides.lua
   ```

2. Start the cluster:
   ```bash
   docker compose up -d
   ```
   All world saves and workshop mods in `modoverrides.lua` will be automatically detected, downloaded, and loaded.

---

## 🎮 Console Commands

Use the bundled `scripts/console.sh` helper to send in-game console commands to running shards:

```bash
# Save world
./scripts/console.sh master "c_save()"

# Broadcast server announcement
./scripts/console.sh master "c_announce('Server restarting in 5 minutes')"

# Rollback world by 1 day
./scripts/console.sh master "c_rollback(1)"

# Graceful shutdown with auto-save
./scripts/console.sh master "c_shutdown()"
```
