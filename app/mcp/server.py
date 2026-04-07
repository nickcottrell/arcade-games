"""MCP tool server for a vault instance.

Standard vault interface -- search, list, get, annotate, galleries.
Each vault is a self-contained app that can live on any chip or host.

Environment variables:
    VAULT_NAME  -- vault identity (e.g. "rose", "finbot", "geo")
    VAULT_DB    -- path to vault.db (default: vault.db in repo root)
    VAULT_ROOT  -- path to vault content root (default: repo root)
    VAULT_MODE  -- full | lite | sync_only (default: full)
"""

from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

_REPO_ROOT = str(Path(__file__).resolve().parent.parent.parent)
_VAULT_NAME = os.environ.get("VAULT_NAME", Path(_REPO_ROOT).name)
_VAULT_DB = os.environ.get("VAULT_DB", os.path.join(_REPO_ROOT, "vault.db"))
_VAULT_ROOT = os.environ.get("VAULT_ROOT", _REPO_ROOT)
_VAULT_MODE = os.environ.get("VAULT_MODE", "full").strip().lower()

mcp = FastMCP("vault-%s" % _VAULT_NAME)

# ---------------------------------------------------------------------------
# Mode enforcement
# ---------------------------------------------------------------------------

VAULT_MODES = {
    "full": {
        "read": True, "write": True, "search": True,
        "gallery_create": True, "gallery_read": True,
        "annotate": True, "extract": True,
    },
    "lite": {
        "read": True, "write": False, "search": True,
        "gallery_create": False, "gallery_read": True,
        "annotate": False, "extract": False,
    },
    "sync_only": {
        "read": True, "write": False, "search": False,
        "gallery_create": False, "gallery_read": False,
        "annotate": False, "extract": False,
    },
}


def _can(operation):
    perms = VAULT_MODES.get(_VAULT_MODE, VAULT_MODES["full"])
    return bool(perms.get(operation, False))


# ---------------------------------------------------------------------------
# DB helpers
# ---------------------------------------------------------------------------

def _db():
    return sqlite3.connect(_VAULT_DB)


def _json(payload):
    return json.dumps(payload)


def _utc():
    return datetime.now(timezone.utc).isoformat()


def _rows(query, params=()):
    try:
        with _db() as conn:
            conn.row_factory = sqlite3.Row
            return [dict(r) for r in conn.execute(query, params).fetchall()]
    except sqlite3.OperationalError:
        return []


def _count(conn, query, params=()):
    try:
        row = conn.execute(query, params).fetchone()
        return int(row[0] or 0) if row else 0
    except sqlite3.OperationalError:
        return 0


# ---------------------------------------------------------------------------
# Tools: status + search
# ---------------------------------------------------------------------------

@mcp.tool()
def vault_status():
    """Vault identity, entry/image counts, and mode permissions."""
    with _db() as conn:
        entries = _count(conn, "SELECT COUNT(DISTINCT slug) FROM vault_images")
        images = _count(conn, "SELECT COUNT(*) FROM vault_images")
    return _json({
        "vault": _VAULT_NAME,
        "entries": entries,
        "images": images,
        "mode": _VAULT_MODE,
        "permissions": dict(VAULT_MODES.get(_VAULT_MODE, {})),
    })


@mcp.tool()
def vault_search(query, limit=20):
    """Search entries by slug (LIKE match)."""
    if not _can("search"):
        return _json([])
    pattern = "%%%s%%" % (query or "")
    return _json(_rows(
        "SELECT DISTINCT slug FROM vault_images WHERE slug LIKE ? ORDER BY slug LIMIT ?",
        (pattern, int(limit)),
    ))


@mcp.tool()
def vault_get(slug):
    """Get image records for a slug."""
    return _json(_rows(
        "SELECT slug, filename, port FROM vault_images WHERE slug = ? ORDER BY filename",
        (slug,),
    ))


