#!/usr/bin/perl -C -w
use strict;
use warnings;
use utf8;

use Config::IniFiles;
use LWP::UserAgent;
use HTML::TableExtract;
use HTML::LinkExtor;

use Mastodon::Client;
use lib "/home/morb/motd_bot";
use MyLib::ATProto qw(post_media );

use Data::Dumper;
use JSON::Parse 'parse_json';


my $site   = "https://www.quaddicted.com/";
my $ssroot = $site."files/quaddicted-images/by-sha256/";
my $fn = "motd_newdb.jpg";

my $ua      = LWP::UserAgent->new(agent=>"motdbot/2.0");

################################################################
my $settings = Config::IniFiles->new( -file => "motd.ini" );
my $mins = $settings->val( 'mastodon', 'ins'  ) or die;
my $mkey = $settings->val( 'mastodon', 'ckey' ) or die;
my $msec = $settings->val( 'mastodon', 'csec' ) or die;
my $mat  = $settings->val( 'mastodon', 'at'   ) or die;
################################################################


my $mt    = Mastodon::Client->new( 
    instance        => $mins,
    client_id       => $mkey,
    client_secret   => $msec,
    access_token    => $mat,
    coerce_entities => 0,
);

my $fetch   = $ua->get($site."db/v1/");
my $content = $fetch->{_content};
utf8::decode($content);
my $te = HTML::TableExtract->new(headers=>["SHA256","Release","Author",
                                                  "Filename","Title"]);
my $le = HTML::LinkExtor->new;

$te->parse($content);

my %db; my $dbref = \%db;

foreach my $ts ($te->tables) {
  foreach my $row ($ts->rows) {
  my ($shasum,$date,$author,$filename,$title) = @$row;
  $date     =~ s/^\s+|\s+$|\n//g; $author   =~ s/^\s+|\s+$|\n//g;
  $filename =~ s/^\s+|\s+$|\n//g; $title    =~ s/^\s+|\s+$|\n//g;
  $dbref->{$shasum}{date}     = $date;
  $dbref->{$shasum}{author}   = $author;
  $dbref->{$shasum}{filename} = $filename;
  $dbref->{$shasum}{title}    = $title;
  }
}

my @sha =  keys(%db);
my $pick = @sha[int(rand(scalar @sha))];

$le->parse($content);
my @links = $le->links;

my ($files,$maps,$sha256,$pre,$date,@tags);


for(my $i=0;$i<(scalar @links);$i++) {
 $links[$i][2] =~ /files\/$pick/ and $files = $site.$links[$i][2];
 $links[$i][2] =~ /maps\/$pick/  and $maps  = $site.$links[$i][2];
}

$fetch = $ua->get($files);
my $json = parse_json($fetch->{_content});
$sha256 = $json->{sha256};
$pre    = substr($sha256,0,2);

foreach my $tag (@{$json->{tags}}) {
      my $tmp; my $datetmp;
      $tmp = $tag if $tag =~ /theme=|type=/;
      $tmp and $tmp =~ s/theme=|type=//gi;
      $tmp and push @tags,"#$tmp";
      $datetmp = $tag if $tag =~ /date/;
      $datetmp and $datetmp   =~ s/release_date=//gi;
      $datetmp and $date = $datetmp;
}

my $ml = 250;
my $abuf = $db{$pick}{author};

if (length $abuf >= 50) {
      $abuf = (substr $abuf,0,50) . "...";
}

my $descbuf = "$json->{description}\n";
my $tagbuf = join(" ",@tags);

my $msg;

$msg .= "Title: $db{$pick}{title}\n";
$msg .= "Author(s): $abuf\n";
$msg .= "Date: $date\n";

$descbuf = substr($descbuf,0,($ml - (length $msg) + (length $tagbuf) ));

if ( (length $msg) + (length $descbuf) <= 220 ) {
      $msg .= $descbuf;
}

$msg .= "\n$maps\n\n";

$msg .= $tagbuf;

print "$msg\n";

my $img = $db{$pick}{filename}; $img =~ s/zip$/jpg/ig;
my $ss  = $ssroot.$pre."/".$sha256."/".$img;
print "$ss\n";

unless (fetch($ss)) {
      `cp no_screenshot.jpg $fn`;
}

my $res = imgres($fn);
my $bluesky;

until (defined $bluesky) {
$bluesky = post_media({ text => $msg, account => 'mybot', fn => $fn, aspectRatio => $res });
print Dumper($bluesky);
}

eval { my $mm = $mt->upload_media($fn); $mt->post_status($msg,{ media_ids => [ $mm->{'id'} ]}) ; };

sub imgres {
  my @fileinfo = split(",\ ",`file @_`);
  chomp @fileinfo;
  my $res = $fileinfo[(scalar(@fileinfo) - 2)];
  return $res;
}

sub fetch {
      my ($file) = @_;
      my $ua     = LWP::UserAgent->new( agent => "quaddicted_motd_bot/2.0" );
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
