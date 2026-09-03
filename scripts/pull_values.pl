#!/usr/bin/perl
# Pulls current dynasty trade values (FantasyCalc) + the current-season roster for
# each dynasty league, and writes bundles/<slug>.values.json (fetched on demand by
# the Trade Calculator).  Run manually / periodically; not part of build_all.pl.
#
#   perl scripts/pull_values.pl              # every dynasty league in scripts/leagues/
#   perl scripts/pull_values.pl dischnasty   # one
use strict; use warnings; use JSON::PP;
use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";
my $J = JSON::PP->new;

sub slurp { local $/; open my $f,'<:raw',$_[0] or return undef; my $c=<$f>; close $f; $c }
sub jload { my $c = slurp($_[0]); $c ? eval { $J->decode($c) } : undef }
sub norm  { my $s = lc($_[0] // ''); $s =~ s/\.//g; $s =~ s/'//g;
            $s =~ s/\b(jr|sr|ii|iii|iv|v)\b//g; $s =~ s/[^a-z0-9 ]/ /g;
            $s =~ s/\s+/ /g; $s =~ s/^ | $//g; return $s }
sub fetch {
  my ($url) = @_;
  my $tmp = "$ROOT/.fcval.tmp";
  my $rc = system("curl", "-sS", "-f", "-o", $tmp, $url);
  die "curl failed ($rc) for $url\n" if $rc != 0;
  my $c = slurp($tmp); unlink $tmp;
  return $J->decode($c);
}

my @slugs = @ARGV;
opendir(my $ld, "$ROOT/scripts/leagues") or die;
my @all = sort map { s/\.json$//r } grep { /\.json$/ } readdir $ld;
closedir $ld;
@slugs = @all unless @slugs;

for my $slug (@slugs) {
  my $cfg = jload("$ROOT/scripts/leagues/$slug.json") or do { warn "no config: $slug\n"; next; };
  if (($cfg->{type} // '') ne 'dynasty') { print STDERR "skip $slug (not dynasty)\n"; next; }
  my $sle = $cfg->{sleeper} || {};
  my ($curYear) = sort { $b <=> $a } keys %$sle;
  my $lid = $sle->{$curYear} or do { warn "$slug: no current sleeper league\n"; next; };
  my $dir = "$ROOT/data/raw/sleeper/$lid";
  my $league  = jload("$dir/league.json")  or do { warn "$slug: missing league.json ($lid) — pull raw data first\n"; next; };
  my $rosters = jload("$dir/rosters.json") || [];
  my $users   = jload("$dir/users.json")   || [];
  my $tpicks  = jload("$dir/traded_picks.json") || [];

  # league format -> FantasyCalc params
  my @rp = @{ $league->{roster_positions} || [] };
  my $numQbs = (grep { /^(SUPER_FLEX|SF)$/ } @rp) ? 2 : (scalar grep { $_ eq 'QB' } @rp);
  $numQbs = 1 if $numQbs < 1; $numQbs = 2 if $numQbs > 2;
  my $sc  = $league->{scoring_settings} || {};
  my $ppr = defined $sc->{rec} ? ($sc->{rec} + 0) : 1;
  my $teams = $league->{total_rosters} || scalar(@$rosters) || 12;

  my $url = "https://api.fantasycalc.com/values/current?isDynasty=true"
          . "&numQbs=$numQbs&numTeams=$teams&ppr=$ppr";
  print STDERR "$slug: $url\n";
  my $fc = fetch($url);

  my (%bySleeper, %byName, %byPick);
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
    if (($p->{sleeperId} // '') =~ /^FP_(\d{4})_(\d+)/) {          # generic pick FP_2027_1 = 1st
      $byPick{"$1|" . ($2)} = $row->{value};
    } elsif ($p->{sleeperId}) {
      $bySleeper{ $p->{sleeperId} } = $row;
    }
    $byName{ norm($p->{name}) . '|' . lc($p->{position} // '') } //= $row;
  }

  # roster_id -> personId  (via config sleeperName)
  my %uName = map { $_->{user_id} => lc($_->{display_name} // '') } @$users;
  my %sn2id = map { lc($_->{sleeperName}) => $_->{id} } grep { $_->{sleeperName} } @{ $cfg->{people} || [] };
  my %rid2pid;
  for my $r (@$rosters) {
    my $dn = $uName{ $r->{owner_id} } // '';
    $rid2pid{ $r->{roster_id} } = $sn2id{$dn} || "sle_$r->{owner_id}";
  }

  # future picks each roster owns: own picks for next 3 seasons, rounds 1-4,
  # minus traded-away, plus traded-for.
  my @futYears = ($curYear + 1 .. $curYear + 3);
  my %traded;   # "season|round|origRoster" -> currentOwnerRoster
  for my $t (@$tpicks) { $traded{"$t->{season}|$t->{round}|$t->{roster_id}"} = $t->{owner_id}; }
  my %pickList;  # roster_id -> [ {season,round,from} ]
  for my $rid (map { $_->{roster_id} } @$rosters) {
    for my $y (@futYears) {
      for my $rd (1 .. 4) {
        my $owner = $traded{"$y|$rd|$rid"} // $rid;
        push @{ $pickList{$owner} }, { season => $y + 0, round => $rd + 0, from => $rid + 0 };
      }
    }
  }
  my %rid2name = map { $_->{roster_id} => ($sn2id{ $uName{$_->{owner_id}} // '' } || '') } @$rosters;

  # assemble per-person teams
  my %teamsOut;
  for my $r (@$rosters) {
    my $pid = $rid2pid{ $r->{roster_id} } or next;
    my @players;
    for my $plid (@{ $r->{players} || [] }) {
      my $v = $bySleeper{$plid};
      next unless $v;                              # no dynasty market value (deep bench / K / DST)
      push @players, {
        key => norm($v->{name}) . '|' . lc($v->{pos} // ''),
        name => $v->{name}, pos => $v->{pos}, nfl => $v->{nfl}, age => $v->{age},
        value => $v->{value}, posRank => $v->{posRank}, trend => $v->{trend},
      };
    }
    @players = sort { $b->{value} <=> $a->{value} } @players;

    my @picks;
    for my $pk (sort { $a->{season} <=> $b->{season} || $a->{round} <=> $b->{round} } @{ $pickList{ $r->{roster_id} } || [] }) {
      my $val = $byPick{"$pk->{season}|$pk->{round}"} // 0;
      my $ord = $pk->{round} == 1 ? '1st' : $pk->{round} == 2 ? '2nd' : $pk->{round} == 3 ? '3rd' : "$pk->{round}th";
      my $viaPid = ($pk->{from} != $r->{roster_id}) ? ($rid2pid{ $pk->{from} } || undef) : undef;
      push @picks, { label => "$pk->{season} $ord", season => $pk->{season}, round => $pk->{round},
                     via => $viaPid, value => ($val + 0) };
    }
    $teamsOut{$pid} = { players => \@players, picks => \@picks };
  }

  my $out = {
    generated => scalar(gmtime()) . ' UTC',
    source    => 'FantasyCalc',
    asOf      => $curYear + 0,
    format    => { dynasty => \1, numQbs => $numQbs + 0, ppr => $ppr + 0, teams => $teams + 0 },
    teams     => \%teamsOut,
  };
  open my $fh, '>:raw', "$ROOT/bundles/$slug.values.json" or die $!;
  print $fh $J->encode($out); close $fh;
  printf STDERR "  wrote %s.values.json — %d teams, %d FantasyCalc entries (%d bytes)\n",
    $slug, scalar(keys %teamsOut), scalar(@$fc), (-s "$ROOT/bundles/$slug.values.json");
}
