#!/usr/bin/perl
# Generates FantasyMags-Methodology.xlsx (a hand-rolled minimal xlsx: a zip of
# XML parts). No CPAN modules -- the zip step is done by scripts/make_methodology_xlsx.ps1.
#   perl scripts/make_methodology_xlsx.pl
#   powershell -File scripts/make_methodology_xlsx.ps1
use strict; use warnings;
use FindBin qw($RealBin);
use File::Path qw(make_path remove_tree);
my $ROOT  = "$RealBin/..";
my $STAGE = "$ROOT/.xlsx_stage";

# =====================================================================
# Sheet 1: Methodology  [ Area, Feature, Where, What, Assumptions, Example ]
# =====================================================================
my @HDR = ('Area','Feature','Where on the site','What we calculate',
           'Key assumptions & choices','Worked example');
my @ROWS = (
['Foundations','Records from game scores','Everywhere',
 'Every W-L-T, points for/against and streak is recomputed from individual matchup scores; the platform\'s stored record is ignored.',
 'A game counts as regular season only if its matchup period is a regular-season period. A tie needs exactly equal scores. Manual-overlay years contribute W-L-T only, no points.',
 'ESPN shows Ryan Murray 14-4-3 in 2015; summing his 21 weekly matchups ourselves also gives 14-4-3, so that is what we display.'],
['Foundations','Cross-platform manager identity','Everywhere',
 'One person\'s multiple ESPN accounts and Sleeper handle are merged into a single manager via a hand-maintained map.',
 'Two ESPN GUIDs under one person are treated as the same human (co-managers or a rebuilt account). Co-managed teams show "A / B" with the more active manager first.',
 '"Jim McGarrity" and "Rob DiNicola" share one baseball franchise, shown as "Jim McGarrity / Rob DiNicola".'],
['Foundations','Played vs scheduled season','Everywhere',
 'A season enters totals/records/averages only once real games are played.',
 'A full schedule with every score 0 = "scheduled, not played" (draft shows; standings do not). A roto season with no weekly games counts if it has real final standings.',
 'The 2026 football league had drafted but not played, so it appeared only on the Drafts tab.'],
['Overview','Reigning champion','Overview',
 'The champion of the most recent played season that has a crowned champion.',
 'An in-progress season with no champion yet is skipped; we walk back to the last finished one.',
 'Baseball shows Linda Kerrigan (2025) as reigning champ while 2026 is still in progress.'],
['Overview','Franchises "Form" sparkline','Overview',
 'A small line of the manager\'s win% by season, 50% baseline, gold dots on title years.',
 'Needs 2+ seasons with game scores, else "-". The sortable career win% includes every season (manual years too).',
 'A manager with one played season shows "-" for Form.'],
['Standings','All-time table','Standings',
 'Career W-L-T, PF, PA and PF per game, aggregated from each season\'s per-manager totals.',
 'Manual-overlay seasons add W-L-T but not points. PF/G divides by games that have box scores, not all games.',
 '11-season manager with 3 manual years: record spans 11 seasons, PF/G is over the 8 scored seasons.'],
['Records','Record book bests & worsts','Records',
 'Highest/lowest single game and season, longest streaks, biggest blowouts.',
 'Fewest-points-in-a-season needs 4+ games so a fragment cannot win. Category leagues show whole numbers ("category wins").',
 'A manager who played only 3 weeks cannot hold the "fewest points in a season" record.'],
['Records','All-time rankings widget','Records',
 'One table, switchable metric (Wins, Win %, PF, PA, PF/G, Trades) with Regular/Playoffs and All-time/Season toggles.',
 'Rate metrics have a games floor: football 20 all-time / 24 combined / 4 playoff; BASEBALL 60 regular / 60 combined / none for playoffs. "Trades" ignores scope and is hidden when a league has no trade data. Manual seasons are excluded here.',
 'A 2-season (26-game) manager is left out of all-time Win % until clearing the floor.'],
['Head-to-Head','Pairwise record & rivalry detail','Head-to-Head',
 'Series lead, meeting count, points each in those meetings, meeting list, and a career side-by-side.',
 'Career record spans all seasons incl. manual; points/PPG are box-score era only. Category leagues label it "Category wins / losses" and use whole numbers.',
 '"Michael Scelsa leads 33-27-8 over Linda Kerrigan, 68 meetings" = every reg-season + playoff matchup between them.'],
['Head-to-Head','Biggest Rivalries / Most Lopsided','Head-to-Head',
 'Ranked lists of the most-played and most one-sided pairings.',
 'A pairing needs a minimum number of meetings to list: 12 for football, 15 for the 24-year baseball league.',
 'Two managers who have met 9 times do not appear on either list.'],
['Head-to-Head','Box scores per meeting (baseball)','Head-to-Head',
 'The category grid: each scoring category, both totals, a check on the winner, a down-arrow where lower is better, and a "categories won" line.',
 'Win/loss per category is ESPN\'s own result flag for 2018+, derived by comparing totals for older seasons. Only categories in use that season are shown.',
 'A 2015 week: "R 45-38 check / HR 9-12 / ... / Categories won 6-4".'],
['Head-to-Head','Box scores per meeting (football)','Head-to-Head',
 'The two starting lineups with per-player points.',
 'Bench is shown where the data has it (2018+); starters only for 2015-17; nothing pre-2011.',
 'A 2016 matchup shows both starting lineups; a 2016-era one shows starters without bench.'],
['Legacy','Prestige Rankings','Legacy',
 'A career points score from weighted honors; weights set per league.',
 'Weights come from each league\'s rulebook. Baseball: Champion 7, Reg-season champ 3, Division champ 2, Runner-up 2, Wildcard 1. "Wildcard" = made playoffs without a division title, so a division winner scores 2 not 3.',
 '2 titles + 1 reg-season crown + 3 division titles = 2x7 + 1x3 + 3x2 = 23.'],
['Legacy','Championship Drought','Legacy',
 'Years since each manager\'s last title, longest first.',
 'Active managers only -- someone whose last season is more than one year before the latest played season is dropped, so a dormant drought does not clutter the table. Never-won shows "never won - N yr" from the year they joined.',
 'A manager who last played 2 seasons ago is not listed even if their drought is the longest.'],
['Legacy','All-Play Win %','Legacy',
 'Each week, score a manager against every other manager\'s score that week; sum the W-L-T over a career.',
 'Only weeks with real box scores on both sides count. This strips schedule luck; it is not the actual record.',
 'A top-3 score in a 12-team week goes about 9-2 in all-play.'],
['Legacy','Playoff Appearance Rate','Legacy',
 'Playoff berths divided by seasons played.',
 'A "berth" is ANY season the manager made the playoff field (incl. division winner / bye) -- separate from the prestige "wildcard" count. Minimum 3 seasons to appear.',
 'Carl Pashko made the baseball playoffs in 10 of 19 seasons = 53%.'],
['Playoffs','Bracket & title-game margins','Playoffs',
 'The playoff bracket per year and a ranked list of championship-game margins.',
 'Category-league scores are whole numbers (category wins), not decimals.',
 'A 6-4 title game is a margin of 2, not "2.00".'],
['Team Names','Name Hall of Fame','Team Names',
 'Managers ranked by number of distinct team names used, plus each name journey.',
 'A "name" is the exact team-name string ESPN recorded; capitalization/spacing differences count as different names.',
 'A manager who used "The Crew" and "the crew" is credited with 2 names.'],
['Drafts','Draft board layout','Drafts',
 'A grid of teams (in first-round slot order) by round; each cell = pick number + player + position.',
 'Per-round snake direction is inferred from who holds pick 1 of that round. ESPN appends the rookie draft as extra rounds; we detect them as the trailing rounds with zero keeper picks and renumber "Rookie R1..".',
 'A 12-team keeper draft with 5 tail rounds where nobody kept anyone = those 5 become "Rookie R1..R5".'],
['Drafts','Traded-pick "via" attribution','Drafts',
 'On Sleeper boards, a pick made by someone other than the slot owner shows an arrow to the drafter.',
 'ESPN records who MADE each pick but never who originally owned it, so ESPN boards show no "via" and carry a note.',
 'Sleeper: "Fernando Mendoza - QB LV - -> Get Your Weight Up" (pick was traded to them).'],
['Drafts','Draft Grades','Drafts',
 'A letter grade per manager per draft from each pick\'s "value surplus" vs what that slot usually returns.',
 'We grade the PICK not the management: outcome = drafted player\'s full-season points that year / that season\'s baseline (mean of the top half of drafted players). BASEBALL: outcome = the drafted player\'s season VALUE (category z-score sum from the Players tab); already era-adjusted, so no baseline division. Dynasty rookie picks also get a draft-time grade from current trade value vs slot, only for classes with 0-1 completed seasons. Expected value by round = mean outcome at that round across all gradeable drafts, lightly smoothed. Pick weight = 1/sqrt(round). Letter is a curve: z-score of the manager\'s score vs all graded manager-drafts (A+ at ~1.3 SD). 12 for football, 15 (category leagues); keeper and auction drafts skipped; a season still in progress (no champion yet) is withheld until it finishes; a pick whose player never cleared ~20 AB / ~10 IP that year has no value and is skipped.',
 '2019 FBL: Carl Pashko took Trout 1.1, Cole 2.12 and Bellinger 4.12 -- three top-of-league values -> A+ class. 2019 dynasty: Ryan Lenahan took CMC at 1.02, who returned 1.2x baseline that year -> large positive surplus.'],
['Trade Values','Trade Calculator','Trade Calculator',
 'Sum the value of each side\'s players (and picks, football); show who the trade favors and by how much.',
 'FOOTBALL: values are a build-time FantasyCalc snapshot matched to league format (SF/1-QB, PPR, teams); pick values use FantasyCalc generic tiers; roster-crunch (on by default) adds the cheapest bench values to the side receiving more players. BASEBALL: no external market -> values are our own season value (category z-score sum); you pick a season (redraft rosters change yearly); a team\'s roster is its end-of-season roster that year; trade value = season value floored at 0; no roster-crunch, no intel report. Verdict both sports: <3% Even, <8% Slight edge, <20% Favors, else Lopsided. Favored side = whoever RECEIVES more value.',
 'Baseball 2024: Lindor 6.9 + Teoscar 4.7 vs Juan Soto 10.2 -> "Carl comes out ahead, 1.3 in value (12%)".'],
['Trade Values','Intelligence report (football)','Trade Calculator',
 'A plain-English read of how the trade changes each roster, across four factors.',
 'Positional depth: startable count per touched position before vs after vs starting slots ("startable" = FantasyCalc positional rank within teams x slots). Roster age & window: value-weighted mean age of the top ~1.2x teams players; win-now = strong+old, rebuilding = weak value, else contending/middle. Stud vs depth: counts of elite (top 2x teams) / starter (top 7x teams) / depth sent vs received -- count-based only. Draft capital: net picks and net firsts each way. Descriptive with light framing, never a verdict.',
 '"For Team A: core age 25.4, 3rd-strongest roster of 12, contending. Sends 1 starter, gets 2 depth -- spreading across more."'],
['Research','Risers & Fallers','Research',
 'Biggest 30-day trade-value movers per format.',
 'Source is FantasyCalc\'s 30-day trend (an absolute point change, converted to % of current value). Noise floor: value >= 1500 dynasty / 700 redraft. Artifacts where the move exceeds the whole value are dropped. Percentage is clamped to +/-99%. 8 risers + 8 fallers per format.',
 'A player worth 2000 with a +300 30-day trend shows "+15%".'],
['Baseball','Season "Value" (player valuation)','Players',
 'One number per player-season = sum of the player\'s z-scores across the league\'s scoring categories vs the rosterable pool.',
 'FULL SEASON, regardless of owner or timing. Scored against THAT season\'s categories (OPS only from the year it was added, etc.). Source = ESPN end-of-season roster snapshot stat lines (complete back to 2008; no outside data). Counting cats (R,HR,RBI,SB,W,K,SV,HLD,IP): z-score of the raw total vs the pool. Rate cats (AVG,OBP,SLG,OPS,ERA,WHIP,K/9): playing-time weighted -- contribution = (player rate - pool PT-weighted rate) x playing time (AB / PA / IP), then z-scored; ERA & WHIP flipped so lower is better. Pool = top (teams x starting slots x 1.6) at hitting and at pitching. ~0 = replacement-level regular; elite ~+10 to +19; no explicit replacement subtraction in v1. Two-way players valued on both sides. Needs ~20 AB or ~10 IP to be valued. In-progress seasons use the current year\'s to-date line.  See the "Judge 2022 example" tab for a full walkthrough.',
 'Jake Arrieta 2015 (22 W, 1.77 ERA, 236 K) = +10.5, the league\'s top value that year. Aaron Judge 2022 (62 HR, .425 OBP) = +19.9, the all-time single-season high.'],
['Baseball','"Drafted by" vs "Team"','Players',
 'Each player-season is credited to the manager who drafted the player; the card also shows who held him at season\'s end.',
 'ESPN keeps no historical transaction log, so only the start (draft) and end (final roster) are known -- mid-season moves between them are not shown. An undrafted in-season pickup shows "(added)".',
 'Vladimir Guerrero Jr. 2024: "Murrderers\' Row -> Baseball Chaz 13" -- drafted by Ryan Murray, finished on Charles Rorke.'],
['Baseball','Player identity','Players / Drafts',
 'Player-seasons are grouped by ESPN\'s permanent player id.',
 'This keeps Vladimir Guerrero Jr. and Sr. separate (a name key would merge them). ~6-13 drafted players per year were cut before any roster snapshot and have no stat line -- shown as "Player <id>" on the board, not valued.',
 'Vlad Jr. (2019-2026) and Vlad Sr. (2009-2010) get separate player cards.'],
['Baseball','Weekly "Wins" record','Standings / Records',
 'A manager\'s W-L-T is the count of weekly MATCHUPS won, not categories won.',
 'Winning a week 7 categories to 5 is one win. The separate "CW / CL" columns are the season\'s category totals and are labeled as such.',
 'A manager who goes 7-5, 8-4, 3-9 over three weeks is 2-1, with 18 category wins and 18 category losses.'],
);

