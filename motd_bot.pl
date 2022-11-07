#!/usr/bin/env perl
#
# quaddicted motd bot for twitter
# 10/22/22 - morb
#


use strict;
use warnings;
use utf8;

use List::Util qw(shuffle);
use HTML::FormatText::Lynx;
use Config::IniFiles;
use LWP::UserAgent;
use MIME::Base64;
use Net::Twitter;
use XML::Simple;

binmode( STDOUT, ":utf8" );

################################################################
my $settings = Config::IniFiles->new( -file => "motd.ini" );
my $ckey = $settings->val( 'twitter', 'ckey' );
my $csec = $settings->val( 'twitter', 'csec' );
my $at   = $settings->val( 'twitter', 'at'   );
my $asec = $settings->val( 'twitter', 'asec' );
################################################################
my $nt = Net::Twitter->new(
    traits              => [qw/API::RESTv1_1/],
    consumer_key        => $ckey,
    consumer_secret     => $csec,
    access_token        => $at,
    access_token_secret => $asec,
    ssl                 => '1',
);
die unless $nt->authorized;

my $xml = XMLin('quaddicted_database.xml');
my $db  = $xml->{"file"};

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
my $enurl   = $urlbase . "/$entry.html";
my $desclen = length $desc;
my $taglen  = 0;
my $tagmax  = 8;
my $tagout  = '';
my $ml      = 256;
my $authors = $db->{$entry}->{"author"};
my $authbuf; 


if (length $authors >= 75) {
    $authbuf = (substr $authors,0,75) . "...";
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

if ($outlen <= 250) {
    $output .= $descbuf . "\n";
}

$output .= $enurl . "\n" . $tagout;

print $output . "\n";
print length $output . "\n";

my $status_update = { status => $output };

unless (&fetch($ssurl)) {
    $fn = "no_screenshot.jpg";
}
$status_update->{media_ids} = &chunklet;

$nt->update($status_update);

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

sub chunklet {
    die unless $nt->authorized;
    my $fs   = -s $fn;
    my $si   = 0;
    my $init = $nt->upload(
        { command => 'INIT', media_type => 'tweet_image', total_bytes => $fs } )
      ;
    my $media_id = $init->{media_id};
    open( IMAGE, $fn ) ;
    binmode IMAGE;

    while ( read( IMAGE, my $chunk, 1048576 ) ) {
        my $file = [
            undef, 'media',
            Content_Type => 'form-data',
            Content      => encode_base64($chunk)
        ];
        eval {
            $nt->upload(
                {
                    command       => 'APPEND',
                    media_id      => $media_id,
                    segment_index => $si,
                    media_data    => $file
                }
            );
        };
        $si += 1;
    }
    close(IMAGE);
    $nt->upload( { command => 'FINALIZE', media_id => $media_id } );
    #    if ($md) {
    #    $nt->create_media_metadata(
    #        { media_id => $media_id, alt_text => { text => $md } } );
    #}
    return ($media_id);
}
