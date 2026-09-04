# FantasyMags — Calculation Methodology & Assumptions

Every number on the site that we compute ourselves (rather than read straight from ESPN/Sleeper), the assumptions behind it, and a worked example. Keep this in sync with the code — it is the source for `FantasyMags-Methodology.xlsx`.

Last updated: 2026-09-04

---

## Foundations (apply everywhere)

### Records are rebuilt from game scores, not read from the platform
**What:** Every W-L-T, points-for, points-against and streak is recomputed from the individual matchup scores in each season's schedule. We do not trust ESPN's stored `record.overall`.
**Assumptions:**
- A regular-season game counts if its matchup period is a regular-season period (not a playoff/consolation tier).
- A tie is scored only when the two sides are exactly equal.
- For leagues that pre-date box scores (manual overlay years), only W-L-T from the overlay is used; points are blank.
**Example:** In 2015 the ESPN app shows Ryan Murray 14-4-3. We add up his 21 weekly matchups ourselves and get the same 14-4-3, so the site shows 14-4-3 with points-for/against we summed from those 21 games.

### Manager identity is merged across platforms and accounts
**What:** One person can appear as an ESPN account, a second ESPN account, and a Sleeper handle. They are collapsed to a single manager via a hand-maintained map (`scripts/leagues/<league>.json` → `people[]`).
**Assumptions:**
- Two ESPN GUIDs listed under one person (`espnAlt`) are the same human (co-managers, or someone who rebuilt their account).
- Co-managed teams are shown as "Name A / Name B"; the more active manager is listed first.
**Example:** In the baseball league, "Jim McGarrity" and "Rob DiNicola" share one franchise, so both GUIDs map to one manager shown as "Jim McGarrity / Rob DiNicola."

### "Played" vs "scheduled" seasons
**What:** A season is only counted in totals, records and averages once real games have been played.
**Assumptions:**
- An ESPN season with a full schedule but every score 0 is treated as "scheduled, not played" (draft shows, standings/records do not).
- A roto season (no weekly matchups) counts if it has real final standings.
**Example:** The 2026 football league had drafted but not played a game as of this writing, so it appears only on the Drafts tab.

---

## Overview

### Reigning champion callout
**What:** The champion of the most recent *played* season with a crowned champion.
**Assumptions:** An in-progress season with no champion yet is skipped; we walk back to the last finished one.
**Example:** Baseball shows Linda Kerrigan (2025) as reigning champion even though 2026 is underway.

### Title-history timeline
**What:** One row per manager who has ever won, a dot on each year they won, earliest title marked in green, repeats in gold.
**Assumptions:** Year axis is evenly spaced by index; if a league skipped a year (e.g. no 2008), the labels are simply irregular.

### Franchises "Form" sparkline
**What:** A 68x20px line of the manager's win% by season, baseline drawn at 50%, gold dots on title years.
**Assumptions:** Needs at least 2 seasons with game scores; otherwise shows "—". Career win% (the sort value) counts every season including manual ones.

---

## Standings

### All-time table
**What:** Career W-L-T, PF, PA, and PF per game, aggregated from each season's per-manager totals.
**Assumptions:**
- Manual-overlay seasons contribute W-L-T but not points.
- "PF/G" divides points by games that actually have box scores, not by all games.
**Example:** A manager with 8 API seasons and 3 manual seasons shows an 11-season record, but PF/G is computed over just the 8 seasons that have scores.

---

## Records tab

### Record book (bests & worsts)
**What:** Highest/lowest single-game and single-season scores, longest streaks, biggest blowouts, etc.
**Assumptions:**
- Rate-style records (fewest points in a season) require a minimum of 4 games played so a 1-week fragment can't win.
- For category leagues these are "category wins," shown as whole numbers.

### All-time rankings widget
**What:** One table, switchable metric (Wins, Win %, Points For, Points Against, Points/Game, Trades), with two toggles: Regular season / Playoffs and All-time / Season.
**Assumptions & minimums:**
- Rate metrics need a games floor so small samples don't top the list. Football: 20 all-time / 24 combined / 4 playoff. Baseball (target): 60 regular-season games / 60 combined / no playoff minimum.
- "Trades" ignores the scope toggle and is hidden entirely for leagues that have no trade data (all ESPN-only leagues).
- Manual-overlay seasons are excluded from every metric here (no game scores) and a note says so.
**Example:** A manager who played 2 seasons (26 games) is left out of the all-time Win % ranking until they clear the 20-game (football) / 60-game (baseball) floor.

---