@mcp.tool()
def vault_filter(tag=None, era=None, limit=50):
    """Filter entries by tag or era."""
    return _json(_rows(
        "SELECT DISTINCT slug FROM vault_images ORDER BY slug LIMIT ?",
        (int(limit),),
    ))


@mcp.tool()
def vault_search_images(query, limit=50):
    """Search images by slug or filename."""
    pattern = "%%%s%%" % (query or "")
    return _json(_rows(
        "SELECT slug, filename, port FROM vault_images "
        "WHERE slug LIKE ? OR filename LIKE ? ORDER BY slug, filename LIMIT ?",
        (pattern, pattern, int(limit)),
    ))


@mcp.tool()
def vault_list_images(limit=200):
    """List all indexed images."""
    return _json(_rows(
        "SELECT slug, filename, port FROM vault_images ORDER BY slug, filename LIMIT ?",
        (int(limit),),
    ))


# ---------------------------------------------------------------------------
# Tools: galleries
# ---------------------------------------------------------------------------

@mcp.tool()
def vault_gallery(title=None, slugs=None, query=None):
    """Create or fetch a gallery."""
    if title:
        if not _can("gallery_create"):
            return _json({"error": "gallery_create not permitted in %s mode" % _VAULT_MODE})
        slug = "gallery-%d" % int(datetime.now(timezone.utc).timestamp())
        images = []
        if slugs:
            items = [s.strip() for s in slugs.split(",")] if isinstance(slugs, str) else [str(s) for s in slugs]
            for item in items:
                images.extend(json.loads(vault_get(item)))
        elif query:
            images = json.loads(vault_search_images(query=query, limit=50))
        payload = {"slug": slug, "title": title, "images": images, "created_at": _utc()}
        with _db() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO galleries (slug, title, images, created_at) VALUES (?, ?, ?, ?)",
                (slug, title, json.dumps(images), payload["created_at"]),
            )
            conn.commit()
        return _json(payload)
    if query:
        return vault_search_images(query=query, limit=50)
    return _json([])


@mcp.tool()
def vault_list_galleries(limit=100):
    """List saved galleries."""
    return _json(_rows(
        "SELECT slug, title, created_at FROM galleries ORDER BY created_at DESC LIMIT ?",
        (int(limit),),
    ))


@mcp.tool()
def vault_get_gallery(slug):
    """Get a gallery by slug."""
    rows = _rows("SELECT slug, title, images, created_at FROM galleries WHERE slug = ? LIMIT 1", (slug,))
    if not rows:
        return _json({})
    gallery = rows[0]
    raw = gallery.get("images")
    if isinstance(raw, str):
        try:
            gallery["images"] = json.loads(raw)
        except json.JSONDecodeError:
            gallery["images"] = []
    return _json(gallery)


# ---------------------------------------------------------------------------
# Tools: annotations
# ---------------------------------------------------------------------------

@mcp.tool()
def vault_annotate(slug, filename, body):
    """Create an annotation on an image."""
    if not _can("annotate"):
        return _json({"error": "annotate not permitted in %s mode" % _VAULT_MODE})
    with _db() as conn:
        cur = conn.execute(
            "INSERT INTO vault_annotations (slug, filename, content, source, created_at) "
            "VALUES (?, ?, ?, 'mcp', ?)",
            (slug, filename, body, _utc()),
        )
        conn.commit()
        return _json({"id": int(cur.lastrowid), "slug": slug, "filename": filename, "body": body, "pinned": 0})


@mcp.tool()
def vault_get_annotations(slug=None, filename=None):
    """List annotations with optional filters."""
    q = "SELECT id, slug, filename, content as body, pinned FROM vault_annotations"
    params = []
    filters = []
    if slug:
        filters.append("slug = ?")
        params.append(slug)
    if filename:
        filters.append("filename = ?")
        params.append(filename)
    if filters:
        q += " WHERE " + " AND ".join(filters)
    q += " ORDER BY id DESC"
    return _json(_rows(q, tuple(params)))


if __name__ == "__main__":
    mcp.run(transport="stdio")
