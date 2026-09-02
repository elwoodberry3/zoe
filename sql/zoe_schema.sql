-- ZOE v.1 — Content & Telemetry Schema
-- Engine: SQLite (see governance §27, §28, §36)
-- Principles applied: source-of-truth (§30), observability (§13),
--   auditability/immutability (§14), idempotency (§16), bounded permissions (§8).
--
-- Approval is a HUMAN act. ZOE reads WHERE approved = 1. ZOE never sets approved.

PRAGMA journal_mode = WAL;      -- concurrent read while single writer works
PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- 1. FUNNEL DESTINATIONS — single source of truth for URLs (§30)
--    URLs are configuration, defined once, referenced by id everywhere else.
-- ---------------------------------------------------------------------------
CREATE TABLE funnel_destination (
    id            INTEGER PRIMARY KEY,
    slug          TEXT NOT NULL UNIQUE,          -- e.g. 'vsl', 'quiz', 'magnet', 'live_launch'
    url           TEXT NOT NULL,
    purpose       TEXT,                          -- human-readable role in the funnel
    active        INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ---------------------------------------------------------------------------
-- 2. MEDIA ASSETS — the 9:16 video and image files (§1 deployment matrix)
--    Stores a POINTER (path) + integrity hash, not the media blob itself.
-- ---------------------------------------------------------------------------
CREATE TABLE media_asset (
    id            INTEGER PRIMARY KEY,
    kind          TEXT NOT NULL CHECK (kind IN ('video','image')),
    relative_path TEXT NOT NULL UNIQUE,          -- path under the media root; root is env config, not stored here
    sha256        TEXT,                           -- integrity / dedupe; verify file matches before publish
    aspect_ratio  TEXT NOT NULL DEFAULT '9:16',
    approved      INTEGER NOT NULL DEFAULT 0 CHECK (approved IN (0,1)),
    active        INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_media_ready ON media_asset(kind, approved, active);

-- ---------------------------------------------------------------------------
-- 3. POST COPY — the 100+ approved captions (§1)
-- ---------------------------------------------------------------------------
CREATE TABLE post_copy (
    id            INTEGER PRIMARY KEY,
    body          TEXT NOT NULL,
    dest_id       INTEGER REFERENCES funnel_destination(id),  -- which funnel this copy drives (nullable = unrouted)
    campaign      TEXT,                                        -- e.g. 'live_launch', 'evergreen'
    approved      INTEGER NOT NULL DEFAULT 0 CHECK (approved IN (0,1)),
    active        INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_copy_ready ON post_copy(approved, active, campaign);

-- ---------------------------------------------------------------------------
-- 4. PAIRINGS — human-approved copy↔asset combinations (§10)
--    ZOE's agent SELECTS from approved pairings; it does not INVENT new ones
--    at execution time. This is the boundary between policy and execution.
-- ---------------------------------------------------------------------------
CREATE TABLE pairing (
    id            INTEGER PRIMARY KEY,
    copy_id       INTEGER NOT NULL REFERENCES post_copy(id),
    asset_id      INTEGER NOT NULL REFERENCES media_asset(id),
    approved      INTEGER NOT NULL DEFAULT 0 CHECK (approved IN (0,1)),
    active        INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    created_at    TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (copy_id, asset_id)
);
CREATE INDEX idx_pairing_ready ON pairing(approved, active);

-- ---------------------------------------------------------------------------
-- 5. WORKLOAD LOG — telemetry for the dashboard (§13), append-only (§14)
--    Every consequential action lands here. idempotency_key (§16) prevents a
--    retried workflow from double-logging / double-acting.
-- ---------------------------------------------------------------------------
CREATE TABLE workload_log (
    id               INTEGER PRIMARY KEY,
    idempotency_key  TEXT NOT NULL UNIQUE,        -- deterministic per intended action; retry reuses it
    ts               TEXT NOT NULL DEFAULT (datetime('now')),
    workflow         TEXT NOT NULL,               -- originating n8n workflow / component
    trigger_source   TEXT,                        -- what initiated it (cron, manual, webhook)
    agent            TEXT,                         -- executing agent/component (§13)
    action           TEXT NOT NULL,               -- e.g. 'publish', 'prepare', 'route'
    pairing_id       INTEGER REFERENCES pairing(id),
    asset_id         INTEGER REFERENCES media_asset(id),
    copy_id          INTEGER REFERENCES post_copy(id),
    dest_id          INTEGER REFERENCES funnel_destination(id),
    target_user      TEXT,                        -- engaged user, when applicable
    delay_applied_ms INTEGER,                      -- scheduling delay (§9: scheduling, NOT anti-detection)
    status           TEXT NOT NULL CHECK (status IN ('planned','success','failed','skipped','escalated')),
    duration_ms      INTEGER,
    retry_count      INTEGER NOT NULL DEFAULT 0,
    error            TEXT,
    escalation_state TEXT
);
CREATE INDEX idx_log_ts       ON workload_log(ts);
CREATE INDEX idx_log_workflow ON workload_log(workflow, status);

-- Immutability (§14): block UPDATE and DELETE on the audit record.
CREATE TRIGGER workload_log_no_update
BEFORE UPDATE ON workload_log
BEGIN
    SELECT RAISE(ABORT, 'workload_log is append-only (governance §14)');
END;
CREATE TRIGGER workload_log_no_delete
BEFORE DELETE ON workload_log
BEGIN
    SELECT RAISE(ABORT, 'workload_log is append-only (governance §14)');
END;

-- ---------------------------------------------------------------------------
-- Dashboard read helpers (§13 high-level + granular views)
-- ---------------------------------------------------------------------------

-- What ZOE may act on right now: fully-approved, active pairings joined to their funnel.
CREATE VIEW v_publishable AS
SELECT p.id AS pairing_id, c.id AS copy_id, c.body, c.campaign,
       a.id AS asset_id, a.kind, a.relative_path,
       d.slug AS dest_slug, d.url AS dest_url
FROM pairing p
JOIN post_copy c        ON c.id = p.copy_id AND c.approved = 1 AND c.active = 1
JOIN media_asset a      ON a.id = p.asset_id AND a.approved = 1 AND a.active = 1
LEFT JOIN funnel_destination d ON d.id = c.dest_id
WHERE p.approved = 1 AND p.active = 1;

-- Granular audit feed for the dashboard's line-item record.
CREATE VIEW v_audit_feed AS
SELECT ts, workflow, agent, action, status,
       copy_id, asset_id, dest_id, target_user,
       delay_applied_ms, retry_count, error
FROM workload_log
ORDER BY ts DESC;
