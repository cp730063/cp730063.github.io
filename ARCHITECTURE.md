# Fantasy League History — Architecture & Getting Started

_Working doc. Reflects real data pulled from your Sleeper league on 2026-09-02._

---

## 1. What I found (current status)

**Your league:** "Aldan: The Eternal Dischnasty" — 12-team **dynasty** (keepers, taxi squads, FAAB $100), PPR-ish scoring, 6 playoff teams, playoffs start week 15.

**History depth on Sleeper is shallow right now:**

| Season | Sleeper league_id | Status |
|---|---|---|
| 2026 | `1343022509649330176` | in season, week 1 |
| 2025 | `1179881509322113024` | complete (champion: roster 2) |
| pre-2025 | — | **not on Sleeper** — the `previous_league_id` chain dead-ends at 2025 |

So today there is exactly **one completed season** of Sleeper history. The pipeline and every feature can still be built now, but "extremely detailed history" stays thin until either (a) more seasons accrue, or (b) we **backfill pre-2025 seasons** from wherever the league lived before (ESPN?). That decision shapes the schema, so it's the main open question below.

**Raw data already pulled and saved** to `data/raw/sleeper/<league_id>/`:
`league`, `users`, `rosters`, `drafts` + per-draft `picks` / `traded_picks`, `winners_bracket`, `losers_bracket`, `traded_picks`, and per-week `matchups/` and `transactions/` (weeks 1–18) for both seasons. Full NFL player catalog at `data/raw/sleeper_players_nfl.json` (14 MB).

**Toolchain gap on this machine:** no Node.js, no usable Python, no Docker — only `git` and `curl`. Anything beyond a static HTML file needs Node installed first (one command, see §8).

---

## 2. Decisions

### Build style → **I scaffold, you steer**
I generate adapters, schema, and page skeletons in reviewable increments. Every judgment call (what counts as a "record", how a trade is scored, how playoff finishes map to standings) gets surfaced to you, not buried in code.

### Language → **TypeScript everywhere (for now)**
- Sleeper/ESPN adapters are plain REST fetches — no Python advantage.
- Sleeper and ESPN both return weekly fantasy points directly, so no neutral stats source (`nfl_data_py`, nflverse) is needed yet.
- Records / H2H / ownership stints / trade pre-post points are mostly SQL + light transforms.
- One language = simplest deploy.
- **Keep the analytics layer as its own module** behind a clean interface, so a Python worker can take over specific heavy jobs later (historical re-scoring under different rules, draft-slot value regression, Knockout survival odds) without touching the rest.

---

## 3. Architecture (four layers, built in this order)

```
[ platform adapters ]  Sleeper, ESPN, Yahoo...  -> raw JSON snapshots (immutable, versioned by fetch date)
        |
[ normalized store ]   Postgres, same shape regardless of source
        |
[ derived analytics ]  records, H2H, ownership timelines, trade evals, draft-slot value  (materialized / cached tables)
        |
[ UI ]                 Next.js pages that only read derived tables
```

Raw snapshots are kept forever. Everything downstream is rebuildable from them — so a schema change or a new metric is just "re-run the transform", never "re-scrape years of history".

### Phasing

| Phase | Scope |
|---|---|
| **0 — Prototype** | Static single-page site built from the saved JSON, opened directly in a browser. No backend, no Node. Proves the features (all-time records, H2H grid, playoff results, trade list) against your real data. |
| **1 — Real app, Sleeper + ESPN backfill** | Next.js + Postgres. Sleeper adapter + **ESPN adapter for the pre-2025 dynasty seasons** + cross-platform identity mapping. Normalized schema, incremental ingestion (cron polls transactions/matchups). Pages: records (reg / reg+playoff / playoff-only), H2H, ownership timeline, trade history + ranking, per-manager top player-seasons. Multi-league schema but no user accounts. |
| **2 — More** | ESPN Knockout league (separate franchise). Draft-slot value analytics. Research/links section. Optionally Yahoo. |
| **3 — Public + social** | User accounts, per-league identity verification, the interactive Trade Block + private messaging. Treat as a **separate product** — different data (PII), real-time, moderation. Do not let it block Phases 1–2. |

### Stack
- **Frontend:** Next.js (App Router) + TypeScript + Tailwind + TanStack Query; Recharts or visx for charts.
- **DB:** Postgres — Neon or Supabase free tier. Drizzle ORM (lighter than Prisma for analytical SQL).
- **Ingestion:** scheduled job (Vercel Cron or a small Railway/Render worker).
- **Deploy:** Vercel + managed Postgres.

---

## 4. Normalized schema (draft)

IDs are surrogate `uuid`/`bigint`; natural keys kept as columns for idempotent upserts.

