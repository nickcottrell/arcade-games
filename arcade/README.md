# Arcade

**VRGB game engine. Play to discover optimal system parameters.**

## Role in the Constellation

The arcade is not entertainment -- it is a parameter search engine. Each game isolates an orchestration primitive (thermal decay, pressure, VRGB navigation) and makes it playable. Gameplay generates tuning data: how humans naturally manage attention, prioritize triage, balance throughput, and navigate colorspace.

That data feeds back into the platform. If players consistently struggle when decay rate exceeds a threshold, the threshold is wrong. If players naturally sort by hottest-first, the triage algorithm should match. The arcade turns human intuition into system configuration.

## Certainty Layer

**Exploration.** The arcade is where the system experiments with its own mechanics. Nothing here is production-critical. Everything here is informative. Games are the lowest-certainty, highest-possibility space in the constellation -- they exist to discover what we do not yet know about how the system should behave.

## Games (13)

| Slug | Title | Mechanic | System Concept |
|------|-------|----------|---------------|
| chomp | Chain Chomp | Dino grazing a provenance chain | Consecutive action chains build value; thermal dot decay |
| trail | Heat Trail | Snake + thermal decay | Body segments cool and shed; eat or die |
| trail-fast | Heat Trail (Fast) | Same, 0.08s frame rate | Stress test at high speed |
| trail-slow | Heat Trail (Slow) | Same, 0.25s frame rate | Relaxed difficulty for observation |
| spectral | Spectral | Asteroids + colorspace navigation | Ship IS an HSL coordinate; combat is hue proximity |
| cooker | Pressure Cooker | Catch items + pressure zones | Pressure system IS the difficulty knob |
| chromafall | Chromafall | Tetris + VRGB hues | Each piece carries a hue; cleared lines emit color tokens |
| unfold | Unfold | Platformer + dimensional expansion | Box grows per level; platforms thermally decay |
| reheat | Reheat | Grid triage | Heat cooled tokens in priority order; chain bonus for hottest-first |
| observatory | Observatory | 9-subsystem monitor | Intervene before subsystems fail; the meta-game |
| buff | Cue-Buff | Offline CueSheet buffer | Walk through a YAML CueSheet with no model |
| vault | Vault Query | FTS search interface | Interactive vault search via TUI |
| madlibs | Mad Libs | Word game + TTS | 110 stories, read aloud via cue-vox |

## Architecture

- **ROMs** -- bash scripts in `roms/`. Each is self-contained.
- **Libs** -- `lib/tui.sh` (terminal UI), `lib/vrgb.sh` (color math), `lib/arcade-tokens.sh` (token emission + pressure system)
- **Manifest** -- `manifest.json` registers all games with metadata.
- **CLI** -- `cli/arcade` launches the menu. `cli/rom-launch` plays a game by slug.

## Key Mechanics

- **Thermal decay** -- dots, segments, and platforms cool over time. The game IS the decay curve.
- **Pressure system** -- leaky bucket that modulates difficulty based on token throughput.
- **VRGB navigation** -- player moves through colorspace, not a color palette. Distance in hue-space equals strategic distance.
- **Token emission** -- every game creates tokens tagged `arcade:<slug>`. Gameplay metrics are the token values.

---

## What We Have Learned From Gameplay

### 1. Thermal Decay Feels Right When It Is Visible

**Source:** Chain Chomp, Heat Trail, Unfold

Dots in Chain Chomp decay from hot (3) to warm (2) to cold (1) to gone (0). You can see them fading. Heat Trail segments dim as they cool. Unfold platforms crumble under your feet.

**Insight:** When decay is visible, the player naturally prioritizes the hottest items. When decay is invisible (just a number changing), the player loses track. This maps directly to cue-mem: token temperature should be surfaced in the UI, not hidden in JSON. The flux capacitor's recent_context.md already does this, but the voice interface could do more -- announcing when tracks go cold, for example.

**System implication:** Thermal decay works as an attention mechanism only if the user can see it happening. The CueSheet thermal conditions (`when: any_token_above: 80`) are the right pattern -- they make decay actionable, not just decorative.

### 2. Chains Are Fragile and That Is the Point

**Source:** Chain Chomp, Heat Trail

In Chain Chomp, consecutive eats build a chain multiplier. One raptor hit breaks it. In Heat Trail, your body IS the chain -- stop eating and it shrinks until you die.

**Insight:** The chain mechanic teaches that momentum has value but is expensive to rebuild. Breaking a chain is not just losing a multiplier -- it is losing the accumulated context that made the multiplier possible. This maps to conversation continuity in cue-vox: when a session breaks (restart, timeout, accidental bump), the context chain breaks. The temporal decay policy exists because of this -- it distinguishes a bump (chain preserved) from a real break (chain rebuilt).

