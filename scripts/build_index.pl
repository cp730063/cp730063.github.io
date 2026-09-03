#!/usr/bin/perl
# Injects every league bundle + the manifest into prototype/template.html -> ./index.html
# (repo-root index.html is what GitHub Pages serves; also mirrored to prototype/index.html)
use strict; use warnings; use JSON::PP;
my $J = JSON::PP->new;
use FindBin qw($RealBin);
my $ROOT = "$RealBin/..";

sub slurp { local $/; open my $f,'<:raw',$_[0] or die "open $_[0]: $!"; my $c=<$f>; close $f; $c }

my %bundles;
opendir(my $bd, "$ROOT/prototype/bundles") or die "no bundles dir: $ROOT/prototype/bundles\n";
for my $fn (sort readdir $bd) {
  next unless $fn =~ /\.json$/;
  (my $slug = $fn) =~ s/\.json$//;
  next if $slug eq 'leagues';
  $bundles{$slug} = $J->decode(slurp("$ROOT/prototype/bundles/$fn"));
}
closedir $bd;
die "no bundles\n" unless %bundles;
my $manifest = -e "$ROOT/prototype/bundles/leagues.json" ? $J->decode(slurp("$ROOT/prototype/bundles/leagues.json")) : { leagues => [] };

my $payload = $J->encode({ manifest => $manifest, bundles => \%bundles });
$payload =~ s{</script>}{<\\/script>}g;   # safety

my $tpl = slurp("$ROOT/prototype/template.html");
$tpl =~ s/__FM_JSON__/$payload/ or die "marker __FM_JSON__ not found in template\n";
for my $out ("$ROOT/index.html", "$ROOT/prototype/index.html") {
  open my $o,'>:raw',$out or die "write $out: $!";
  print $o $tpl; close $o;
}

printf STDERR "index.html %d bytes  (leagues: %s)\n",
  (-s "$ROOT/index.html"), join(", ", sort keys %bundles);