## Head-to-Head

### Pairwise record & rivalry detail
**What:** For any two managers: series lead, total meetings, points each in those meetings, a meeting-by-meeting list, and a career side-by-side (Win %, record, PPG, PF, PA).
**Assumptions:**
- Career record spans every season including manual; points and PPG are only the box-score era.
- For category leagues the labels read "Category wins / Category losses" and scores are whole numbers.
**Example:** "Michael Scelsa leads 33-27-8 over Linda Kerrigan, 68 meetings" — that record is every regular-season and playoff matchup between them.

### Biggest Rivalries / Most Lopsided Series
**What:** Ranked lists of the most-played and most one-sided pairings.
**Assumptions:** A pairing needs a minimum number of meetings to appear — currently 12, target 15 for the baseball league so 24 years of data doesn't bury the real rivalries.

### Box scores (per meeting)
**Football:** the two starting lineups with per-player points; bench shown where the data has it (2018+), starters-only for 2015-17, nothing pre-2011.
**Baseball:** the category grid — each scoring category, both managers' totals, a check on the one they won, a down-arrow on categories where lower is better, and a "categories won" line.
**Assumptions (baseball):** Win/loss per category is taken from ESPN's own result flag for 2018+ and derived by comparing the two totals for older seasons. Only the categories in use *that season* are shown.
**Example:** A 2015 week might show "R 45-38 ✓ / HR 9-12 / ... / Categories won 6-4" — six of ten categories won.

---

## Legacy tab

### Prestige Rankings
**What:** A career points score from weighted honors, weights set per league.
**Assumptions:**
- Weights come from each league's own rulebook. Baseball: Champion 7, Regular-season champ 3, Division champ 2, Runner-up 2, Wildcard 1.
- "Wildcard" means *made the playoffs without winning a division*, so a division winner scores 2 (division), not 3 (division + berth).
**Example:** A manager with 2 titles, 1 regular-season crown and 3 division titles scores 2x7 + 1x3 + 3x2 = 23.

### Championship Drought
**What:** Years since each manager's last title, longest first.
**Assumptions:**
- Active managers only — someone whose most recent season is more than one year before the latest played season is dropped, so their drought doesn't grow forever and clutter the table.
- A manager who has never won shows "never won · N yr" where N is years since they joined.

### All-Play Win %
**What:** Every week, score each manager against every other manager's score that week; sum the resulting W-L-T over a career.
**Assumptions:**
- Only weeks with real box scores on both sides count (both scores > 0).
- This removes schedule luck — it is not the manager's actual record.
**Example:** In a 12-team week you get 11 all-play results; a top-3 score that week might go 9-2.

### Playoff Appearance Rate
**What:** Playoff berths ÷ seasons played.
**Assumptions:**
- A "berth" is *any* season the manager made the playoff field, including as a division winner or bye — this is separate from the prestige "wildcard" count.
- Minimum 3 seasons to appear.
**Example:** Carl Pashko made the baseball playoffs in 10 of his 19 seasons → 53%.

---

## Playoffs tab

### Bracket & title-game margins
**What:** The playoff bracket per year and a ranked list of championship-game margins.
**Assumptions:** For category leagues, scores are whole numbers (category wins), not decimals.

---

## Team Names

### Name Hall of Fame
**What:** Managers ranked by how many distinct team names they have used, plus each manager's full name journey.
**Assumptions:** A "name" is the exact team-name string ESPN recorded for that manager that season; capitalization/spacing changes count as different names.

---

## Drafts tab

### Draft board layout
**What:** A grid of teams (in first-round slot order) by round, each cell the pick number + player + position.
**Assumptions:**
- Snake direction each round is inferred from who holds pick 1 of that round.
- ESPN appends the rookie draft as extra rounds after the keeper draft; we detect the rookie rounds as the trailing block of rounds in which nobody kept a player, and renumber them "Rookie R1, R2…".
- "Via <manager>" (traded pick) is shown on Sleeper boards only. ESPN's draft data records who *made* each pick but never who originally owned it, so ESPN boards show no "via" and carry a note saying so.

