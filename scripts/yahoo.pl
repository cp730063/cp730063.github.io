#!/usr/bin/perl
# Yahoo Fantasy Sports OAuth2 helper + API explorer.
#
#   perl scripts/yahoo.pl authurl              -> prints a URL to open in your browser
#   perl scripts/yahoo.pl exchange <code>      -> trades the code Yahoo shows you for tokens
#   perl scripts/yahoo.pl refresh              -> refreshes an expired access token
#   perl scripts/yahoo.pl get <api-path>       -> GETs an API path (auto-refreshes as needed)
#
# Example, once you have tokens:
#   perl scripts/yahoo.pl get "users;use_login=1/games;game_codes=mlb?format=json"
#
# Reads your app's Client ID (line 1) and Client Secret (line 2) from:
#   C:/Users/cp730/Downloads/Yahoo creds.txt
# Token cache lives at data/yahoo_tokens.json (gitignored — data/ is never committed).
use strict; use warnings;
use FindBin qw($RealBin);
use JSON::PP;
use MIME::Base64 qw(encode_base64);

my $ROOT    = "$RealBin/..";
my $CREDS   = "C:/Users/cp730/Downloads/Yahoo creds.txt";
my $TOKFILE = "$ROOT/data/yahoo_tokens.json";
my $j       = JSON::PP->new->pretty->canonical;

sub read_creds {
  open my $fh, '<', $CREDS
    or die "Can't read $CREDS: $!\n" .
           "Create it with your Yahoo app's Client ID on line 1 and Client Secret on line 2.\n";
  my @lines = grep { /\S/ } <$fh>;
  close $fh;
  chomp @lines; s/[\r\n]+$//g for @lines;
  die "Need 2 non-blank lines (Client ID, Client Secret) in $CREDS\n" unless @lines >= 2;
  return ($lines[0], $lines[1]);
}

sub save_tokens {
  my ($resp) = @_;
  my $d = eval { JSON::PP->new->decode($resp) };
  die "Yahoo's response wasn't valid JSON:\n$resp\n" unless $d;
  die "Yahoo returned an error:\n" . $j->encode($d) . "\n" if $d->{error};
  $d->{obtained_at} = time();
  mkdir "$ROOT/data" unless -d "$ROOT/data";
  open my $fh, '>', $TOKFILE or die "write $TOKFILE: $!\n";
  print $fh $j->encode($d);
  close $fh;
  print "Saved tokens to $TOKFILE (expires in $d->{expires_in}s)\n";
}

sub load_tokens {
  open my $fh, '<', $TOKFILE or die "No token file yet at $TOKFILE — run 'exchange <code>' first.\n";
  local $/; my $c = <$fh>; close $fh;
  return JSON::PP->new->decode($c);
}

sub do_token_request {
  my (%form) = @_;
  my ($cid, $csecret) = read_creds();
  my $auth = encode_base64("$cid:$csecret", '');
  my $body = join('&', map { "$_=$form{$_}" } keys %form);
  my @cmd = ('curl', '-s', '-X', 'POST', 'https://api.login.yahoo.com/oauth2/get_token',
             '-H', "Authorization: Basic $auth",
             '-H', 'Content-Type: application/x-www-form-urlencoded',
             '-d', $body);
  open my $ph, '-|', @cmd or die "curl failed: $!\n";
  local $/; my $out = <$ph>; close $ph;
  return $out;
}

my ($mode, @args) = @ARGV;
$mode //= '';

if ($mode eq 'authurl') {
  my ($cid) = read_creds();
  print "Open this URL in a browser signed into the Yahoo account that owned the old FBL league:\n\n";
  print "https://api.login.yahoo.com/oauth2/request_auth?client_id=$cid&redirect_uri=oob&response_type=code&language=en-us\n\n";
  print "Approve access, copy the code Yahoo shows you, then run:\n";
  print "  perl scripts/yahoo.pl exchange <code>\n";
}
elsif ($mode eq 'exchange') {
  my $code = $args[0] or die "usage: yahoo.pl exchange <code>\n";
  save_tokens(do_token_request(grant_type => 'authorization_code', redirect_uri => 'oob', code => $code));
}
elsif ($mode eq 'refresh') {
  my $tok = load_tokens();
  save_tokens(do_token_request(grant_type => 'refresh_token', redirect_uri => 'oob', refresh_token => $tok->{refresh_token}));
}
elsif ($mode eq 'get') {
  my $path = $args[0] or die "usage: yahoo.pl get <api-path>\n";
  my $tok = load_tokens();
  # refresh proactively if the access token is more than ~55 minutes old
  if (time() - ($tok->{obtained_at} // 0) > 55 * 60) {
    save_tokens(do_token_request(grant_type => 'refresh_token', redirect_uri => 'oob', refresh_token => $tok->{refresh_token}));
    $tok = load_tokens();
  }
  my $url = "https://fantasysports.yahooapis.com/fantasy/v2/$path";
  my @cmd = ('curl', '-s', '-H', "Authorization: Bearer $tok->{access_token}", $url);
  open my $ph, '-|', @cmd or die "curl failed: $!\n";
  local $/; my $out = <$ph>; close $ph;
  # pretty-print if it's JSON, else dump raw (Yahoo defaults to XML without ?format=json)
  my $d = eval { JSON::PP->new->decode($out) };
  print $d ? $j->encode($d) : $out;
}
else {
  die "usage: yahoo.pl authurl | exchange <code> | refresh | get <api-path>\n";
}
