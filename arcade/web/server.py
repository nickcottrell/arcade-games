#!/usr/bin/env python3
"""Arcade Web — browser-based VRGB game player and activity panels.

Spawns a real PTY per game session so bash ROM scripts run unmodified.
xterm.js on the client renders raw ANSI output natively.
Also serves activity panels (vault, money, planning, ops, quick).
"""

import json
import os
import sys
import pty
import select
import signal
import struct
import subprocess
import fcntl
import termios
import threading

import time as _time
from datetime import datetime
from flask import Flask, render_template, abort, request, jsonify
from flask_socketio import SocketIO, emit
from jinja2 import ChoiceLoader, FileSystemLoader

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

ARCADE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAESTRO_DIR = os.environ.get("MAESTRO_ROOT", os.path.dirname(ARCADE_DIR))
MANIFEST_PATH = os.path.join(ARCADE_DIR, "manifest.json")
ROMS_DIR = os.path.join(ARCADE_DIR, "roms")
PORT = int(os.environ.get("ARCADE_WEB_PORT", 3001))
CUE_VOX_PORT = int(os.environ.get("CUE_VOX_PORT", 3000))

JEFF_DIR = os.path.join(MAESTRO_DIR, "tools", "jeff")
CUE_SHEETS_DIR = os.path.join(MAESTRO_DIR, "cue-sheets")

app = Flask(__name__)
app.config["SECRET_KEY"] = "arcade-vrgb"
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")


