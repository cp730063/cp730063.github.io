#!/usr/bin/perl
# Pull ESPN's FULL player pool (not just rostered players) per season, with each
# player's full-season stat line. Fills the gap where a player drafted then cut
# mid-season had no value in the bundle (they were never on a year-end roster).
#
#   perl scripts/pull_espn_pool.pl <flb-leagueId> <firstYear> <lastYear>
#
# Writes data/raw/espn/<id>/pool/<year>.json = { year, count, players:[ {id,name,pos,stats} ] }
# (data/ is gitignored — local only.)
use strict; use warnings; use JSON::PP;
use FindBin qw($RealBin);
my $j = JSON::PP->new;
my $ROOT = "$RealBin/..";

my $LID = shift(@ARGV) or die "usage: pull_espn_pool.pl <espnLeagueId> <firstYear> <lastYear>\n";
my $Y0  = shift(@ARGV) // 2008;
my $Y1  = shift(@ARGV) // 2026;
my $CRED = "C:/Users/cp730/Downloads/ESPN creds.txt";
my $UA   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0 Safari/537.36";

open my $c,'<',$CRED or die "creds: $!";
my @cl = <$c>; close $c;
my ($SWID) = grep { /\{[0-9A-F-]+\}/i } @cl; chomp $SWID; $SWID =~ s/\s//g;
my ($S2)   = grep { length($_) > 60 && !/\{/ } @cl; chomp $S2; $S2 =~ s/\s//g;
die "cred parse failed\n" unless $SWID && $S2;

my $JAR = "C:/Users/cp730/AppData/Local/Temp/claude/espn_pool_jar.txt";
open my $jf,'>',$JAR or die; print $jf ".espn.com\tTRUE\t/\tTRUE\t0\tSWID\t$SWID\n.espn.com\tTRUE\t/\tTRUE\t0\tespn_s2\t$S2\n"; close $jf;

my $TMP = "C:/Users/cp730/AppData/Local/Temp/claude/espn_pool_resp.json";
sub fetch_page {
  my ($url, $filter) = @_;
  system('curl','-s','--compressed','-H',"User-Agent: $UA",'-H',"x-fantasy-filter: $filter",'-b',$JAR,'-o',$TMP,$url);
  local $/; open my $f,'<:raw',$TMP or return undef; my $raw=<$f>; close $f;
  my $x = eval { $j->decode($raw) };
  return ref $x eq 'ARRAY' ? $x->[0] : $x;
}

my $outdir = "$ROOT/data/raw/espn/$LID/pool";
mkdir "$ROOT/data/raw/espn/$LID" unless -d "$ROOT/data/raw/espn/$LID";
mkdir $outdir unless -d $outdir;

for my $y ($Y0..$Y1) {
  my $hist = $y <= 2017;   # ESPN's old platform for early years
  my $base = $hist
    ? "https://lm-api-reads.fantasy.espn.com/apis/v3/games/flb/leagueHistory/$LID?seasonId=$y&view=kona_player_info"
    : "https://lm-api-reads.fantasy.espn.com/apis/v3/games/flb/seasons/$y/segments/0/leagues/$LID?view=kona_player_info";

  my %seen;   # id -> {id,name,pos,stats}
  my $offset = 0;
  my $pages  = 0;
  while (1) {
    my $filter = qq({"players":{"limit":1000,"offset":$offset,"sortPercOwned":{"sortPriority":1,"sortAsc":false}}});
    my $d = fetch_page($base, $filter);
    my $players = (ref $d eq 'HASH' && ref $d->{players} eq 'ARRAY') ? $d->{players} : undef;
    last unless $players && @$players;
    $pages++;
    for my $pe (@$players) {
      my $pl = $pe->{player} || {};
      my $id = $pl->{id} // next;
      next if $seen{$id};
      my @c0 = grep { ($_->{statSourceId}//1)==0 && ($_->{statSplitTypeId}//1)==0 } @{ $pl->{stats} || [] };
      my ($blk) = grep { ($_->{seasonId} // $y) == $y } @c0;
      $blk ||= $c0[0];
      next unless $blk && ref $blk->{stats} eq 'HASH' && %{ $blk->{stats} };
      $seen{$id} = { id => $id + 0, name => ($pl->{fullName} // "Player $id"),
                     pos => ($pl->{defaultPositionId} // -1) + 0, stats => $blk->{stats} };
    }
    $offset += 1000;
    last if @$players < 1000;
    last if $offset > 6000;   # safety
  }

  if (!%seen) { print STDERR "  $y: no pool data (skipped)\n"; next; }
  my @rows = map { $seen{$_} } sort { $a <=> $b } keys %seen;
  open my $o,'>:raw',"$outdir/$y.json" or die $!;
  print $o $j->encode({ year => $y + 0, count => scalar(@rows), players => \@rows });
  close $o;
  printf STDERR "  %d: %d players (%d page%s) -> pool/%d.json\n", $y, scalar(@rows), $pages, ($pages==1?'':'s'), $y;
}

unlink $JAR;
print STDERR "done\n";
