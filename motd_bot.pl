#!/usr/bin/env perl
#
# quaddicted motd bot for twitter
# 10/22/22 - morb
#


use strict;
use warnings;
use utf8;

use lib ".";
use MyLib::ATProto qw( post_media );
use List::Util qw(shuffle);
use HTML::FormatText::Lynx;
use Config::IniFiles;
use Mastodon::Client;
use LWP::UserAgent;
use MIME::Base64;
use XML::Simple;

binmode( STDOUT, ":utf8" );

################################################################
my $mins = $settings->val( 'mastodon', 'ins' ); 
my $mkey = $settings->val( 'mastodon', 'ckey');
my $msec = $settings->val( 'mastodon', 'csec');
my $mat  = $settings->val( 'mastodon', 'at'  );
################################################################
my $mt = Mastodon::Client->new( 
    instance            => $mins,
    client_id           => $mkey,
    client_secret       => $msec,
    access_token        => $mat,
    coerce_entities     => 0,
);

my $xml = XMLin('quaddicted_database.xml');
my $db  = $xml->{"file"};

START:

srand;

my @names = ( keys %$db );
my $entry = ( shuffle(@names) );
my $fn    = "motd.jpg";

my $desc = HTML::FormatText::Lynx->new(
    leftmargin   => 0,
    rightmargin  => 0,
    lynx_options => ['-nolist']
)->format( $db->{$entry}->{"description"} );

my $urlbase = "https://www.quaddicted.com/reviews";
my $ssurl   = $urlbase . "/screenshots/$entry.jpg";
my $enurl   = $urlbase . "/$entry.html"; $enurl =~ (s/\ /+/g);
my $desclen = length $desc;
my $taglen  = 0;
my $tagmax  = 5;
my $tagout  = '';
my $ml      = 250;
my $authors = $db->{$entry}->{"author"};
my $authbuf; 


if (length $authors >= 50) {
    $authbuf = (substr $authors,0,50) . "...";
  } else { 
    $authbuf .= $authors;
}

#dumb tag handler

if ( $db->{$entry}->{'tags'} ) {
    my $test = $db->{$entry}->{'tags'}->{'tag'};
    if ( ref $test ) {
        my @tags = @{ $db->{$entry}->{'tags'}->{'tag'} };
        $taglen = scalar @tags;
        if ($taglen > $tagmax) { $taglen = $tagmax; }
        for ( my $i = 0 ; $i < $taglen ; $i++ ) {
            $tags[$i] =~ s/(\ |-)//g;
            $tagout .= "#" . $tags[$i] . " ";
        }
    }
    else {
        $tagout .= "#" . $test;
    }
}

my $output =
    "Author(s): "
  . $authbuf . "\n"
  . "Title: "
  . $db->{$entry}->{"title"} . "\n"
  . "Date: "
  . $db->{$entry}->{"date"} . "\n";

my $outlen  = length $output;
my $descbuf = substr $desc, 0, ( $ml - ( $outlen + $taglen ) );

if ($outlen + ( length $descbuf ) <= 220 ) {
    $output .= $descbuf . "\n";
}

$outlen = length $output;
$output .= $enurl . "\n";

# bluesky can't handle >300c
if ($outlen + (length $tagout ) + 2 < 300 ) {
    $output .= $tagout;
}

print $output . "\n";
print length $output . "\n";

my $status_update = { status => $output };

unless (fetch($ssurl)) {
    $fn = "no_screenshot.jpg";
}

my $bluesky;

until (defined $bluesky) { 
      $bluesky = post_media({ text => $output,  account => 'mybot', fn => $fn });
  }
eval { my $mm = $mt->upload_media($fn); $mt->post_status($output,{ media_ids => [ $mm->{'id'} ]}) ; };
exit 0;
}
else { 
      goto START;
}

sub fetch {
    my ($file) = @_;
    my $ua     = LWP::UserAgent->new( agent => "quaddicted_motd_bot/0.1" );
    my $req    = HTTP::Request->new( GET => $file );
    my $resp   = $ua->request($req);
    if ( $resp->is_success ) {
        open( my $FH, ">", $fn );
        print $FH $ua->request($req)->content;
        close $FH;
    } else {
        return 0;
  }
}
