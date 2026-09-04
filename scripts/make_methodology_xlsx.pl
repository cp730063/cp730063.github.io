#!/usr/bin/perl
# Generates FantasyMags-Methodology.xlsx (a hand-rolled minimal xlsx: a zip of
# XML parts). No CPAN modules -- the zip step is done by PowerShell .NET.
#   perl scripts/make_methodology_xlsx.pl
use strict; use warnings;
use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";
my $STAGE = "$ROOT/.xlsx_stage";
my $OUT   = "$ROOT/FantasyMags-Methodology.xlsx";

# ---- content: [ Area, Feature, Where, What we calculate, Assumptions, Example ] ----
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
 'Rate metrics have a games floor: football 20 all-time / 24 combined / 4 playoff; baseball target 60 reg-season / 60 combined / none for playoffs. "Trades" ignores scope and is hidden when a league has no trade data. Manual seasons are excluded here.',
 'A 2-season (26-game) manager is left out of all-time Win % until clearing the floor.'],
['Head-to-Head','Pairwise record & rivalry detail','Head-to-Head',
 'Series lead, meeting count, points each in those meetings, meeting list, and a career side-by-side.',
 'Career record spans all seasons incl. manual; points/PPG are box-score era only. Category leagues label it "Category wins / losses" and use whole numbers.',
 '"Michael Scelsa leads 33-27-8 over Linda Kerrigan, 68 meetings" = every reg-season + playoff matchup between them.'],
['Head-to-Head','Biggest Rivalries / Most Lopsided','Head-to-Head',
 'Ranked lists of the most-played and most one-sided pairings.',
 'A pairing needs a minimum number of meetings to list: currently 12, target 15 for the 24-year baseball league.',
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
['Drafts','Draft Grades (football)','Drafts',
 'A letter grade per manager per draft from each pick\'s "value surplus" vs what that slot usually returns.',
 'We grade the PICK not the management: outcome = drafted player\'s full-season points that year / that season\'s baseline (mean of the top half of drafted players). Dynasty rookie picks also get a draft-time grade from current trade value vs slot, only for classes with 0-1 completed seasons. Expected value by round = mean outcome at that round across all gradeable drafts, lightly smoothed. Pick weight = 1/sqrt(round). Letter is a curve: z-score of the manager\'s score vs all graded manager-drafts (A+ at ~1.3 SD). Keeper and auction drafts are skipped; future seasons show "TBD".',
 '2019: Ryan Lenahan took Christian McCaffrey at 1.02; CMC returned 1.2x baseline that year -> large positive surplus -> contributes to an A+ class.'],
['Trade Values','Trade Calculator (football)','Trade Calculator',
 'Sum the market value of each side\'s players and picks; show who the trade favors and by how much.',
 'Player values are a build-time FantasyCalc snapshot matched to the league format (SF/1-QB, PPR, teams). Pick values use FantasyCalc generic tiers. Verdict: <3% Even, <8% Slight edge, <20% Favors, else Lopsided. Favored side = whoever RECEIVES more value. Roster-crunch (on by default): if the sides trade an unequal number of PLAYERS (picks do not count), the side getting more players has its cheapest bench values added, since it must cut to fit them.',
 'A sends one player (1930); B sends two (2552 total) -> "A wins by 622 (24%)". With crunch on, B also absorbs a body, shrinking the edge.'],
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
 'FULL SEASON, regardless of owner or timing. Scored against THAT season\'s categories (OPS only from the year it was added, etc.). Source = ESPN end-of-season roster snapshot stat lines (complete back to 2008; no outside data). Counting cats (R,HR,RBI,SB,W,K,SV,HLD,IP): z-score of the raw total vs the pool. Rate cats (AVG,OBP,SLG,OPS,ERA,WHIP,K/9): playing-time weighted -- contribution = (player rate - pool PT-weighted rate) x playing time (AB / PA / IP), then z-scored; ERA & WHIP flipped so lower is better. Pool = top (teams x starting slots x 1.6) at hitting and at pitching. ~0 = replacement-level regular; elite ~+10 to +19; no explicit replacement subtraction in v1. Two-way players valued on both sides. Needs ~20 AB or ~10 IP to be valued. In-progress seasons use the current year\'s to-date line.',
 'Jake Arrieta 2015 (22 W, 1.77 ERA, 236 K) = +10.5, the league\'s top value that year. Aaron Judge 2022 (62 HR, .425 OBP) = +19.9, the all-time single-season high.'],
['Baseball','"Drafted by" vs "Team"','Players',
 'Each player-season is credited to the drafting manager; the card also shows who held him at season\'s end.',
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

# ------------------------------------------------------------------ xlsx XML ---
sub xesc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }

my $ncols = scalar @HDR;
my $lastcol = chr(ord('A') + $ncols - 1);            # 'F'
my $nrows = scalar(@ROWS) + 1;

sub cell {
  my ($col, $rownum, $text, $style) = @_;
  my $ref = $col . $rownum;
  my $s = defined $style ? " s=\"$style\"" : '';
  return qq{<c r="$ref"$s t="inlineStr"><is><t xml:space="preserve">} . xesc($text) . qq{</t></is></c>};
}

my $sheet = <<'XML_HEAD';
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

# header row (style 1 = bold + fill + wrap + top)
$sheet .= qq{<row r="1" ht="30">};
for my $i (0 .. $#HDR) {
  $sheet .= cell(chr(ord('A')+$i), 1, $HDR[$i], 1);
}
$sheet .= qq{</row>\n};

# body rows (style 2 = wrap + top)
my $r = 2;
for my $row (@ROWS) {
  $sheet .= qq{<row r="$r">};
  for my $i (0 .. $#$row) {
    $sheet .= cell(chr(ord('A')+$i), $r, $row->[$i], 2);
  }
  $sheet .= qq{</row>\n};
  $r++;
}
$sheet .= qq{</sheetData>\n<autoFilter ref="A1:${lastcol}${nrows}"/>\n</worksheet>\n};

my $styles = <<'XML';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2">
<font><sz val="11"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>
</fonts>
<fills count="3">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF2E5E4E"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="3">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
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
<sheets><sheet name="Methodology" sheetId="1" r:id="rId1"/></sheets>
</workbook>
XML

my $wb_rels = <<'XML';
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
XML

# ---- write the staged parts ----
use File::Path qw(make_path remove_tree);
remove_tree($STAGE) if -d $STAGE;
make_path("$STAGE/_rels", "$STAGE/xl/_rels", "$STAGE/xl/worksheets");
my %parts = (
  "$STAGE/[Content_Types].xml"           => $content_types,
  "$STAGE/_rels/.rels"                   => $root_rels,
  "$STAGE/xl/workbook.xml"               => $workbook,
  "$STAGE/xl/_rels/workbook.xml.rels"    => $wb_rels,
  "$STAGE/xl/styles.xml"                 => $styles,
  "$STAGE/xl/worksheets/sheet1.xml"      => $sheet,
);
for my $p (sort keys %parts) {
  open my $fh, '>:raw', $p or die "write $p: $!";
  print $fh $parts{$p};
  close $fh;
}
print "staged xlsx parts in $STAGE\n";
print "now run the PowerShell zip step (see scripts/make_methodology_xlsx.ps1)\n";
