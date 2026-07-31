#!/usr/bin/env python3
"""Maestro Chess -- refereed head-to-head loop.

python-chess is the referee. Every player -- human or model -- submits
moves through the same validation. Illegal moves are bounced identically
no matter who sends them; a model that cannot produce a legal move inside
its retry budget forfeits, exactly as it would if you couldn't.

Any seat is either 'human' or an ollama model name, so this plays:
  human vs model      --white human          --black gemma2:27b
  model vs model       --white gemma2:27b     --black qwen2.5:14b   (GPU vs GPU)
  human vs human       --white human          --black human
"""

import argparse
import colorsys
import datetime
import hashlib
import json
import os
import re
import sys
import time
import urllib.request

import chess

OLLAMA_URL = "http://localhost:11434/api/chat"
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

# 256-color board palette + unicode pieces
LIGHT_BG = 180
DARK_BG = 94
CELL_W = 5   # square width in terminal columns
CELL_H = 3   # square height in rows; glyph sits dead-center (>=3 gives a 1-char frame)
GLYPH = {
    "P": "♙", "N": "♘", "B": "♗", "R": "♖", "Q": "♕", "K": "♔",
    "p": "♟", "n": "♞", "b": "♝", "r": "♜", "q": "♛", "k": "♚",
}

# ---------------------------------------------------------------------------
# VRGB eval-color -- a position's advantage read as a coordinate.
# This is the SLI split: the position is the coordinate, the eval is the
# schema that interprets it, and the reading is rendered as color, not a number.
# ---------------------------------------------------------------------------

MATERIAL = {chess.PAWN: 100, chess.KNIGHT: 320, chess.BISHOP: 330, chess.ROOK: 500, chess.QUEEN: 900}


def eval_cp(board):
    """Material balance in centipawns, White-positive."""
    if board.is_checkmate():
        return -100000 if board.turn == chess.WHITE else 100000
    cp = 0
    for pt, v in MATERIAL.items():
        cp += v * (len(board.pieces(pt, chess.WHITE)) - len(board.pieces(pt, chess.BLACK)))
    return cp


def cp_to_rgb(cp):
    """Advantage -> HSL -> RGB. Warm = White ahead, cool = Black ahead, grey = level."""
    m = max(-1000, min(1000, cp)) / 1000.0
    hue = 18 if m >= 0 else 210            # red-orange vs azure
    sat = 0.15 + 0.75 * abs(m)             # near-level washes to grey
    r, g, b = colorsys.hls_to_rgb(hue / 360.0, 0.5, sat)
    return int(r * 255), int(g * 255), int(b * 255)


def rgb_to_hex(rgb):
    return "#%02x%02x%02x" % rgb