```
platform            (id, name)                                  -- 'sleeper','espn','yahoo'
league              (id, platform_id, name, sport)              -- the *franchise*, spanning all seasons
league_season       (id, league_id, season, source_league_id,   -- one Sleeper league_id per row
                     scoring_json, roster_slots_json, settings_json,
                     playoff_week_start, num_teams, league_type) -- redraft|keeper|dynasty|knockout|guillotine

person              (id, display_name, notes)                   -- a human, spans seasons & platforms
person_identity     (id, person_id, platform_id, source_user_id,-- maps Sleeper user_id / ESPN memberId
                     handle, confidence)                        -- 'confirmed' | 'auto' | 'suspected'

team_season         (id, league_season_id, source_roster_id,    -- Sleeper roster_id (per season)
                     person_id, co_person_ids[], team_name,
                     division)
standing_season     (team_season_id, wins, losses, ties,
                     points_for, points_against, points_potential,-- Sleeper 'ppts' = optimal lineup
                     regular_seed, final_rank, playoff_result)   -- 'champion'|'runner_up'|'3rd'|'lost_R1'|...

player              (id, source, source_player_id, full_name,
                     position, nfl_team, status)                -- from sleeper_players_nfl.json
player_week_stat    (league_season_id, player_id, week,
                     fantasy_points, is_starter, team_season_id) -- from matchups[].players_points / starters

matchup             (id, league_season_id, week, source_matchup_id,
                     team_season_id, opponent_team_season_id,
                     points, opponent_points, is_playoff,
                     playoff_round, bracket)                     -- 'winners'|'losers'|null
                                                                -- expand each Sleeper matchup pair into 2 rows

draft               (id, league_season_id, source_draft_id, type,-- 'startup'|'rookie'|'annual'
                     rounds, scoring_type, draft_order_json)
draft_pick          (id, draft_id, round, slot, overall_pick,
                     team_season_id, player_id, is_keeper)
draft_pick_asset    (id, league_id, season, round, original_team_season_id,
                     current_person_id)                          -- future-pick ownership (Sleeper traded_picks)

transaction         (id, league_season_id, week, source_txn_id,
                     type, status, created_at)                   -- 'trade'|'waiver'|'free_agent'|'commissioner'
transaction_item    (id, transaction_id, kind,                   -- 'add_player'|'drop_player'|'pick'|'faab'
                     team_season_id, player_id,
                     pick_season, pick_round,
                     faab_amount, faab_from_team_season_id,
                     faab_to_team_season_id)

-- derived / materialized
ownership_stint     (id, league_id, player_id, person_id,
                     team_season_id, acquired_event, acquired_type,-- 'startup_draft'|'rookie_draft'|'trade'|'waiver'|'free_agent'
                     acquired_at, ended_event, ended_type, ended_at,
                     is_current)
trade_eval          (transaction_id, team_season_id, person_id,
                     points_received_rest_of_season,
                     points_sent_rest_of_season,
                     points_received_next_season,
                     value_delta, rank_in_league_history)
h2h_record          (league_id, person_a, person_b, wins_a, wins_b,
                     ties, points_a, points_b, playoff_wins_a, playoff_wins_b)
record_book         (league_id, scope, metric, person_id,        -- scope: 'all_time'|'season'|'playoff'|'week'
                     team_season_id, week, value, context_json)  -- one row per notable record
```

