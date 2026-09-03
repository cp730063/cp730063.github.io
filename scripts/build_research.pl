#!/usr/bin/perl
# Fetch the Research-tab feeds + FantasyCalc value movers -> bundles/research.json
# Core Perl only (JSON::PP, Time::Local, POSIX) so it runs unmodified on CI.
use strict; use warnings;
use FindBin qw($RealBin);
use JSON::PP;
use Time::Local qw(timegm);
use POSIX qw(strftime);
use Encode qw(decode);

my $ROOT = "$RealBin/..";
my $J = JSON::PP->new->canonical(1)->utf8->pretty(0);
my $UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
       . 'Chrome/124.0 Safari/537.36 FantasyMags/1.0 (+https://cp730063.github.io)';

# ---- article sources (RSS/Atom) ------------------------------------------------
my @SOURCES = (
  # one NFL news wire (PFT is the fullest/fastest); the rest is fantasy analysis.
  { key=>'pft',          name=>'Pro Football Talk', home=>'https://www.nbcsports.com/nfl/profootballtalk',
    feed=>'https://www.nbcsports.com/profootballtalk.rss' },
  { key=>'fantasypros',  name=>'FantasyPros',       home=>'https://www.fantasypros.com/nfl/',
    feed=>'https://www.fantasypros.com/rss/' },
  { key=>'dynastynerds', name=>'Dynasty Nerds',     home=>'https://www.dynastynerds.com/',
    feed=>'https://www.dynastynerds.com/feed/' },
);
my $PER_SOURCE = 6;

# ---- helpers -----------------------------------------------------------------
sub fetch {
  my ($url) = @_;
  my $tmp = "$ROOT/.research_$$.tmp";
  my $rc = system('curl','-sL','--compressed','--max-time','25','-A',$UA,'-o',$tmp,$url);
  my $body;
  if ($rc == 0 && open my $f, '<:raw', $tmp) { local $/; $body = <$f>; close $f; }
  unlink $tmp;
  return undef unless $body && length($body) > 200;
  $body =~ s/^\x{EF}\x{BB}\x{BF}//;                     # strip UTF-8 BOM
  my $txt = eval { decode('UTF-8', $body, Encode::FB_CROAK) };
  return defined $txt ? $txt : decode('cp1252', $body); # fall back to Windows-1252

}

my %ENT = ( amp=>'&', lt=>'<', gt=>'>', quot=>'"', apos=>"'", nbsp=>' ',
  hellip=>"\x{2026}", mdash=>"\x{2014}", ndash=>"\x{2013}",
  rsquo=>"\x{2019}", lsquo=>"\x{2018}", rdquo=>"\x{201D}", ldquo=>"\x{201C}", amp39=>"'" );
sub ent {
  my $s = shift; return '' unless defined $s;
  $s =~ s/&#x([0-9a-fA-F]+);/chr(hex $1)/ge;
  $s =~ s/&#(\d+);/$1 < 0x110000 ? chr($1) : ''/ge;
  $s =~ s/&([a-zA-Z][a-zA-Z0-9]*);/exists $ENT{lc $1} ? $ENT{lc $1} : "&$1;"/ge;
  return $s;
}
sub strip {
  my $s = shift; return '' unless defined $s;
  $s =~ s/<!\[CDATA\[(.*?)\]\]>/$1/gs;
  $s =~ s/<[^>]+>/ /g;
  $s = ent($s);
  $s =~ s/\s+/ /g; $s =~ s/^\s+|\s+$//g;
  return $s;
}
sub excerpt {
  my $s = strip(shift); return '' unless length $s;
  return $s if length($s) <= 210;
  my $cut = substr($s, 0, 210); $cut =~ s/\s+\S*$//;
  return $cut . "\x{2026}";
}
sub tag1 {  # first <tag ...>inner</tag>
  my ($xml, $t) = @_;
  return undef unless $xml =~ m{<\Q$t\E\b[^>]*>(.*?)</\Q$t\E>}is;
  my $v = $1; $v =~ s/<!\[CDATA\[(.*?)\]\]>/$1/gs; return $v;
}

