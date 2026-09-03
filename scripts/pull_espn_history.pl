#!/usr/bin/perl
# Pull a full ESPN fantasy league's season history -> data/raw/espn/<id>/history/<year>.json
#   perl scripts/pull_espn_history.pl <ffl|flb> <leagueId> <firstYear> <lastYear>
# ffl = football, flb = baseball. Reads ESPN creds from the local file; never echoes them.
use strict; use warnings;
use FindBin qw($RealBin);
use JSON::PP;

my $GAME = shift(@ARGV) || die "usage: pull_espn_history.pl <ffl|flb> <leagueId> <y0> <y1>\n";
my $LID  = shift(@ARGV) || die "need a league id\n";
my $Y0   = shift(@ARGV) // die "need first year\n";
my $Y1   = shift(@ARGV) // $Y0;
$GAME =~ /^(ffl|flb)$/ or die "game must be ffl or flb\n";

my $ROOT = "$RealBin/..";
my $CRED = "C:/Users/cp730/Downloads/ESPN creds.txt";
my $UA   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

open my $c, '<', $CRED or die "creds: $!";
my @cl = <$c>; close $c;
my ($SWID) = grep { /\{[0-9A-F-]+\}/i } @cl;
my ($S2)   = grep { length($_) > 60 && !/\{/ } @cl;
s/\s//g for grep { defined } ($SWID, $S2);
die "cred parse failed\n" unless $SWID && $S2;

my @VIEWS = qw(mSettings mTeam mRoster mMatchup mMatchupScore mStandings mDraftDetail mTransactions2 mStatus);
my $vq = join('&', map { "view=$_" } @VIEWS);

my $dir = "$ROOT/data/raw/espn/$LID/history";
system('mkdir', '-p', $dir) if !-d $dir;   # git-bash mkdir
mkdir "$ROOT/data" unless -d "$ROOT/data";
mkdir "$ROOT/data/raw" unless -d "$ROOT/data/raw";
mkdir "$ROOT/data/raw/espn" unless -d "$ROOT/data/raw/espn";
mkdir "$ROOT/data/raw/espn/$LID" unless -d "$ROOT/data/raw/espn/$LID";
mkdir $dir unless -d $dir;

for my $y ($Y0 .. $Y1) {
  my $url = $y >= 2018
    ? "https://lm-api-reads.fantasy.espn.com/apis/v3/games/$GAME/seasons/$y/segments/0/leagues/$LID?$vq"
    : "https://lm-api-reads.fantasy.espn.com/apis/v3/games/$GAME/leagueHistory/$LID?seasonId=$y&$vq";
  my $tmp = "$ROOT/.pull_$$.json";
  my $rc = system('curl','-s','--compressed','--max-time','40','-A',$UA,
                  '-b',"SWID=$SWID; espn_s2=$S2",'-o',$tmp,$url);
  if ($rc != 0) { warn "  $y: curl failed\n"; unlink $tmp; next; }
  local $/; open my $f,'<:raw',$tmp or do { warn "  $y: no file\n"; next };
  my $raw = <$f>; close $f; unlink $tmp;
  my $d = eval { JSON::PP->new->decode($raw) };
  my $obj = ref $d eq 'ARRAY' ? $d->[0] : $d;
  if (ref $obj ne 'HASH' || !$obj->{settings}) { warn "  $y: no league data\n"; next; }
  open my $o,'>:raw',"$dir/$y.json" or die "write $y: $!";
  print $o $raw; close $o;
  my $s = $obj->{settings} || {};
  printf STDERR "  %s: %-26s  %s  teams=%d members=%d sched=%d picks=%d  (%d bytes)\n",
    $y, ($s->{name}//'?'),
    (($s->{scoringSettings}||{})->{scoringType} // '?'),
    scalar(@{$obj->{teams}||[]}), scalar(@{$obj->{members}||[]}),
    (ref $obj->{schedule} eq 'ARRAY' ? scalar(@{$obj->{schedule}}) : 0),
    scalar(@{ ($obj->{draftDetail}||{})->{picks} || [] }),
    length($raw);
}
print STDERR "done -> $dir\n";