def write_move_token(tokens_dir, game_id, ply, san, fen, cp, hexcolor, side):
    """Each move becomes a thermal cue-mem token. The game is the lineage
    (tag game:<id>); the position is addressed in colorspace (hex = eval-color).
    Best-effort -- a token failure never interrupts the game."""
    try:
        os.makedirs(tokens_dir, exist_ok=True)
        tid = "chess_%s_m%03d" % (game_id, ply)
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        temp = 65
        token = {
            "token_id": tid, "type": "chess_move", "label": "move_%d" % ply,
            "value": san, "temperature": temp, "base_temp": temp,
            "visibility": "shared", "status": "active",
            "half_life_hours": 2.0, "floor_temp": 0,
            "tags": ["chess", "arcade:chess", "game:%s" % game_id, "move:%d" % ply, "side:%s" % side],
            "created_at": now,
            "metadata": {"fen": fen, "san": san, "ply": ply, "cp": cp},
            "emitted_by": "maestro-chess", "human_verified": False,
            "hex": hexcolor,
        }
        canonical = {"token_id": tid, "value": san, "temperature": temp, "created_at": now}
        token["content_hash"] = hashlib.sha256(
            json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        with open(os.path.join(tokens_dir, tid + ".json"), "w", encoding="utf-8") as fh:
            json.dump(token, fh, ensure_ascii=False, indent=2, sort_keys=True)
            fh.write("\n")
    except Exception:
        pass

# UCI like e2e4 or e7e8q ; SAN like Nf3, exd5, O-O, Qh4+
UCI_RE = re.compile(r"\b([a-h][1-8][a-h][1-8][qrbnQRBN]?)\b")
SAN_RE = re.compile(r"\b(O-O-O|O-O|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?)\b")


def render(board, white_name, black_name, last=None, strip=None, cp=0):
    mid_r, mid_c = CELL_H // 2, CELL_W // 2
    print()
    print(f"     \033[1m{black_name}\033[0m (black)")
    for rank in range(7, -1, -1):
        for sub in range(CELL_H):
            line = f" {rank + 1} " if sub == mid_r else "   "
            for file in range(8):
                piece = board.piece_at(chess.square(file, rank))
                bg = LIGHT_BG if (file + rank) % 2 else DARK_BG
                cell = ""
                for col in range(CELL_W):
                    if sub == mid_r and piece and col == mid_c:
                        fg = 231 if piece.color == chess.WHITE else 16
                        cell += f"\033[1;38;5;{fg}m{GLYPH[piece.symbol()]}\033[22;39m"
                    else:
                        cell += " "
                line += f"\033[48;5;{bg}m{cell}\033[0m"
            print(line)
    print("   " + "".join(f.center(CELL_W) for f in "abcdefgh"))
    print(f"     \033[1m{white_name}\033[0m (white)")
    # VRGB eval-color: the ribbon is the game's arc of advantage; the swatch is now.
    if strip:
        ribbon = "".join(f"\033[48;2;{r};{g};{b}m \033[0m" for (r, g, b) in strip[-48:])
        print(f"\n   advantage  {ribbon}")
    r, g, b = cp_to_rgb(cp)
    print(f"   now        \033[48;2;{r};{g};{b}m     \033[0m  \033[2m{cp / 100:+.1f}\033[0m")
    if last is not None:
        print(f"   last: \033[1m{last}\033[0m")


def ollama_move(model, board, feedback, temperature):
    """Ask a model for its move. Returns raw text."""
    sys_msg = (
        "You are playing chess. Reply with ONE move only, in UCI form "
        "(from-square then to-square, e.g. e2e4, or e7e8q to promote). "
        "No words, no explanation, just the move."
    )
    user = (
        f"Position (FEN): {board.fen()}\n"
        f"You are {'White' if board.turn == chess.WHITE else 'Black'}. "
        f"It is your move.\n{feedback}\nYour move:"
    )
    payload = {
        "model": model,
        "messages": [
            {"role": "system", "content": sys_msg},
            {"role": "user", "content": user},
        ],
        "stream": False,
        "options": {"temperature": temperature},
    }
    req = urllib.request.Request(
        OLLAMA_URL, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
    return data.get("message", {}).get("content", "")


def parse_move(text, board):
    """Pull the first LEGAL move out of a model's reply (UCI preferred)."""
    for m in UCI_RE.findall(text):
        try:
            mv = chess.Move.from_uci(m.lower())
            if mv in board.legal_moves:
                return mv
        except ValueError:
            pass
    for m in SAN_RE.findall(text):
        try:
            return board.parse_san(m)
        except (ValueError, chess.IllegalMoveError, chess.InvalidMoveError, chess.AmbiguousMoveError):
            pass
    return None


def get_model_move(model, board, budget, temperature):
    """Model plays. Same rules as a human: illegal -> try again, up to budget."""
    feedback = ""
    for attempt in range(1, budget + 1):
        raw = ollama_move(model, board, feedback, temperature)
        mv = parse_move(raw, board)
        if mv is not None:
            print(f"   \033[2m{model} plays {board.san(mv)}  (try {attempt})\033[0m")
            return mv
        snippet = raw.strip().replace("\n", " ")[:60]
        print(f"   \033[31m{model} illegal/unparsable: '{snippet}'  (try {attempt}/{budget})\033[0m")
        feedback = "Your previous answer was not a legal move. Try a different, legal move."
    return None  # forfeit


# ---------------------------------------------------------------------------
# CPU engine -- deterministic, algorithmic, runs on the CPU. Built straight on
# python-chess, so it only ever produces legal moves. This is the "honest
# computer": unlike the GPU models, it cannot flail on legality -- the contrast
# is the point.
# ---------------------------------------------------------------------------

PIECE_VALUES = {
    chess.PAWN: 100, chess.KNIGHT: 320, chess.BISHOP: 330,
    chess.ROOK: 500, chess.QUEEN: 900, chess.KING: 0,
}
MATE = 1_000_000


def evaluate(board):
    """Score from the side-to-move's perspective (negamax convention)."""
    if board.is_checkmate():
        return -MATE
    if board.is_stalemate() or board.is_insufficient_material():
        return 0
    score = 0
    for piece_type, value in PIECE_VALUES.items():
        score += value * len(board.pieces(piece_type, chess.WHITE))
        score -= value * len(board.pieces(piece_type, chess.BLACK))
    if board.turn == chess.BLACK:
        score = -score
    # cheap positional nudge: reward mobility for the side to move
    score += 5 * board.legal_moves.count()
    return score


def negamax(board, depth, alpha, beta):
    if depth == 0 or board.is_game_over():
        return evaluate(board)
    best = -MATE * 2
    for mv in board.legal_moves:
        board.push(mv)
        val = -negamax(board, depth - 1, -beta, -alpha)
        board.pop()
        if val > best:
            best = val
        if best > alpha:
            alpha = best
        if alpha >= beta:
            break
    return best


def cpu_move(board, depth):
    best_mv, best_val = None, -MATE * 2
    for mv in board.legal_moves:
        board.push(mv)
        val = -negamax(board, depth - 1, -MATE * 2, MATE * 2)
        board.pop()
        if val > best_val:
            best_val, best_mv = val, mv
    print(f"   \033[2mcpu (depth {depth}) plays {board.san(best_mv)}\033[0m")
    return best_mv


def get_human_move(board):
    while True:
        try:
            raw = input("   your move (UCI/SAN, or 'quit'): ").strip()
        except EOFError:
            return None
        if raw.lower() in ("quit", "resign", "q"):
            return None
        try:
            return board.parse_uci(raw.lower()) if UCI_RE.fullmatch(raw.lower()) else board.parse_san(raw)
        except (ValueError, chess.IllegalMoveError, chess.InvalidMoveError, chess.AmbiguousMoveError):
            print("   \033[31millegal -- try again\033[0m")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--white", default="human")
    ap.add_argument("--black", default="gemma2:27b")
    ap.add_argument("--budget", type=int, default=3, help="model illegal-move retries before forfeit")
    ap.add_argument("--depth", type=int, default=3, help="cpu engine search depth")
    ap.add_argument("--temp", type=float, default=0.3)
    ap.add_argument("--max-plies", type=int, default=0, help="0 = play to the end")
    ap.add_argument("--no-tokens", action="store_true", help="do not emit cue-mem tokens")
    ap.add_argument("--tokens-dir", default=os.path.join(ROOT, ".claude", "tokens"))
    args = ap.parse_args()

    board = chess.Board()
    seats = {chess.WHITE: args.white, chess.BLACK: args.black}
    game_id = str(int(time.time()))
    strip, cur_cp = [], 0
    print(f"\n\033[1mMAESTRO CHESS\033[0m   white: {args.white}   black: {args.black}   game {game_id}")

    last = None
    while not board.is_game_over(claim_draw=True):
        if args.max_plies and board.ply() >= args.max_plies:
            print("\n   (ply cap reached)")
            break
        render(board, args.white, args.black, last, strip, cur_cp)
        who = seats[board.turn]
        if who == "human":
            mv = get_human_move(board)
        elif who == "cpu" or who.startswith("cpu:"):
            depth = int(who.split(":", 1)[1]) if ":" in who else args.depth
            mv = cpu_move(board, depth)
        else:
            mv = get_model_move(who, board, args.budget, args.temp)
        if mv is None:
            side = "White" if board.turn == chess.WHITE else "Black"
            print(f"\n   \033[1m{seats[board.turn]} ({side}) forfeits.\033[0m")
            return
        mover = "white" if board.turn == chess.WHITE else "black"
        last = board.san(mv)
        board.push(mv)
        cur_cp = eval_cp(board)
        rgb = cp_to_rgb(cur_cp)
        strip.append(rgb)
        if not args.no_tokens:
            write_move_token(args.tokens_dir, game_id, board.ply(), last,
                             board.fen(), cur_cp, rgb_to_hex(rgb), mover)

    render(board, args.white, args.black, last, strip, cur_cp)
    print(f"\n   \033[1mResult: {board.result(claim_draw=True)}\033[0m  ({board.outcome(claim_draw=True)})"
          if board.is_game_over(claim_draw=True) else "")


if __name__ == "__main__":
    main()
