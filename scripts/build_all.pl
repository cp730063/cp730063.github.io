#!/usr/bin/perl
# Builds every league config in scripts/leagues/*.json and writes the manifest.
use strict; use warnings; use JSON::PP;
my $j = JSON::PP->new;
use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";

opendir(my $ld, "$ROOT/scripts/leagues") or die "no leagues dir: $ROOT/scripts/leagues\n";
my @cfgs = sort map { "$ROOT/scripts/leagues/$_" } grep { /\.json$/ } readdir $ld;
closedir $ld;
die "no league configs\n" unless @cfgs;

my @manifest;
for my $cfgpath (@cfgs) {
  (my $slug = $cfgpath) =~ s{.*/}{}; $slug =~ s/\.json$//;
  print STDERR "=== building $slug ===\n";
  my $rc = system($^X, "$ROOT/scripts/build_bundle2.pl", $slug);
  die "build failed for $slug\n" if $rc != 0;

  local $/; open my $f, '<:raw', "$ROOT/bundles/$slug.json" or die;
  my $b = $j->decode(<$f>); close $f;
  push @manifest, {
    slug => $b->{league}{slug}, label => $b->{league}{name}, type => $b->{league}{type},
    primary => ($b->{league}{primary} ? 1 : 0),
    firstSeason => $b->{league}{firstSeason}, lastSeason => $b->{league}{lastSeason},
    seasons => scalar(grep { $_->{played} } @{$b->{seasons}}),
    hasPlayers => ($b->{league}{hasPlayers} ? \1 : \0), hasTrades => ($b->{league}{hasTrades} ? \1 : \0),
    hasDrafts => ($b->{league}{hasDrafts} ? \1 : \0),
  };
}
# primary league first, then most seasons
@manifest = sort { $b->{primary} <=> $a->{primary} || $b->{seasons} <=> $a->{seasons} || $a->{label} cmp $b->{label} } @manifest;
open my $m, '>:raw', "$ROOT/bundles/leagues.json" or die;
print $m $j->canonical->pretty->encode({ leagues => \@manifest });
close $m;
print STDERR "\nwrote manifest: ", join(", ", map { "$_->{slug} ($_->{seasons} seasons)" } @manifest), "\n";