### Judgment calls to confirm
1. **"All-time record"** = regular season only, or regular + playoffs? (recommend: track both, show regular-season by default.)
2. **Points "potential" (`ppts`)** — surface it? It enables "best manager vs luckiest manager" analysis. (recommend: yes.)
3. **Trade evaluation window** — rest-of-current-season, next full season, or rolling 16 games from trade date? (recommend: rest-of-season + next season, both shown.)
4. **Dynasty startup draft** — count startup picks as "acquisitions" in ownership history, or treat startup as the baseline "everyone started here"? (recommend: label them `startup_draft` so they're distinguishable but still show on the timeline.)
5. **Co-owners** — attribute records to both people, or a primary? (recommend: both, with a primary flag.)

---

## 5. Platform adapters

### Sleeper (done enough to build against)
- Public, no auth, CORS-enabled, JSON, ~1000 req/min. Chain seasons via `previous_league_id`.
- Endpoints used: `/league/{id}`, `/users`, `/rosters`, `/matchups/{week}`, `/transactions/{week}`, `/drafts` + `/draft/{id}/picks` + `/draft/{id}/traded_picks`, `/league/{id}/traded_picks`, `/winners_bracket`, `/losers_bracket`, `/players/nfl` (cache daily — 14 MB).
- Identity is easy within Sleeper: `rosters[].owner_id` = a stable Sleeper `user_id` across all seasons; `co_owners[]` for shared teams.
- Matchups: two rows sharing `matchup_id` = one H2H pairing. Has `points`, `players_points{}`, `starters[]`, `starters_points[]` → gives H2H, all-play, optimal-lineup.
- Brackets: `p:1` = championship game, `p:3` = 3rd place; `w`/`l` are winner/loser `roster_id`.
- Trades: `transaction.type='trade'` with `adds`/`drops` (`{player_id: roster_id}`), plus `draft_picks[]` and `waiver_budget[]` (FAAB) as separate trade components.
- Watch out: week-1 (`leg` 1) transactions file lumps in a lot of preseason activity.

### ESPN — including your **Knockout** (guillotine) league — Phase 2
- No official API. Unofficial `https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/{year}/segments/0/leagues/{id}?view=...`.
- Private leagues need `espn_s2` + `SWID` cookies → must run **server-side** (never in the browser; keep credentials in env/secret store).
- History: `?view=mMatchupScore&view=mTeam` per season; older seasons sometimes via a `leagueHistory` endpoint.
- Knockout specifics: ESPN exposes it as a league type, but eliminations may surface as roster changes / standings rather than a clean "eliminated week N" field. Plan to **derive elimination week** from when a team stops having valid lineups / drops to 0 active players, and store it explicitly (`standing_season.playoff_result = 'eliminated_wk_N'`). Build against saved fixtures because the endpoints change without notice.

### Yahoo — optional, later
OAuth2 3-legged + app registration; XML/JSON. Only if you or users have Yahoo leagues.

---

## 6. Your wishlist → where it lives

| Feature | Data needed | Phase |
|---|---|---|
| All-time records, H2H, playoff, playoff H2H, championships | `matchup`, `standing_season`, brackets | 1 |
| Player ownership history (click a player → full league timeline) | `ownership_stint` (from draft + `transaction` stream) | 1 |
| Length of time each manager has held a player | `ownership_stint` durations | 1 |
| Per-manager ranking of top player-seasons / total fantasy points | `player_week_stat` aggregated by `team_season` | 1 |
| Trade history + trade ranking (pre/post points) | `transaction` + `trade_eval` | 1 |
| Draft-pick value over league history (avg points by draft slot) | `draft_pick` + `player_week_stat`, multi-season | 2 (needs more seasons) |
| Research section / outbound links (possible affiliate $) | static content + link tracking | 2 |
| Knockout-specific views (survival timeline, elimination odds) | ESPN adapter + derived elimination week | 2 |
| Interactive Trade Block + private messaging | new: accounts, real-time, moderation | 3 (separate product) |

---

## 7. Open questions — RESOLVED 2026-09-02

1. **Pre-2025 history:** YES — the dynasty league was on ESPN before 2025. User wants ESPN attached so full league history is pulled. → **ESPN adapter + cross-platform identity mapping move into Phase 1**, not Phase 2. The `league` franchise spans both the old ESPN `league_season` rows and the Sleeper ones; `person` unifies managers across the two platforms.
2. **ESPN Knockout league:** entirely different league and different people. Separate `league` row; no shared `person` records assumed.
3. **Records:** regular season only is the **default/primary** view. Also build (a) a combined regular+playoff record book and (b) a playoff-only record book. All three use `record_book.scope` (`all_time` = reg only, `all_time_incl_playoffs`, `playoff`).
4. **Phase 0 format:** see recommendation below — going with the shareable hosted page (Artifact), snapshot embedded.

---

## 8. Next steps

**You:**
- [ ] Answer the 4 questions in §7.
- [ ] Install Node LTS so Phase 1 can run locally:
  ```bash
  winget install OpenJS.NodeJS.LTS
  ```
- [ ] Confirm whether the league has pre-2025 history to backfill.

**Me (next increment):**
- [ ] Build the Phase 0 prototype from the saved JSON: all-time records + per-season standings + H2H grid + 2025 playoff bracket + trade list.
- [ ] Turn this schema into a Drizzle migration + a Sleeper adapter module (TypeScript) once Node is available.
- [ ] Write the raw→normalized transform with the §4 judgment calls wired to your answers.

---

## Appendix — files in this workspace

```
fantasy-history/
  ARCHITECTURE.md                     <- this file
  data/
    raw/
      sleeper/
        1179881509322113024/          <- 2025 season
        1343022509649330176/          <- 2026 season
        ../sleeper_players_nfl.json   <- full NFL player catalog (14 MB)
    needed_player_ids.txt             <- 464 player ids referenced by these two seasons
```