### Draft Grades (football)
**What:** A letter grade per manager per draft, from the "value surplus" of each pick versus what that draft slot usually returns.
**Assumptions:**
- We grade the *pick*, not in-season management: a pick's outcome is the drafted player's full-season fantasy points that year, divided by that season's baseline (mean of the top half of drafted players) to normalize 2003 vs 2025.
- Rookie picks in a dynasty league also get a draft-time grade from the player's *current* trade value vs the slot — only for classes with 0-1 completed seasons; older classes are judged on production.
- Expected value by round = the mean outcome at that round across every gradeable draft, lightly smoothed with its neighbors.
- Pick weight in the manager's score is 1/√round, so round 1 matters more than round 15.
- Letter grade is a curve: the manager's score is z-scored against all graded manager-drafts (A+ ≈ 1.3 SD above, F at the bottom).
- Keeper and auction drafts are skipped; a pick for a season not yet played shows "TBD".
**Example:** In 2019 Ryan Lenahan drafted Christian McCaffrey at 1.02 and CMC returned 1.2x the baseline that year → a big positive surplus, contributing to an A+ class.

---

## Trade Values

### Trade Calculator (football)
**What:** Add players/picks to each side; the tool sums market values and shows who the trade favors and by how much.
**Assumptions:**
- Player values are a build-time snapshot from FantasyCalc, matched to the league's exact format (superflex/1-QB, PPR, team count). Re-run to refresh.
- Pick values use FantasyCalc's generic "2026 1st (early/mid/late)" tiers.
- Fairness verdict thresholds: under 3% = Even, under 8% = Slight edge, under 20% = Favors, otherwise Lopsided.
- The favored side is whoever *receives* more value.
- Roster-crunch (optional, on by default): if the sides trade an unequal number of *players* (picks don't count, they don't fill a roster spot), the side receiving more players has the value of its cheapest bench players added, because it will have to cut someone to fit them.
**Example:** Side A sends one player worth 1930; Side B sends two worth 2552 total → "Side A wins by 622 (24%)". With roster-crunch on, Side B also absorbs an extra body, shrinking the edge.

### Trade intelligence report (football)
**What:** A plain-English read of how the trade changes each roster, across four factors.
**Assumptions & definitions:**
- **Positional depth vs league:** for each position the trade touches, count of "startable" players before vs after, compared to the number of starting slots. "Startable" = FantasyCalc positional rank inside teams x starting-slots-at-that-position.
- **Roster age & window:** value-weighted mean age of the roster's core (top ~1.2 x teams players). "Win-now" = strong and old; "rebuilding" = weak roster value; otherwise "contending / middle".
- **Stud vs depth balance:** counts of elite / starter / depth players sent vs received (elite = top 2x teams by value, starter = top 7x teams). Deliberately count-based, never a quality judgment, so it can't contradict the value bar.
- **Draft capital:** net picks and net first-rounders moving each way, plus their total value.
- The report is descriptive with light framing — it never issues a verdict.

---

## Research tab

### Risers & Fallers
**What:** Biggest 30-day trade-value movers, per format.
**Assumptions:**
- Source is FantasyCalc's 30-day trend (an absolute point change, which we convert to a percentage of current value).
- Floor to filter noise: current value ≥ 1500 (dynasty) / 700 (redraft).
- Drop obvious data artifacts where the reported move is larger than the player's whole value.
- Percentage is clamped to ±99%.
- 8 risers + 8 fallers per format.

---

## Baseball — player value engine

