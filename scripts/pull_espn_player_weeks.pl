#!/usr/bin/perl
use strict; use warnings; use JSON::PP;
my $j = JSON::PP->new;

use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";
my $LID   = shift(@ARGV) or die "usage: pull_espn_player_weeks.pl <espnLeagueId> <firstYear> <lastYear>
";
my $Y0    = shift(@ARGV) // 2015;
my $Y1    = shift(@ARGV) // 2024;
my $CRED = "C:/Users/cp730/Downloads/ESPN creds.txt";
my $UA   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0 Safari/537.36";

open my $c,'<',$CRED or die "creds: $!";
my @cl = <$c>; close $c;
my ($SWID) = grep { /\{[0-9A-F-]+\}/i } @cl; chomp $SWID; $SWID =~ s/\s//g;
my ($S2)   = grep { length($_) > 60 && !/\{/ } @cl; chomp $S2; $S2 =~ s/\s//g;
die "cred parse failed\n" unless $SWID && $S2;

my $JAR = "C:/Users/cp730/AppData/Local/Temp/claude/espn_pw_jar.txt";
open my $jf,'>',$JAR or die;
print $jf ".espn.com\tTRUE\t/\tTRUE\t0\tSWID\t$SWID\n.espn.com\tTRUE\t/\tTRUE\t0\tespn_s2\t$S2\n";
close $jf;

my $POS = {1=>'QB',2=>'RB',3=>'WR',4=>'TE',5=>'K',16=>'DST',9=>'DL',10=>'LB',11=>'DB',7=>'HC'};

sub fetch {
  my ($url) = @_;
  my $tmp = "C:/Users/cp730/AppData/Local/Temp/claude/espn_pw_resp.json";
  system('curl','-s','--compressed','-H',"User-Agent: $UA",'-b',$JAR,'-o',$tmp,$url);
  local $/; open my $f,'<:raw',$tmp or return undef; my $raw=<$f>; close $f;
  my $x = eval { $j->decode($raw) };
  return ref $x eq 'ARRAY' ? $x->[0] : $x;
}

# per-week applied points for a player, for scoring period $sp
sub week_pts {
  my ($player, $sp) = @_;
  for my $s (@{$player->{stats} || []}) {
    next unless ($s->{scoringPeriodId} // -9) == $sp;
    next unless ($s->{statSourceId}   // -9) == 0;   # actual, not projection
    next unless ($s->{statSplitTypeId}// -9) == 1;   # by scoring period
    return $s->{appliedTotal};
  }
  return undef;
}

my %OUT;     # season -> week -> { pid => [pts, starter, teamId] }
my %PLAYERS; # pid -> [name, pos]
my %COUNT;

for my $y ($Y0..$Y1) {
  my $hist = $y <= 2017;
  for my $sp (1..17) {
    my $url = $hist
      ? "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/leagueHistory/$LID?seasonId=$y&view=mRoster&view=mMatchup&scoringPeriodId=$sp"
      : "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/$y/segments/0/leagues/$LID?view=mBoxscore&scoringPeriodId=$sp";
    my $d = fetch($url);
    unless ($d && ref $d->{schedule} eq 'ARRAY') { print STDERR "  $y wk$sp: no data\n"; next; }
    my $n = 0;
    for my $g (@{$d->{schedule}}) {
      next unless ref $g eq 'HASH';
      # only the week whose matchupPeriod == sp carries the live roster we want,
      # but rosterForCurrentScoringPeriod is filtered to sp regardless; take any game that has it
      for my $side (qw(home away)) {
        my $s = $g->{$side}; next unless ref $s eq 'HASH';
        my $tid = $s->{teamId};
        my $r = $s->{rosterForCurrentScoringPeriod} || $s->{rosterForMatchupPeriod};
        next unless $r && ref $r->{entries} eq 'ARRAY';
        for my $e (@{$r->{entries}}) {
          my $pp = $e->{playerPoolEntry} || {};
          my $pl = $pp->{player} || {};
          my $pid = $pl->{id} // next;
          my $slot = $e->{lineupSlotId} // 20;
          my $starter = ($slot == 20 || $slot == 21) ? 0 : 1;
          my $pts = week_pts($pl, $sp);
          $pts = $pp->{appliedStatTotal} if !defined $pts && ($g->{matchupPeriodId}//0)==$sp;
          next unless defined $pts;
          # keep the row (last write wins; a player appears once per week per team)
          $OUT{$y}{$sp}{$pid} = [ 0 + sprintf('%.2f',$pts), $starter, $tid ];
          $PLAYERS{$pid} ||= [ $pl->{fullName} // "Player $pid", $POS->{ $pl->{defaultPositionId} // 0 } // '' ];
          $n++;
        }
      }
    }
    $COUNT{$y} += $n;
    print STDERR "  $y wk$sp: $n player-rows\n" if $sp == 1 || $sp == 17;
  }
  print STDERR "== $y done: $COUNT{$y} rows ==\n";
}

unlink $JAR;

my $bundle = { league_id => $LID, players => \%PLAYERS, seasons => \%OUT,
               generated_at => scalar(gmtime())." UTC" };
open my $o,'>:raw',"$ROOT/data/espn_player_weeks_$LID.json" or die $!;
print $o $j->encode($bundle);
close $o;
printf STDERR "\nwrote data/espn_player_weeks.json : %d players, %d bytes\n",
  scalar(keys %PLAYERS), (-s "$ROOT/data/espn_player_weeks_$LID.json");