my %MON = (jan=>0,feb=>1,mar=>2,apr=>3,may=>4,jun=>5,jul=>6,aug=>7,sep=>8,oct=>9,nov=>10,dec=>11);
sub parse_date {
  my $d = shift; return 0 unless defined $d; $d =~ s/^\s+|\s+$//g;
  if ($d =~ /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?\s*(Z|[+-]\d{2}:?\d{2})?/) {
    my ($Y,$Mo,$Da,$H,$Mi,$S,$tz) = ($1,$2,$3,$4,$5,$6//0,$7//'Z');
    my $e = eval { timegm($S,$Mi,$H,$Da,$Mo-1,$Y-1900) }; return 0 unless defined $e;
    if (($tz//'') =~ /^([+-])(\d{2}):?(\d{2})$/) { $e -= ($2*3600+$3*60) * ($1 eq '-' ? -1 : 1); }
    return $e;
  }
  if ($d =~ /(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{2,4})?/) {
    my ($Da,$Mon,$Y,$H,$Mi,$S,$tz) = ($1,lc$2,$3,$4,$5,$6//0,$7//'GMT');
    my $mo = $MON{$Mon}; return 0 unless defined $mo;
    my $e = eval { timegm($S,$Mi,$H,$Da,$mo,$Y-1900) }; return 0 unless defined $e;
    if (($tz//'') =~ /^([+-])(\d{2})(\d{2})$/) { $e -= ($2*3600+$3*60) * ($1 eq '-' ? -1 : 1); }
    return $e;
  }
  return 0;
}

sub parse_feed {
  my ($xml, $max, $want_author) = @_;
  my @out;
  my @chunks = $xml =~ m{<(?:item|entry)\b[^>]*>(.*?)</(?:item|entry)>}gis;
  for my $c (@chunks) {
    my $title = strip(tag1($c,'title'));
    next unless length $title;
    my $link;
    if ($c =~ m{<link\b[^>]*\bhref="([^"]+)"}i)          { $link = $1 }
    elsif (defined(my $l = tag1($c,'link')))             { $link = strip($l) }
    next unless $link && $link =~ m{^https?://};
    $link =~ s/&amp;/&/g;
    my $raw = tag1($c,'pubDate') // tag1($c,'published') // tag1($c,'updated')
           // tag1($c,'dc:date') // tag1($c,'date');
    my $desc = tag1($c,'description') // tag1($c,'summary') // tag1($c,'content:encoded') // tag1($c,'content');
    my $img;
    if    ($c =~ m{<media:(?:content|thumbnail)\b[^>]*\burl="([^"]+)"}i)              { $img = $1 }
    elsif ($c =~ m{<enclosure\b[^>]*\burl="([^"]+)"[^>]*\btype="image}i)             { $img = $1 }
    elsif ($c =~ m{<enclosure\b[^>]*\btype="image[^"]*"[^>]*\burl="([^"]+)"}i)       { $img = $1 }
    elsif (defined $desc && $desc =~ m{<img\b[^>]*\bsrc="([^"]+)"}i)                 { $img = $1 }
    $img =~ s/&amp;/&/g if $img;
    my %row = ( title=>$title, link=>$link, epoch=>parse_date($raw)+0, excerpt=>excerpt($desc) );
    $row{image} = $img if $img && $img =~ m{^https?://};
    if ($want_author) {
      my $a = tag1($c,'author'); $a = tag1($a,'name') if defined $a && $a =~ /<name>/i;
      $row{author} = strip($a) if defined $a && length strip($a);
    }
    push @out, \%row;
  }
  @out = sort { $b->{epoch} <=> $a->{epoch} } @out;
  return [ @out[0 .. ($#out < $max-1 ? $#out : $max-1)] ];
}

# ---- FantasyCalc value movers ----------------------------------------------
sub movers {
  my ($is_dyn) = @_;
  my $url = 'https://api.fantasycalc.com/values/current?isDynasty=' . ($is_dyn ? 'true' : 'false')
          . '&numQbs=1&numTeams=12&ppr=1';
  my $raw = fetch($url) or return { risers=>[], fallers=>[] };
  my $arr = eval { JSON::PP->new->decode($raw) };
  return { risers=>[], fallers=>[] } unless ref $arr eq 'ARRAY';
  my $floor = $is_dyn ? 1500 : 700;   # keep it to draft-relevant players, not waiver lottery tickets
  my @pl = grep {
    my $p = $_->{player} || {};
    my $val = ($_->{value} || $_->{redraftValue} || 0);
    ($p->{name}//'') ne '' && ($p->{position}//'') ne '' && ($p->{position}//'') ne 'PICK'
      && ($p->{name}//'') !~ /^\d{4}\s+(?:Round|Pick|R\d)/i
      && $val >= $floor
      && abs($_->{trend30Day} || 0) <= $val   # drop data artifacts (a move bigger than the whole value)
  } @$arr;
  my $mk = sub {
    my $v = shift; my $p = $v->{player} || {};
    my $val = ($v->{value} || $v->{redraftValue} || 0) + 0;
    my $tr  = ($v->{trend30Day} || 0) + 0;
    my $pct = $val ? int(100*$tr/$val + ($tr<0 ? -0.5 : 0.5)) : 0;
    $pct = 99 if $pct > 99; $pct = -99 if $pct < -99;
    return { name=>$p->{name}, pos=>$p->{position}, team=>($p->{maybeTeam}//''),
             value=>$val, trend=>$tr, pct=>$pct };
  };
  my @up   = sort { ($b->{trend30Day}||0) <=> ($a->{trend30Day}||0) } @pl;
  my @down = reverse @up;
  return {
    risers  => [ map { $mk->($_) } grep { ($_->{trend30Day}||0) > 0 } @up[0 .. ($#up < 7 ? $#up : 7)] ],
    fallers => [ map { $mk->($_) } grep { ($_->{trend30Day}||0) < 0 } @down[0 .. ($#down < 7 ? $#down : 7)] ],
  };
}

# ---- run ------------------------------------------------------------------
my @src_out;
for my $s (@SOURCES) {
  my $xml = fetch($s->{feed});
  my $items = $xml ? parse_feed($xml, $PER_SOURCE, 0) : [];
  printf STDERR "  %-13s %s -> %d items\n", $s->{key}, ($xml ? 'ok' : 'FETCH FAILED'), scalar @$items;
  push @src_out, { key=>$s->{key}, name=>$s->{name}, home=>$s->{home}, items=>$items };
}

my $reddit_xml = fetch('https://www.reddit.com/r/DynastyFF/.rss');
my $reddit_items = $reddit_xml ? parse_feed($reddit_xml, 12, 1) : [];
printf STDERR "  %-13s %s -> %d items\n", 'reddit', ($reddit_xml ? 'ok' : 'FETCH FAILED'), scalar @$reddit_items;

my $mv_dyn = movers(1);
my $mv_red = movers(0);
printf STDERR "  movers        dynasty %d/%d  redraft %d/%d\n",
  scalar @{$mv_dyn->{risers}}, scalar @{$mv_dyn->{fallers}},
  scalar @{$mv_red->{risers}}, scalar @{$mv_red->{fallers}};

my $out = {
  generated => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime()),
  sources   => \@src_out,
  reddit    => { name=>'r/DynastyFF', home=>'https://www.reddit.com/r/DynastyFF/', items=>$reddit_items },
  movers    => { dynasty=>$mv_dyn, redraft=>$mv_red },
};

open my $o, '>:raw', "$ROOT/bundles/research.json" or die "write research.json: $!";
print $o $J->encode($out);
close $o;
printf STDERR "wrote bundles/research.json (%d bytes)\n", -s "$ROOT/bundles/research.json";
