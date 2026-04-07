-- Vault standard schema
-- Every vault instance uses this as its base.

CREATE TABLE IF NOT EXISTS vault_entries (
    slug        TEXT PRIMARY KEY,
    title       TEXT,
    description TEXT,
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS vault_images (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    slug     TEXT NOT NULL,
    filename TEXT NOT NULL,
    port     TEXT,
    UNIQUE(slug, filename)
);

CREATE TABLE IF NOT EXISTS vault_annotations (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    slug       TEXT NOT NULL,
    filename   TEXT,
    content    TEXT NOT NULL,
    source     TEXT DEFAULT 'mcp',
    pinned     INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS galleries (
    slug       TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    images     TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Full-text search on entries
CREATE VIRTUAL TABLE IF NOT EXISTS vault_fts USING fts5(slug, title, description);
