#!/usr/bin/perl
# Normalizes one league (ESPN API + optional Sleeper + optional manual overlay) into
# bundles/<slug>.json.   Usage: build_bundle2.pl <league-slug>
use strict; use warnings;
use JSON::PP;
my $j = JSON::PP->new->canonical(1);

use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";
my $SLE  = "$ROOT/data/raw/sleeper";

sub slurp { my ($p)=@_; open my $fh,'<:raw',$p or die "open $p: $!"; local $/; my $c=<$fh>; close $fh; $c }
sub jload { my ($p)=@_; my $x = eval { $j->decode(slurp($p)) }; $x }
sub r2 { my ($n)=@_; defined $n ? 0+sprintf("%.2f",$n) : 0 }

my $SLUG = $ARGV[0] or die "usage: build_bundle2.pl <league-slug>\n";
my $CFG  = jload("$ROOT/scripts/leagues/$SLUG.json") or die "no config: scripts/leagues/$SLUG.json\n";
my $SPORT = $CFG->{sport} || 'nfl';                 # 'nfl' (points) | 'mlb' (category / roto)
my $ESPN   = "$ROOT/data/raw/espn/$CFG->{espnId}/history";
my @ESPN_Y = ($CFG->{espnYears}[0] .. $CFG->{espnYears}[1]);
my $PW_FILE = $CFG->{playerWeeksFile};              # ESPN player-week pull, or undef
my $SLE_PW  = $CFG->{sleeperPlayerWeeksLeague};     # Sleeper league id for player weeks, or undef
my $OVERLAY = $CFG->{overlay};                      # manual pre-API overlay file, or undef
my $REGCHAMP_FIX = $CFG->{regSeasonChampByYear} || {};  # {year => personId} — override where
                                                        # the league's real tiebreaker (per the
                                                        # commissioner's records) differs from
                                                        # what W-L-T / points-for alone imply

# ---------------------------------------------------------------------------
# 1. Canonical people, from the league config.
# ---------------------------------------------------------------------------
my @PEOPLE = @{ $CFG->{people} || [] };
my %ESPN_TO_ID;            # ESPN member GUID (upper) -> canonical id
my %SLEEPER_NAME_TO_ID;    # lowercase Sleeper display_name -> canonical id
my %OVERLAY_NAME_TO_ID;    # exact person name -> canonical id (for the manual overlay)
for my $p (@PEOPLE) {
  $ESPN_TO_ID{uc $p->{espn}} = $p->{id} if $p->{espn};
  $ESPN_TO_ID{uc $_} = $p->{id} for @{ $p->{espnAlt} || [] };
  $SLEEPER_NAME_TO_ID{ lc $p->{sleeperName} } = $p->{id} if $p->{sleeperName};
  $OVERLAY_NAME_TO_ID{ $p->{name} } = $p->{id};
  $OVERLAY_NAME_TO_ID{ $_ } = $p->{id} for @{ $p->{alias} || [] };
}
my %P; for my $p (@PEOPLE) { $P{$p->{id}} = { %$p }; $P{$p->{id}}{firstSeason}=9999; $P{$p->{id}}{seasons}={}; $P{$p->{id}}{titles}=[]; }