# =====================================================================
# Sheet 2: "Judge 2022 example"  [ label, detail ]  (label '' = full-width prose)
# style: H = section header, sub = indented sub-row
# =====================================================================
my @J = (
 ['H','THE SHORT VERSION',''],
 ['','','Value = for each scoring category, how many standard deviations better than a typical rosterable hitter he was, added up. A "standard deviation" is just a normal amount of spread: if most rostered hitters are within about 10 HR of each other, 1 standard deviation is about 10 HR.'],
 ['','',''],
 ['H','STEP 1  -  which categories counted in 2022',''],
 ['','','The FBL used 6 hitting categories that year: Runs, HR, RBI, SB, Slugging, On-Base %. Only hitting categories apply to a hitter; pitching categories are scored separately for pitchers.'],
 ['','',''],
 ['H','STEP 2  -  build the pool',''],
 ['','','Take every hitter that season with about 20 or more at-bats (a real amount of playing time). In 2022 that is 153 hitters. This pool is the yardstick: "a typical rosterable hitter" means the average of this group.'],
 ['','',''],
 ['H','STEP 3  -  score the counting categories (Runs, HR, RBI, SB)',''],
 ['','','Compare his total to the pool, measured in standard deviations.'],
 ['sub','Home runs, worked in full:',''],
 ['sub','   Pool average','18.9 HR'],
 ['sub','   1 standard deviation (typical spread)','9.8 HR'],
 ['sub','   Judge','62 HR'],
 ['sub','   Score','(62 - 18.9) / 9.8 = +4.38   ->   about 4.4 "normal gaps" above average'],
 ['sub','All four counting categories:',''],
 ['sub','   Runs','Judge 133  |  pool avg ~78  |  score +2.90'],
 ['sub','   HR','Judge 62  |  pool avg ~19  |  score +4.38'],
 ['sub','   RBI','Judge 131  |  pool avg ~74  |  score +2.75'],
 ['sub','   SB','Judge 16  |  pool avg ~13  |  score +0.97'],
 ['','',''],
 ['H','STEP 4  -  score the rate categories (SLG, OBP)',''],
 ['','','A .425 on-base in 25 at-bats is not as valuable as .425 over a full year, so rates are weighted by playing time. The question becomes: over all his plate appearances, how many EXTRA times did he reach base compared with an average hitter?'],
 ['sub','On-base %, worked in full:',''],
 ['sub','   Playing-time-weighted league OBP','.334'],
 ['sub','   Judge OBP, over 696 plate appearances','.425'],
 ['sub','   Extra times on base','696 x (.425 - .334) = about 63'],
 ['sub','   1 standard deviation of that "extra times on base" number across the pool','about 16.6'],
 ['sub','   Score','63 / 16.6 = +3.79'],
 ['sub','Slugging','Same method  ->  +5.07 (a .686 slugging over a full season)'],
 ['','',''],
 ['H','STEP 5  -  add it up',''],
 ['sub','   Runs','+2.90'],
 ['sub','   HR','+4.38'],
 ['sub','   RBI','+2.75'],
 ['sub','   SB','+0.97'],
 ['sub','   SLG','+5.07'],
 ['sub','   OBP','+3.79'],
 ['sub','   VALUE','+19.9'],
 ['','',''],
 ['H','WHAT THE NUMBER MEANS',''],
 ['sub','   about 0','replacement-level everyday player - a waiver-wire stream'],
 ['sub','   +8 to +12','a strong first-round season'],
 ['sub','   +19.9','best in league history: elite (not just good) in five of six categories in the same year; only SB is ordinary'],
 ['','',''],
 ['H','HOW "1 STANDARD DEVIATION" IS CALCULATED  (the 2022 HR pool)',''],
 ['sub','Step 1 - average','2,885 total HR / 153 hitters = 18.86'],
 ['sub','Step 2 - distance from average, per hitter','their HR minus 18.86  (a 30-HR hitter is +11.1; Judge is +43.1)'],
 ['sub','Step 3 - square each distance and add them up','sum = 14,719   (squaring makes them all positive and weights big misses more)'],
 ['sub','Step 4 - divide by (hitters - 1), then square-root','14,719 / 152 = 96.8 (variance);   sqrt(96.8) = 9.84 (standard deviation)'],
 ['sub','Why square then square-root','raw distances would cancel to zero; the square-root at the end puts the answer back in home runs'],
 ['','',''],
 ['sub','Tiny version you can check by hand','5 hitters: 8, 14, 19, 24, 30 HR'],
 ['sub','   mean','95 / 5 = 19'],
 ['sub','   squared distances','121 + 25 + 0 + 25 + 121 = 292'],
 ['sub','   variance, then standard deviation','292 / 4 = 73;   sqrt(73) = 8.5'],
 ['','',''],
 ['H','THE 20 AT-BAT MINIMUM',''],
 ['','','A judgment call, not a statistical rule. It only keeps cup-of-coffee seasons out of the list and the pool pre-rank. It is deliberately low because the rate-stat weighting and the counting-stat penalties already handle small samples on their own. Raising it (say to 50 AB) would drop marginal names but move no real player\'s value.'],
);

