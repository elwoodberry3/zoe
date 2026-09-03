#!/usr/bin/env bash
# ZOE v.1 — Project scaffold
# Creates the ZOE project tree under $HOME/zoe. No sudo. No writes outside ZOE_ROOT.
# Idempotent: safe to re-run; never overwrites existing files.
set -euo pipefail

ZOE_ROOT="${HOME}/zoe"

# --- Guardrails (governance §5, §24, §35) -----------------------------------
# Refuse to run anywhere near the filesystem root or a system path.
case "$ZOE_ROOT" in
  /|/zoe|/root/*|/etc/*|/usr/*|/var/*|/bin/*|/sbin/*)
    echo "REFUSING: \$HOME resolves to a system path ($ZOE_ROOT). Aborting." >&2
    exit 1 ;;
esac
if [ "$(id -u)" -eq 0 ]; then
  echo "REFUSING: do not run this as root/sudo. Run as your normal Linux user." >&2
  exit 1
fi

echo "ZOE_ROOT = $ZOE_ROOT"

# --- Directory tree ----------------------------------------------------------
for d in \
  config data data/zoe.db.backup media/video media/image \
  src workflows logs tests ; do
  mkdir -p "$ZOE_ROOT/$d"
done

# --- Helper: write a file only if it does not already exist ------------------
write_once () {
  # $1 = relative path, stdin = contents
  local target="$ZOE_ROOT/$1"
  if [ -e "$target" ]; then
    echo "  skip (exists): $1"
    cat > /dev/null            # drain stdin
  else
    cat > "$target"
    echo "  wrote:          $1"
  fi
}

# --- .gitignore — the governance-critical file (§11, §12, §28) ---------------
write_once ".gitignore" <<'EOF'
# Secrets — NEVER commit (governance §11)
.env
.env.*
!.env.example

# Business data / user identifiers (§11, §12) — binary, sensitive
data/*.db
data/*.db-wal
data/*.db-shm
data/zoe.db.backup/

# Large media assets (§28 resource discipline)
media/

# Runtime logs (§28) — rotate, don't version
logs/

# Python / OS noise
__pycache__/
*.pyc
.venv/
.DS_Store
EOF

# --- .env.example — committed template, NO real values (§11) -----------------
write_once ".env.example" <<'EOF'
# Copy to .env and fill in. .env is gitignored and must NEVER be committed (§11).
# Redact when displaying (§11): sk_live_****************92AD

# --- Runtime mode (§26) ---
DRY_RUN=true            # true = exercise logic, emit NO real external actions
ENVIRONMENT=development # development | production

# --- Database (§30 single source of truth) ---
ZOE_DB_PATH=./data/zoe.db

# --- Media root (schema stores relative paths; root lives here, not in the DB) ---
ZOE_MEDIA_ROOT=./media

# --- Instagram / platform credentials (fill in; keep secret) ---
IG_ACCESS_TOKEN=
IG_ACCOUNT_ID=

# --- Integrations ---
N8N_WEBHOOK_SECRET=
EOF

# --- config/funnel.yaml — single source of truth for URLs (§30, §31) ---------
# URLs left BLANK on purpose. Do not invent them (§31). Fill from the real repo/brand.
write_once "config/funnel.yaml" <<'EOF'
# Funnel destinations — single source of truth (governance §30).
# Referenced by slug elsewhere; defined ONCE here.
# Values intentionally blank — fill with authoritative URLs (§31 no silent assumptions).
destinations:
  vsl:
    url: ""          # e.g. Video Sales Letter endpoint
    purpose: "Video Sales Letter — deep funnel education"
  quiz:
    url: ""          # Interactive segmentation/qualification
    purpose: "Segmentation / qualification tool"
  magnet:
    url: ""          # Lead magnet endpoint
    purpose: "Lead magnet / opt-in"
  live_launch:
    url: ""          # Live launch campaign
    purpose: "Primary live launch campaign"
    date: ""         # launch date — blank in source docs; fill when confirmed

campaigns:
  - live_launch
  - evergreen
EOF

# --- README.md — purpose / recovery (§29) ------------------------------------
write_once "README.md" <<'EOF'
# ZOE v.1 — Project Root

Governed autonomous social-media operations agent for IAS Bootcamp.
This tree is the single home for all ZOE code, config, data, and workflows.

## Layout
- `config/`    single source of truth (funnel URLs, campaigns) — §30
- `data/`      SQLite database + timestamped backups — gitignored — §12, §33
- `media/`     9:16 video/image assets — gitignored, backed up separately — §28
- `src/`       Python: schema, loaders, agent tools — §6
- `workflows/` n8n workflow exports (committed) — §30
- `logs/`      runtime telemetry spillover — gitignored, rotated — §28
- `tests/`     testing contract — §25

## Never committed (§11, §12)
`.env`, `data/*.db`, `media/`. A clone + restored `.env` + media backup
fully reconstitutes ZOE (§33 recoverability).

## Recovery
- Stop:    disable the n8n workflow / stop the runtime.
- Inspect: open `data/zoe.db`; read the append-only `workload_log` (§14).
- Restore: `git clone`, restore `.env` and `media/`, copy back a `zoe.db` backup.

## Environments (§26)
`DRY_RUN=true` by default. Dev and prod are conceptually distinct even on one machine.
EOF

# --- Place the schema if it's sitting next to this script --------------------
if [ -f "./zoe_schema.sql" ] && [ ! -f "$ZOE_ROOT/src/zoe_schema.sql" ]; then
  cp "./zoe_schema.sql" "$ZOE_ROOT/src/zoe_schema.sql"
  echo "  copied:         src/zoe_schema.sql (from current directory)"
else
  echo "  note:           put zoe_schema.sql in $ZOE_ROOT/src/ and build data/zoe.db when ready"
fi

# --- Initialize git if not already a repo ------------------------------------
if [ ! -d "$ZOE_ROOT/.git" ]; then
  git -C "$ZOE_ROOT" init -q
  echo "  git:            initialized empty repo"
else
  echo "  git:            repo already present"
fi

# --- Report (§39) ------------------------------------------------------------
echo
echo "Scaffold complete. Tree:"
find "$ZOE_ROOT" -maxdepth 2 -not -path '*/.git/*' | sort | sed "s|$HOME|~|"
echo
echo "Next:"
echo "  1. cd ~/zoe"
echo "  2. cp .env.example .env   # then fill in real values (never commit .env)"
echo "  3. verify .gitignore is working:  git status --short   (.env must NOT appear)"
echo "  4. build the DB:  python3 -c \"import sqlite3; sqlite3.connect('data/zoe.db').executescript(open('src/zoe_schema.sql').read())\""