### Season "Value"
**What:** One number per player per season = the sum of that player's z-scores across the league's scoring categories, measured against the pool of rosterable players.
**Assumptions & choices:**
- **Full season**, regardless of who owned the player or when. (A separate "what the manager actually got" view is a later addition.)
- **Each season is scored against that season's own categories** — OPS only counts from the year the league added it, holds only in the years holds were a category, etc.
- Data source is ESPN's end-of-season roster snapshot, which carries a full stat line for every rostered player back to 2008. No outside data.
- **Counting categories** (R, HR, RBI, SB, W, K, SV, HLD, IP): z-score of the raw total vs the pool.
- **Rate categories** (AVG, OBP, SLG, OPS, ERA, WHIP, K/9): playing-time weighted — contribution = (player rate − pool's playing-time-weighted rate) x the player's playing time (AB, plate appearances, or innings), then z-scored. ERA and WHIP are flipped so lower is better.
- The "pool" is the top (teams x starting slots x 1.6) players at each of hitting and pitching, chosen by a rough pre-rank on the counting stats.
- A player value near 0 is a replacement-level everyday player; elite seasons land around +10 to +19. There is no explicit replacement-level subtraction in v1 — the pool mean already sits near 0.
- Two-way players (e.g. Ohtani) are valued on both their hitting and pitching categories and can exceed +18.
- A player must have ~20 AB or ~10 IP to be valued at all.
- For an in-progress season, the current-year to-date line is used (an ESPN file for a live season also contains last year's final line — we pick the one whose season matches).
**Example:** Jake Arrieta's 2015 (22 W, 1.77 ERA, 236 K, 0.86 WHIP) scored +10.5 — the top value in that league that year. Aaron Judge's 2022 (62 HR, .425 OBP) is the all-time single-season high at +19.9.

### "Drafted by" vs "Team"
**What:** Each player-season is credited to the manager who drafted the player; the card and table also show who held him at season's end.
**Assumptions:** ESPN keeps no historical transaction log, so only the start point (draft) and end point (final roster) are known — mid-season moves between the two are not shown. An undrafted player picked up during the year shows "(added)".

### Player identity
**What:** Player-seasons are grouped by ESPN's permanent player id.
**Assumptions:** This keeps Vladimir Guerrero Jr. and Sr. as separate players (a name-based key would merge them). ~6-13 drafted players per year were cut before any roster snapshot and have no stat line — they show "Player &lt;id&gt;" on the draft board and are not valued.

### Baseball "Wins" (weekly record)
**What:** A manager's W-L-T is the count of weekly *matchups* won, not categories won.
**Assumptions:** Winning a week 7 categories to 5 is one win. The separate "CW / CL" columns are the season's category totals and are labeled as such.

---

## Worked example — Aaron Judge, 2022 (value +19.9)

This is the "Judge 2022 example" tab in the workbook, kept here too so the doc is self-contained. If the value engine changes, update both this section and the `@J` array in `scripts/make_methodology_xlsx.pl`.

**Short version:** value = for each scoring category, how many standard deviations better than a typical rosterable hitter he was, added up. A standard deviation is just a normal amount of spread — if most rostered hitters are within ~10 HR of each other, 1 SD ≈ 10 HR.

**Step 1 — categories that counted in 2022:** Runs, HR, RBI, SB, Slugging, On-Base % (6 hitting categories; pitching categories are scored separately for pitchers).

**Step 2 — the pool:** every hitter that season with ~20+ at-bats = 153 hitters. "A typical rosterable hitter" = the average of this group.

**Step 3 — counting categories (Runs, HR, RBI, SB):** compare his total to the pool, in standard deviations.

Home runs in full: pool average 18.9, 1 SD = 9.8, Judge 62 → (62 − 18.9) ÷ 9.8 = **+4.38**.

| Category | Judge | Pool avg | Score |
|---|---|---|---|
| Runs | 133 | ~78 | +2.90 |
| HR | 62 | ~19 | +4.38 |
| RBI | 131 | ~74 | +2.75 |
| SB | 16 | ~13 | +0.97 |

**Step 4 — rate categories (SLG, OBP):** weighted by playing time, so a small hot sample can't inflate them. Question: over all his plate appearances, how many extra times did he reach base vs an average hitter?

On-base % in full: PT-weighted league OBP .334, Judge .425 over 696 PA → extra times on base = 696 × (.425 − .334) ≈ 63. 1 SD of that "extra times on base" number across the pool ≈ 16.6. Score = 63 ÷ 16.6 = **+3.79**. Slugging by the same method = **+5.07**.

**Step 5 — add it up:** 2.90 + 4.38 + 2.75 + 0.97 + 5.07 + 3.79 = **+19.9**.

**What the number means:** ~0 = replacement-level regular; +8 to +12 = a strong first-round season; +19.9 = best in league history, because he was elite (not just good) in five of six categories at once (only SB is ordinary).

### How "1 standard deviation" is calculated (the 2022 HR pool)

1. **Average:** 2,885 total HR ÷ 153 hitters = 18.86.
2. **Distance from average, per hitter:** their HR − 18.86 (a 30-HR hitter is +11.1; Judge is +43.1).
3. **Square each distance and add them up:** 14,719. Squaring makes them all positive and weights big misses more.
4. **Divide by (hitters − 1), then square-root:** 14,719 ÷ 152 = 96.8 (variance); √96.8 = **9.84** (standard deviation). The square-root puts the answer back in home runs.

Tiny version to check by hand — 5 hitters with 8, 14, 19, 24, 30 HR: mean = 19; squared distances = 121 + 25 + 0 + 25 + 121 = 292; variance = 292 ÷ 4 = 73; SD = √73 = 8.5.

### The 20 at-bat minimum

A judgment call, not a statistical rule. It only keeps cup-of-coffee seasons out of the list and the pool pre-rank. It is deliberately low because the rate-stat weighting and the counting-stat penalties already handle small samples on their own. Raising it (say to 50 AB) would drop marginal names but move no real player's value.