# ------------------------------------------------------------------ xlsx XML ---
sub xesc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
sub cell {
  my ($col, $rownum, $text, $style) = @_;
  my $s = defined $style ? " s=\"$style\"" : '';
  return qq{<c r="$col$rownum"$s t="inlineStr"><is><t xml:space="preserve">} . xesc($text) . qq{</t></is></c>};
}
# styles: 1 = green header (bold white, fill), 2 = body wrap/top, 3 = bold wrap/top (no fill)

# ---- sheet 1 ----
my $ncols  = scalar @HDR;
my $lastc1 = chr(ord('A') + $ncols - 1);
my $nrow1  = scalar(@ROWS) + 1;
my $sheet1 = <<'XML_HEAD';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetViews><sheetView workbookViewId="0" tabSelected="1"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="15"/>
<cols>
<col min="1" max="1" width="14" customWidth="1"/>
<col min="2" max="2" width="26" customWidth="1"/>
<col min="3" max="3" width="18" customWidth="1"/>
<col min="4" max="4" width="46" customWidth="1"/>
<col min="5" max="5" width="72" customWidth="1"/>
<col min="6" max="6" width="60" customWidth="1"/>
</cols>
<sheetData>
XML_HEAD
$sheet1 .= qq{<row r="1" ht="30">};
$sheet1 .= cell(chr(ord('A')+$_), 1, $HDR[$_], 1) for 0 .. $#HDR;
$sheet1 .= qq{</row>\n};
my $r = 2;
for my $row (@ROWS) {
  $sheet1 .= qq{<row r="$r">};
  $sheet1 .= cell(chr(ord('A')+$_), $r, $row->[$_], 2) for 0 .. $#$row;
  $sheet1 .= qq{</row>\n};
  $r++;
}
$sheet1 .= qq{</sheetData>\n<autoFilter ref="A1:$lastc1$nrow1"/>\n</worksheet>\n};

