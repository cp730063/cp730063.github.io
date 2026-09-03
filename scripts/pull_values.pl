#!/usr/bin/perl
# Pulls current trade values (FantasyCalc) + current rosters for each league and
# writes bundles/<slug>.values.json (fetched on demand by the Trade Calculator).
# Dynasty leagues use Sleeper rosters + dynasty values (with rookie picks);
# redraft leagues use the current ESPN season roster + redraft values.
# Run manually / periodically; NOT part of build_all.pl.
#
#   perl scripts/pull_values.pl              # every league in scripts/leagues/
#   perl scripts/pull_values.pl dischnasty   # one
use strict; use warnings; use JSON::PP;
use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";
my $J  = JSON::PP->new;
my $UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0 Safari/537.36";
my $ESPN_CRED = "C:/Users/cp730/Downloads/ESPN creds.txt";

sub slurp { local $/; open my $f,'<:raw',$_[0] or return undef; my $c=<$f>; close $f; $c }
sub jload { my $c = slurp($_[0]); $c ? eval { $J->decode($c) } : undef }
sub norm  { my $s = lc($_[0] // ''); $s =~ s/\.//g; $s =~ s/'//g;
            $s =~ s/\b(jr|sr|ii|iii|iv|v)\b//g; $s =~ s/[^a-z0-9 ]/ /g;
            $s =~ s/\s+/ /g; $s =~ s/^ | $//g; return $s }

sub curl_json {
  my (%o) = @_;                                    # url => , headers => [], jar =>
  my $tmp = "$ROOT/.pv.tmp";
  my @cmd = ("curl", "-sS", "--compressed", "-H", "User-Agent: $UA", "-o", $tmp);
  push @cmd, "-b", $o{jar} if $o{jar};
  push @cmd, "-H", $_ for @{ $o{headers} || [] };
  push @cmd, $o{url};
  my $rc = system(@cmd);
  die "curl failed ($rc): $o{url}\n" if $rc != 0;
  my $c = slurp($tmp); unlink $tmp;
  return $J->decode($c);
}

# --- FantasyCalc values, indexed for joining ---------------------------------
sub fc_values {
  my ($isDyn, $numQbs, $teams, $ppr) = @_;
  my $url = sprintf(
    "https://api.fantasycalc.com/values/current?isDynasty=%s&numQbs=%d&numTeams=%d&ppr=%s",
    ($isDyn ? "true" : "false"), $numQbs, $teams, $ppr);
  print STDERR "  $url\n";
  my $fc = curl_json(url => $url);
  my (%bySle, %byEspn, %byName, %byPick);
  for my $e (@$fc) {
    my $p = $e->{player} || {};
    my $row = {
      name => $p->{name}, pos => $p->{position},
      nfl  => ($p->{maybeTeam} || undef),
      age  => (defined $p->{maybeAge} ? ($p->{maybeAge} + 0) : undef),
      value => ($e->{value} + 0),
      posRank => ($e->{positionRank} || undef),
      trend => (defined $e->{trend30Day} ? ($e->{trend30Day} + 0) : 0),
    };
    if (($p->{sleeperId} // '') =~ /^FP_(\d{4})_(\d+)/) { $byPick{"$1|$2"} = $row->{value}; }
    else {
      $bySle{ $p->{sleeperId} }  = $row if $p->{sleeperId};
      $byEspn{ $p->{espnId} }    = $row if $p->{espnId};
    }
    $byName{ norm($p->{name}) . '|' . lc($p->{position} // '') } //= $row;
  }
  return (\%bySle, \%byEspn, \%byName, \%byPick, scalar(@$fc));
}

sub player_row {
  my ($v) = @_;
  return {
    key => norm($v->{name}) . '|' . lc($v->{pos} // ''),
    name => $v->{name}, pos => $v->{pos}, nfl => $v->{nfl}, age => $v->{age},
    value => $v->{value}, posRank => $v->{posRank}, trend => $v->{trend},
  };
}

sub write_values {
  my ($slug, $fmt, $curYear, $nEntries, $teamsOut) = @_;
  my $out = {
    generated => scalar(gmtime()) . ' UTC',
    source => 'FantasyCalc', asOf => $curYear + 0,
    format => $fmt, teams => $teamsOut,
  };
  open my $fh, '>:raw', "$ROOT/bundles/$slug.values.json" or die $!;
  print $fh $J->encode($out); close $fh;
  printf STDERR "  wrote %s.values.json — %d teams, %d FantasyCalc entries (%d bytes)\n",
    $slug, scalar(keys %$teamsOut), $nEntries, (-s "$ROOT/bundles/$slug.values.json");
}

# ---------------------------------------------------------------------------
sub do_dynasty {
  my ($cfg, $slug) = @_;
  my $sle = $cfg->{sleeper} || {};
  my ($curYear) = sort { $b <=> $a } keys %$sle;
  my $lid = $sle->{$curYear} or do { warn "$slug: no current sleeper league\n"; return; };
  my $dir = "$ROOT/data/raw/sleeper/$lid";
  my $league  = jload("$dir/league.json")  or do { warn "$slug: missing raw sleeper data ($lid)\n"; return; };
  my $rosters = jload("$dir/rosters.json") || [];
  my $users   = jload("$dir/users.json")   || [];
  my $tpicks  = jload("$dir/traded_picks.json") || [];

  my @rp = @{ $league->{roster_positions} || [] };
  my $numQbs = (grep { /^(SUPER_FLEX|SF)$/ } @rp) ? 2 : (scalar grep { $_ eq 'QB' } @rp);
  $numQbs = 1 if $numQbs < 1; $numQbs = 2 if $numQbs > 2;
  my $sc  = $league->{scoring_settings} || {};
  my $ppr = defined $sc->{rec} ? ($sc->{rec} + 0) : 1;
  my $teams = $league->{total_rosters} || scalar(@$rosters) || 12;

  my ($bySle, undef, $byName, $byPick, $n) = fc_values(1, $numQbs, $teams, $ppr);

  my %uName = map { $_->{user_id} => lc($_->{display_name} // '') } @$users;
  my %sn2id = map { lc($_->{sleeperName}) => $_->{id} } grep { $_->{sleeperName} } @{ $cfg->{people} || [] };
  my %rid2pid = map { $_->{roster_id} => ($sn2id{ $uName{$_->{owner_id}} // '' } || "sle_$_->{owner_id}") } @$rosters;

  my @futYears = ($curYear + 1 .. $curYear + 3);
  my %traded;
  for my $t (@$tpicks) { $traded{"$t->{season}|$t->{round}|$t->{roster_id}"} = $t->{owner_id}; }
  my %pickList;
  for my $rid (map { $_->{roster_id} } @$rosters) {
    for my $y (@futYears) { for my $rd (1 .. 4) {
      my $owner = $traded{"$y|$rd|$rid"} // $rid;
      push @{ $pickList{$owner} }, { season => $y + 0, round => $rd + 0, from => $rid + 0 };
    }}
  }

  my %teamsOut;
  for my $r (@$rosters) {
    my $pid = $rid2pid{ $r->{roster_id} } or next;
    my @players;
    for my $plid (@{ $r->{players} || [] }) {
      my $v = $bySle->{$plid} or next;
      push @players, player_row($v);
    }
    @players = sort { $b->{value} <=> $a->{value} } @players;
    my @picks;
    for my $pk (sort { $a->{season} <=> $b->{season} || $a->{round} <=> $b->{round} } @{ $pickList{ $r->{roster_id} } || [] }) {
      my $ord = $pk->{round} == 1 ? '1st' : $pk->{round} == 2 ? '2nd' : $pk->{round} == 3 ? '3rd' : "$pk->{round}th";
      push @picks, {
        label => "$pk->{season} $ord", season => $pk->{season}, round => $pk->{round},
        via => ($pk->{from} != $r->{roster_id} ? ($rid2pid{ $pk->{from} } || undef) : undef),
        value => (($byPick->{"$pk->{season}|$pk->{round}"} // 0) + 0),
      };
    }
    $teamsOut{$pid} = { players => \@players, picks => \@picks };
  }
  write_values($slug, { dynasty => \1, numQbs => $numQbs + 0, ppr => $ppr + 0, teams => $teams + 0 },
               $curYear, $n, \%teamsOut);
}

# ---------------------------------------------------------------------------
sub do_redraft {
  my ($cfg, $slug) = @_;
  my $lid = $cfg->{espnId} or do { warn "$slug: no espnId\n"; return; };
  open my $cf, '<', $ESPN_CRED or do { warn "$slug: ESPN creds not readable — skipping redraft calc\n"; return; };
  my @cl = <$cf>; close $cf;
  my ($SWID) = grep { /\{[0-9A-F-]+\}/i } @cl;
  my ($S2)   = grep { length($_) > 60 && !/\{/ } @cl;
  return warn "$slug: cred parse failed\n" unless $SWID && $S2;
  s/\s//g for $SWID, $S2;
  my $jar = "$ROOT/.pv.espnjar";
  open my $jf, '>', $jar or die; $|=1;
  print $jf ".espn.com\tTRUE\t/\tTRUE\t0\tSWID\t$SWID\n.espn.com\tTRUE\t/\tTRUE\t0\tespn_s2\t$S2\n";
  close $jf;

  my $curYear = (gmtime())[5] + 1900;
  my $base = "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons";
  my $lg;
  for my $y ($curYear, $curYear - 1) {
    my $x = eval { curl_json(url => "$base/$y/segments/0/leagues/$lid?view=mTeam&view=mRoster&view=mSettings", jar => $jar) };
    my $d = ref $x eq 'ARRAY' ? $x->[0] : $x;
    if ($d && $d->{teams} && grep { @{ $_->{roster}{entries} || [] } } @{ $d->{teams} }) { $lg = $d; $curYear = $y; last; }
  }
  unlink $jar;
  return warn "$slug: no current ESPN roster data\n" unless $lg;

  my $rs = $lg->{settings}{rosterSettings}{lineupSlotCounts} || {};
  my $numQbs = ($rs->{0} || 1) >= 2 ? 2 : 1;                 # slot 0 = QB
  my $teams  = $lg->{settings}{size} || scalar(@{ $lg->{teams} || [] }) || 12;
  my $ppr = 0;
  for my $it (@{ $lg->{settings}{scoringSettings}{scoringItems} || [] }) {
    $ppr = ($it->{points} || $it->{pointsOverrides}{16} || 0) + 0 if ($it->{statId} // -1) == 53;  # 53 = receptions
  }
  $ppr = 1 if $ppr > 1;   # clamp odd configs

  my (undef, $byEspn, $byName, undef, $n) = fc_values(0, $numQbs, $teams, $ppr);

  my %g2id = map { uc($_->{espn}) => $_->{id} } grep { $_->{espn} } @{ $cfg->{people} || [] };
  for my $p (@{ $cfg->{people} || [] }) { $g2id{uc $_} = $p->{id} for @{ $p->{espnAlt} || [] }; }

  my %teamsOut;
  for my $t (@{ $lg->{teams} || [] }) {
    my $g = uc(($t->{owners} || [])->[0] // '');
    my $pid = $g2id{$g} or next;
    my @players;
    for my $ent (@{ $t->{roster}{entries} || [] }) {
      my $pl = $ent->{playerPoolEntry}{player} || $ent->{player} || {};
      my $eid = $pl->{id} // next;
      my $v = $byEspn->{$eid} || $byName->{ norm($pl->{fullName}) . '|' . lc($pl->{defaultPosition} // '') };
      next unless $v;
      push @players, player_row($v);
    }
    @players = sort { $b->{value} <=> $a->{value} } @players;
    $teamsOut{$pid} = { players => \@players, picks => [] };
  }
  write_values($slug, { dynasty => \0, numQbs => $numQbs + 0, ppr => $ppr + 0, teams => $teams + 0 },
               $curYear, $n, \%teamsOut);
}

# ---------------------------------------------------------------------------
my @slugs = @ARGV;
opendir(my $ld, "$ROOT/scripts/leagues") or die;
push @slugs, sort map { s/\.json$//r } grep { /\.json$/ } readdir $ld unless @slugs;
closedir $ld;

for my $slug (@slugs) {
  my $cfg = jload("$ROOT/scripts/leagues/$slug.json") or do { warn "no config: $slug\n"; next; };
  my $type = $cfg->{type} // '';
  print STDERR "== $slug ($type) ==\n";
  if    ($type eq 'dynasty') { do_dynasty($cfg, $slug); }
  elsif ($type eq 'redraft') { do_redraft($cfg, $slug); }
  else { print STDERR "  skip (type '$type' has no trade calculator)\n"; }
}