**System implication:** Context chains should be cheap to maintain and expensive to rebuild. Pinned tokens are the "power pellets" -- they protect the chain from decay. The chain metaphor validates the design decision to make token expiry gradual (temperature curve) rather than sudden (hard TTL).

### 3. Pressure Is a Better Difficulty Knob Than Speed

**Source:** Pressure Cooker, Chain Chomp

Pressure Cooker's entire game IS the pressure system. The medium zone is the sweet spot: 1x multiplier, manageable pace. Going too low (critical zone, 0x multiplier) is worse than going too high (meltdown risk but 2x multiplier). Chain Chomp uses pressure to modulate raptor speed and fern decay rate.

**Insight:** Traditional difficulty scaling (things move faster) creates a hard ceiling. Pressure scaling (throughput changes the rules) creates a dynamic equilibrium. The player self-regulates: graze fast, pressure rises, raptors slow down (reward). Eat slow, pressure drops, dots decay faster (punishment). The system finds its own balance.

**System implication:** The CueSheet pressure-gated inputs (prompt 48) are the right abstraction. When the system is under high pressure (many hot tokens, fast creation rate), slider defaults should shift. The user does not need to know about pressure -- they just feel the system being more urgent when it should be, and more relaxed when it can afford to be.

### 4. Colorspace Navigation Is Intuitive But Matching Is Hard

**Source:** Spectral, Chromafall

In Spectral, your ship rotates through hue-space to match enemy colors. Exact matches (distance < 5) are hard to hit but very rewarding. Hot matches (5-15) are easier. Warm matches (15-30) damage you. In Chromafall, each tetromino carries a hue, and cleared rows emit the dominant color as a token.

**Insight:** Players quickly learn to navigate the hue wheel (left/right rotation feels natural). But precise matching is difficult -- the difference between hue 115 and hue 125 is not visually obvious at game speed. This means VRGB categories should use wide hue bands, not narrow ones. The 30-degree "analogous" threshold from the game design matches human perceptual boundaries.

**System implication:** VRGB routing in CueSheets (prompt 46) uses a 90-degree context switch threshold. Spectral gameplay suggests this is about right -- 90 degrees feels like a genuine domain change (orange to blue), while 30 degrees feels like a variation within the same domain (orange to red-orange). The hue distance function wrapping around 360 is correct and necessary.

### 5. Dimensional Expansion Teaches Progressive Disclosure

**Source:** Unfold

Unfold starts in a 10x6 box with no gravity, no enemies, 3 jewels. Each dimension adds size, mechanics, and complexity. By dimension 4, the box is 40x22 with gravity, 12 platforms, 6 enemies, and 24 jewels. Each dimension has a hue on the color wheel (red -> orange -> yellow -> green -> blue).

**Insight:** Progressive disclosure works when each level adds exactly one new concept. Unfold does not dump all mechanics at once -- it reveals them dimension by dimension. The hue progression reinforces this: you can feel yourself moving through the spectrum as complexity grows.

**System implication:** CueSheet design should follow the same pattern. A new user should start with simple CueSheets (quick-task: one input, two cues, done). Advanced CueSheets add thermal conditions, VRGB routing, context budgets, policy gates. The system should never show all capabilities at once. The weight class system (full/lite/sync-only/none) is dimensional expansion applied to infrastructure.

### 6. The Meta-Game Is About Triage, Not Perfection

**Source:** Observatory, Reheat

Observatory monitors 9 subsystems simultaneously. You cannot keep all 9 at 100% -- you have limited interventions. The game is about knowing which subsystem to save and which to let dip. Reheat rewards heating the hottest token first (chain bonus) -- if you waste heat on a cold token, you break your chain.

**Insight:** Operators triage, they do not optimize. The goal is not to keep everything perfectly heated -- it is to prevent anything from dying while making progress on the things that matter most. This is exactly how track management works in maestro: hot tracks get attention, warm tracks get monitoring, cold tracks get a one-line summary. Trying to keep all tracks hot simultaneously is the anti-pattern.

**System implication:** The track landscape policy and track focus policy already encode this insight. The Observatory game validates them: a player who tries to intervene on every subsystem runs out of interventions. A player who lets the stable ones coast and focuses on the critical ones scores higher. The CueSheet thermal awareness (`when: any_token_above: 85`) is the triage gate.

### 7. All Real Game Loops Are Simple

**Source:** All games

Every game that works is simple. Chain Chomp: graze ferns, dodge raptors. Heat Trail: eat food, do not stop. Spectral: rotate hue, match enemies. The games that do not work are the ones that try to explain too much.

**Insight:** The platform should be the same. Cue-mem should feel like "tokens cool, heat the important ones." CueSheets should feel like "answer the questions, the system does the rest." If a module requires a paragraph to explain what it does, it is too complex.

**System implication:** "Dumb by design" is not just a policy -- it is a gameplay lesson. The games that players return to are the ones where the mechanic is immediately obvious and the depth emerges from repetition. The platform modules should have the same property.
