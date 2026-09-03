#!/usr/bin/perl
use strict; use warnings;

use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";
my $RAW  = "$ROOT/data/raw/sleeper";
my %SEASONS = ( "2025" => "1179881509322113024", "2026" => "1343022509649330176" );

sub slurp { my ($p)=@_; open my $fh,'<:raw',$p or die "open $p: $!"; local $/; my $c=<$fh>; close $fh; return $c; }
sub slurp_or { my ($p,$d)=@_; return -e $p ? slurp($p) : $d; }

# ---------- 1. slim player map ----------
my %need;
for (split /\n/, slurp("$ROOT/data/needed_player_ids.txt")) { s/\s+//g; $need{$_}=1 if length; }
# team defenses are keyed by team abbreviation in Sleeper rosters/matchups/transactions
$need{$_}=1 for qw(ARI ATL BAL BUF CAR CHI CIN CLE DAL DEN DET GB HOU IND JAX KC LAC LAR LV MIA MIN NE NO NYG NYJ PHI PIT SEA SF TB TEN WAS);
my $players_raw = slurp("$ROOT/data/raw/sleeper_players_nfl.json");
my %pmap;
# also always include team DEFs that show up as 2-3 upper keys
for my $id (keys %need) {
  my $q = quotemeta($id);
  # match "id":{ ... } up to the next top-level key  ,"key":{   (metadata is the only nested obj, shallow)
  if ($players_raw =~ /"$q":(\{.{0,8000}?\})(?=,"[0-9A-Za-z]{2,14}":\{|\}\s*$)/s) {
    my $obj = $1;
    my ($fn) = $obj =~ /"full_name":"([^"]*)"/;
    my ($first) = $obj =~ /"first_name":"([^"]*)"/;
    my ($last)  = $obj =~ /"last_name":"([^"]*)"/;
    my ($pos)   = $obj =~ /"position":"([^"]*)"/;
    my ($tm)    = $obj =~ /"team":"([^"]*)"/;
    my $name = $fn // (join " ", grep { defined && length } ($first,$last));
    $name = $id unless defined $name && length $name;
    $pos //= ""; $tm //= "";
    $pmap{$id} = [$name,$pos,$tm];
  } else {
    $pmap{$id} = [$id,"",""];
  }
}
# JSON-encode the player map by hand (values are simple strings)
sub jstr { my ($s)=@_; $s //= ""; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\n/ /g; return "\"$s\""; }
my @pj;
for my $id (sort keys %pmap) {
  my ($n,$p,$t) = @{$pmap{$id}};
  push @pj, jstr($id).":[".jstr($n).",".jstr($p).",".jstr($t)."]";
}
my $players_json = "{".join(",",@pj)."}";
print STDERR "players in map: ".scalar(@pj)."\n";

# ---------- 2. assemble bundle ----------
my @season_json;
for my $season (sort keys %SEASONS) {
  my $lid = $SEASONS{$season};
  my $d = "$RAW/$lid";
  my @mw; for my $w (1..18) { push @mw, "\"$w\":".slurp_or("$d/matchups/week_$w.json","null"); }
  my @tw; for my $w (1..18) { push @tw, "\"$w\":".slurp_or("$d/transactions/week_$w.json","null"); }
  # draft picks: find draft_*_picks.json files
  my @dp;
  opendir(my $dh,$d); my @files = readdir($dh); closedir($dh);
  for my $f (sort @files) {
    if ($f =~ /^draft_(\d+)_picks\.json$/) { push @dp, "\"$1\":".slurp_or("$d/$f","null"); }
  }
  my $s = "\"$season\":{"
    . "\"league_id\":\"$lid\","
    . "\"league\":".slurp_or("$d/league.json","null").","
    . "\"users\":".slurp_or("$d/users.json","null").","
    . "\"rosters\":".slurp_or("$d/rosters.json","null").","
    . "\"drafts\":".slurp_or("$d/drafts.json","null").","
    . "\"draft_picks\":{".join(",",@dp)."},"
    . "\"traded_picks\":".slurp_or("$d/traded_picks.json","null").","
    . "\"winners_bracket\":".slurp_or("$d/winners_bracket.json","null").","
    . "\"losers_bracket\":".slurp_or("$d/losers_bracket.json","null").","
    . "\"matchups\":{".join(",",@mw)."},"
    . "\"transactions\":{".join(",",@tw)."}"
    . "}";
  push @season_json, $s;
}

my $bundle = "{".join(",",@season_json).",\"players\":$players_json,\"generated_at\":\"".scalar(gmtime())." UTC\"}";

# validate: quick brace balance sanity + try a JSON parse if module present
my $ok = eval { require JSON::PP; JSON::PP::decode_json($bundle); 1 };
if ($ok) { print STDERR "JSON::PP parse: OK\n"; }
else { print STDERR "JSON::PP parse: FAILED or module missing: $@\n"; }

open my $out,'>:raw',"$ROOT/prototype/bundle.json" or die $!;
print $out $bundle; close $out;
print STDERR "wrote prototype/bundle.json (".length($bundle)." bytes)\n";