# Era-aware manager name: a person config may carry a `names` list of
# { "until": <year>, "name": <str> } rules (e.g. a co-manager who joined a
# franchise partway through). Returns the name in effect for a given season,
# or undef when it matches the canonical `name` (so the bundle stays small).
sub mgr_name_for {
  my ($pid, $y) = @_;
  my $p = $P{$pid} or return undef;
  my $nm = $p->{name};
  for my $r (@{ $p->{names} || [] }) {
    if (!defined $r->{until} || $y <= $r->{until}) { $nm = $r->{name}; last; }
  }
  return (defined $nm && $nm ne ($p->{name} // '')) ? $nm : undef;
}

# captured during the season loops, used later for player-level data
my %ESPN_T2P;          # year -> { espn teamId -> canonical person id }
my %SLE_R2P;           # year -> { sleeper roster_id -> canonical person id }
my %ESPN_DRAFT;        # year -> { espn playerId -> [round, overallPick, teamId, kept] }
my %ESPN_ROOKIE_FIRST; # year -> first ESPN round that is the appended rookie draft (or maxRound+1 if none)
my %ESPN_DRAFT_INFO;   # year -> { type, pickOrder[], picks[ {playerId,round,roundPick,overall,teamId,kept,bid} ] }
my %SLE_DRAFT_INFO;    # year -> { rounds, teams, type, order{}, uid2pid{}, picks[], traded[] }
my %SLE_FUTURE_PICKS;  # sleeper year -> [ league-level traded_picks with season > that year ]
my %SLE_FUTURE_R2P;    # sleeper year -> { roster_id -> pid } for resolving future picks

# non-NFL sports have no playerWeeks file; resolve player names from ESPN roster
# snapshots in the raw season files instead (id -> [name, pos]).
my %ESPN_PLAYER_NAME;
my %MLB_POS = (1=>'SP', 2=>'C', 3=>'1B', 4=>'2B', 5=>'3B', 6=>'SS',
               7=>'OF', 8=>'OF', 9=>'OF', 10=>'DH', 11=>'RP');

# baseball H2H box scores: per-matchup category grid, keyed like the football
# lineups file. cats[] carries both sides' totals + who won each category.
my %MLB_BOX;   # "year|week|personId" -> { vs, cats:[{k,lo,me,op,r}], w, l, t }
# ESPN MLB statId -> [ short label, lowerIsBetter ].  Only the ids that show up
# in a season's scoringSettings.scoringItems ever get read; anything unmapped
# renders as "S<id>".
my %MLB_STAT = (
  20=>['R',0], 5=>['HR',0], 21=>['RBI',0], 23=>['SB',0], 24=>['CS',1],
  2=>['AVG',0], 17=>['OBP',0], 9=>['SLG',0], 18=>['OPS',0], 10=>['BB',0],
  1=>['H',0], 3=>['2B',0], 4=>['3B',0], 0=>['AB',0], 27=>['SO',1], 25=>['GIDP',1],
  53=>['W',0], 54=>['L',1], 57=>['SV',0], 58=>['BS',1], 83=>['SVHD',0],
  48=>['K',0], 47=>['ERA',1], 41=>['WHIP',1], 49=>['K/9',0], 42=>['K/BB',0],
  44=>['BB',1], 45=>['H',1], 46=>['ER',1], 34=>['IP',0], 32=>['GS',0],
  37=>['QS',0], 39=>['CG',0], 13=>['SHO',0],
);
sub r3 { my ($n)=@_; defined $n ? 0+sprintf("%.3f",$n) : undef }
# regular-season standings rank by WIN % (ties = half a win), not raw win count —
# a 12-5-4 team finishes ahead of a 13-7-1 team.
sub wpct { my ($w,$l,$t)=@_; my $g=($w||0)+($l||0)+($t||0); $g ? (($w||0)+0.5*($t||0))/$g : 0 }

# which MLB_STAT ids are rate stats (need averaging, not summing) vs counting
my %RATE_ID = map { $_=>1 } (2, 17, 9, 18, 47, 41, 49, 42);   # AVG OBP SLG OPS ERA WHIP K/9 K/BB

# baseball player valuation: per season we need the category set, the team count,
# the starting-slot split, and every rostered player's full season stat line.
my (%MLB_CATS, %MLB_TEAMCT, %MLB_SLOTS, %MLB_PSTATS);
# statId -> [ label, group(h/p), kind(c=counting / r=rate), lowerBetter, weightStat ]
#   weightStat: which raw stat to weight a rate by (0=AB, 16=PA, 34=outs)
my %MLB_CATDEF = (
  20=>['R',  'h','c',0,0 ], 5 =>['HR', 'h','c',0,0 ], 21=>['RBI','h','c',0,0 ],
  23=>['SB', 'h','c',0,0 ], 2 =>['AVG','h','r',0,0 ], 17=>['OBP','h','r',0,16],
  9 =>['SLG','h','r',0,0 ], 18=>['OPS','h','r',0,16],
  53=>['W',  'p','c',0,0 ], 57=>['SV', 'p','c',0,0 ], 83=>['SVHD','p','c',0,0 ],
  48=>['K',  'p','c',0,0 ], 34=>['IP', 'p','c',0,0 ],
  47=>['ERA','p','r',1,34], 41=>['WHIP','p','r',1,34], 49=>['K/9','p','r',0,34],
);

# ---------------------------------------------------------------------------
# 2. ESPN seasons 2015-2024
# ---------------------------------------------------------------------------
my @seasons;
my $DIV_ORDER;   # ESPN division order (names) from the newest season with divisions
for my $y (@ESPN_Y) {
  my $raw = jload("$ESPN/$y.json") or next;
  my $d = ref $raw eq 'ARRAY' ? $raw->[0] : $raw;

  if ($SPORT ne 'nfl') {
    for my $t (@{ $d->{teams} || [] }) {
      for my $en (@{ ($t->{roster} || {})->{entries} || [] }) {
        my $pl = ($en->{playerPoolEntry} || {})->{player} or next;
        next unless defined $pl->{id} && defined $pl->{fullName};
        $ESPN_PLAYER_NAME{ $pl->{id} } ||=
          [ $pl->{fullName}, ($MLB_POS{ $pl->{defaultPositionId} // -1 } // '') ];
      }
    }
  }
  my $st = $d->{settings} || {};
  my $ss = $st->{scheduleSettings} || {};
  my $regWeeks = $ss->{matchupPeriodCount} || 14;
  my $poTeams  = $ss->{playoffTeamCount}  || 4;
  my @divList  = @{ $ss->{divisions} || [] };
  my %divName  = map { $_->{id} => $_->{name} } @divList;
  my $hasDivs  = (scalar(keys %divName) > 1) ? 1 : 0;
  # remember ESPN's own division order (East, Central, West, …) from the newest
  # season that has one
  $DIV_ORDER = [ map { $_->{name} } sort { ($a->{id}//0) <=> ($b->{id}//0) } @divList ] if $hasDivs;

  # team_id -> canonical person id (via owners GUID)  &  team_id -> division name.
  # A team with 2+ owners is co-managed: every co-owner shares that season's
  # honors (division title, runner-up, championship, ...).  %tid2co keeps the
  # extra resolved personIds beyond the primary.
  my %tid2pid; my %tid2div; my %tid2co;
  for my $t (@{$d->{teams}||[]}) {
    $tid2div{$t->{id}} = $hasDivs ? ($divName{ $t->{divisionId} } // undef) : undef;
    my @pids;
    for my $g (@{ $t->{owners} || [] }) {
      my $p = $ESPN_TO_ID{ uc $g };
      push @pids, $p if $p && !grep { $_ eq $p } @pids;
    }
    my $pid = $pids[0];
    if (!$pid) { $pid = 'espn_'.($t->{id}); $P{$pid} ||= { id=>$pid, name=>"ESPN team $t->{id}", mgr=>'(unmatched)', firstSeason=>9999, seasons=>{}, titles=>[] }; }
    $tid2pid{$t->{id}} = $pid;
    $tid2co{$t->{id}}  = [ @pids[1..$#pids] ] if @pids > 1;
  }
  $ESPN_T2P{$y} = { %tid2pid };
  my $dset = $st->{draftSettings} || {};
  $ESPN_DRAFT_INFO{$y} = { type => ($dset->{type} // ''), pickOrder => ($dset->{pickOrder} || []),
                           budget => ($dset->{auctionBudget} || 0), picks => [] };
  my %rndKeep;   # roundId -> [total picks, keeper picks]
  for my $pk (@{ ($d->{draftDetail}||{})->{picks} || [] }) {
    next unless defined $pk->{playerId};
    my $kept = ($pk->{keeper} || $pk->{reservedForKeeper}) ? 1 : 0;
    $ESPN_DRAFT{$y}{ $pk->{playerId} } = [ $pk->{roundId}, $pk->{overallPickNumber}, $pk->{teamId}, $kept, $pk->{roundPickNumber} ];
    push @{ $ESPN_DRAFT_INFO{$y}{picks} }, {
      playerId=>$pk->{playerId}, round=>$pk->{roundId}, roundPick=>$pk->{roundPickNumber},
      overall=>$pk->{overallPickNumber}, teamId=>$pk->{teamId}, kept=>$kept,
      bid=>($pk->{bidAmount} ? $pk->{bidAmount}+0 : 0),
    };
    my $r = $pk->{roundId} // next;
    $rndKeep{$r}[0]++; $rndKeep{$r}[1] += $kept;
  }
  # The rookie draft was appended as extra rounds at the end. Detect it as the
  # contiguous block of final rounds in which nobody kept a player.
  my @allR = sort { $a <=> $b } keys %rndKeep;
  my $maxR = $allR[-1] // 0;
  my $first = $maxR + 1;
  for (my $r = $maxR; $r >= 1; $r--) {
    last unless $rndKeep{$r};
    last if ($rndKeep{$r}[1] // 0) > 0;   # a kept player in this round -> not a rookie round
    $first = $r;
  }
  $first = $maxR + 1 if $first <= 1;       # startup year: every round is "real", no rookie tail
  $ESPN_ROOKIE_FIRST{$y} = $first;

  # games from schedule
  my (@games, %rs);   # %rs: pid -> reg-season tallies
  # mlb: the scoring categories for THIS season, in the league's chosen order
  my @catIds = $SPORT eq 'mlb'
    ? map { $_->{statId} } @{ ($st->{scoringSettings} || {})->{scoringItems} || [] } : ();
  my %catAcc;   # pid -> statId -> {sum,n} — regular-season team category totals

  # mlb: stash the season's category set + every rostered player's season stat line
  # (for the player-valuation pass after the loop)
  if ($SPORT eq 'mlb' && @catIds) {
    $MLB_CATS{$y}   = [ @catIds ];
    $MLB_TEAMCT{$y} = scalar @{ $d->{teams} || [] };
    my $lsc = ($st->{rosterSettings} || {})->{lineupSlotCounts} || {};
    my ($hs, $ps) = (0, 0);
    for my $sid (keys %$lsc) {
      next if $sid >= 16;                       # 16 bench, 17 IL, 19 NA
      ($sid >= 13 ? $ps : $hs) += $lsc->{$sid}; # 13 P / 14 SP / 15 RP are pitching
    }
    $MLB_SLOTS{$y} = { hit => ($hs || 9), pit => ($ps || 8) };
    for my $t (@{ $d->{teams} || [] }) {
      my $own = $tid2pid{ $t->{id} };
      for my $en (@{ ($t->{roster} || {})->{entries} || [] }) {
        my $pl = ($en->{playerPoolEntry} || {})->{player} or next;
        next unless defined $pl->{id};
        # an in-progress season's file carries BOTH last year's final line and this
        # year's to-date line, both as src0/split0 — pick the one for THIS season.
        my @c0  = grep { ($_->{statSourceId}//1)==0 && ($_->{statSplitTypeId}//1)==0 }
                  @{ $pl->{stats} || [] };
        my ($blk) = grep { ($_->{seasonId} // $y) == $y } @c0;
        $blk ||= $c0[0];
        next unless $blk && ref $blk->{stats} eq 'HASH' && %{ $blk->{stats} };
        $MLB_PSTATS{$y}{ $pl->{id} } ||= {
          name => $pl->{fullName}, pos => ($MLB_POS{ $pl->{defaultPositionId} // -1 } // ''),
          own  => $own, s => $blk->{stats},
        };
      }
    }
  }

  for my $g (@{$d->{schedule}||[]}) {
    my $wk = $g->{matchupPeriodId};
    my $tier = $g->{playoffTierType} || 'NONE';
    my $h = $g->{home} || {}; my $a = $g->{away} || {};
    next unless defined $h->{teamId} && defined $a->{teamId};

    # mlb: capture the category-by-category box for this matchup (both sides)
    if ($SPORT eq 'mlb' && @catIds) {
      my $hsb = ($h->{cumulativeScore} || {})->{scoreByStat} || {};
      my $asb = ($a->{cumulativeScore} || {})->{scoreByStat} || {};
      # regular-season team category totals: sum counting stats across every
      # regular-season week; rate stats are averaged across those same weeks
      # (ESPN's own season totals include playoff weeks and are recomputed
      # from full underlying box scores we don't have — a plain average of
      # weekly rates is the honest approximation; flagged as such in the UI).
      if ($tier eq 'NONE') {
        my $bhp0 = $tid2pid{$h->{teamId}}; my $bap0 = $tid2pid{$a->{teamId}};
        for my $pr ([$bhp0,$hsb], [$bap0,$asb]) {
          my ($pid,$sb) = @$pr; next unless $pid;
          for my $sid (@catIds) {
            my $v = $sb->{$sid}{score}; next unless defined $v;
            my $a2 = ($catAcc{$pid}{$sid} ||= {sum=>0,n=>0});
            $a2->{sum} += $v; $a2->{n}++;
          }
        }
      }
      my $bhp = $tid2pid{$h->{teamId}}; my $bap = $tid2pid{$a->{teamId}};
      if (%$hsb && $bhp && $bap) {
        my (@hc, @ac); my ($hw,$hl,$ht) = (0,0,0);
        for my $sid (@catIds) {
          my ($lbl,$lo) = @{ $MLB_STAT{$sid} || ["S$sid",0] };
          my $hv = $hsb->{$sid}{score}; my $av = $asb->{$sid}{score};
          next unless defined $hv && defined $av;
          my $hr = $hsb->{$sid}{result} // '';
          my $res;   # from HOME perspective: 1 win / 0 loss / -1 tie
          if    ($hr eq 'WIN')  { $res = 1 }
          elsif ($hr eq 'LOSS') { $res = 0 }
          elsif ($hr eq 'TIE')  { $res = -1 }
          else { my $c = $hv <=> $av; $c = -$c if $lo; $res = $c > 0 ? 1 : $c < 0 ? 0 : -1 }
          push @hc, { k=>$lbl, lo=>$lo, me=>r3($hv), op=>r3($av), r=>$res };
          push @ac, { k=>$lbl, lo=>$lo, me=>r3($av), op=>r3($hv), r=>($res < 0 ? -1 : 1-$res) };
          if    ($res == 1) { $hw++ }
          elsif ($res == 0) { $hl++ }
          else              { $ht++ }
        }
        if (@hc) {
          $MLB_BOX{"$y|$wk|$bhp"} = { vs=>$bap, cats=>\@hc, w=>$hw, l=>$hl, t=>$ht };
          $MLB_BOX{"$y|$wk|$bap"} = { vs=>$bhp, cats=>\@ac, w=>$hl, l=>$hw, t=>$ht };
        }
      }
    }
    # nfl: totalPoints is the score. mlb (H2H categories): the weekly "score" is
    # categories won, in cumulativeScore.wins (ESPN stopped mirroring it to
    # totalPoints in 2019).
    my ($hp, $ap);
    if ($SPORT eq 'mlb') {
      $hp = r2( ($h->{cumulativeScore}||{})->{wins} // $h->{totalPoints} );
      $ap = r2( ($a->{cumulativeScore}||{})->{wins} // $a->{totalPoints} );
    } else {
      $hp = r2($h->{totalPoints}); $ap = r2($a->{totalPoints});
    }
    my $type = $tier eq 'NONE' ? 'reg'
             : $tier eq 'WINNERS_BRACKET' ? 'playoff'
             : 'consolation';
    my $hpid = $tid2pid{$h->{teamId}}; my $apid = $tid2pid{$a->{teamId}};
    next unless $hpid && $apid;
    push @games, { week=>$wk, type=>$type, a=>$hpid, ap=>$hp, b=>$apid, bp=>$ap };
  }

  # scoring model: nfl = points; mlb = category wins per matchup, or roto (no matchups)
  my $isRoto = uc( ($st->{scoringSettings} || {})->{scoringType} // '' ) eq 'ROTO';

  # a season ESPN has scheduled but not yet played: fixtures exist, every score is 0.
  my $espnPlayed = grep { $_->{type} eq 'reg' && (($_->{ap}||0) > 0 || ($_->{bp}||0) > 0) } @games;
  # a roto season has no weekly games but does have real final standings.
  my $standingsOnly = !$espnPlayed
    && grep { ($_->{rankCalculatedFinal} || $_->{rankFinal}) } @{ $d->{teams} || [] };
  my $counts = $espnPlayed || $standingsOnly;   # season is real (played or roto), vs. not-yet-played

  # entries: per person, reg-season record computed from games + final placement from teams[]
  my %entry;
  for my $t (@{$d->{teams}||[]}) {
    my $pid = $tid2pid{$t->{id}};
    my $nm = (($t->{location}//'').' '.($t->{nickname}//'')); $nm =~ s/^\s+|\s+$//g;
    $nm ||= $t->{name} // $t->{abbrev} // "Team $t->{id}";
    my $fr = $counts ? ($t->{rankCalculatedFinal} || $t->{rankFinal} || 0) : 0;
    my $por = $fr==1 ? 'champion' : $fr==2 ? 'runner_up' : $fr==3 ? 'third'
            : ($fr==4 && $poTeams>=4) ? 'r1_loss' : undef;
    $entry{$pid} = {
      personId=>$pid, team=>$nm, division=>$tid2div{$t->{id}},
      w=>0,l=>0,t=>0, pf=>0,pa=>0,
      seed=>($espnPlayed ? ($t->{playoffSeed}||undef) : undef), finalRank=>$fr||undef,
      poResult=>$por,
      madePlayoffs=>($fr && $poTeams && $fr<=$poTeams ? 1 : 0),
      ($tid2co{$t->{id}} && @{$tid2co{$t->{id}}} ? (coPids => $tid2co{$t->{id}}) : ()),
    };
  }
  if ($espnPlayed) {
    for my $g (@games) {
      next unless $g->{type} eq 'reg';
      for my $side ([$g->{a},$g->{ap},$g->{bp}], [$g->{b},$g->{bp},$g->{ap}]) {
        my ($pid,$pf,$pa) = @$side; my $e = $entry{$pid} or next;
        $e->{pf}+=$pf; $e->{pa}+=$pa;
        if ($pf>$pa){$e->{w}++} elsif($pf<$pa){$e->{l}++} else {$e->{t}++}
      }
    }
  }
  $_->{pf}=r2($_->{pf}), $_->{pa}=r2($_->{pa}) for values %entry;

  # regular-season standings order: win % (ties = half a win), then points-for,
  # then raw wins.
  my @byRec = sort {
    wpct($b->{w},$b->{l},$b->{t}) <=> wpct($a->{w},$a->{l},$a->{t})
      || ($b->{pf}||0) <=> ($a->{pf}||0)
      || $b->{w} <=> $a->{w}
  } values %entry;
  my $regChamp = $standingsOnly
    ? ( (map { $_->{personId} } grep { ($_->{finalRank}||0)==1 } values %entry)[0] )
    : ( ($espnPlayed && @byRec) ? $byRec[0]{personId} : undef );
  $regChamp = $REGCHAMP_FIX->{$y}
    if $REGCHAMP_FIX->{$y} && $entry{ $REGCHAMP_FIX->{$y} };
  if ($hasDivs && $espnPlayed) {
    my %dbest;
    for my $e (@byRec) { my $d = $e->{division} // next; $dbest{$d} ||= $e; }
    $_->{divisionChamp} = 0 for values %entry;
    for my $e (values %dbest) { $entry{$e->{personId}}{divisionChamp} = 1; }
  }

  my ($champ) = map { $_->{personId} } grep { ($_->{poResult}//'') eq 'champion' } values %entry;
  my ($ru)    = map { $_->{personId} } grep { ($_->{poResult}//'') eq 'runner_up' } values %entry;
  my ($th)    = map { $_->{personId} } grep { ($_->{poResult}//'') eq 'third' } values %entry;

  # mark the last winners-bracket week as the championship game
  { my @pg = grep { $_->{type} eq 'playoff' } @games;
    if (@pg) { my $mx = 0; for (@pg) { $mx = $_->{week} if $_->{week} > $mx } $_->{final} = 1 for grep { $_->{week}==$mx } @pg; } }

  # register people seasons/titles (real seasons only — played or roto, not not-yet-played)
  if ($counts) {
    for my $pid (keys %entry) {
      my $p = $P{$pid}; $p->{seasons}{$y}=1; $p->{firstSeason}=$y if $y<$p->{firstSeason};
      for my $cp (@{ $entry{$pid}{coPids} || [] }) {
        my $q = $P{$cp} or next; $q->{seasons}{$y}=1; $q->{firstSeason}=$y if $y<$q->{firstSeason};
      }
    }
    if ($champ) {
      push @{$P{$champ}{titles}}, $y;
      my ($ce) = grep { $_->{personId} eq $champ } values %entry;
      push @{$P{$_}{titles}}, $y for @{ ($ce && $ce->{coPids}) || [] };
    }
  }

  # mlb: attach each team's regular-season category totals (counting stats
  # summed, rate stats averaged across regular-season weeks — see catAcc note
  # above). A roto season has no weekly matchups at all (catAcc stays empty),
  # but ESPN's team.valuesByStat IS the real season-long total in that case
  # (no playoff-week contamination to worry about — roto has no separate
  # playoff period), so use it directly instead of leaving the season blank.
  if ($SPORT eq 'mlb' && @catIds) {
    if ($isRoto) {
      for my $t (@{ $d->{teams} || [] }) {
        my $pid = $tid2pid{$t->{id}} or next;
        my $vbs = $t->{valuesByStat} || {};
        my @ct;
        for my $sid (@catIds) {
          my $v = $vbs->{$sid}; next unless defined $v;
          my ($lbl,$lo) = @{ $MLB_STAT{$sid} || ["S$sid",0] };
          my $rate = $RATE_ID{$sid} ? 1 : 0;
          push @ct, { k=>$lbl, v=>($rate ? r3($v) : r2($v)), lo=>$lo, rate=>$rate };
        }
        $entry{$pid}{catTotals} = \@ct if @ct;
      }
    } else {
      for my $pid (keys %entry) {
        my $acc = $catAcc{$pid} or next;
        my @ct;
        for my $sid (@catIds) {
          my $a3 = $acc->{$sid} or next;
          my ($lbl,$lo) = @{ $MLB_STAT{$sid} || ["S$sid",0] };
          my $rate = $RATE_ID{$sid} ? 1 : 0;
          my $val = $rate ? ($a3->{n} ? $a3->{sum}/$a3->{n} : undef) : $a3->{sum};
          next unless defined $val;
          push @ct, { k=>$lbl, v=>($rate ? r3($val) : r2($val)), lo=>$lo, rate=>$rate };
        }
        $entry{$pid}{catTotals} = \@ct if @ct;
      }
    }
  }

  push @seasons, {
    year=>$y, platform=>'espn', teams=>scalar(keys %entry),
    regWeeks=>$regWeeks, playoffTeams=>$poTeams, hasDivisions=>($hasDivs?\1:\0),
    played=>($counts ? 1 : 0), hasOptimal=>0,
    scoring=>($SPORT eq 'nfl' ? 'points' : $isRoto ? 'roto' : 'cats'),
    entries=>[ map { $entry{$_} } sort { $entry{$a}{personId} cmp $entry{$b}{personId} } keys %entry ],
    games=>($espnPlayed ? \@games : []),
    champion=>$champ, runnerUp=>$ru, third=>$th, regSeasonChamp=>$regChamp,
  };
}

# ---------------------------------------------------------------------------
# 3. Sleeper seasons (2025 played, 2026 live) from earlier bundle raw dirs
# ---------------------------------------------------------------------------
my %SLE_LEAGUES = %{ $CFG->{sleeper} || {} };   # year => sleeper league id
my %playersOut; my @tradesOut;

for my $y (sort keys %SLE_LEAGUES) {
  my $lid = $SLE_LEAGUES{$y};
  my $dir = "$SLE/$lid";
  my $league = jload("$dir/league.json") or next;
  my $set = $league->{settings} || {};
  my $poStart = $set->{playoff_week_start} || 15;
  my $users = jload("$dir/users.json") || [];
  my $rosters = jload("$dir/rosters.json") || [];
  my %uById; $uById{$_->{user_id}} = $_ for @$users;

  # roster_id -> canonical pid
  my %rid2pid;
  for my $r (@$rosters) {
    my $u = $uById{$r->{owner_id}} || {};
    my $dn = lc($u->{display_name} // '');
    my $pid = $SLEEPER_NAME_TO_ID{$dn};
    if (!$pid) { $pid = 'sle_'.$r->{owner_id};
      $P{$pid} ||= { id=>$pid, name=>($u->{metadata}{team_name} // $u->{display_name} // "Roster $r->{roster_id}"),
                     mgr=>($u->{display_name}//''), firstSeason=>9999, seasons=>{}, titles=>[] }; }
    $rid2pid{$r->{roster_id}} = $pid;
    $P{$pid}{sleeper} = $r->{owner_id};
  }
  $SLE_R2P{$y} = { %rid2pid };
  my %uid2pid = map { ($_->{owner_id} // '') => $rid2pid{$_->{roster_id}} } @$rosters;

  # ---- draft (pick the completed draft with actual picks) ----
  {
    my $drafts = jload("$dir/drafts.json") || [];
    my ($best, $bestPicks);
    for my $dr (@$drafts) {
      my $pf = "$dir/draft_$dr->{draft_id}_picks.json";
      my $pk = -e $pf ? (jload($pf) || []) : [];
      next unless @$pk;
      if (!$bestPicks || @$pk > @$bestPicks) { $best = $dr; $bestPicks = $pk; }
    }
    if ($best) {
      my $tp = jload("$dir/draft_$best->{draft_id}_traded_picks.json") || [];
      $SLE_DRAFT_INFO{$y} = {
        rounds => ($best->{settings}{rounds} || 0),
        teams  => ($best->{settings}{teams}  || scalar(@$rosters)),
        type   => ($best->{type} // 'linear'),
        order  => ($best->{draft_order} || {}),   # user_id -> slot
        uid2pid=> { %uid2pid },
        picks  => $bestPicks,
        traded => $tp,                            # [{round, roster_id(orig), owner_id(now)}]
      };
    }
    # future draft capital (league-level, dynasty)
    my $ltp = jload("$dir/traded_picks.json") || [];
    $SLE_FUTURE_PICKS{$y} = [ grep { ($_->{season}//'') gt $y } @$ltp ];
    $SLE_FUTURE_R2P{$y} = { %rid2pid };
  }

  # entries
  my %entry;
  for my $r (@$rosters) {
    my $pid = $rid2pid{$r->{roster_id}};
    my $u = $uById{$r->{owner_id}} || {};
    my $rs = $r->{settings} || {};
    $entry{$pid} = {
      personId=>$pid,
      team=>($u->{metadata}{team_name} // $u->{display_name} // "Roster $r->{roster_id}"),
      w=>0,l=>0,t=>0,pf=>0,pa=>0,
      optimal=> r2( ($rs->{ppts}||0) + ($rs->{ppts_decimal}||0)/100 ),
      seed=>undef, finalRank=>undef, result=>undef,
    };
  }

  # games from weekly matchups
  my @games; my $played = 0;
  for my $w (1..18) {
    my $mw = jload("$dir/matchups/week_$w.json");
    next unless ref $mw eq 'ARRAY' && @$mw;
    my $any = grep { ($_->{points}||0) > 0 } @$mw;
    next unless $any; $played = 1;
    my %bym;
    for my $e (@$mw) { next unless defined $e->{matchup_id}; push @{$bym{$e->{matchup_id}}}, $e; }
    for my $mid (sort { $a <=> $b } keys %bym) {
      my $g = $bym{$mid}; next unless @$g == 2;
      my $pa = $rid2pid{$g->[0]{roster_id}}; my $pb = $rid2pid{$g->[1]{roster_id}};
      next unless $pa && $pb;
      push @games, { week=>$w, type=> ($w < $poStart ? 'reg' : 'playoff_week'),
                     a=>$pa, ap=>r2($g->[0]{points}), b=>$pb, bp=>r2($g->[1]{points}) };
    }
  }

  # playoff teams / champion from winners bracket
  my $wb = jload("$dir/winners_bracket.json") || [];
  my %poRid; for my $m (@$wb) { for (qw(t1 t2 w l)) { $poRid{$m->{$_}}=1 if defined $m->{$_} && $m->{$_}=~/^\d+$/ } }
  my ($cm) = grep { ($_->{p}//0)==1 } @$wb;
  my ($tm) = grep { ($_->{p}//0)==3 } @$wb;
  my $champ = $cm && $cm->{w} ? $rid2pid{$cm->{w}} : undef;
  my $ru    = $cm && $cm->{l} ? $rid2pid{$cm->{l}} : undef;
  my $th    = $tm && $tm->{w} ? $rid2pid{$tm->{w}} : undef;

  # playoff result per person, from the bracket
  my %poRes;
  $poRes{$champ}='champion' if $champ;
  $poRes{$ru}='runner_up'   if $ru;
  $poRes{$th}='third'       if $th;
  if ($tm && defined $tm->{l}) { my $p4 = $rid2pid{$tm->{l}}; $poRes{$p4} ||= 'fourth' if $p4; }
  for my $rid (sort { $a <=> $b } keys %poRid) {
    my $pid = $rid2pid{$rid} or next; next if $poRes{$pid};
    my ($lm) = grep { defined $_->{l} && "$_->{l}" eq "$rid" } @$wb;
    my $rnd = $lm ? ($lm->{r}||1) : 1;
    $poRes{$pid} = $rnd <= 1 ? 'r1_loss' : 'r'.$rnd.'_loss';
  }

  # reclassify sleeper playoff-week games: real playoff only if both in bracket
  for my $g (@games) {
    next unless $g->{type} eq 'playoff_week';
    my ($ina,$inb)=(0,0);
    for my $r (keys %poRid){ my $pp=$rid2pid{$r}||''; $ina=1 if $pp eq $g->{a}; $inb=1 if $pp eq $g->{b}; }
    $g->{type} = ($ina && $inb) ? 'playoff' : 'consolation';
  }
  # use the bracket to tag the championship game and drop the 3rd-place game
  # (only ever touches games already classified as 'playoff')
  for my $mm (grep { defined $_->{p} } @$wb) {
    my $pa = $rid2pid{$mm->{t1}//-1} // ''; my $pb = $rid2pid{$mm->{t2}//-1} // '';
    next unless $pa && $pb;
    for my $g (@games) {
      next unless $g->{type} eq 'playoff';
      next unless ($g->{a} eq $pa && $g->{b} eq $pb) || ($g->{a} eq $pb && $g->{b} eq $pa);
      if    ($mm->{p}==3) { $g->{type} = 'consolation'; }
      elsif ($mm->{p}==1) { $g->{final} = 1; }
    }
  }

  # reg-season tallies
  for my $g (@games) {
    next unless $g->{type} eq 'reg';
    for my $side ([$g->{a},$g->{ap},$g->{bp}],[$g->{b},$g->{bp},$g->{ap}]) {
      my ($pid,$pf,$pa)=@$side; my $e=$entry{$pid} or next;
      $e->{pf}+=$pf; $e->{pa}+=$pa;
      if($pf>$pa){$e->{w}++}elsif($pf<$pa){$e->{l}++}else{$e->{t}++}
    }
  }
  $_->{pf}=r2($_->{pf}), $_->{pa}=r2($_->{pa}) for values %entry;
  for my $pid (keys %entry) {
    $entry{$pid}{poResult} = $poRes{$pid};
    $entry{$pid}{madePlayoffs} = ($poRes{$pid} ? 1 : 0);
  }
  $entry{$champ}{finalRank}=1 if $champ;
  $entry{$ru}{finalRank}=2    if $ru;
  $entry{$th}{finalRank}=3    if $th;

  for my $pid (keys %entry) { my $p=$P{$pid}; $p->{seasons}{$y}=1 if $played; $p->{firstSeason}=$y if $played && $y<$p->{firstSeason}; }
  push @{$P{$champ}{titles}}, $y if $champ && $played;

  my ($sRegChamp) = map { $_->{personId} }
    sort { $b->{w} <=> $a->{w} || ($b->{pf}||0) <=> ($a->{pf}||0) } values %entry;

  push @seasons, {
    year=>$y+0, platform=>'sleeper', teams=>scalar(keys %entry),
    regWeeks=>$poStart-1, playoffTeams=>$set->{playoff_teams}||6, hasDivisions=>\0,
    played=>$played?1:0, hasOptimal=>1,
    entries=>[ map { $entry{$_} } sort keys %entry ],
    games=>\@games,
    champion=>$champ, runnerUp=>$ru, third=>$th, regSeasonChamp=>($played ? $sRegChamp : undef),
  };

  # ---- trades: every completed trade in the transaction log (incl. offseason
  #      trades filed under an unplayed season's round 1) ----
  for my $w (0..18) {
    my $tx = jload("$dir/transactions/week_$w.json");
    next unless ref $tx eq 'ARRAY';
    for my $t (@$tx) {
      next unless ($t->{type}//'') eq 'trade' && ($t->{status}//'') eq 'complete';
      my $adds = $t->{adds} || {}; my $drops = $t->{drops} || {};
      my $rids = $t->{roster_ids} || [];
      my @sides;
      for my $rid (@$rids) {
        my $pid = $rid2pid{$rid} or next;
        my @got;
        for my $plid (keys %$adds) { next unless $adds->{$plid}==$rid;
          push @got, { kind=>'player', id=>$plid };
          $playersOut{$plid} ||= 1;
        }
        for my $pk (@{$t->{draft_picks}||[]}) { next unless ($pk->{owner_id}//-1)==$rid;
          push @got, { kind=>'pick', text=>"$pk->{season} R$pk->{round}" };
        }
        for my $fb (@{$t->{waiver_budget}||[]}) { next unless ($fb->{receiver}//-1)==$rid;
          push @got, { kind=>'faab', text=>"\$$fb->{amount} FAAB" };
        }
        push @sides, {
          personId=>$pid, got=>\@got,
          poResult=>($played ? $poRes{$pid} : undef),
          madePlayoffs=>($played && $poRes{$pid} ? 1 : 0),
        };
      }
      push @tradesOut, { season=>$y+0, week=>$w+0, created=>($t->{created}//0), sides=>\@sides };
    }
  }
}

# ---------------------------------------------------------------------------
# 3a. Manual trade overlay: trades executed via commissioner tools / outside
#     the in-app trade flow, which never land in Sleeper's transaction log.
# ---------------------------------------------------------------------------
if (my $TOV = $CFG->{tradeOverlay}) {
  if (-e "$ROOT/$TOV") {
    my $tov = jload("$ROOT/$TOV") || {};
    for my $tr (@{ $tov->{trades} || [] }) {
      my $ts = 0;
      if (($tr->{date} // '') =~ /^(\d{4})-(\d{2})-(\d{2})/) {
        eval { require Time::Local; $ts = Time::Local::timegm(0,0,12,$3+0,$2-1,$1-1900) * 1000; };
      }
      my @sides;
      for my $sd (@{ $tr->{sides} || [] }) {
        my $pid = $sd->{person};
        next unless $pid && $P{$pid};
        my @got;
        for my $g (@{ $sd->{got} || [] }) {
          if    ($g =~ /^\s*\d{4}\s*R\d/i)  { push @got, { kind=>'pick',  text=>$g }; }
          elsif ($g =~ /FAAB|\$/i)          { push @got, { kind=>'faab',  text=>$g }; }
          else                              { push @got, { kind=>'player', name=>$g }; }
        }
        push @sides, { personId=>$pid, got=>\@got };
      }
      push @tradesOut, { season=>($tr->{season} || 0)+0, week=>0, created=>$ts,
                         manual=>\1, sides=>\@sides } if @sides >= 2;
    }
  } else {
    warn "tradeOverlay not found: $ROOT/$TOV\n";
  }
}

# ---------------------------------------------------------------------------
# 3b. Manual overlay: pre-API seasons the platform APIs can't reach.
#     Standings only (no per-game scores) -> games:[], pf/pa null.
# ---------------------------------------------------------------------------
if ($OVERLAY && -e "$ROOT/$OVERLAY") {
  my $ov = jload("$ROOT/$OVERLAY") || {};
  my $regBy = $ov->{regWeeksByYear} || {};
  my $poBy  = $ov->{playoffTeamsByYear} || {};
  sub ov_pid {
    my ($name) = @_;
    return $OVERLAY_NAME_TO_ID{$name} if $OVERLAY_NAME_TO_ID{$name};
    my $id = 'ov_' . lc($name); $id =~ s/[^a-z0-9]+/_/g;
    $P{$id} ||= { id=>$id, name=>$name, mgr=>'(pre-API)', firstSeason=>9999, seasons=>{}, titles=>[] };
    $OVERLAY_NAME_TO_ID{$name} = $id;
    return $id;
  }
  for my $s (@{ $ov->{seasons} || [] }) {
    my $y = $s->{year} + 0;
    my $champPid = $s->{champion} ? ov_pid($s->{champion}) : undef;
    my $ruPid    = $s->{runnerUp} ? ov_pid($s->{runnerUp}) : undef;
    my $thirdPid = $s->{third}    ? ov_pid($s->{third})    : undef;
    # catStandings: this year was scored as season-long category totals (roto /
    # total-categories), not weekly head-to-head. The w/l/t in the overlay is
    # the CATEGORY record — keep it in a separate `catRec` so it never sums into
    # the weekly-matchup career totals, and rank teams by their listed order.
    my $catStd = $s->{catStandings} ? 1 : 0;
    my @rows;
    my $i = 0;
    for my $t (@{ $s->{teams} || [] }) {
      $i++;
      push @rows, { pid=>ov_pid($t->{owner}), team=>$t->{owner},
                    w=>($t->{w}||0)+0, l=>($t->{l}||0)+0, t=>($t->{t}||0)+0,
                    ord=>$i, division=>$t->{division} };
    }
    my $poN = $poBy->{$y} // $s->{playoffTeams} // 4;
    # playoff berths: for a catStandings year use the listed finish order; else
    # top N by wins (no seed data pre-API)
    my @byRank = $catStd ? @rows
               : sort { $b->{w} <=> $a->{w} || $a->{l} <=> $b->{l} } @rows;
    my %made; $made{ $byRank[$_]{pid} } = 1 for 0 .. ($poN-1 < $#byRank ? $poN-1 : $#byRank);
    # division champs
    my %divBest;
    for my $r (@rows) {
      next unless $r->{division};
      my $d = $r->{division};
      $divBest{$d} = $r if !$divBest{$d} || $r->{w} > $divBest{$d}{w};
    }
    my %isDivChamp = map { $_->{pid} => 1 } values %divBest;

    my @entries;
    for my $r (@rows) {
      my $por = $champPid && $r->{pid} eq $champPid ? 'champion'
              : $ruPid    && $r->{pid} eq $ruPid    ? 'runner_up'
              : $thirdPid  && $r->{pid} eq $thirdPid ? 'third' : undef;
      my $e = {
        personId=>$r->{pid}, team=>$r->{team},
        w=>($catStd ? 0 : $r->{w}), l=>($catStd ? 0 : $r->{l}), t=>($catStd ? 0 : $r->{t}),
        pf=>undef, pa=>undef,
        seed=>undef, finalRank=>($catStd ? $r->{ord} : undef),
        poResult=>$por, madePlayoffs=>($made{$r->{pid}} ? 1 : 0),
        division=>$r->{division}, divisionChamp=>($isDivChamp{$r->{pid}} ? 1 : 0),
      };
      $e->{catRec} = { w=>$r->{w}, l=>$r->{l}, t=>$r->{t} } if $catStd;
      push @entries, $e;
      my $p = $P{$r->{pid}}; $p->{seasons}{$y}=1; $p->{firstSeason}=$y if $y < $p->{firstSeason};
    }
    push @{ $P{$champPid}{titles} }, $y if $champPid;
    my $mRegChamp = $s->{regSeasonChamp} ? ov_pid($s->{regSeasonChamp})
                  : (@byRank ? $byRank[0]{pid} : undef);
    push @seasons, {
      year=>$y, platform=>'manual', teams=>scalar(@entries),
      regWeeks=>($regBy->{$y} // 13), playoffTeams=>$poN,
      hasDivisions=>(%divBest ? \1 : \0),
      played=>1, hasOptimal=>0, manual=>1,
      ($s->{scoring} ? (scoring=>$s->{scoring}) : ()),
      ($catStd ? (catStandings=>\1) : ()),
      entries=>[ sort { $a->{personId} cmp $b->{personId} } @entries ],
      games=>[],
      champion=>$champPid, runnerUp=>$ruPid, third=>$thirdPid, regSeasonChamp=>$mRegChamp,
    };
  }
}

# ---------------------------------------------------------------------------
# 4. weekly player points (Sleeper) for trade "after" figures + player names
#    Only runs for a league that has a Sleeper player-weeks source.
# ---------------------------------------------------------------------------
my $sle2025 = $SLE_PW ? "$SLE/$SLE_PW" : undef;
my %wkpts;  # week -> {plid: pts}
my %need = %playersOut;
if ($sle2025) {
  for my $w (1..18) {
    my $mw = jload("$sle2025/matchups/week_$w.json"); next unless ref $mw eq 'ARRAY';
    my %acc;
    for my $e (@$mw) {
      my $pp = $e->{players_points} || {};
      $acc{$_} += $pp->{$_} for keys %$pp;
      $need{$_} = 1 for keys %$pp;                                  # every scored player -> name lookup
      $need{$_} = 1 for grep { defined && $_ ne '0' } @{ $e->{starters} || [] };
    }
    $wkpts{$w} = \%acc;
  }
}
# player name map: slim map from the big catalog for referenced ids
if ($sle2025) {
  my $ros = jload("$sle2025/rosters.json") || [];
  for my $r (@$ros) { $need{$_}=1 for @{$r->{players}||[]} }
}
$need{$_}=1 for ($SPORT eq 'nfl'
  ? qw(ARI ATL BAL BUF CAR CHI CIN CLE DAL DEN DET GB HOU IND JAX KC LAC LAR LV MIA MIN NE NO NYG NYJ PHI PIT SEA SF TB TEN WAS)
  : ());
my $catalog = -e "$ROOT/data/raw/sleeper_players_nfl.json" ? slurp("$ROOT/data/raw/sleeper_players_nfl.json") : '';
my %pmap;
for my $id (keys %need) {
  my $q = quotemeta $id;
  if ($catalog =~ /"$q":(\{.{0,8000}?\})(?=,"[0-9A-Za-z]{2,14}":\{|\}\s*$)/s) {
    my $o=$1;
    my ($fn)=$o=~/"full_name":"([^"]*)"/; my ($f)=$o=~/"first_name":"([^"]*)"/;
    my ($l)=$o=~/"last_name":"([^"]*)"/; my ($pos)=$o=~/"position":"([^"]*)"/; my ($tm)=$o=~/"team":"([^"]*)"/;
    my $nm = $fn // join(' ', grep {defined && length} ($f,$l)); $nm = $id unless defined $nm && length $nm;
    $pmap{$id} = [$nm, $pos//'', $tm//''];
  } else { $pmap{$id} = [$id,'',''] }
}

# attach "after trade" points to trade player assets
for my $tr (@tradesOut) {
  my $fromW = $tr->{week} <= 1 ? 1 : $tr->{week};
  for my $s (@{$tr->{sides}}) {
    my $tot = 0; my $has = 0;
    for my $g (@{$s->{got}}) {
      next unless $g->{kind} eq 'player';
      next unless defined $g->{id};                       # manual-overlay players carry a name, no id
      my $nm = $pmap{$g->{id}} || [$g->{id},'',''];
      $g->{name} = $nm->[0]; $g->{pos} = $nm->[1];
      my $p = 0; for my $w ($fromW..18) { $p += $wkpts{$w}{$g->{id}} if $wkpts{$w} && defined $wkpts{$w}{$g->{id}} }
      $g->{after} = r2($p); $tot += $p; $has = 1;
    }
    $s->{afterTotal} = $has ? r2($tot) : undef;
  }
}
$playersOut{$_} = $pmap{$_} for keys %pmap;

# ---------------------------------------------------------------------------
# 4b. player-level data: unify players across platforms, aggregate per
#     manager/season, and build dated ownership timelines.
# ---------------------------------------------------------------------------
sub norm_name {
  my ($s) = @_; $s = lc($s // '');
  $s =~ s/\.//g; $s =~ s/'//g;
  $s =~ s/\b(jr|sr|ii|iii|iv|v)\b//g;
  $s =~ s/[^a-z0-9 ]/ /g; $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
  return $s;
}
my %KEY_META;       # key -> [displayName, pos]
my %ESPN_PID2KEY;   # espn playerId -> key
my %SLE_PID2KEY;    # sleeper playerId -> key
my (%KEY_ESPN_ID, %KEY_SLE_ID);   # key -> a representative platform id (for headshots)

my $epw = ($PW_FILE && -e "$ROOT/$PW_FILE") ? (jload("$ROOT/$PW_FILE") || {}) : {};
my $epw_players = $epw->{players} || {};
my $epw_seasons = $epw->{seasons} || {};
for my $pid (sort keys %$epw_players) {
  my ($nm, $pos) = @{$epw_players->{$pid}};
  $pos = uc($pos // '');
  my $key = norm_name($nm) . '|' . lc($pos);
  $ESPN_PID2KEY{$pid} = $key;
  $KEY_META{$key} ||= [ $nm, $pos ];
  $KEY_ESPN_ID{$key} ||= $pid if $pid =~ /^\d+$/;
}
for my $pid (sort keys %pmap) {
  my ($nm, $pos) = @{$pmap{$pid}};
  $pos = uc($pos // ''); $pos = 'DST' if $pos eq 'DEF';
  my $key = norm_name($nm) . '|' . lc($pos);
  $SLE_PID2KEY{$pid} = $key;
  $KEY_META{$key} ||= [ $nm, $pos ];
  $KEY_SLE_ID{$key} ||= $pid;
}
sub headshot {
  my ($key) = @_;
  my $pos = $KEY_META{$key}[1] // '';
  return undef if $pos eq 'DST';
  if (my $e = $KEY_ESPN_ID{$key}) { return "https://a.espncdn.com/i/headshots/nfl/players/full/$e.png"; }
  if (my $s = $KEY_SLE_ID{$key})  { return "https://sleepercdn.com/content/nfl/players/thumb/$s.jpg"; }
  return undef;
}

# --- box-score lineups -> bundles/<slug>.lineups.json (fetched on demand) ----
#     row = [ name, pos, slot, nflTeam, points, headshotUrl ]
{
  my %LG;                     # "year|week|personId" -> { tot, st:[ rows ] }
  my (%covFull, %covStart);   # year -> 1

  # ESPN: starter flag only (no slot labels, no NFL team); 2015-17 = starters-only source
  my %POS_ORD = (QB=>1, RB=>2, WR=>3, TE=>4, K=>8, DST=>9);
  for my $y (@ESPN_Y) {
    my $t2p = $ESPN_T2P{$y} || {};
    my $wks = $epw_seasons->{$y} || {};
    next unless %$wks;
    my $sawBench = 0;
    for my $wk (keys %$wks) {
      my %byteam;
      for my $ep (keys %{$wks->{$wk}}) {
        my ($pts,$st,$tid) = @{$wks->{$wk}{$ep}};
        my $pid = $t2p->{$tid} or next;
        $sawBench = 1 if !$st;
        next unless $st;                                   # starters only
        push @{$byteam{$pid}}, [$ep, $pts];
      }
      for my $pid (keys %byteam) {
        my @rows = sort {
          my $pa = uc($KEY_META{ $ESPN_PID2KEY{$a->[0]} // '' }[1] // '');
          my $pb = uc($KEY_META{ $ESPN_PID2KEY{$b->[0]} // '' }[1] // '');
          ($POS_ORD{$pa} // 5) <=> ($POS_ORD{$pb} // 5) || $b->[1] <=> $a->[1]
            || ($a->[0] <=> $b->[0])   # stable tiebreak: equal pos+points -> by player id
        } @{$byteam{$pid}};
        my $tot = 0; my @st;
        for my $r (@rows) {
          my ($ep,$pts) = @$r;
          my $key = $ESPN_PID2KEY{$ep};
          my $nm  = $key ? $KEY_META{$key}[0] : "Player $ep";
          my $pos = $key ? uc($KEY_META{$key}[1] // '') : '';
          $tot += $pts;
          push @st, [ $nm, $pos, $pos, undef, r2($pts), ($key ? headshot($key) : undef) ];
        }
        $LG{"$y|$wk|$pid"} = { tot => r2($tot), st => \@st };
      }
    }
    ($sawBench ? $covFull{$y} : $covStart{$y}) = 1;
  }

  # Sleeper: real slot labels from roster_positions, ordered starters
  for my $y (sort keys %SLE_LEAGUES) {
    my $dir = "$SLE/$SLE_LEAGUES{$y}";
    my $lg  = jload("$dir/league.json") or next;
    my @slots = grep { !/^(BN|IR|TAXI)$/ } @{ $lg->{roster_positions} || [] };
    my $r2p = $SLE_R2P{$y} || {};
    my $any = 0;
    for my $w (1..18) {
      my $mw = jload("$dir/matchups/week_$w.json"); next unless ref $mw eq 'ARRAY' && @$mw;
      next unless grep { ($_->{points} || 0) > 0 } @$mw;
      $any = 1;
      for my $e (@$mw) {
        my $pid = $r2p->{ $e->{roster_id} } or next;
        my @starters = @{ $e->{starters} || [] };
        my $sp = $e->{starters_points} || [];
        my $pp = $e->{players_points} || {};
        my $tot = 0; my @st;
        for my $i (0 .. $#starters) {
          my $plid = $starters[$i];
          next if !defined $plid || $plid eq '0';
          my $pts  = defined $sp->[$i] ? $sp->[$i] : ($pp->{$plid} // 0);
          my $key  = $SLE_PID2KEY{$plid};
          my $meta = $pmap{$plid} || ($key ? [ @{ $KEY_META{$key} }[0,1], '' ] : ["Player $plid", '', '']);
          my $pos  = uc($meta->[1] // ''); $pos = 'DST' if $pos eq 'DEF';
          $tot += $pts;
          push @st, [ $meta->[0], $pos, ($slots[$i] // $pos), ($meta->[2] || undef), r2($pts),
                      ($key ? headshot($key) : undef) ];
        }
        $LG{"$y|$w|$pid"} = { tot => r2($tot), st => \@st };
      }
    }
    $covFull{$y} = 1 if $any;
  }

  my $out;
  if ($SPORT eq 'mlb') {
    # baseball: no lineups, a category-grid box per matchup instead
    my %yr; for (keys %MLB_BOX) { /^(\d+)\|/ and $yr{$1} = 1 }
    my @cy = sort { $a <=> $b } keys %yr;
    %LG = %MLB_BOX;
    $out = { sport => 'mlb',
             coverage => { cats => (@cy ? [ $cy[0]+0, $cy[-1]+0 ] : undef) },
             g => \%LG };
  } else {
    my @f = sort { $a <=> $b } keys %covFull;
    my @s = sort { $a <=> $b } grep { !$covFull{$_} } keys %covStart;
    $out = { coverage => { full     => (@f ? [ $f[0]+0, $f[-1]+0 ] : undef),
                           starters => (@s ? [ $s[0]+0, $s[-1]+0 ] : undef) },
             g => \%LG };
  }
  open my $lf, ">:raw", "$ROOT/bundles/$SLUG.lineups.json" or die "write lineups: $!";
  print $lf $j->encode($out);
  close $lf;
  printf STDERR "  %s: %d game-sides -> %s.lineups.json (%d bytes)\n",
    ($SPORT eq 'mlb' ? 'box scores' : 'lineups'),
    scalar(keys %LG), $SLUG, (-s "$ROOT/bundles/$SLUG.lineups.json");
}

# --- 4b.1 player-season aggregates -------------------------------------------
my %PS;  # "$y|$pid|$key" -> {pts, weeks{}, starts, best[wk,pts]}
sub ps_row { my ($y,$pid,$key)=@_; $PS{"$y|$pid|$key"} ||= { y=>$y+0, personId=>$pid, key=>$key, pts=>0, weeks=>{}, starts=>0, best=>[0,-999] }; }

for my $y (@ESPN_Y) {
  my $t2p = $ESPN_T2P{$y} || {};
  my $wks = $epw_seasons->{$y} || {};
  for my $wk (sort { $a <=> $b } keys %$wks) {
    for my $ep (sort keys %{$wks->{$wk}}) {
      my ($pts,$starter,$tid) = @{$wks->{$wk}{$ep}};
      my $pid = $t2p->{$tid} or next;
      my $key = $ESPN_PID2KEY{$ep} or next;
      my $r = ps_row($y,$pid,$key);
      $r->{pts} += $pts; $r->{weeks}{$wk+0} = 1; $r->{starts}++ if $starter;
      $r->{best} = [$wk+0, r2($pts)] if $pts > $r->{best}[1];
    }
  }
}
if ($SLE_PW) {
  my $dir = "$SLE/$SLE_PW";
  for my $w (1..18) {
    my $mw = jload("$dir/matchups/week_$w.json"); next unless ref $mw eq 'ARRAY';
    for my $e (@$mw) {
      my $pid = $SLE_R2P{2025}{ $e->{roster_id} } or next;
      my $pp = $e->{players_points} || {};
      my %starter = map { $_ => 1 } @{ $e->{starters} || [] };
      for my $plid (sort keys %$pp) {
        my $pts = $pp->{$plid}; next unless defined $pts;
        my $key = $SLE_PID2KEY{$plid} or next;
        my $r = ps_row(2025,$pid,$key);
        $r->{pts} += $pts; $r->{weeks}{$w} = 1; $r->{starts}++ if $starter{$plid};
        $r->{best} = [$w, r2($pts)] if $pts > $r->{best}[1];
      }
    }
  }
}
my @playerSeasons;
for my $k (sort keys %PS) {
  my $r = $PS{$k};
  my $wc = scalar keys %{$r->{weeks}};
  next unless $wc;
  push @playerSeasons, {
    year=>$r->{y}, personId=>$r->{personId}, key=>$r->{key},
    name=>$KEY_META{$r->{key}}[0], pos=>$KEY_META{$r->{key}}[1],
    pts=>r2($r->{pts}), weeks=>$wc, starts=>$r->{starts},
    ppg=> r2($r->{pts} / $wc),
    best=>{ week=>$r->{best}[0], pts=>$r->{best}[1] },
  };
}

# --- 4b.1b baseball player valuation ---------------------------------------
#   season "value" = sum of category z-scores vs the rosterable player pool.
#   ~0 = a replacement-level everyday player; elite hitter/pitcher seasons land
#   ~+8..+15. Rate cats (AVG/OBP/OPS/ERA/WHIP/K9) are playing-time weighted so a
#   .350 hitter in 40 AB doesn't grade like one in 600. Each season uses its own
#   scoring categories, so OPS/K9/etc. only count in the years the league used them.
if ($SPORT eq 'mlb') {
  my $msd = sub {                       # mean + sample sd (sd floored at a tiny +)
    my @v = grep { defined } @_; return (0, 1) unless @v;
    my $m = 0; $m += $_ for @v; $m /= @v;
    my $var = 0; $var += ($_ - $m) ** 2 for @v; $var /= (@v > 1 ? @v - 1 : 1);
    ($m, $var > 1e-9 ? sqrt($var) : 1);
  };
  my $strip0 = sub { (my $s = sprintf('%.3f', $_[0])) =~ s/^(-?)0\./$1./; $s };

  for my $y (sort { $a <=> $b } keys %MLB_PSTATS) {
    my $cats  = $MLB_CATS{$y} or next;
    my $P     = $MLB_PSTATS{$y};
    my $teams = $MLB_TEAMCT{$y} || 12;
    my $slots = $MLB_SLOTS{$y}  || { hit => 9, pit => 8 };

    my (%isHit, %isPit);
    for my $eid (keys %$P) {
      my $s   = $P->{$eid}{s};
      my $pit = ($P->{$eid}{pos} eq 'SP' || $P->{$eid}{pos} eq 'RP');
      my $ab  = $s->{0}  // 0;
      my $out = $s->{34} // 0;
      if ($pit) { $isPit{$eid} = 1 if $out >= 30; $isHit{$eid} = 1 if $ab >= 60; }
      else      { $isHit{$eid} = 1 if $ab  >= 20; $isPit{$eid} = 1 if $out >= 60; }
    }
    my @hit = keys %isHit;
    my @pit = keys %isPit;
    next unless @hit || @pit;

    # crude pre-rank (each counting stat scaled to its own max) -> rosterable pool
    my $pool_of = sub {
      my ($ids, $keys, $want) = @_;
      return [] unless @$ids;
      my %mx;
      for my $c (@$keys) { for my $e (@$ids) { my $v = $P->{$e}{s}{$c} // 0; $mx{$c} = $v if !defined $mx{$c} || $v > $mx{$c} } }
      my %sc;
      for my $e (@$ids) { my $t = 0; for my $c (@$keys) { $t += $mx{$c} ? ($P->{$e}{s}{$c} // 0) / $mx{$c} : 0 } $sc{$e} = $t }
      my @r = sort { $sc{$b} <=> $sc{$a} } @$ids;
      $want = $#r if $want > $#r;
      [ @r[0 .. $want] ];
    };
    my $hPool = $pool_of->(\@hit, [20, 5, 21, 23],       int($teams * $slots->{hit} * 1.6) - 1);
    my $pPool = $pool_of->(\@pit, [53, 48, 57, 83, 34],  int($teams * $slots->{pit} * 1.6) - 1);

    my (%Z, %CV);                       # eid -> {label => z} , eid -> {label => display value}
    for my $c (@$cats) {
      my $def = $MLB_CATDEF{$c} or next;
      my ($lbl, $grp, $kind, $lo, $wtc) = @$def;
      my @ids  = $grp eq 'h' ? @hit : @pit;
      my $pool = $grp eq 'h' ? $hPool : $pPool;
      next unless @$pool;

      if ($kind eq 'c') {
        my ($m, $sd) = $msd->(map { $P->{$_}{s}{$c} // 0 } @$pool);
        for my $e (@ids) {
          my $v = $P->{$e}{s}{$c} // 0;
          $Z{$e}{$lbl}  = ($v - $m) / $sd;
          $CV{$e}{$lbl} = $c == 34 ? r2($v / 3) : $v + 0;   # IP shown as innings
        }
      } else {
        my $wof = sub {
          my $s = $P->{$_[0]}{s};
          return $wtc == 34 ? (($s->{34} // 0) / 3)
               : $wtc == 16 ? ($s->{16} // (($s->{0} // 0) + ($s->{10} // 0)))
               :              ($s->{0} // 0);
        };
        my ($sw, $swr) = (0, 0);
        for my $e (@$pool) { my $w = $wof->($e); $sw += $w; $swr += $w * ($P->{$e}{s}{$c} // 0) }
        my $lg = $sw > 0 ? $swr / $sw : 0;
        my ($m, $sd) = $msd->(map { $wof->($_) * (($P->{$_}{s}{$c} // 0) - $lg) } @$pool);
        for my $e (@ids) {
          my $z = ($wof->($e) * (($P->{$e}{s}{$c} // 0) - $lg) - $m) / $sd;
          $Z{$e}{$lbl}  = $lo ? -$z : $z;
          $CV{$e}{$lbl} = r3($P->{$e}{s}{$c} // 0);
        }
      }
    }

    my %val;
    for my $e (keys %Z) { my $t = 0; $t += $_ for values %{ $Z{$e} }; $val{$e} = $t }
    my @ranked = sort { $val{$b} <=> $val{$a} } keys %val;
    my %vrank; my $i = 1; $vrank{$_} = $i++ for @ranked;

    my @ordLbl = map { $MLB_CATDEF{$_} ? $MLB_CATDEF{$_}[0] : () } @$cats;

    for my $e (@ranked) {
      my $pm  = $P->{$e};
      my $cv  = $CV{$e};
      my $h   = $isHit{$e} ? 1 : 0;
      my $p   = $isPit{$e} ? 1 : 0;
      my @seg;
      if ($h) {
        my $rate = defined $cv->{OPS} ? $strip0->($cv->{OPS}) . ' OPS'
                 : defined $cv->{AVG} ? $strip0->($cv->{AVG}) . ' AVG'
                 : defined $cv->{OBP} ? $strip0->($cv->{OBP}) . ' OBP' : undef;
        push @seg, $rate if $rate;
        push @seg, int($cv->{HR}) . ' HR'  if defined $cv->{HR};
        push @seg, int($cv->{R})  . ' R'   if defined $cv->{R};
        push @seg, int($cv->{RBI}) . ' RBI' if defined $cv->{RBI};
        push @seg, int($cv->{SB}) . ' SB'  if defined $cv->{SB};
      }
      if ($p) {
        push @seg, int($cv->{W}) . ' W'              if defined $cv->{W};
        push @seg, sprintf('%.2f ERA',  $cv->{ERA})  if defined $cv->{ERA};
        push @seg, sprintf('%.2f WHIP', $cv->{WHIP}) if defined $cv->{WHIP};
        push @seg, int($cv->{K}) . ' K'              if defined $cv->{K};
        push @seg, sprintf('%.1f K/9', $cv->{'K/9'}) if defined $cv->{'K/9'} && !defined $cv->{K};
        push @seg, int($cv->{IP}) . ' IP'            if defined $cv->{IP};
        push @seg, int($cv->{SV}) . ' SV'            if $cv->{SV};
        push @seg, int($cv->{HLD}) . ' HLD'          if $cv->{HLD};
      }

      my $drafter;
      if (my $dp = $ESPN_DRAFT{$y}{$e}) { $drafter = $ESPN_T2P{$y}{ $dp->[2] }; }
      my $ended  = $pm->{own};                       # roster-snapshot owner (season end)
      my $primary = $drafter // $ended;
      next unless $primary;

      my $grp = $p && !$h ? 'pit' : $h && $p ? 'both' : 'hit';
      push @playerSeasons, {
        year => $y + 0, personId => $primary,
        draftedBy => $drafter, endedOn => $ended, espnId => $e + 0,
        key  => 'e' . $e,          # ESPN player id — stable across years, unique per player (Jr. != Sr.)
        name => $pm->{name}, pos => $pm->{pos},
        val  => r2($val{$e}), vRank => $vrank{$e} + 0, group => $grp,
        drafted => ($ESPN_DRAFT{$y}{$e} ? { round => $ESPN_DRAFT{$y}{$e}[0] + 0, overall => $ESPN_DRAFT{$y}{$e}[1] + 0 } : undef),
        line => join('  ·  ', @seg),
        cats => [ map { { k => $_, v => $CV{$e}{$_}, z => r2($Z{$e}{$_}) } }
                  grep { defined $Z{$e}{$_} } @ordLbl ],
      };
    }
  }
  printf STDERR "  mlb valuation: %d player-seasons across %d years\n",
    scalar(@playerSeasons), scalar(keys %MLB_PSTATS);
}

# --- 4b.2 ownership timelines ----------------------------------------------
my %OWN;  # key -> [ {season, personId, startWk, endWk, weeks, pts, acq{}} ]

# ESPN era: contiguous-week runs per season (tolerate a 1-wk gap: bye / benched)
for my $y (@ESPN_Y) {
  my $t2p = $ESPN_T2P{$y} || {};
  my $wks = $epw_seasons->{$y} || {};
  my %byKey;   # key -> wk -> [pts, pid]
  for my $wk (sort { $a <=> $b } keys %$wks) {
    for my $ep (sort keys %{$wks->{$wk}}) {
      my ($pts,$st,$tid) = @{$wks->{$wk}{$ep}};
      my $pid = $t2p->{$tid} or next;
      my $key = $ESPN_PID2KEY{$ep} or next;
      $byKey{$key}{$wk+0} = [$pts, $pid];
    }
  }
  for my $key (keys %byKey) {
    my $cur;
    for my $wk (sort { $a <=> $b } keys %{$byKey{$key}}) {
      my ($pts,$pid) = @{$byKey{$key}{$wk}};
      if ($cur && $cur->{personId} eq $pid && $wk <= $cur->{endWk} + 2) {
        $cur->{endWk} = $wk; $cur->{weeks}++; $cur->{pts} += $pts;
      } else {
        push @{$OWN{$key}}, $cur if $cur;
        $cur = { season=>$y+0, personId=>$pid, startWk=>$wk, endWk=>$wk, weeks=>1, pts=>$pts, acq=>{type=>'unknown'} };
      }
    }
    push @{$OWN{$key}}, $cur if $cur;
  }
}
# ESPN draft cross-reference for acquisition on a wk<=2 opening stint
for my $y (@ESPN_Y) {
  my $dr = $ESPN_DRAFT{$y} || {}; my $t2p = $ESPN_T2P{$y} || {};
  for my $ep (sort keys %$dr) {
    my ($rnd,$ov,$tid,$kept,$rpn) = @{$dr->{$ep}};
    $rpn ||= (($ov - 1) % 10) + 1;   # fall back to position within a 10-team round
    my $pid = $t2p->{$tid} or next;
    my $key = $ESPN_PID2KEY{$ep} or next;
    my $rf = $ESPN_ROOKIE_FIRST{$y} // 999;
    my $acq;
    if ($kept)         { $acq = { type=>'kept' }; }
    elsif ($rnd >= $rf){ my $rr = $rnd - $rf + 1;
                         $acq = { type=>'rookie', detail=>"$rr.$rpn", overall=>(($rr-1)*10 + $rpn) }; }
    else              { $acq = { type=>'draft',  detail=>"$rnd.$rpn", overall=>$ov }; }
    for my $st (@{ $OWN{$key} || [] }) {
      next unless $st->{season} == $y && $st->{personId} eq $pid && $st->{startWk} <= 2;
      $st->{acq} = $acq;
      last;
    }
  }
}

# Sleeper 2025: real stints from draft + transaction stream
if ($SLE_PW) {
  my $dir = "$SLE/$SLE_PW";
  my $r2p = $SLE_R2P{2025} || {};
  my $teams = scalar(@{ jload("$dir/rosters.json") || [] }) || 10;
  my %draftAcq;   # plid -> {rid, round, pir, keeper}
  opendir(my $dh, $dir); my @files = readdir($dh); closedir($dh);
  for my $fn (@files) {
    next unless $fn =~ /^draft_\d+_picks\.json$/;
    for my $pk (@{ jload("$dir/$fn") || [] }) {
      next unless defined $pk->{player_id};
      my $pir = ($pk->{pick_no} && $pk->{round}) ? ($pk->{pick_no} - ($pk->{round}-1)*$teams) : undef;
      $draftAcq{ $pk->{player_id} } = { rid=>$pk->{roster_id}, round=>$pk->{round}, pir=>$pir, keeper=>($pk->{is_keeper}?1:0) };
    }
  }
  my @events;   # chronological add/drop events
  for my $w (1..18) {
    for my $t (@{ jload("$dir/transactions/week_$w.json") || [] }) {
      next unless ($t->{status}//'') eq 'complete';
      my $adds = $t->{adds} || {}; my $drops = $t->{drops} || {};
      for my $plid (sort keys %$adds) {
        push @events, { plid=>$plid, created=>($t->{created}//0), week=>$w+0,
                        type=>($t->{type}//''), add_rid=>$adds->{$plid}, from_rid=>$drops->{$plid} };
      }
    }
  }
  @events = sort { $a->{created} <=> $b->{created}
                   || $a->{week} <=> $b->{week} || $a->{plid} cmp $b->{plid} } @events;

  my (%onRoster, %wp);   # plid -> wk -> rid ;  plid -> wk -> pts
  for my $w (1..18) {
    my $mw = jload("$dir/matchups/week_$w.json"); next unless ref $mw eq 'ARRAY';
    for my $e (@$mw) {
      my $pp = $e->{players_points} || {};
      for my $plid (keys %$pp) { $onRoster{$plid}{$w} = $e->{roster_id}; $wp{$plid}{$w} = $pp->{$plid}; }
    }
  }
  for my $plid (sort keys %onRoster) {
    my $key = $SLE_PID2KEY{$plid} or next;
    my @stints; my $cur;
    for my $w (sort { $a <=> $b } keys %{$onRoster{$plid}}) {
      my $rid = $onRoster{$plid}{$w};
      if ($cur && $cur->{rid} == $rid && $w <= $cur->{endWk} + 2) {
        $cur->{endWk} = $w; $cur->{weeks}++; $cur->{pts} += ($wp{$plid}{$w} // 0);
      } else {
        push @stints, $cur if $cur;
        $cur = { rid=>$rid, personId=>$r2p->{$rid}, season=>2025, startWk=>$w, endWk=>$w, weeks=>1, pts=>($wp{$plid}{$w}//0) };
      }
    }
    push @stints, $cur if $cur;
    for my $st (@stints) {
      my $acq;
      if ($draftAcq{$plid} && $draftAcq{$plid}{rid} == $st->{rid} && $st->{startWk} <= 2) {
        my $da = $draftAcq{$plid};
        $acq = $da->{keeper} ? { type=>'keeper' }
             : { type=>'draft', detail=>($da->{pir} ? "$da->{round}.$da->{pir}" : "R$da->{round}") };
      }
      if (!$acq) {
        my $best;
        for my $ev (@events) {
          next unless $ev->{plid} eq $plid && ($ev->{add_rid}//-1) == $st->{rid};
          next unless $ev->{week} <= $st->{startWk} + 1;
          $best = $ev;
        }
        if ($best) {
          my %lbl = (trade=>'trade', waiver=>'waiver', free_agent=>'free agent');
          my $detail;
          if ($best->{type} eq 'trade' && defined $best->{from_rid} && $r2p->{$best->{from_rid}}) {
            $detail = "from " . $P{ $r2p->{$best->{from_rid}} }{name};
          }
          # the Jan platform-import shows up as a week-1 'commissioner' add for every holdover
          my $type = $best->{type};
          if ($type eq 'commissioner' && $best->{week} <= 1) {
            $acq = { type=>'retained' };
          } else {
            $acq = { type=>($lbl{$type} // $type), detail=>$detail, date=>$best->{created} };
          }
        }
      }
      $acq ||= { type=>'retained' };
      $st->{acq} = $acq;
      $st->{pts} = r2($st->{pts});
      delete $st->{rid};
    }
    push @{ $OWN{$key} }, @stints;
  }
}

my %ownershipOut;
for my $key (keys %OWN) {
  my @s = sort { $a->{season} <=> $b->{season} || $a->{startWk} <=> $b->{startWk}
                 || $a->{endWk} <=> $b->{endWk}
                 || ($a->{personId} // '') cmp ($b->{personId} // '') } @{ $OWN{$key} };
  next unless @s;
  # collapse repeated same-owner stints: only the first of a run keeps a real acquisition
  for my $i (1 .. $#s) {
    $s[$i]{acq} = { type=>'continued' } if $s[$i]{personId} eq $s[$i-1]{personId};
  }
  $ownershipOut{$key} = { name=>$KEY_META{$key}[0], pos=>$KEY_META{$key}[1], photo=>headshot($key), stints=>\@s };
}

# ---------------------------------------------------------------------------
# 4c. drafts: one board per season (ESPN + Sleeper), traded-pick attribution,
#     keeper / rookie flags, player names linked to the Players tab.
# ---------------------------------------------------------------------------
my @draftsOut;

sub espn_player_meta {
  my ($ep) = @_;
  my $key  = $ESPN_PID2KEY{$ep};
  my $meta = $key ? $KEY_META{$key}
                  : ($epw_players->{$ep} || $ESPN_PLAYER_NAME{$ep} || undef);
  # mlb has no cross-platform key; use the ESPN player id so draft picks join to
  # playerSeasons (which is also keyed 'e'.<espnId>). NFL keeps the norm-name key.
  my $pkey = $SPORT eq 'mlb' ? (defined $ep ? 'e' . $ep : undef) : $key;
  return ( ($meta ? $meta->[0] : "Player $ep"),
           ($meta ? uc($meta->[1] // '') : ''),
           $pkey );
}

# -- ESPN drafts (one board per segment: keeper/main draft + appended rookie draft) --
for my $y (@ESPN_Y) {
  my $di = $ESPN_DRAFT_INFO{$y} or next;
  my @picks = @{ $di->{picks} || [] };  next unless @picks;
  my $t2p   = $ESPN_T2P{$y} || {};
  my $teams = do { my %s; $s{$_->{teamId}}=1 for @picks; scalar keys %s };
  my $maxR  = 0; for (@picks) { $maxR = $_->{round} if $_->{round} > $maxR; }
  my $rookieFirst = $ESPN_ROOKIE_FIRST{$y};
  my $isAuction   = uc($di->{type}) eq 'AUCTION';

  if ($isAuction) {
    my @outPicks;
    for my $p (sort { ($b->{bid}||0) <=> ($a->{bid}||0) || $a->{overall} <=> $b->{overall} } @picks) {
      my ($pname,$ppos,$key) = espn_player_meta($p->{playerId});
      push @outPicks, {
        round=>$p->{round}+0, roundPick=>undef, overall=>$p->{overall}+0, slot=>undef,
        personId=>($t2p->{$p->{teamId}} || undef), viaPersonId=>undef,
        keeper=>($p->{kept} ? \1 : \0), rookie=>\0, rookieRound=>undef,
        bid=>($p->{bid} ? $p->{bid}+0 : 0),
        player=>{ name=>$pname, pos=>$ppos, nfl=>undef }, playerKey=>$key,
      };
    }
    push @draftsOut, {
      year=>$y+0, platform=>'espn', kind=>'auction', format=>'auction',
      rounds=>0, teams=>$teams+0, roundOffset=>0,
      auctionBudget=>(($di->{budget}||0)+0), slots=>[], picks=>\@outPicks,
    };
    next;
  }

  # segments: [firstRound, lastRound, kind]
  my $mainMax = ($rookieFirst && $rookieFirst <= $maxR) ? $rookieFirst - 1 : $maxR;
  my @segs = ( [1, $mainMax, ($rookieFirst && $rookieFirst <= $maxR) ? 'keeper' : ($CFG->{type} eq 'dynasty' ? 'startup' : 'redraft')] );
  push @segs, [$rookieFirst, $maxR, 'rookie'] if $rookieFirst && $rookieFirst <= $maxR;

  for my $seg (@segs) {
    my ($s0, $s1, $kind) = @$seg;
    # base column order = segment's first round, by roundPick
    my @base;   # col index 0.. -> teamId
    for my $p (@picks) { $base[ $p->{roundPick}-1 ] = $p->{teamId} if $p->{round} == $s0 && $p->{roundPick}; }
    next unless grep { defined } @base;
    my $ncol = scalar @base;
    my @slots = map { { slot=>$_+1, personId=>($t2p->{$base[$_]} || undef) } } 0 .. $#base;

    my @outPicks;
    for my $p (sort { $a->{overall} <=> $b->{overall} } grep { $_->{round} >= $s0 && $_->{round} <= $s1 } @picks) {
      my ($pname,$ppos,$key) = espn_player_meta($p->{playerId});
      my $pid = $t2p->{$p->{teamId}} || undef;
      my $rp  = $p->{roundPick} || 0;
      # board column: place the pick by its roundPick, accounting for snake direction
      my ($rp1tid) = map { $_->{teamId} } grep { $_->{round}==$p->{round} && ($_->{roundPick}||0)==1 } @picks;
      my $rev = (defined $rp1tid && $ncol && $rp1tid == $base[-1] && $base[0] != $base[-1]) ? 1 : 0;
      my $col = $rev ? ($ncol + 1 - $rp) : $rp;                 # 1-based board column
      # NOTE: ESPN's draftDetail records only who made each pick, never original pick
      # ownership, so traded-pick ("via") attribution is impossible for ESPN drafts.
      # (Inferring it from column drift produced false positives on draft-order quirks.)
      push @outPicks, {
        round=>($p->{round} - $s0 + 1)+0, roundPick=>$rp+0, overall=>$p->{overall}+0,
        slot=>$col+0, personId=>$pid, viaPersonId=>undef,
        keeper=>($p->{kept} ? \1 : \0),
        rookie=>($kind eq 'rookie' ? \1 : \0), rookieRound=>($kind eq 'rookie' ? ($p->{round}-$s0+1)+0 : undef),
        bid=>undef, player=>{ name=>$pname, pos=>$ppos, nfl=>undef }, playerKey=>$key,
      };
    }
    my %r1; for my $p (@picks) { $r1{$p->{round}} = $p->{teamId} if $p->{round}>=$s0 && $p->{round}<=$s1 && ($p->{roundPick}||0)==1; }
    my $isSnake = grep { defined $_ && $ncol && $_ == $base[-1] && $base[0] != $base[-1] } values %r1;
    push @draftsOut, {
      year=>$y+0, platform=>'espn', kind=>$kind,
      format=>($isSnake ? 'snake' : 'linear'),
      rounds=>($s1 - $s0 + 1)+0, teams=>$ncol+0, roundOffset=>($s0-1)+0,
      auctionBudget=>undef, slots=>\@slots, picks=>\@outPicks,
    };
  }
}

# -- Sleeper drafts --
for my $y (sort keys %SLE_DRAFT_INFO) {
  my $di = $SLE_DRAFT_INFO{$y};
  my @picks = @{ $di->{picks} || [] };  next unless @picks;
  my $u2p   = $di->{uid2pid} || {};
  my $r2p   = $SLE_R2P{$y} || {};
  my $teams = $di->{teams} || 10;

  # slot -> pid from draft_order (user_id -> slot)
  my @slots; my %slotRid;
  my %slotUser = reverse %{ $di->{order} || {} };   # slot -> user_id
  for my $s (1 .. $teams) {
    my $uid = $slotUser{$s};
    my $pid = defined $uid ? $u2p->{$uid} : undef;
    push @slots, { slot=>$s+0, personId=>$pid };
  }
  # original roster at each slot (for traded-pick 'via')
  my %slotOrigRid;
  for my $r (@{ jload("$SLE/$SLE_LEAGUES{$y}/rosters.json") || [] }) {
    my $uid = $r->{owner_id} // '';
    for my $s (1 .. $teams) { $slotOrigRid{$s} = $r->{roster_id} if ($slotUser{$s}//'') eq $uid; }
  }
  # traded picks in this draft: round -> origRosterId -> nowRosterId
  my %traded;
  for my $tp (@{ $di->{traded} || [] }) { $traded{ $tp->{round} }{ $tp->{roster_id} } = $tp->{owner_id}; }

  my @outPicks;
  for my $p (sort { $a->{pick_no} <=> $b->{pick_no} } @picks) {
    my $md   = $p->{metadata} || {};
    my $nm   = join(' ', grep { defined && length } ($md->{first_name}, $md->{last_name}));
    my $plid = $p->{player_id};
    my $key  = $plid ? $SLE_PID2KEY{$plid} : undef;
    $nm ||= ($key && $KEY_META{$key} ? $KEY_META{$key}[0] : "Player $plid");
    my $ppos = uc($md->{position} // ($key && $KEY_META{$key} ? $KEY_META{$key}[1] : '') // '');
    $ppos = 'DST' if $ppos eq 'DEF';
    my $slot = $p->{draft_slot} || 0;
    my $pid  = $r2p->{ $p->{roster_id} } || $u2p->{ $p->{picked_by} // '' } || undef;
    my $via;
    my $origRid = $slotOrigRid{$slot};
    if (defined $origRid && $traded{ $p->{round} } && defined $traded{ $p->{round} }{$origRid}) {
      my $vp = $r2p->{ $origRid };
      $via = $vp if $vp && $vp ne ($pid // '');
    }
    push @outPicks, {
      round=>$p->{round}+0, roundPick=>($slot ? $slot+0 : undef), overall=>$p->{pick_no}+0,
      slot=>($slot ? $slot+0 : undef),
      personId=>$pid, viaPersonId=>$via,
      keeper=>($p->{is_keeper} ? \1 : \0),
      rookie=>($CFG->{type} eq 'dynasty' ? \1 : \0), rookieRound=>undef,
      bid=>undef,
      player=>{ name=>$nm, pos=>$ppos, nfl=>($md->{team} || undef) },
      playerKey=>$key,
    };
  }
  push @draftsOut, {
    year=>$y+0, platform=>'sleeper',
    kind=>($CFG->{type} eq 'dynasty' ? 'rookie' : 'redraft'),
    format=>($di->{type} eq 'snake' ? 'snake' : 'linear'),
    rounds=>($di->{rounds}||0)+0, teams=>$teams+0, roundOffset=>0,
    auctionBudget=>undef, slots=>\@slots, picks=>\@outPicks,
  };
}

# newest year first; within a year show the rookie board before the keeper board
my %KIND_ORD = (rookie=>0, auction=>1, keeper=>2, startup=>1, redraft=>1);
@draftsOut = sort { $b->{year} <=> $a->{year}
                    || ($KIND_ORD{$a->{kind}}//9) <=> ($KIND_ORD{$b->{kind}}//9) } @draftsOut;

# future draft capital (dynasty): most-recent Sleeper season's league-level traded picks
my @futurePicks;
if ($CFG->{type} eq 'dynasty' && %SLE_FUTURE_PICKS) {
  my ($ly) = sort { $b <=> $a } keys %SLE_FUTURE_PICKS;
  my $r2p  = $SLE_FUTURE_R2P{$ly} || {};
  for my $tp (sort { $a->{season} <=> $b->{season} || $a->{round} <=> $b->{round}
                     || ($a->{roster_id}||0) <=> ($b->{roster_id}||0) } @{ $SLE_FUTURE_PICKS{$ly} }) {
    push @futurePicks, {
      season=>$tp->{season}.'', round=>$tp->{round}+0,
      originalPersonId=>($r2p->{ $tp->{roster_id} } || undef),
      ownerPersonId   =>($r2p->{ $tp->{owner_id}  } || undef),
    };
  }
}

# ---------------------------------------------------------------------------
# 5. people output
# ---------------------------------------------------------------------------
@seasons = sort { $a->{year} <=> $b->{year} } @seasons;

# stamp era-aware manager names onto each season entry (see mgr_name_for).
# A co-managed entry shows all its managers joined with " / " unless an
# explicit era-name rule already covers that year.
for my $s (@seasons) {
  for my $e (@{ $s->{entries} || [] }) {
    my $nm = mgr_name_for($e->{personId}, $s->{year});
    if (!defined $nm && $e->{coPids} && @{$e->{coPids}}) {
      $nm = join(' / ', map { ($P{$_} || {})->{name} // $_ } $e->{personId}, @{$e->{coPids}});
    }
    $e->{mgrName} = $nm if defined $nm;
  }
}

# people referenced only by a draft board (e.g. new managers in a not-yet-played season)
my %draftPid;
for my $d (@draftsOut) {
  $draftPid{ $_->{personId} } = 1 for grep { $_->{personId} } @{ $d->{slots} || [] };
  $draftPid{ $_->{personId} } = 1 for grep { $_->{personId} } @{ $d->{picks} || [] };
}
$draftPid{ $_->{originalPersonId} } = 1 for grep { $_->{originalPersonId} } @futurePicks;
$draftPid{ $_->{ownerPersonId} }    = 1 for grep { $_->{ownerPersonId} }    @futurePicks;
my @peopleOut;
for my $pid (sort { scalar(keys %{$P{$b}{seasons}}) <=> scalar(keys %{$P{$a}{seasons}})
                    || $a cmp $b } keys %P) {
  my $p = $P{$pid};
  next unless %{$p->{seasons}} || $draftPid{$pid};
  push @peopleOut, {
    id=>$pid, name=>$p->{name}, mgr=>$p->{mgr}//'', team=>$p->{team},
    firstSeason=>($p->{firstSeason}==9999?undef:$p->{firstSeason}),
    seasons=>[ map {0+$_} sort keys %{$p->{seasons}} ],
    titles=>[ map {0+$_} sort @{$p->{titles}} ],
  };
}

my @playedYears = sort { $a <=> $b } map { $_->{year} } grep { $_->{played} } @seasons;

# Build stamp: the data snapshot's own commit date (YYYY-MM-DD), not wall-clock,
# so rebuilding without new commits leaves bundles byte-identical.
my $generated;
if (open my $gh, '-|', 'git', '-C', $ROOT, 'log', '-1', '--format=%cs') {
  local $/; $generated = <$gh>; close $gh;
  $generated =~ s/\s+//g if defined $generated;
}
unless (defined $generated && $generated =~ /^\d{4}-\d{2}-\d{2}$/) {
  my @t = gmtime(); $generated = sprintf("%04d-%02d-%02d", $t[5]+1900, $t[4]+1, $t[3]);
}

my $out = {
  league => {
    slug => $CFG->{slug}, name => $CFG->{label}, type => $CFG->{type},
    sport => $SPORT,
    scoring => ($SPORT eq 'nfl' ? 'points'
                : ((grep { ($_->{scoring}//'') eq 'cats' } @seasons) ? 'cats' : 'roto')),
    primary => ($CFG->{primary} ? \1 : \0),
    firstSeason => ($playedYears[0] // undef), lastSeason => ($playedYears[-1] // undef),
    hasPlayers => (($PW_FILE || @playerSeasons) ? \1 : \0), hasTrades => ($SLE_PW ? \1 : \0),
    hasDrafts => (@draftsOut ? \1 : \0),
    hasDivisions => ((grep { $_->{hasDivisions} } @seasons) ? \1 : \0),
    divisionsSince => ($CFG->{divisionsSince} ? $CFG->{divisionsSince}+0 : undef),
    divisionOrder => ($DIV_ORDER || undef),
    prestige => ($CFG->{prestige} || { championship=>10, regularSeasonTitle=>4, runnerUp=>3, divisionTitle=>2, thirdPlace=>0, lastPlace=>0, playoffBerth=>0 }),
  },
  generated_at => $generated,
  people => \@peopleOut,
  seasons => \@seasons,
  trades => [ sort { $b->{created} <=> $a->{created} } @tradesOut ],
  players => \%playersOut,
  playerSeasons => \@playerSeasons,
  ownership => \%ownershipOut,
  drafts => \@draftsOut,
  futurePicks => \@futurePicks,
};
mkdir "$ROOT/bundles" unless -d "$ROOT/bundles"; open my $fh, ">:raw", "$ROOT/bundles/$SLUG.json" or die $!;
print $fh $j->encode($out);
close $fh;

printf STDERR "seasons: %d (%s..%s)  people: %d  trades: %d  players: %d  playerSeasons: %d  ownership keys: %d  drafts: %d  futurePicks: %d  bytes: %d\n",
  scalar(@seasons), $seasons[0]{year}, $seasons[-1]{year},
  scalar(@peopleOut), scalar(@tradesOut), scalar(keys %playersOut),
  scalar(@playerSeasons), scalar(keys %ownershipOut),
  scalar(@draftsOut), scalar(@futurePicks), (-s "$ROOT/bundles/$SLUG.json");
