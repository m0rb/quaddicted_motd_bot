#!/usr/bin/perl -w
use strict;
use warnings;

use utf8;
use Config::IniFiles;
use Mastodon::Client;
use HTML::TreeBuilder;
use JSON qw(decode_json);
use DateTime::Format::Strptime;
use Unicode::UTF8 qw(encode_utf8);
use LWP::UserAgent;

use lib "/home/morb/motd_bot";
use MyLib::ATProto qw(post_media );
use Data::Dumper;


my $urlroot = "https://www.slipseer.com";
my $index   = "/index.php?resources/categories/maps.1/";
srand;srand;

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
my $fn = "motd.jpg";


START:

# time is in iso8601
my $strp = DateTime::Format::Strptime->new({pattern=>"%FT%T%z"});

# fetch initial landing page for maps
my $get = HTML::TreeBuilder->new_from_url($urlroot.$index);

# fetch a random map page from slipseer then update get
$get = HTML::TreeBuilder->new_from_url(
 $urlroot.$index.'&page='.int(rand(&pages($get)))
);


# pick and preserve a random link
my $link    = &randomlink($get);

# build a tree from it
my $tree    = HTML::TreeBuilder->new_from_url($link);

# extract elements
my @tags    = &tags($tree);
my @desc    = &description($tree);
my $shot    = &meta($tree);


my $decoded = decode_json(&encode_utf8($desc[0][0])) or goto START;
# build output buffer

my $target    = 219;
my $countdown = $target;
my ($outbuf,$authbuf,$tagbuf);
my ($name,$headline,$alt,$description,$version,$date,$author) = (
  $decoded->{mainEntity}{headline},
  $decoded->{mainEntity}{headline},
  $decoded->{mainEntity}{alternativeHeadline},
  $decoded->{mainEntity}{description},
  $decoded->{mainEntity}{version},
  $decoded->{mainEntity}{dateCreated},
  $decoded->{mainEntity}{author} 
);
chomp $description;



$countdown = $countdown - (length $name);

foreach ($author->{name}) {
      $countdown = $countdown - (length $_);
      $authbuf .= "$_ "
}

if (length $authbuf > 75) {
  $authbuf = substr($authbuf,0,75) . "...";
}

$outbuf .= "Author(s): ".$authbuf."\n";
($name) ? $outbuf .= "Title: $name\n" : undef;

for (@tags) {
      $tagbuf .= "\#$_ ";
}
$tagbuf .= "\#slipseer\n";
my $taglen = length $tagbuf;

$taglen += ( ( scalar @tags ) * 2 );
$countdown = $countdown - $taglen;

if ((length $description) > ( $countdown - 3 )) {
  $description = substr($description,0,($countdown - 3)) .  "…" ;
}

($alt) ? $outbuf .= "$alt\n" : undef;
$outbuf .= "\n".$link."\n\n$tagbuf";

unless (fetch($shot)) {
  `cp no_screenshot.jpg $fn`;
}

`convert $fn $fn`;
my $res = imgres($fn);
my $bluesky;

until (defined $bluesky) {
  $bluesky = post_media({ 
              text => $outbuf, 
              account => 'mybot', 
              fn => $fn, 
              aspectRatio => $res 
  });
}

eval { 
  my $mm = $mt->upload_media($fn); 
  $mt->post_status($outbuf,{ media_ids => [ $mm->{'id'} ]}) ; 
};


sub imgres {
  my @fileinfo = split(",\ ",`file @_`);
  chomp @fileinfo;
  my $res = $fileinfo[(scalar(@fileinfo) - 2)];
  return $res;
}

sub description {
  my $in = shift;
  my $json = $in->look_down(_tag=>'script', type=>'application/ld+json');
  return $json->{_content};
}

sub pages {
  my $in = shift; 
  my @out;
  foreach my $a ($in->look_down('_tag', 'a')) {
    if ($a->attr('href')) {
     if ($a->attr('href') =~ /page=/ ) {
      push @out, $a->attr('href');
      }
    }
  }
  @out = uniq(@out);
  $out[$#out] =~ s/.*page=//;
  return $out[$#out];
}

sub tags {
  my $in = shift; 
  my @out;
  foreach my $a ($in->look_down('_tag', 'a')) {
    if ($a->attr('href')) {
    if ($a->attr('href') =~ /\?tags/ ) {
      push @out, $a->attr('href');
      }
    }
  }
  @out = uniq(@out);
  foreach (@out) {
    $_ =~ s/.*\?tags\///;
    $_ =~ s/\//\ /;
  }
  return @out;
}

sub meta {
  my $in = shift; 
  my @out;
  my $sref = $in->look_down(_tag=>'meta',property=>'og:image');
  my $ret;
  if ($sref->{'content'}) {
       $ret = $sref->{'content'};
  }
  return $ret;
}

sub randomlink {
  my $in = shift; 
  my @out;
  foreach my $a ($in->look_down('_tag', 'a')) {
    if  ($a->attr('href')) {
      if (($a->attr('href') =~ /resource/ ) && 
         ( $a->attr('href') !~ /categories/ )) {
          push @out, $urlroot.$a->attr('href');
      }
    }
  }
  @out = uniq(@out);
  #remove the top three anchors
  for(0..2) { shift @out; }
  return rr(@out);
}

sub rr {
  my @input  = @_;
  my $length = $#input + 1;
  $length = rand($length);
  $length = int $length;
  return $input[$length];
}

sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
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