# ---- sheet 2 ----
my $sheet2 = <<'XML_HEAD';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetViews><sheetView workbookViewId="0"/></sheetViews>
<sheetFormatPr defaultRowHeight="15"/>
<cols>
<col min="1" max="1" width="42" customWidth="1"/>
<col min="2" max="2" width="95" customWidth="1"/>
</cols>
<sheetData>
XML_HEAD
$sheet2 .= qq{<row r="1" ht="24"><c r="A1" s="1" t="inlineStr"><is><t>Aaron Judge - 2022 - how the +19.9 season value is built</t></is></c><c r="B1" s="1" t="inlineStr"><is><t xml:space="preserve"> </t></is></c></row>\n};
my $r2 = 2;
for my $row (@J) {
  my ($kind, $a, $b) = @$row;
  my $sa = $kind eq 'H' ? 1 : $kind eq 'sub' ? 3 : 2;
  my $sb = 2;
  $sheet2 .= qq{<row r="$r2">} . cell('A', $r2, $a, $sa) . cell('B', $r2, $b, $sb) . qq{</row>\n};
  $r2++;
}
$sheet2 .= qq{</sheetData>\n<mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells>\n</worksheet>\n};

my $styles = <<'XML';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="3">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><name val="Calibri"/></font>
</fonts>
<fills count="3">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF2E5E4E"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="4">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
XML