def _build_template_loader():
    """Build a Jinja loader that discovers templates from:
    1. Arcade's own templates/ dir (games + panel-base.html)
    2. cue-sheets/<slug>/ dirs (legacy panel templates)
    3. Active vault app/web/templates/ dirs (chip panel templates)
    """
    paths = [os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates")]

    # cue-sheet slug dirs
    if os.path.isdir(CUE_SHEETS_DIR):
        for entry in sorted(os.listdir(CUE_SHEETS_DIR)):
            slug_dir = os.path.join(CUE_SHEETS_DIR, entry)
            if os.path.isdir(slug_dir):
                paths.append(slug_dir)

    # Active vault volumes (read Jeff config)
    active_file = os.path.join(JEFF_DIR, ".jeff-volumes-active.json")
    volumes_file = os.path.join(JEFF_DIR, "volumes.json")
    if os.path.isfile(active_file) and os.path.isfile(volumes_file):
        with open(active_file) as fh:
            active_names = json.load(fh)
        with open(volumes_file) as fh:
            volumes_cfg = {v["name"]: v for v in json.load(fh)}
        for vol_name in active_names:
            vol = volumes_cfg.get(vol_name)
            if not vol:
                continue
            vol_path = os.path.join(MAESTRO_DIR, vol["path"])
            if not os.path.isdir(vol_path):
                continue
            if vol.get("type") == "chip":
                for d in sorted(os.listdir(vol_path)):
                    tpl_dir = os.path.join(vol_path, d, "app", "web", "templates")
                    if os.path.isdir(tpl_dir):
                        paths.append(tpl_dir)
            else:
                tpl_dir = os.path.join(vol_path, "app", "web", "templates")
                if os.path.isdir(tpl_dir):
                    paths.append(tpl_dir)

    return ChoiceLoader([FileSystemLoader(p) for p in paths])


app.jinja_loader = _build_template_loader()

# Active PTY sessions keyed by socket request.sid
sessions = {}


# ---------------------------------------------------------------------------
# Manifest helpers
# ---------------------------------------------------------------------------

def load_manifest():
    with open(MANIFEST_PATH) as f:
        return json.load(f)


def find_rom(slug):
    manifest = load_manifest()
    for rom in manifest.get("roms", []):
        if rom["slug"] == slug:
            return rom
    return None


def check_cue_vox():
    """Return True if cue-vox is listening on its port."""
    import socket as _socket
    with _socket.socket(_socket.AF_INET, _socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", CUE_VOX_PORT)) == 0


# ---------------------------------------------------------------------------
# HTTP routes
# ---------------------------------------------------------------------------

@app.route("/")
def picker():
    manifest = load_manifest()
    roms = manifest.get("roms", [])
    server_up = check_cue_vox()
    return render_template("picker.html", roms=roms, server_up=server_up,
                           cache_bust=int(_time.time()))


@app.route("/play/<slug>")
def player(slug):
    rom = find_rom(slug)
    if not rom:
        abort(404)
    return render_template("player.html", rom=rom,
                           cache_bust=int(_time.time()))


# ---------------------------------------------------------------------------
# Activity Panels
# ---------------------------------------------------------------------------

PULL_STAGING_DIR = os.path.join(MAESTRO_DIR, "tools", "zapier", "pull", "latest")
CUESHEETS_DIR = os.path.join(MAESTRO_DIR, "cue-sheets")


def _pull_agent_status():
    """Read pull agent freshness from _staging/latest/ timestamps."""
    agents = []
    for name in ("calendar", "horizon", "gmail"):
        path = os.path.join(PULL_STAGING_DIR, name + ".json")
        age_str = "no data"
        freshness = "unknown"
        if os.path.isfile(path):
            mtime = os.path.getmtime(path)
            age_sec = _time.time() - mtime
            if age_sec < 3600:
                age_str = "%dm ago" % (age_sec / 60)
                freshness = "fresh"
            elif age_sec < 14400:
                age_str = "%.1fh ago" % (age_sec / 3600)
                freshness = "aging"
            else:
                age_str = "%.1fh ago" % (age_sec / 3600)
                freshness = "stale"
        agents.append({"name": name.title(), "age": age_str, "freshness": freshness})
    return agents


@app.route("/api/ops/status")
def api_ops_status():
    """Return pull agent status as JSON for live refresh."""
    agents = _pull_agent_status()
    return jsonify({"agents": agents, "checked_at": _time.strftime("%I:%M %p")})


@app.route("/panel/vault")
def panel_vault():
    return render_template("vault-panel.html", cache_bust=int(_time.time()))


@app.route("/panel/money")
def panel_money():
    return render_template("money-panel.html", cache_bust=int(_time.time()))


@app.route("/panel/planning")
def panel_planning():
    return render_template("planning-panel.html", cache_bust=int(_time.time()))


@app.route("/panel/ops")
def panel_ops():
    agents = _pull_agent_status()
    return render_template("ops-panel.html", agents=agents,
                           cache_bust=int(_time.time()))


@app.route("/panel/quick")
def panel_quick():
    return render_template("quick-panel.html", cache_bust=int(_time.time()))


@app.route("/panel/compose")
def panel_compose():
    return render_template("compose-panel.html", cache_bust=int(_time.time()))


# ---------------------------------------------------------------------------
# Tracks landscape API
# ---------------------------------------------------------------------------

# The canonical 7 life categories (Trello board columns)
CANONICAL_CATEGORIES = [
    {"slug": "wealth", "name": "Wealth", "icon": "\U0001f4b0"},
    {"slug": "home", "name": "Home", "icon": "\U0001f3e1"},
    {"slug": "play", "name": "Play", "icon": "\U0001f3ad"},
    {"slug": "work", "name": "Work", "icon": "\U0001f4bc"},
    {"slug": "family", "name": "Family", "icon": "\U0001f468\u200d\U0001f469\u200d\U0001f467"},
    {"slug": "school-church", "name": "School & Church", "icon": "\U0001f3b6"},
    {"slug": "health", "name": "Health", "icon": "\U0001f9d8"},
]

# Map Trello label/list text to canonical slug (fuzzy matching)
_LABEL_TO_SLUG = {}
for _cat in CANONICAL_CATEGORIES:
    _LABEL_TO_SLUG[_cat["name"].lower()] = _cat["slug"]
    # Also map individual words for label matching
    for _word in _cat["name"].lower().split():
        if _word not in ("&",):
            _LABEL_TO_SLUG[_word] = _cat["slug"]


def _match_category(text):
    """Match a label or list name to a canonical category slug."""
    clean = text.strip().lower()
    for key in _LABEL_TO_SLUG:
        if key in clean:
            return _LABEL_TO_SLUG[key]
    return None


def _load_trello_items():
    """Load active Trello cards grouped by canonical category.

    Supports two data shapes:
    1. Category-named lists (wealth, home, play, etc.) as top-level keys
    2. doing/todo lists with label-based categorization
    """
    trello_path = os.path.join(PULL_STAGING_DIR, "trello.json")
    if not os.path.isfile(trello_path):
        return {}
    try:
        with open(trello_path) as fh:
            raw = json.load(fh)
        data = raw.get("data", {})
        items_by_cat = {}

        # Priority: category-named lists first, then "doing" list
        # Skip "todo" (backlog) — only show active work
        cat_lists = []
        active_lists = []
        for list_name in data:
            if not isinstance(data[list_name], list):
                continue
            if _match_category(list_name):
                cat_lists.append(list_name)
            elif list_name.lower() == "doing":
                active_lists.append(list_name)

        for list_name in cat_lists + active_lists:
            cards = data[list_name]

            # Check if the list name itself IS a canonical category
            list_slug = _match_category(list_name)

            for card in cards:
                card_name = card.get("name", "")
                if not card_name:
                    continue

                # Determine category: list name first, then labels
                slug = list_slug
                if not slug:
                    for label in card.get("labels", []):
                        slug = _match_category(label)
                        if slug:
                            break

                if not slug:
                    slug = "uncategorized"

                if slug not in items_by_cat:
                    items_by_cat[slug] = []
                items_by_cat[slug].append({
                    "name": card_name,
                    "due": card.get("due_date"),
                    "list": list_name,
                })

        return items_by_cat
    except Exception:
        return {}


def _thermal_label(temp):
    if temp >= 60:
        return "hot"
    if temp >= 30:
        return "warm"
    if temp >= 15:
        return "cool"
    return "cold"


def _ensure_cuemem():
    """Ensure cue-mem lib is importable."""
    cuemem_lib = os.path.join(MAESTRO_DIR, "cue-mem", "lib")
    if cuemem_lib not in sys.path:
        sys.path.insert(0, cuemem_lib)


@app.route("/api/tracks/landscape")
def api_tracks_landscape():
    """Return work context — what you are doing and figuring out."""
    _ensure_cuemem()

    try:
        from tokens import list_tokens
        all_tokens = list_tokens()
    except ImportError:
        all_tokens = []

    # --- Section 1: Recent sessions (deduped cue-sheet launches) ---
    sessions = {}
    for t in all_tokens:
        tags = t.get("tags", [])
        if "buff-launch" not in tags:
            continue
        temp = t.get("current_temperature", t.get("temperature", 0))
        if temp < 20:
            continue
        for tag in tags:
            if tag.startswith("buff:"):
                name = tag.split(":", 1)[1]
                if name not in sessions or temp > sessions[name]["temp"]:
                    sessions[name] = {
                        "name": name.replace("-", " ").title(),
                        "slug": name,
                        "temp": round(temp),
                        "thermal": _thermal_label(temp),
                    }

    session_list = sorted(sessions.values(), key=lambda s: -s["temp"])

    # --- Section 2: Trello doing cards grouped by canonical category ---
    trello_items = _load_trello_items()
    categories = []
    for cat in CANONICAL_CATEGORIES:
        slug = cat["slug"]
        items = trello_items.get(slug, [])
        if not items:
            continue
        categories.append({
            "slug": slug,
            "name": cat["name"],
            "icon": cat["icon"],
            "items": [{"name": i["name"]} for i in items[:3]],
            "total": len(items),
        })

    # Uncategorized doing cards
    uncat = trello_items.get("uncategorized", [])
    if uncat:
        categories.append({
            "slug": "uncategorized",
            "name": "Other",
            "icon": "",
            "items": [{"name": i["name"]} for i in uncat[:3]],
            "total": len(uncat),
        })

    # Sort by item count
    categories.sort(key=lambda c: -c["total"])

    # --- Section 3: Radar items (user-added context) ---
    radar = []
    for t in all_tokens:
        tags = t.get("tags", [])
        if "radar" not in tags:
            continue
        temp = t.get("current_temperature", t.get("temperature", 0))
        if temp < 5:
            continue
        value = str(t.get("value", "")).replace("\n", " ").strip()
        if not value:
            continue
        cat_slug = ""
        for tag in tags:
            if tag.startswith("cat:"):
                cat_slug = tag.split(":", 1)[1]
        radar.append({
            "value": value[:100],
            "category": cat_slug,
            "temp": round(temp),
            "thermal": _thermal_label(temp),
        })
    radar.sort(key=lambda r: -r["temp"])

    return jsonify({
        "sessions": session_list[:6],
        "doing": categories,
        "radar": radar[:5],
    })


# Intent detection keywords for cue-sheet routing
_INTENT_PATTERNS = {
    "add-to-trello": [
        "trello", "add to board", "add a card", "put on trello",
        "track this", "add to doing",
    ],
    "add-to-calendar": [
        "calendar", "schedule", "book", "set a reminder",
        "add an event", "put on calendar", "appointment",
    ],
    "draft-email": [
        "email", "draft", "send a message", "write to",
        "reply to", "respond to", "mail",
    ],
}


@app.route("/api/tracks/do", methods=["POST"])
def api_tracks_do():
    """Submit an action: create a token, detect intent, return cue-sheet to launch."""
    _ensure_cuemem()

    data = request.get_json(force=True)
    text = (data.get("text") or "").strip()
    urgency = int(data.get("urgency", 25))

    if not text:
        return jsonify({"ok": False, "error": "empty text"}), 400

    # Detect intent from text
    text_lower = text.lower()
    cuesheet = "quick-task"
    for sheet, patterns in _INTENT_PATTERNS.items():
        for pattern in patterns:
            if pattern in text_lower:
                cuesheet = sheet
                break
        if cuesheet != "quick-task":
            break

    # Map urgency 0-100 to base temp (40-95)
    base_temp = 40 + (urgency / 100.0) * 55

    try:
        from tokens import create_token
        token = create_token(
            label="action",
            value=text,
            token_type="radar",
            visibility="shared",
            base_temp=base_temp,
            half_life_hours=168,
            tags=["radar", "take-action", "route:" + cuesheet],
        )
        return jsonify({
            "ok": True,
            "token_id": token.get("token_id", ""),
            "cuesheet": cuesheet,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Compose API (block-based document composition)
# ---------------------------------------------------------------------------

COMPOSE_DIR = os.path.join(MAESTRO_DIR, ".compose")


def _safe_slug(value, fallback="default"):
    """Strip a value down to a safe filesystem slug."""
    import re
    slug = re.sub(r"[^a-zA-Z0-9_-]", "", str(value))
    return slug[:64] if slug else fallback


def _compose_doc_dir(doc_id):
    """Return the directory for a composition document, creating if needed."""
    safe_id = _safe_slug(doc_id)
    d = os.path.join(COMPOSE_DIR, safe_id)
    os.makedirs(d, exist_ok=True)
    return d


def _load_doc_meta(doc_id):
    """Load or create document metadata."""
    doc_dir = _compose_doc_dir(doc_id)
    meta_path = os.path.join(doc_dir, "meta.json")
    if os.path.isfile(meta_path):
        with open(meta_path, "r") as f:
            return json.load(f)
    meta = {
        "doc_id": doc_id,
        "title": "Untitled",
        "origin": None,
        "chain": [],
        "created_at": datetime.now().isoformat(),
        "updated_at": datetime.now().isoformat(),
    }
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    return meta


def _save_doc_meta(doc_id, meta):
    """Persist document metadata."""
    doc_dir = _compose_doc_dir(doc_id)
    meta["updated_at"] = datetime.now().isoformat()
    with open(os.path.join(doc_dir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)


def _load_blocks(doc_id):
    """Load the ordered block list for a document."""
    doc_dir = _compose_doc_dir(doc_id)
    blocks_path = os.path.join(doc_dir, "blocks.json")
    if os.path.isfile(blocks_path):
        with open(blocks_path, "r") as f:
            return json.load(f)
    return []


def _save_blocks(doc_id, blocks):
    """Persist the ordered block list."""
    doc_dir = _compose_doc_dir(doc_id)
    with open(os.path.join(doc_dir, "blocks.json"), "w") as f:
        json.dump(blocks, f, indent=2)


@app.route("/api/compose/doc", methods=["GET"])
def api_compose_doc():
    """Load a document and its blocks."""
    doc_id = request.args.get("id", "default")
    meta = _load_doc_meta(doc_id)
    blocks = _load_blocks(doc_id)
    return jsonify({"meta": meta, "blocks": blocks})


@app.route("/api/compose/state", methods=["GET"])
def api_compose_state():
    """Return the full document state as Claude would read it.

    Returns title, block count, updated_at, and a plain-text rendering
    of all blocks so Claude can understand the document without parsing JSON.
    """
    doc_id = request.args.get("doc_id", "default")
    meta = _load_doc_meta(doc_id)
    blocks = _load_blocks(doc_id)
    context = _load_context(doc_id)

    # Render blocks as a readable outline
    lines = []
    for i, b in enumerate(blocks):
        prefix = "[%d:%s:%s]" % (i, b.get("type", "text"), b.get("id", "?"))
        content = b.get("content", "").replace("\n", " | ")
        lines.append("%s %s" % (prefix, content))

    # Render context cards
    ctx_lines = []
    for c in context:
        ctx_lines.append("[%s] %s: %s" % (c.get("card_type", "?"), c.get("label", "?"), c.get("value", "")))

    chain = meta.get("chain", [])
    return jsonify({
        "title": meta.get("title", "Untitled"),
        "origin": meta.get("origin"),
        "updated_at": meta.get("updated_at", ""),
        "block_count": len(blocks),
        "blocks": blocks,
        "text": "\n".join(lines),
        "context_cards": context,
        "context_text": "\n".join(ctx_lines),
        "chain_length": len(chain),
        "latest_save": chain[-1] if chain else None,
    })


@app.route("/api/compose/title", methods=["POST"])
def api_compose_title():
    """Update document title."""
    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")
    title = (data.get("title") or "").strip() or "Untitled"
    meta = _load_doc_meta(doc_id)
    meta["title"] = title
    _save_doc_meta(doc_id, meta)
    return jsonify({"ok": True, "title": title})


@app.route("/api/compose/blocks", methods=["POST"])
def api_compose_add_block():
    """Add a block to the composition."""
    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")
    block_type = data.get("type", "text")
    content = data.get("content", "")

    block_id = "blk_%s_%s" % (
        block_type[:3],
        datetime.now().strftime("%H%M%S%f")[:10]
    )

    block = {
        "id": block_id,
        "type": block_type,
        "content": content,
        "created_at": datetime.now().isoformat(),
    }

    blocks = _load_blocks(doc_id)
    blocks.append(block)
    _save_blocks(doc_id, blocks)

    # Update doc timestamp
    meta = _load_doc_meta(doc_id)
    _save_doc_meta(doc_id, meta)

    return jsonify({"ok": True, "block": block})


@app.route("/api/compose/blocks/<block_id>", methods=["PUT"])
def api_compose_update_block(block_id):
    """Update a block content."""
    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")
    content = data.get("content", "")

    blocks = _load_blocks(doc_id)
    for b in blocks:
        if b["id"] == block_id:
            b["content"] = content
            b["updated_at"] = datetime.now().isoformat()
            break
    _save_blocks(doc_id, blocks)
    return jsonify({"ok": True})


@app.route("/api/compose/blocks/<block_id>", methods=["DELETE"])
def api_compose_remove_block(block_id):
    """Remove a block from the composition."""
    doc_id = request.args.get("doc_id", "default")
    blocks = _load_blocks(doc_id)
    blocks = [b for b in blocks if b["id"] != block_id]
    _save_blocks(doc_id, blocks)
    return jsonify({"ok": True})


@app.route("/api/compose/reorder", methods=["POST"])
def api_compose_reorder():
    """Reorder blocks by providing an ordered list of block IDs."""
    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")
    order = data.get("order", [])

    blocks = _load_blocks(doc_id)
    block_map = {}
    for b in blocks:
        block_map[b["id"]] = b

    reordered = []
    for bid in order:
        if bid in block_map:
            reordered.append(block_map.pop(bid))
    # Append any blocks not in the order list (safety net)
    for b in block_map.values():
        reordered.append(b)

    _save_blocks(doc_id, reordered)
    return jsonify({"ok": True})


@app.route("/api/compose/export", methods=["POST"])
def api_compose_export():
    """Export the composition as markdown."""
    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")

    meta = _load_doc_meta(doc_id)
    blocks = _load_blocks(doc_id)

    lines = ["# %s" % meta.get("title", "Untitled"), ""]

    for b in blocks:
        btype = b.get("type", "text")
        content = b.get("content", "")
        if btype == "text":
            lines.append(content)
            lines.append("")
        elif btype == "heading":
            lines.append("## %s" % content)
            lines.append("")
        elif btype == "divider":
            lines.append("---")
            lines.append("")
        elif btype == "quote":
            for qline in content.split("\n"):
                lines.append("> %s" % qline)
            lines.append("")
        elif btype == "list":
            for lline in content.split("\n"):
                stripped = lline.strip()
                if stripped:
                    lines.append("- %s" % stripped)
            lines.append("")
        else:
            lines.append(content)
            lines.append("")

    md = "\n".join(lines)

    # Save to file
    out_dir = os.path.join(MAESTRO_DIR, "vault-hot", "HOT")
    os.makedirs(out_dir, exist_ok=True)
    slug = meta.get("title", "untitled").lower().replace(" ", "-")[:40]
    filename = "%s_%s.md" % (slug, datetime.now().strftime("%Y%m%d-%H%M%S"))
    out_path = os.path.join(out_dir, filename)
    with open(out_path, "w") as f:
        f.write(md)

    # --- Chain: link this save to the previous one via tokens ---
    _ensure_cuemem()

    # Find the previous save's token_id (last entry in the chain)
    chain = meta.get("chain", [])
    prev_token_id = chain[-1].get("token_id") if chain else None

    # Create a save token that references the previous save
    save_token_id = None
    try:
        from tokens import create_token
        extra = {"save_path": out_path, "doc_id": doc_id}
        if prev_token_id:
            extra["references"] = [prev_token_id]
        if meta.get("origin"):
            extra["origin"] = meta["origin"]

        token = create_token(
            label="save:%s" % slug,
            value="saved %s" % filename,
            token_type="context",
            visibility="shared",
            base_temp=55,
            half_life_hours=168,
            tags=["compose", "compose:%s" % doc_id, "save"],
            extra_fields=extra,
        )
        save_token_id = token.get("token_id", "")
    except Exception:
        pass

    # Append to the chain
    chain.append({
        "filename": filename,
        "path": out_path,
        "token_id": save_token_id,
        "prev_token_id": prev_token_id,
        "saved_at": datetime.now().isoformat(),
    })
    meta["chain"] = chain
    _save_doc_meta(doc_id, meta)

    return jsonify({
        "ok": True,
        "path": out_path,
        "filename": filename,
        "markdown": md,
        "chain_length": len(chain),
        "token_id": save_token_id,
    })


# --- Context rail: token-backed cards chained to a composition ---

def _context_file(doc_id):
    """Return path to the context cards index for a doc."""
    return os.path.join(_compose_doc_dir(doc_id), "context.json")


def _load_context(doc_id):
    """Load context cards list."""
    path = _context_file(doc_id)
    if os.path.isfile(path):
        with open(path, "r") as f:
            return json.load(f)
    return []


def _save_context(doc_id, cards):
    """Persist context cards list."""
    with open(_context_file(doc_id), "w") as f:
        json.dump(cards, f, indent=2)


@app.route("/api/compose/context", methods=["GET"])
def api_compose_context_list():
    """List context cards for a document."""
    doc_id = request.args.get("doc_id", "default")
    cards = _load_context(doc_id)
    return jsonify({"cards": cards})


@app.route("/api/compose/context", methods=["POST"])
def api_compose_context_add():
    """Add a context card — creates a real token in the thermal pool."""
    _ensure_cuemem()
    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")
    card_type = data.get("card_type", "note")
    label = data.get("label", card_type)
    value = data.get("value", "")

    # Build the card record
    card = {
        "card_type": card_type,
        "label": label,
        "value": str(value),
        "created_at": datetime.now().isoformat(),
    }

    if card_type == "slider":
        card["slider_value"] = int(data.get("value", 50))
        card["scale_low"] = data.get("scale_low", "low")
        card["scale_high"] = data.get("scale_high", "high")
        # Build semantic value text
        pct = card["slider_value"]
        if pct < 25:
            card["value"] = card["scale_low"]
        elif pct < 50:
            card["value"] = "leaning " + card["scale_low"]
        elif pct < 75:
            card["value"] = "leaning " + card["scale_high"]
        else:
            card["value"] = card["scale_high"]

    elif card_type == "yesno":
        card["answer"] = None

    # Create a real token in the thermal pool
    try:
        from tokens import create_token
        token = create_token(
            label=label,
            value=card["value"],
            token_type="context",
            visibility="shared",
            base_temp=65,
            half_life_hours=24,
            tags=["compose", "compose:%s" % doc_id, "card:%s" % card_type],
        )
        card["token_id"] = token.get("token_id", "")
    except Exception as e:
        # Still save the card even if token creation fails
        card["token_id"] = "local_%s" % datetime.now().strftime("%H%M%S%f")[:10]

    # Persist to context index
    cards = _load_context(doc_id)
    cards.append(card)
    _save_context(doc_id, cards)

    return jsonify({"ok": True, "card": card})


@app.route("/api/compose/context/<token_id>", methods=["DELETE"])
def api_compose_context_remove(token_id):
    """Remove a context card and resolve its token."""
    doc_id = request.args.get("doc_id", "default")
    cards = _load_context(doc_id)
    cards = [c for c in cards if c.get("token_id") != token_id]
    _save_context(doc_id, cards)
    return jsonify({"ok": True})


@app.route("/api/compose/context/<token_id>/answer", methods=["POST"])
def api_compose_context_answer(token_id):
    """Answer a yes/no context card — updates the token value."""
    _ensure_cuemem()
    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")
    answer = data.get("answer", "")

    cards = _load_context(doc_id)
    updated_card = None
    for card in cards:
        if card.get("token_id") == token_id:
            card["answer"] = answer
            card["value"] = card.get("label", "decision") + ": " + answer
            updated_card = card
            break
    _save_context(doc_id, cards)

    # Update the token file value directly
    if updated_card and not token_id.startswith("local_"):
        try:
            token_path = os.path.join(MAESTRO_DIR, ".claude", "tokens", "%s.json" % token_id)
            if os.path.isfile(token_path):
                with open(token_path, "r") as tf:
                    tok = json.load(tf)
                tok["value"] = updated_card["value"]
                with open(token_path, "w") as tf:
                    json.dump(tok, tf, indent=2)
        except Exception:
            pass

    return jsonify({"ok": True, "card": updated_card})


@app.route("/api/compose/import-md", methods=["POST"])
def api_compose_import_md():
    """Parse a markdown string into canvas blocks, replacing current content."""
    import re

    data = request.get_json(force=True)
    doc_id = data.get("doc_id", "default")
    md = data.get("markdown", "")
    filename = data.get("filename", "")

    # Extract title from first H1 or use filename
    lines = md.split("\n")
    title = os.path.splitext(filename)[0] if filename else "Untitled"
    body_start = 0

    if lines and lines[0].startswith("# "):
        title = lines[0][2:].strip()
        body_start = 1
        # Skip blank line after title
        if body_start < len(lines) and lines[body_start].strip() == "":
            body_start += 1

    # Update doc title and record origin
    meta = _load_doc_meta(doc_id)
    meta["title"] = title
    meta["origin"] = filename
    if "chain" not in meta:
        meta["chain"] = []
    _save_doc_meta(doc_id, meta)

    # Parse remaining lines into blocks
    blocks = []
    current_text = []

    def flush_text():
        if current_text:
            content = "\n".join(current_text).strip()
            if content:
                blocks.append({"type": "text", "content": content})
            current_text[:] = []

    for line in lines[body_start:]:
        stripped = line.strip()

        # Heading (## or ###)
        if re.match(r"^#{2,6}\s+", line):
            flush_text()
            heading_text = re.sub(r"^#{2,6}\s+", "", line).strip()
            blocks.append({"type": "heading", "content": heading_text})

        # Horizontal rule
        elif re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped):
            flush_text()
            blocks.append({"type": "divider", "content": ""})

        # Blockquote
        elif stripped.startswith("> "):
            flush_text()
            blocks.append({"type": "quote", "content": stripped[2:]})

        # List item
        elif re.match(r"^[-*+]\s+", stripped):
            # Collect consecutive list items
            if current_text and not re.match(r"^[-*+]\s+", current_text[-1].strip()):
                flush_text()
            item_text = re.sub(r"^[-*+]\s+", "", stripped)
            current_text.append(item_text)

        # Blank line — flush
        elif stripped == "":
            # Check if current_text looks like list items
            if current_text and re.match(r"^[^#>-]", current_text[0].strip()):
                flush_text()
            elif current_text:
                # List block
                content = "\n".join(current_text).strip()
                if content:
                    blocks.append({"type": "text", "content": content})
                current_text[:] = []

        # Regular text
        else:
            current_text.append(line)

    flush_text()

    # Save blocks with IDs
    saved_blocks = []
    for i, b in enumerate(blocks):
        block_id = "blk_%s_%s%02d" % (
            b["type"][:3],
            datetime.now().strftime("%H%M%S"),
            i
        )
        saved_blocks.append({
            "id": block_id,
            "type": b["type"],
            "content": b["content"],
            "created_at": datetime.now().isoformat(),
        })

    _save_blocks(doc_id, saved_blocks)

    # --- Hydrate chained tokens from the pool ---
    # Look for tokens tagged compose:* that reference this filename or origin
    hydrated_cards = []
    _ensure_cuemem()
    try:
        from tokens import list_tokens
        all_tokens = list_tokens()
        # Find the most recent save token that matches this filename
        origin_doc_id = None
        for t in all_tokens:
            tags = t.get("tags", [])
            extra = t.get("extra_fields", {}) or {}
            # Match by save_path containing the filename, or origin field
            if "save" in tags and "compose" in tags:
                save_path = extra.get("save_path", "") or t.get("value", "")
                if filename in save_path:
                    # Found a save token for this file — extract its doc_id from tags
                    for tag in tags:
                        if tag.startswith("compose:") and tag != "compose":
                            origin_doc_id = tag.split(":", 1)[1]
                            break
                    break

        # If we found the original doc_id, re-save everything under it
        # so the chain stays connected
        if origin_doc_id:
            # Re-save blocks and meta under the original doc_id
            orig_meta = _load_doc_meta(origin_doc_id)
            orig_meta["title"] = title
            orig_meta["origin"] = filename
            if "chain" not in orig_meta:
                orig_meta["chain"] = []
            _save_doc_meta(origin_doc_id, orig_meta)
            _save_blocks(origin_doc_id, saved_blocks)
            # Point doc_id to the original for the rest of this request
            doc_id = origin_doc_id

            for t in all_tokens:
                tags = t.get("tags", [])
                if ("compose:%s" % origin_doc_id) in tags and "save" not in tags:
                    # Determine card type from tags
                    card_type = "note"
                    for tag in tags:
                        if tag.startswith("card:"):
                            card_type = tag.split(":", 1)[1]
                            break
                    card = {
                        "card_type": card_type,
                        "label": t.get("label", card_type),
                        "value": t.get("value", ""),
                        "token_id": t.get("token_id", ""),
                        "created_at": t.get("created_at", ""),
                    }
                    if card_type == "slider":
                        card["slider_value"] = t.get("slider_value", 50)
                        card["scale_low"] = t.get("scale_low", "low")
                        card["scale_high"] = t.get("scale_high", "high")
                    elif card_type == "yesno":
                        card["answer"] = t.get("answer")
                    elif card_type == "image":
                        card["filename"] = t.get("value", "").replace("imported ", "").replace(" to HOT", "")
                    hydrated_cards.append(card)

            # Save hydrated cards as context for this new doc
            if hydrated_cards:
                _save_context(doc_id, hydrated_cards)
    except Exception:
        pass

    return jsonify({
        "ok": True,
        "block_count": len(saved_blocks),
        "title": title,
        "hydrated_context": len(hydrated_cards),
        "origin_doc_id": origin_doc_id,
    })


@app.route("/api/compose/upload", methods=["POST"])
def api_compose_upload():
    """Accept a file drop -- save to vault-hot/HOT and create a context card."""
    _ensure_cuemem()

    uploaded = request.files.get("file")
    if not uploaded or not uploaded.filename:
        return jsonify({"ok": False, "error": "No file"}), 400

    # Size guard: 20MB max
    uploaded.seek(0, 2)
    size = uploaded.tell()
    uploaded.seek(0)
    if size > 20 * 1024 * 1024:
        return jsonify({"ok": False, "error": "File too large (20MB max)"}), 400

    # Sanitize filename: strip path components, keep only safe chars
    from werkzeug.utils import secure_filename
    raw_name = secure_filename(uploaded.filename)
    if not raw_name:
        return jsonify({"ok": False, "error": "Invalid filename"}), 400

    ext = os.path.splitext(raw_name)[1].lower()
    allowed = {".png", ".jpg", ".jpeg", ".csv"}
    if ext not in allowed:
        return jsonify({"ok": False, "error": "File type not allowed"}), 400

    filename = raw_name

    # Save to vault-hot/HOT
    hot_dir = os.path.join(MAESTRO_DIR, "vault-hot", "HOT")
    os.makedirs(hot_dir, exist_ok=True)
    dest = os.path.join(hot_dir, filename)

    # Avoid overwriting — append timestamp if exists
    if os.path.exists(dest):
        name, extension = os.path.splitext(filename)
        filename = "%s_%s%s" % (name, datetime.now().strftime("%H%M%S"), extension)
        dest = os.path.join(hot_dir, filename)

    uploaded.save(dest)

    doc_id = request.form.get("doc_id", "default")

    # Determine card type from extension
    if ext in (".png", ".jpg", ".jpeg"):
        card_type = "image"
        label = "image"
    else:
        card_type = "file"
        label = "csv"

    card = {
        "card_type": card_type,
        "label": label,
        "value": filename,
        "filename": filename,
        "path": dest,
        "created_at": datetime.now().isoformat(),
    }

    # Create a token in the thermal pool
    try:
        from tokens import create_token
        token = create_token(
            label="import:%s" % label,
            value="imported %s to HOT" % filename,
            token_type="context",
            visibility="shared",
            base_temp=60,
            half_life_hours=24,
            tags=["compose", "compose:%s" % doc_id, "card:%s" % card_type, "import"],
        )
        card["token_id"] = token.get("token_id", "")
    except Exception:
        card["token_id"] = "local_%s" % datetime.now().strftime("%H%M%S%f")[:10]

    # Persist to context index
    cards = _load_context(doc_id)
    cards.append(card)
    _save_context(doc_id, cards)

    return jsonify({"ok": True, "card": card})


# ---------------------------------------------------------------------------
# Vault image serving (shared resolver)
# ---------------------------------------------------------------------------

_vault_serve_lib = os.path.join(MAESTRO_DIR, "tools", "vault-template", "app")
if _vault_serve_lib not in sys.path:
    sys.path.insert(0, _vault_serve_lib)
try:
    from serve import resolve_image as _vault_resolve_image
except ImportError:
    _vault_resolve_image = None

_VAULT_DB = os.path.join(MAESTRO_DIR, "vault-hot", "vault.db")
_VAULT_ROOT = os.path.join(MAESTRO_DIR, "vault-hot")


@app.route("/vault/hot/<slug>/<path:filename>")
def serve_vault_hot(slug, filename):
    """Serve registered images from the hot port."""
    from flask import send_from_directory
    directory, fname = _vault_resolve_image(slug, filename, "hot", _VAULT_DB, _VAULT_ROOT)
    if directory is None:
        return "Not found", 404
    return send_from_directory(directory, fname)


@app.route("/vault/cold/<slug>/<path:filename>")
def serve_vault_cold(slug, filename):
    """Serve registered images from the cold port."""
    from flask import send_from_directory
    directory, fname = _vault_resolve_image(slug, filename, "cold", _VAULT_DB, _VAULT_ROOT)
    if directory is None:
        return "Not found", 404
    return send_from_directory(directory, fname)


@app.route("/hot-file/<path:filename>")
def hot_file(filename):
    """Serve flat files from vault-hot/HOT (compose uploads)."""
    from flask import send_from_directory
    hot_dir = os.path.join(MAESTRO_DIR, "vault-hot", "HOT")
    full = os.path.join(hot_dir, filename)
    if os.path.isfile(full):
        return send_from_directory(os.path.dirname(full), os.path.basename(full))
    return "Not found", 404


# ---------------------------------------------------------------------------
# Panel API endpoints (lightweight data for panel UIs)
# ---------------------------------------------------------------------------

@app.route("/api/vault/search")
def api_vault_search():
    """Hybrid BM25 + vector search over the vault."""
    query = request.args.get("q", "")
    mode = request.args.get("mode", "hybrid")
    port = request.args.get("port", "")
    limit = min(int(request.args.get("limit", 20)), 50)
    if not query:
        return jsonify({"results": []})

    # Import vault search directly -- no subprocess
    vault_lib = os.path.join(MAESTRO_DIR, "tools", "vault-template", "app")
    if vault_lib not in sys.path:
        sys.path.insert(0, vault_lib)

    try:
        from config import get_fts_db_path
        from fts import get_connection, hybrid_search, search as fts_search, vector_search

        db_path = get_fts_db_path()
        if not os.path.isfile(db_path):
            return jsonify({"results": [], "error": "vault.db not found"})

        conn = get_connection(db_path)
        port_filter = port if port else None

        if mode == "vector":
            results = vector_search(conn, query, limit=limit, port=port_filter)
        elif mode == "keyword":
            results = fts_search(conn, query, limit=limit, port=port_filter)
        else:
            results = hybrid_search(conn, query, limit=limit, port=port_filter)

        # Fetch first image for each result
        slug_images = {}
        for r in results:
            slug = r.get("slug", "")
            if slug and slug not in slug_images:
                row = conn.execute(
                    "SELECT filename, port FROM vault_images WHERE slug = ? LIMIT 1",
                    (slug,)
                ).fetchone()
                if row:
                    slug_images[slug] = (row[0], row[1] or "cold")

        conn.close()

        # Clean up results for JSON
        clean = []
        for r in results:
            slug = r.get("slug", "")
            entry = {
                "slug": slug,
                "title": r.get("title", ""),
                "summary": r.get("summary", ""),
                "category": r.get("category", ""),
                "era": r.get("era", ""),
                "tags": r.get("tags", ""),
                "port": r.get("port", "cold"),
                "score": round(r.get("score", r.get("rank", 0)), 3),
                "snippet": r.get("snippet", ""),
                "word_count": r.get("word_count", 0),
            }
            if slug in slug_images:
                img_fname, img_port = slug_images[slug]
                entry["image"] = "/vault/%s/%s/%s" % (img_port, slug, img_fname)
            clean.append(entry)
        return jsonify({"results": clean, "mode": mode, "query": query})

    except Exception as e:
        return jsonify({"results": [], "error": str(e)})


@app.route("/api/money/dashboard")
def api_money_dashboard():
    """Four-questions financial dashboard with calibration support.

    1. Are we good? (status vibe — green/yellow/red)
    2. How much runway? (months of cushion)
    3. How to build float? (monthly net breakdown)
    4. What if? (impact of additional expense)

    Client-side calibration slider adjusts soft numbers to match
    the real Chase balance, then everything tightens around that.
    """
    try:
        finbot_ops = os.path.join(MAESTRO_DIR, "tools", "finbot", "ops")
        if finbot_ops not in sys.path:
            sys.path.insert(0, finbot_ops)

        from data import read_csv, parse_amount, get_confidence, days_remaining
        from config import WEEKS_PER_MONTH, STARTING_BALANCE

        today = datetime.now()
        import calendar as _cal
        days_in_month = _cal.monthrange(today.year, today.month)[1]
        days_left = max(days_remaining(), 1)
        day_of_month = today.day
        elapsed_fraction = day_of_month / days_in_month
        remaining_fraction = days_left / days_in_month

        # --- Monthly recurring income ---
        income_items = []
        income_total = 0.0
        for row in read_csv("pipeline.csv"):
            if row["date"] != "recurring":
                continue
            amt = parse_amount(row["amount"])
            conf = get_confidence(row)
            weighted = amt * conf / 100.0
            income_total += weighted
            income_items.append({
                "name": row.get("source", "?"),
                "amount": round(amt, 2),
                "confidence": conf,
                "weighted": round(weighted, 2),
            })

        # --- Monthly bills (locks) — separate hard from soft ---
        bills_items = []
        bills_total = 0.0
        bills_hard = 0.0
        bills_soft = 0.0
        for row in read_csv("locks.csv"):
            amt = parse_amount(row["amount"])
            freq = row.get("frequency", "monthly").strip().lower()
            conf = get_confidence(row)
            monthly_amt = amt * WEEKS_PER_MONTH if freq == "weekly" else amt
            weighted = monthly_amt * conf / 100.0
            bills_total += weighted
            hard = conf >= 95
            if hard:
                bills_hard += weighted
            else:
                bills_soft += weighted
            bills_items.append({
                "name": row.get("item", "?"),
                "amount": round(monthly_amt, 2),
                "confidence": conf,
                "weighted": round(weighted, 2),
                "frequency": freq,
                "category": row.get("category", ""),
                "hard": hard,
            })

        monthly_net = income_total - bills_total

        # --- Actuals (one-time payments already made this month) ---
        actuals = []
        actuals_total = 0.0
        for row in read_csv("actuals.csv"):
            try:
                dt = datetime.strptime(row["date"], "%Y-%m-%d")
            except (ValueError, KeyError):
                continue
            if dt.year == today.year and dt.month == today.month:
                amt = parse_amount(row.get("amount", "0"))
                actuals_total += amt
                actuals.append({
                    "date": row["date"],
                    "day": dt.day,
                    "amount": round(amt, 2),
                    "category": row.get("category", ""),
                    "notes": row.get("notes", ""),
                })

        # --- Resolved state (one-way ratchet) ---
        from paths import get_data_dir
        resolved_path = get_data_dir() / "resolved.json"
        resolved = {}
        saved_offset = 0
        saved_balances = None
        if resolved_path.exists():
            try:
                with open(resolved_path) as _rf:
                    _rdata = json.load(_rf)
                resolved = _rdata.get("resolved", {})
                saved_offset = _rdata.get("offset", 0)
                saved_balances = _rdata.get("balances", None)
            except (json.JSONDecodeError, OSError):
                pass

        # --- Big moves (one-time events this month) ---
        big_moves = []
        windfalls_pending = 0.0
        horizon_pending = 0.0

        for row in read_csv("pipeline.csv"):
            if row["date"] == "recurring":
                continue
            try:
                dt = datetime.strptime(row["date"], "%Y-%m-%d")
            except (ValueError, KeyError):
                continue
            if dt.year == today.year and dt.month == today.month:
                amt = parse_amount(row["amount"])
                conf = get_confidence(row)
                name = row.get("source", "?")
                is_resolved = name in resolved
                past = dt.day < day_of_month
                if not past and not is_resolved:
                    windfalls_pending += amt * conf / 100.0
                big_moves.append({
                    "name": name,
                    "amount": round(amt, 2),
                    "confidence": conf,
                    "direction": "in",
                    "date": row["date"],
                    "day": dt.day,
                    "past": past,
                    "resolved": is_resolved,
                })

        for row in read_csv("horizon.csv"):
            try:
                dt = datetime.strptime(row["date"], "%Y-%m-%d")
            except (ValueError, KeyError):
                continue
            if dt.year == today.year and dt.month == today.month:
                amt = parse_amount(row["amount"])
                conf = get_confidence(row)
                name = row.get("source", "?")
                is_resolved = name in resolved
                past = dt.day < day_of_month
                if not past and not is_resolved:
                    horizon_pending += amt * conf / 100.0
                big_moves.append({
                    "name": name,
                    "amount": round(amt, 2),
                    "confidence": conf,
                    "direction": "out",
                    "date": row["date"],
                    "day": dt.day,
                    "past": past,
                    "resolved": is_resolved,
                })

        big_moves.sort(key=lambda m: m["date"])

        # --- Model estimate of current balance ---
        # What the model thinks Chase should show right now:
        # starting + income earned so far - bills burned so far - actuals paid
        model_balance = (STARTING_BALANCE
                         + income_total * elapsed_fraction
                         - bills_total * elapsed_fraction
                         - actuals_total)
        # Adjust for past big moves (windfalls received, horizon paid)
        for m in big_moves:
            if m["past"]:
                w = m["amount"] * m["confidence"] / 100.0
                if m["direction"] == "in":
                    model_balance += w
                else:
                    model_balance -= w

        # --- Float (end-of-month projection, uncalibrated) ---
        current_balance = STARTING_BALANCE - actuals_total
        float_value = (current_balance
                       + income_total * remaining_fraction
                       - bills_total * remaining_fraction
                       + windfalls_pending - horizon_pending)

        # --- Soft items for inspection (sorted by monthly impact) ---
        inspect_items = [b for b in bills_items if not b["hard"]]
        inspect_items.sort(key=lambda b: -abs(b["weighted"]))

        return jsonify({
            "date": today.strftime("%Y-%m-%d"),
            "day_of_month": day_of_month,
            "days_in_month": days_in_month,
            "days_left": days_left,
            "saved_offset": saved_offset,
            "saved_balances": saved_balances,
            "balance": {
                "starting": round(STARTING_BALANCE, 2),
                "model": round(model_balance, 2),
            },
            "operating": {
                "income": round(income_total, 2),
                "bills": round(bills_total, 2),
                "bills_hard": round(bills_hard, 2),
                "bills_soft": round(bills_soft, 2),
                "net": round(monthly_net, 2),
                "income_items": income_items,
                "bills_items": sorted(
                    bills_items, key=lambda b: -abs(b["weighted"])),
            },
            "float": {
                "value": round(float_value, 2),
            },
            "big_moves": {
                "items": big_moves,
                "windfalls_pending": round(windfalls_pending, 2),
                "horizon_pending": round(horizon_pending, 2),
            },
            "actuals": actuals,
            "inspect": inspect_items[:8],
        })
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)})


@app.route("/api/money/resolve", methods=["POST"])
def api_money_resolve():
    """Mark a big move as resolved (one-way ratchet).

    Once resolved, an item cannot be un-resolved. This removes it
    from pending projections since it is now reflected in the
    calibrated Chase balance.
    """
    try:
        finbot_ops = os.path.join(MAESTRO_DIR, "tools", "finbot", "ops")
        if finbot_ops not in sys.path:
            sys.path.insert(0, finbot_ops)
        from paths import get_data_dir

        data = request.get_json() or {}
        name = data.get("name", "").strip()
        if not name:
            return jsonify({"error": "name required"}), 400

        resolved_path = get_data_dir() / "resolved.json"
        state = {}
        if resolved_path.exists():
            try:
                with open(resolved_path) as f:
                    state = json.load(f)
            except (json.JSONDecodeError, OSError):
                state = {}

        if "resolved" not in state:
            state["resolved"] = {}

        # One-way ratchet: resolve only, never un-resolve
        if name in state["resolved"]:
            return jsonify({"ok": True, "action": "already_resolved", "name": name})

        state["resolved"][name] = datetime.now().strftime("%Y-%m-%d")
        action = "resolved"

        with open(resolved_path, "w") as f:
            json.dump(state, f, indent=2)

        return jsonify({"ok": True, "action": action, "name": name})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def _generate_drift_report(data_dir, drift_log_path, timestamp,
                           combined, offset_pct, resolved_names):
    """Generate a C2D2 drift analysis report from accumulated drift data.

    Reads the full drift log, builds a prompt with context, and saves
    the report to drift-reports/ in the finbot data dir.
    Returns the report text, or an error string if C2D2 is unavailable.
    """
    c2d2_path = os.path.join(MAESTRO_DIR, "tools", "c2d2")
    if c2d2_path not in sys.path:
        sys.path.insert(0, c2d2_path)
    try:
        import ollama_client
    except ImportError:
        return "ERROR: C2D2 not available"

    if not ollama_client.is_available():
        return "ERROR: Ollama not running"

    # Read drift log history
    drift_csv = ""
    if drift_log_path.exists():
        with open(drift_log_path) as f:
            drift_csv = f.read()

    # Read horizon for pending context
    horizon_csv = ""
    horizon_path = data_dir / "horizon.csv"
    if horizon_path.exists():
        with open(horizon_path) as f:
            horizon_csv = f.read()

    row_count = len(drift_csv.strip().split("\n")) - 1  # minus header

    prompt = (
        "You are a personal finance analyst. Analyze this drift log from a "
        "household budget calibration system. Each row is a Lock snapshot "
        "where the user calibrated their model against real Chase balances.\n\n"
        "DRIFT LOG (CSV, %d snapshots):\n%s\n\n"
        "PENDING BIG MOVES:\n%s\n\n"
        "CURRENT STATE: combined balance $%s, drift offset %s%%, "
        "%d items resolved (%s)\n\n"
        "Provide a brief analysis:\n"
        "1. Balance trend (up/down/stable)\n"
        "2. Drift pattern (is the model tracking reality?)\n"
        "3. Resolved item progress\n"
        "4. One actionable insight\n\n"
        "Keep it under 150 words. No preamble."
    ) % (
        row_count, drift_csv, horizon_csv,
        "{:,.2f}".format(combined), offset_pct,
        len(resolved_names),
        ", ".join(resolved_names) if resolved_names else "none"
    )

    try:
        report = ollama_client.generate(prompt, max_tokens=256, timeout=15)
    except Exception:
        report = None

    if not report:
        return "ERROR: C2D2 generation failed"

    # Save report to drift-reports/
    reports_dir = data_dir / "drift-reports"
    reports_dir.mkdir(exist_ok=True)
    safe_ts = timestamp.replace(":", "-")
    report_path = reports_dir / ("%s.md" % safe_ts)
    with open(report_path, "w") as f:
        f.write("# Drift Report -- %s\n\n" % timestamp)
        f.write("Combined: $%s | Offset: %s%% | Resolved: %d\n\n" % (
            "{:,.2f}".format(combined), offset_pct, len(resolved_names)
        ))
        f.write(report)
        f.write("\n")

    return report


@app.route("/api/money/lockin", methods=["POST"])
def api_money_lockin():
    """Lock in the current calibration offset.

    Saves the offset so the dashboard remembers your last
    calibration on next open. One-way: offset only persists
    forward, resolved items stay resolved.
    """
    try:
        finbot_ops = os.path.join(MAESTRO_DIR, "tools", "finbot", "ops")
        if finbot_ops not in sys.path:
            sys.path.insert(0, finbot_ops)
        from paths import get_data_dir

        data = request.get_json() or {}
        new_offset = int(data.get("offset", 0))
        primary = data.get("primary", 0)
        taxes = data.get("taxes", 0)
        resolved_names = data.get("resolved", [])

        resolved_path = get_data_dir() / "resolved.json"
        state = {}
        if resolved_path.exists():
            try:
                with open(resolved_path) as f:
                    state = json.load(f)
            except (json.JSONDecodeError, OSError):
                state = {}

        now_str = datetime.now().strftime("%Y-%m-%d")
        now_ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

        state["offset"] = new_offset
        state["balances"] = {"primary": primary, "taxes": taxes}
        state["locked_at"] = now_ts

        # Persist resolved items from lock-in
        if "resolved" not in state:
            state["resolved"] = {}
        for name in resolved_names:
            if name not in state["resolved"]:
                state["resolved"][name] = now_str

        with open(resolved_path, "w") as f:
            json.dump(state, f, indent=2)

        # Append to drift log (accumulates for analysis)
        drift_log = get_data_dir() / "drift-log.csv"
        write_header = not drift_log.exists()
        combined = primary + taxes
        resolved_count = len(resolved_names)
        with open(drift_log, "a") as dl:
            if write_header:
                dl.write("timestamp,primary,taxes,combined,offset_pct,"
                         "resolved_count,resolved_items\n")
            dl.write("{},{},{},{},{},{},{}\n".format(
                now_ts, primary, taxes, combined, new_offset,
                resolved_count,
                ";".join(resolved_names) if resolved_names else ""))

        # C2D2 drift report -- local LLM summarizes the drift history
        drift_report = _generate_drift_report(
            get_data_dir(), drift_log, now_ts, combined, new_offset,
            resolved_names
        )

        return jsonify({
            "ok": True,
            "offset": new_offset,
            "drift_report": drift_report
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/money/report", methods=["POST"])
def api_money_report():
    """Generate a PDF financial check-in focused on obstacles.

    Structure: C2D2 intro at top, then obstacle data (pending moves,
    what could help), then detailed notes at bottom. Neutral tone,
    ends on a positive note.
    """
    try:
        from fpdf import FPDF

        finbot_ops = os.path.join(MAESTRO_DIR, "tools", "finbot", "ops")
        if finbot_ops not in sys.path:
            sys.path.insert(0, finbot_ops)
        from data import read_csv, parse_amount, get_confidence
        from config import WEEKS_PER_MONTH
        from paths import get_data_dir

        today = datetime.now()
        import calendar as _cal
        dim = _cal.monthrange(today.year, today.month)[1]
        days_left = dim - today.day

        data_dir = get_data_dir()

        pipeline = read_csv("pipeline.csv")
        horizon = read_csv("horizon.csv")
        locks = read_csv("locks.csv")

        # Resolved state
        resolved_path = data_dir / "resolved.json"
        saved = {}
        if resolved_path.exists():
            try:
                with open(resolved_path) as f:
                    saved = json.load(f)
            except (json.JSONDecodeError, OSError):
                saved = {}
        resolved_names = saved.get("resolved", {})
        saved_bal = saved.get("balances", {})

        # Calibrated balance
        cal_primary = saved_bal.get("primary", 0)
        cal_taxes = saved_bal.get("taxes", 0)
        cal_total = cal_primary + cal_taxes

        # -- Obstacles: pending big moves --
        pending = []
        resolved = []
        pending_total = 0
        resolved_total = 0
        for row in horizon:
            amt = parse_amount(row.get("amount", "0"))
            conf = get_confidence(row)
            name = row.get("source", "")
            dt = row.get("date", "")
            notes = row.get("notes", "")
            is_resolved = name in resolved_names
            if is_resolved:
                resolved.append((name, amt, dt, notes))
                resolved_total += amt
            else:
                pending.append((name, amt, conf, dt, notes))
                pending_total += amt

        # -- What could help: windfalls --
        windfalls = []
        windfall_total = 0
        for row in pipeline:
            date_field = row.get("date", "").strip().lower()
            if date_field == "recurring":
                continue
            amt = parse_amount(row.get("amount", "0"))
            conf = get_confidence(row)
            windfalls.append((
                row.get("source", ""), amt, conf,
                row.get("date", ""), row.get("notes", "")
            ))
            windfall_total += amt * conf / 100

        # -- Monthly budget (stated, for context only) --
        bills_total = 0
        for row in locks:
            amt = parse_amount(row.get("amount", "0"))
            freq = row.get("frequency", "monthly").lower()
            monthly = amt
            if "week" in freq:
                monthly = amt * WEEKS_PER_MONTH
            elif "biweek" in freq or "bi-week" in freq:
                monthly = amt * (WEEKS_PER_MONTH / 2)
            bills_total += monthly

        # Top 3 each by amount
        pending.sort(key=lambda x: x[1], reverse=True)
        pending = pending[:3]
        windfalls.sort(key=lambda x: x[1], reverse=True)
        windfalls = windfalls[:3]

        # Recalc totals for display after trim
        pending_total = sum(a for _, a, _, _, _ in pending)
        windfall_total = sum(a * c / 100 for _, a, c, _, _ in windfalls)

        # Gap: what we owe vs what we have
        gap = pending_total - cal_total
        gap_after_windfalls = gap - windfall_total

        # -- C2D2: introduction (top of report) --
        intro = ""
        detail = ""
        c2d2_path = os.path.join(MAESTRO_DIR, "tools", "c2d2")
        if c2d2_path not in sys.path:
            sys.path.insert(0, c2d2_path)
        try:
            import ollama_client
            if ollama_client.is_available():
                # Build context strings
                pending_text = ""
                for name, amt, conf, dt, notes in pending:
                    pending_text += "  - %s: $%s by %s" % (
                        name, "{:,.0f}".format(amt), dt)
                    if notes:
                        pending_text += " (%s)" % notes
                    pending_text += "\n"

                resolved_text = ""
                for name, amt, dt, notes in resolved:
                    resolved_text += "  - %s: $%s\n" % (
                        name, "{:,.0f}".format(amt))

                windfall_text = ""
                for name, amt, conf, dt, notes in windfalls:
                    windfall_text += "  - %s: $%s by %s (%d%% likely)" % (
                        name, "{:,.0f}".format(amt), dt, conf)
                    if notes:
                        windfall_text += " - %s" % notes
                    windfall_text += "\n"

                intro_prompt = (
                    "RULES: Write in first person plural (we/our). "
                    "Do NOT include any preamble, labels, or meta-text "
                    "like 'Here is' or 'Here are'. Start directly with "
                    "the content. Do NOT repeat dollar amounts -- the "
                    "reader will see the numbers in the charts below. "
                    "Keep it to 2-3 sentences.\n\n"
                    "TASK: Write a brief introduction for a household "
                    "financial check-in between spouses. Characterize "
                    "the overall situation without restating numbers. "
                    "Neutral and grounded tone. End on a forward-looking "
                    "note.\n\n"
                    "CONTEXT (do not restate these, just use for tone):\n"
                    "- %d pending obligations\n"
                    "- Gap exists between what is owed and what is on hand\n"
                    "- Significant windfalls expected this month\n"
                    "- %d days left in the month\n"
                    "- %d items already resolved\n"
                ) % (len(pending), days_left, len(resolved))
                intro = ollama_client.generate(
                    intro_prompt, max_tokens=120, timeout=15
                ) or ""

                detail_prompt = (
                    "RULES: Write in first person plural (we/our). "
                    "Do NOT include any preamble, labels, or meta-text. "
                    "Start directly with the content. Do NOT repeat exact "
                    "dollar amounts -- the reader already sees the numbers "
                    "in the charts above. Focus on relationships between "
                    "items, timing, and what it all means. "
                    "No bullet points.\n\n"
                    "TASK: Write 2-3 short paragraphs for the notes "
                    "section of a household financial check-in between "
                    "spouses.\n\n"
                    "OBSTACLES:\n%s\n"
                    "CLEARED:\n%s\n"
                    "WHAT COULD HELP:\n%s\n"
                    "CONTEXT: %d days left this month.\n\n"
                    "Paragraph 1: Timing and sequencing -- which items "
                    "depend on each other, what needs to happen first.\n"
                    "Paragraph 2: How the expected windfalls change the "
                    "picture -- what becomes possible once they land.\n"
                    "Paragraph 3: End on a genuinely positive note -- "
                    "something encouraging about the trajectory or a "
                    "real development worth celebrating.\n\n"
                    "Keep it under 120 words total."
                ) % (
                    pending_text or "  None\n",
                    resolved_text or "  None yet\n",
                    windfall_text or "  None expected\n",
                    days_left
                )
                detail = ollama_client.generate(
                    detail_prompt, max_tokens=300, timeout=20
                ) or ""
        except Exception:
            pass

        # Sanitize C2D2 text for Helvetica (ASCII-safe)
        def _sanitize(text):
            return (text
                .replace("\u2013", "-").replace("\u2014", "--")
                .replace("\u2018", "'").replace("\u2019", "'")
                .replace("\u201c", '"').replace("\u201d", '"')
                .replace("\u2026", "...").replace("\u00a0", " "))
        intro = _sanitize(intro)
        detail = _sanitize(detail)

        # -- Build PDF --
        pdf = FPDF()
        pdf.set_auto_page_break(auto=True, margin=20)
        pdf.add_page()

        # Title
        pdf.set_font("Helvetica", "B", 18)
        pdf.cell(0, 12, "Financial Check-In", new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 10)
        pdf.set_text_color(120, 120, 120)
        pdf.cell(0, 6, today.strftime("%B %d, %Y"),
                 new_x="LMARGIN", new_y="NEXT")
        pdf.set_text_color(0, 0, 0)
        pdf.ln(6)

        # Introduction (C2D2 generated)
        if intro:
            pdf.set_font("Helvetica", "", 10)
            pdf.multi_cell(0, 5, intro)
            pdf.ln(6)

        # --- Obstacles ---
        pdf.set_font("Helvetica", "B", 12)
        pdf.cell(0, 8, "In Our Way", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)

        if pending:
            pdf.set_font("Helvetica", "", 10)
            for name, amt, conf, dt, notes in pending:
                pdf.set_font("Helvetica", "B", 10)
                pdf.cell(0, 6, name, new_x="LMARGIN", new_y="NEXT")
                pdf.set_font("Helvetica", "", 9)
                line = "$%s  |  %s" % ("{:,.0f}".format(amt), dt)
                if notes:
                    line += "  |  %s" % notes
                pdf.set_text_color(100, 100, 100)
                pdf.cell(0, 5, line, new_x="LMARGIN", new_y="NEXT")
                pdf.set_text_color(0, 0, 0)
                pdf.ln(2)
        else:
            pdf.set_font("Helvetica", "I", 10)
            pdf.cell(0, 6, "Nothing pending", new_x="LMARGIN", new_y="NEXT")

        # Pending total
        pdf.ln(2)
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(80, 6, "Total pending", new_x="RIGHT")
        pdf.cell(0, 6, "$%s" % "{:,.0f}".format(pending_total),
                 new_x="LMARGIN", new_y="NEXT")
        pdf.cell(80, 6, "On hand", new_x="RIGHT")
        pdf.cell(0, 6, "$%s" % "{:,.0f}".format(cal_total),
                 new_x="LMARGIN", new_y="NEXT")
        if gap > 0:
            pdf.set_text_color(218, 54, 51)
            pdf.cell(80, 6, "Gap", new_x="RIGHT")
            pdf.cell(0, 6, "$%s" % "{:,.0f}".format(gap),
                     new_x="LMARGIN", new_y="NEXT")
            pdf.set_text_color(0, 0, 0)
        pdf.ln(4)

        # --- Cleared ---
        if resolved:
            pdf.set_font("Helvetica", "B", 12)
            pdf.cell(0, 8, "Cleared", new_x="LMARGIN", new_y="NEXT")
            pdf.set_font("Helvetica", "", 10)
            for name, amt, dt, notes in resolved:
                pdf.cell(80, 6, name, new_x="RIGHT")
                pdf.cell(0, 6, "$%s" % "{:,.0f}".format(amt),
                         new_x="LMARGIN", new_y="NEXT")
            pdf.ln(4)

        # --- What Could Help ---
        if windfalls:
            pdf.set_font("Helvetica", "B", 12)
            pdf.cell(0, 8, "What Could Help", new_x="LMARGIN", new_y="NEXT")
            pdf.ln(2)
            pdf.set_font("Helvetica", "", 10)
            for name, amt, conf, dt, notes in windfalls:
                pdf.set_font("Helvetica", "B", 10)
                pdf.cell(0, 6, name, new_x="LMARGIN", new_y="NEXT")
                pdf.set_font("Helvetica", "", 9)
                line = "$%s  |  %s  |  %d%% likely" % (
                    "{:,.0f}".format(amt), dt, conf)
                if notes:
                    line += "  |  %s" % notes
                pdf.set_text_color(100, 100, 100)
                pdf.cell(0, 5, line, new_x="LMARGIN", new_y="NEXT")
                pdf.set_text_color(0, 0, 0)
                pdf.ln(2)
            pdf.ln(4)

        # --- Detail / Notes (C2D2 generated, bottom of report) ---
        if detail:
            pdf.set_font("Helvetica", "B", 12)
            pdf.cell(0, 8, "Notes", new_x="LMARGIN", new_y="NEXT")
            pdf.ln(2)
            pdf.set_font("Helvetica", "", 10)
            pdf.multi_cell(0, 5, detail)
            pdf.ln(4)

        # Footer
        pdf.set_font("Helvetica", "I", 8)
        pdf.set_text_color(120, 120, 120)
        pdf.cell(0, 6, "Generated by Maestro finbot  |  %s" %
                 today.strftime("%Y-%m-%d %H:%M"),
                 new_x="LMARGIN", new_y="NEXT")

        # Save PDF
        reports_dir = data_dir / "reports"
        reports_dir.mkdir(exist_ok=True)
        filename = "financial-report_%s.pdf" % today.strftime("%Y%m%d-%H%M%S")
        pdf_path = reports_dir / filename
        pdf.output(str(pdf_path))

        return jsonify({
            "ok": True,
            "path": str(pdf_path),
            "filename": filename
        })
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500


@app.route("/api/money/reports/<path:filename>")
def api_money_report_file(filename):
    """Serve a generated financial report PDF."""
    from flask import send_from_directory
    finbot_ops = os.path.join(MAESTRO_DIR, "tools", "finbot", "ops")
    if finbot_ops not in sys.path:
        sys.path.insert(0, finbot_ops)
    from paths import get_data_dir
    reports_dir = get_data_dir() / "reports"
    safe = os.path.basename(filename)
    return send_from_directory(str(reports_dir), safe)


@app.route("/api/planning/context")
def api_planning_context():
    """Return 30/60/90 horizon data from the canonical date registry."""
    registry_path = os.path.join(PULL_STAGING_DIR, "horizon-dates.json")
    if not os.path.isfile(registry_path):
        return jsonify({"windows": {}, "error": "no registry"})

    try:
        with open(registry_path) as f:
            registry = json.load(f)
    except (json.JSONDecodeError, OSError):
        return jsonify({"windows": {}, "error": "bad registry"})

    from datetime import datetime as _dt, timezone as _tz
    today = _dt.now(_tz.utc).date()
    windows = {"30": [], "60": [], "90": []}

    recent = []

    for key, entry in registry.get("events", {}).items():
        date_str = entry.get("date", "")
        try:
            event_date = _dt.strptime(date_str, "%Y-%m-%d").date()
        except ValueError:
            continue

        days_out = (event_date - today).days

        if days_out < 0 and days_out >= -14:
            # Recently passed (last 2 weeks)
            recent.append({
                "key": key,
                "date": date_str,
                "days_out": days_out,
                "summary": entry.get("summary", key),
                "category": entry.get("category", "milestone"),
                "recurring": entry.get("recurring", False),
                "recurrence_pattern": entry.get("recurrence", {}).get("pattern", ""),
                "descriptions": entry.get("descriptions", []),
            })
            continue

        if days_out < 0:
            continue

        if days_out <= 30:
            bucket = "30"
        elif days_out <= 60:
            bucket = "60"
        elif days_out <= 90:
            bucket = "90"
        else:
            continue

        windows[bucket].append({
            "key": key,
            "date": date_str,
            "days_out": days_out,
            "summary": entry.get("summary", key),
            "category": entry.get("category", "milestone"),
            "recurring": entry.get("recurring", False),
            "recurrence_pattern": entry.get("recurrence", {}).get("pattern", ""),
            "descriptions": entry.get("descriptions", []),
        })

    for bucket in windows:
        windows[bucket].sort(key=lambda e: e["date"])
    recent.sort(key=lambda e: e["date"], reverse=True)

    counts = {k: len(v) for k, v in windows.items()}
    counts["recent"] = len(recent)
    return jsonify({"windows": windows, "recent": recent, "counts": counts,
                     "updated_at": registry.get("updated_at", "")})


@app.route("/api/planning/event/<key>/note", methods=["POST"])
def api_planning_add_note(key):
    """Add a note/description to a registry event."""
    registry_path = os.path.join(PULL_STAGING_DIR, "horizon-dates.json")
    if not os.path.isfile(registry_path):
        return jsonify({"error": "no registry"}), 404

    note = request.json.get("note", "").strip() if request.json else ""
    if not note:
        return jsonify({"error": "empty note"}), 400

    try:
        with open(registry_path) as f:
            registry = json.load(f)
    except (json.JSONDecodeError, OSError):
        return jsonify({"error": "bad registry"}), 500

    events = registry.get("events", {})
    if key not in events:
        return jsonify({"error": "event not found"}), 404

    descriptions = events[key].get("descriptions", [])
    if note not in descriptions:
        descriptions.append(note)
        events[key]["descriptions"] = descriptions

    with open(registry_path, "w") as f:
        json.dump(registry, f, indent=2)
        f.write("\n")

    # Emit token immediately so cue-vox sees the note in context
    summary = events[key].get("summary", key)
    token_value = "%s -- %s" % (summary, note)
    import re as _re
    token_label = "note_" + _re.sub(r"[^a-z0-9]+", "_", summary.lower())[:30].strip("_")

    createtoken = os.path.join(MAESTRO_DIR, "cue-mem", "cli", "createtoken")
    subprocess.run(
        [createtoken, token_label, token_value,
         "--tags", "system,event-note,event:%s,planning-panel" % key,
         "--base-temp", "90",
         "--half-life", "168"],
        capture_output=True, text=True
    )

    return jsonify({"ok": True, "descriptions": descriptions})


@app.route("/api/planning/event/<key>/color", methods=["POST"])
def api_planning_color_event(key):
    """Set a feeling value on a registry event and emit a token."""
    registry_path = os.path.join(PULL_STAGING_DIR, "horizon-dates.json")
    if not os.path.isfile(registry_path):
        return jsonify({"error": "no registry"}), 404

    data = request.json or {}
    value = data.get("value")
    if value is None:
        return jsonify({"error": "missing value"}), 400
    value = int(value)

    try:
        with open(registry_path) as f:
            registry = json.load(f)
    except (json.JSONDecodeError, OSError):
        return jsonify({"error": "bad registry"}), 500

    events = registry.get("events", {})
    if key not in events:
        return jsonify({"error": "event not found"}), 404

    # Determine if past or upcoming
    from datetime import datetime as _dt, timezone as _tz
    today = _dt.now(_tz.utc).date()
    date_str = events[key].get("date", "")
    is_past = False
    try:
        event_date = _dt.strptime(date_str, "%Y-%m-%d").date()
        is_past = event_date < today
    except ValueError:
        pass

    # Write to registry
    field_name = "retro" if is_past else "feeling"
    events[key][field_name] = value

    with open(registry_path, "w") as f:
        json.dump(registry, f, indent=2)
        f.write("\n")

    # Emit token immediately
    summary = events[key].get("summary", key)
    import re as _re

    if is_past:
        # Retro dimension: terrible <> amazing
        if value <= 20:
            feeling_label = "terrible"
        elif value <= 40:
            feeling_label = "not great"
        elif value <= 60:
            feeling_label = "okay"
        elif value <= 80:
            feeling_label = "good"
        else:
            feeling_label = "amazing"
        token_value = "%s was %s (%d/100)" % (summary, feeling_label, value)
        token_label = "retro_" + _re.sub(r"[^a-z0-9]+", "_", summary.lower())[:30].strip("_")
    else:
        # Upcoming dimension: stressed <> good
        if value <= 20:
            feeling_label = "stressed about"
        elif value <= 40:
            feeling_label = "uneasy about"
        elif value <= 60:
            feeling_label = "neutral about"
        elif value <= 80:
            feeling_label = "good about"
        else:
            feeling_label = "great about"
        token_value = "%s %s (%d/100)" % (feeling_label, summary, value)
        token_label = "feeling_" + _re.sub(r"[^a-z0-9]+", "_", summary.lower())[:30].strip("_")

    tag_type = "event-retro" if is_past else "event-color"
    createtoken = os.path.join(MAESTRO_DIR, "cue-mem", "cli", "createtoken")
    result = subprocess.run(
        [createtoken, token_label, token_value,
         "--tags", "system,%s,event:%s,planning-panel" % (tag_type, key),
         "--base-temp", "80",
         "--half-life", "168"],
        capture_output=True, text=True
    )

    return jsonify({"ok": True, field_name: value,
                     "token": result.returncode == 0})


@app.route("/api/ops/pull", methods=["POST"])
def api_ops_pull():
    """Fire all pull agents."""
    try:
        for source in ("calendar", "horizon", "gmail"):
            script = os.path.join(MAESTRO_DIR, "tools", "zapier", "pull",
                                  "check-%s.sh" % source)
            if os.path.isfile(script):
                subprocess.Popen(
                    ["bash", script, "--fire"],
                    cwd=MAESTRO_DIR,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
        return jsonify({"message": "All agents fired"})
    except Exception as e:
        return jsonify({"message": "Error: %s" % str(e)}), 500


# ---------------------------------------------------------------------------
# PTY reader thread
# ---------------------------------------------------------------------------

def pty_reader(sid, master_fd):
    """Read PTY output in a loop and emit to the client."""
    try:
        while True:
            ready, _, _ = select.select([master_fd], [], [], 0.1)
            if ready:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                socketio.emit("game_output", {"data": data.decode("utf-8", errors="replace")}, to=sid)
    finally:
        socketio.emit("game_end", {}, to=sid)
        cleanup_session(sid)


def cleanup_session(sid):
    """Kill child process and close master fd."""
    session = sessions.pop(sid, None)
    if not session:
        return
    pid = session.get("child_pid")
    master_fd = session.get("master_fd")
    if pid:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if master_fd:
        try:
            os.close(master_fd)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Socket.IO events
# ---------------------------------------------------------------------------

@socketio.on("game_start")
def on_game_start(data):
    slug = data.get("slug")
    cols = data.get("cols", 80)
    rows = data.get("rows", 30)

    # Clean up any existing session for this client
    cleanup_session(request.sid)

    rom = find_rom(slug)
    if not rom:
        emit("game_end", {"error": "ROM not found"})
        return

    # Check server dependency before spawning
    if rom.get("requires_server") and not check_cue_vox():
        emit("game_error", {
            "error": "server_required",
            "message": "cue-vox must be running on port {} for this game to create tokens.".format(CUE_VOX_PORT),
        })
        return

    script_path = os.path.join(ROMS_DIR, rom["file"])
    if not os.path.isfile(script_path):
        emit("game_end", {"error": "ROM file missing"})
        return

    # Spawn PTY
    master_fd, slave_fd = pty.openpty()

    # Set initial terminal size
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(slave_fd, termios.TIOCSWINSZ, winsize)

    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    env["COLUMNS"] = str(cols)
    env["LINES"] = str(rows)

    child = subprocess.Popen(
        ["bash", script_path],
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        cwd=ARCADE_DIR,
        env=env,
        preexec_fn=os.setsid,
    )
    os.close(slave_fd)

    sid = request.sid

    sessions[sid] = {
        "master_fd": master_fd,
        "child_pid": child.pid,
        "slug": slug,
    }

    # Start reader thread
    t = threading.Thread(target=pty_reader, args=(sid, master_fd), daemon=True)
    t.start()


@socketio.on("game_input")
def on_game_input(data):
    from flask import request
    session = sessions.get(request.sid)
    if not session:
        return
    raw = data.get("data", "")
    try:
        os.write(session["master_fd"], raw.encode("utf-8"))
    except OSError:
        pass


@socketio.on("game_reset")
def on_game_reset(data):
    """Kill current game and respawn the same ROM."""
    from flask import request
    sid = request.sid
    session = sessions.get(sid)
    if not session:
        return
    slug = session["slug"]
    cols = data.get("cols", 80)
    rows = data.get("rows", 30)
    cleanup_session(sid)
    # Re-emit game_start to respawn
    on_game_start({"slug": slug, "cols": cols, "rows": rows})


@socketio.on("game_resize")
def on_game_resize(data):
    from flask import request
    session = sessions.get(request.sid)
    if not session:
        return
    cols = data.get("cols", 80)
    rows = data.get("rows", 30)
    winsize = struct.pack("HHHH", rows, cols, 0, 0)
    try:
        fcntl.ioctl(session["master_fd"], termios.TIOCSWINSZ, winsize)
        # Signal the process group so the game redraws
        os.kill(session["child_pid"], signal.SIGWINCH)
    except (OSError, ProcessLookupError):
        pass


@socketio.on("disconnect")
def on_disconnect():
    from flask import request
    cleanup_session(request.sid)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Arcade Web starting on http://localhost:{}".format(PORT))
    socketio.run(app, host="0.0.0.0", port=PORT, debug=False, allow_unsafe_werkzeug=True)
