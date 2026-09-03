# FantasyMags — League History & Analytics

An interactive history site for fantasy football leagues (ESPN + Sleeper), covering
all-time records, head-to-head, legacy rankings, player ownership history, drafts,
trades, and playoffs.

**Live site:** https://cp730063.github.io

## How it's built

Everything is a static, self-contained `index.html`. No server, no framework.

- `scripts/` — Perl build pipeline (raw API JSON → normalized per-league bundles → injected into the page)
  - `pull_espn_player_weeks.pl` — pulls ESPN weekly rosters/scoring
  - `build_bundle2.pl <slug>` — normalizes one league (config in `scripts/leagues/<slug>.json`)
  - `build_all.pl` — builds every league + the manifest
  - `build_index.pl` — injects the league manifest into `prototype/template.html` → `index.html`
  - `pull_values.pl` — dynasty trade values (FantasyCalc) + current rosters → `bundles/<slug>.values.json` (run periodically; not part of build_all)
- `prototype/template.html` — the app (HTML + CSS + one JS file)
- `bundles/*.json` — per-league data fetched on demand: `<slug>.json` (history), `<slug>.lineups.json` (box scores), `<slug>.values.json` (trade calc), `leagues.json` (manifest)
- `index.html` — the built shell (repo root; what GitHub Pages serves)
- `reference/` — manual pre-API overlays and source material
- `data/` — raw API dumps (local only, not tracked)

Rebuild: `perl scripts/build_all.pl && perl scripts/build_index.pl`