my $content_types = <<'XML';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
XML

my $root_rels = <<'XML';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
XML

my $workbook = <<'XML';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>
<sheet name="Methodology" sheetId="1" r:id="rId1"/>
<sheet name="Judge 2022 example" sheetId="2" r:id="rId2"/>
</sheets>
</workbook>
XML

my $wb_rels = <<'XML';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
XML

remove_tree($STAGE) if -d $STAGE;
make_path("$STAGE/_rels", "$STAGE/xl/_rels", "$STAGE/xl/worksheets");
my %parts = (
  "$STAGE/[Content_Types].xml"        => $content_types,
  "$STAGE/_rels/.rels"                => $root_rels,
  "$STAGE/xl/workbook.xml"            => $workbook,
  "$STAGE/xl/_rels/workbook.xml.rels" => $wb_rels,
  "$STAGE/xl/styles.xml"              => $styles,
  "$STAGE/xl/worksheets/sheet1.xml"   => $sheet1,
  "$STAGE/xl/worksheets/sheet2.xml"   => $sheet2,
);
for my $p (sort keys %parts) {
  open my $fh, '>:raw', $p or die "write $p: $!";
  print $fh $parts{$p};
  close $fh;
}
print "staged xlsx parts (2 sheets) in $STAGE\n";
print "now: powershell -File scripts/make_methodology_xlsx.ps1\n";
