#!/usr/bin/perl
# Injects only the league MANIFEST into prototype/template.html -> ./index.html.
# Per-league bundle data lives in bundles/<slug>.json and is fetched on demand by the page.
use strict; use warnings; use JSON::PP;
my $J = JSON::PP->new->canonical(1);
use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";

sub slurp { local $/; open my $f,'<:raw',$_[0] or die "open $_[0]: $!"; my $c=<$f>; close $f; $c }

my $manifest = -e "$ROOT/bundles/leagues.json"
  ? $J->decode(slurp("$ROOT/bundles/leagues.json"))
  : { leagues => [] };
die "no leagues in manifest\n" unless @{ $manifest->{leagues} || [] };

# cache-busting version stamp for bundle fetches (changes every build)
my @t = gmtime();
my $version = sprintf("%04d%02d%02d%02d%02d%02d", $t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]);

my $payload = $J->encode({ manifest => $manifest, version => $version });
$payload =~ s{</script>}{<\\/script>}g;   # safety

my $tpl = slurp("$ROOT/prototype/template.html");
$tpl =~ s/__FM_JSON__/$payload/ or die "marker __FM_JSON__ not found in template\n";
open my $o,'>:raw',"$ROOT/index.html" or die "write $ROOT/index.html: $!";
print $o $tpl; close $o;

printf STDERR "index.html %d bytes  ·  v%s  ·  leagues: %s\n",
  (-s "$ROOT/index.html"), $version,
  join(", ", map { $_->{slug} } @{ $manifest->{leagues} });
