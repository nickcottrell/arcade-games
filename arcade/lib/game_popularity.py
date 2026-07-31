#!/usr/bin/env python3
"""Rank arcade games by a blended relevance score from the token pool.

Every arcade game tags its tokens `arcade:<slug>`. We read three signals from
each game's tokens, all thermally decayed to *now*:

  footprint = sum of current heat        -- share of the warm pool (volume+recency)
  peak      = hottest single token       -- how recently it was last touched
  plays     = distinct sessions          -- how many times it has been played
              (counted from `game:<id>` / `session:<id>` tags)

Each signal is normalized across games (value / max) and combined:

  score = W_FOOT*footprint_n + W_PEAK*peak_n + W_PLAYS*plays_n

Footprint stays primary; peak and plays keep a token-chatty game from simply
dominating on volume. Weights are tunable via env vars.

Output (tab-separated, hottest first):
  slug <TAB> score <TAB> footprint <TAB> peak <TAB> plays
"""

import datetime
import glob
import json
import os
import sys

W_FOOT = float(os.environ.get("ARCADE_POP_W_FOOTPRINT", "0.5"))
W_PEAK = float(os.environ.get("ARCADE_POP_W_PEAK", "0.3"))
W_PLAYS = float(os.environ.get("ARCADE_POP_W_PLAYS", "0.2"))


def current_heat(tok):
    """Decay a token's stored temperature to its heat right now."""
    base = tok.get("base_temp", tok.get("temperature", 0)) or 0
    floor = tok.get("floor_temp", 0) or 0
    half_life = tok.get("half_life_hours") or 2.0
    created = tok.get("created_at")
    if not created:
        return float(base)
    try:
        dt = datetime.datetime.fromisoformat(created)
    except ValueError:
        return float(base)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    age_h = (datetime.datetime.now(datetime.timezone.utc) - dt).total_seconds() / 3600.0
    if half_life <= 0:
        return float(base)
    return floor + (base - floor) * (0.5 ** (age_h / half_life))


def main():
    if len(sys.argv) > 1:
        tokens_dir = sys.argv[1]
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        tokens_dir = os.path.join(here, "..", "..", "..", ".claude", "tokens")
    tokens_dir = os.path.normpath(tokens_dir)

    foot, peak, sessions = {}, {}, {}
    for path in glob.glob(os.path.join(tokens_dir, "*.json")):
        try:
            with open(path, encoding="utf-8") as fh:
                tok = json.load(fh)
        except (ValueError, OSError):
            continue
        tags = tok.get("tags") or []
        slug = None
        for tag in tags:
            if isinstance(tag, str) and tag.startswith("arcade:"):
                slug = tag.split(":", 1)[1]
                break
        if not slug:
            continue
        h = max(0.0, current_heat(tok))
        foot[slug] = foot.get(slug, 0.0) + h
        peak[slug] = max(peak.get(slug, 0.0), h)
        for tag in tags:
            if isinstance(tag, str) and (tag.startswith("game:") or tag.startswith("session:")):
                sessions.setdefault(slug, set()).add(tag)

    if not foot:
        return
    plays = {s: len(sessions.get(s, ())) for s in foot}

    def norm(d):
        mx = max(d.values()) if d else 0.0
        return (lambda v: v / mx) if mx > 0 else (lambda v: 0.0)

    nf, npk, npl = norm(foot), norm(peak), norm(plays)
    score = {
        s: W_FOOT * nf(foot[s]) + W_PEAK * npk(peak[s]) + W_PLAYS * npl(plays[s])
        for s in foot
    }

    for s in sorted(score, key=lambda k: score[k], reverse=True):
        print("%s\t%.4f\t%.1f\t%.1f\t%d" % (s, score[s], foot[s], peak[s], plays[s]))


if __name__ == "__main__":
    main()
