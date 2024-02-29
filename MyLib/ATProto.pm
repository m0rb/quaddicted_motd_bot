#!/usr/bin/perl
#
# This is a modified version of the ATProto perl module by William Shunn
#
# https://betterprogramming.pub/building-a-perl-module-for-posting-to-bluesky-social-92fc732fc297 


package MyLib::ATProto;

use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw( post_bluesky post_blob post_media post_avatar get_profile );
use Data::Dumper;
use Config::File     qw( read_config_file );
use DateTime;
use JSON             qw( encode_json decode_json );
use LWP::UserAgent;
use URI;
use MyLib::Constants qw( CREATESESSION CREATERECORD PUTRECORD RESOLVEHANDLE
                         POSTBLOB FEEDPOST MEDIAPOST FACETLINK FACETMENTION
                         FACETTAG GETPROFILE BSCONFIGFILE BSUSERAGENT BSMAXLENGTH );

### EXPORTED METHODS ###

# post_bluesky( $args )
# Post a text string to Bluesky Social as a new update
# $args: hash reference
#    account => string (req), name of field group from config file
#    text => string (req), 300 char limit, text of update to post
# return: ref to HTTP::Response object containing post results

sub post_bluesky {
  my $args = shift || {};
  my $account = $args->{account} || die "bluesky account missing\n";
  my $text = $args->{text} || die "status text missing\n";
  die "status text too long\n" if length($text) > BSMAXLENGTH;

  # open connection to host
  my $bs = get_connection({ account => $account });
  # parse text for URIs and mentions
  my $facets = get_facets({ text => $text, bs => $bs });
  # build JSON and post to com.atproto.repo.createRecord endpoint
  my $json = encode_json({
    repo => $bs->{did},
    collection => FEEDPOST,
    record => {
      text => $text,
      facets => $facets,
      createdAt => &get_iso_string,
    },
  });
  my $response = $bs->{ua}->post(
    "https://$bs->{host}/xrpc/${\CREATERECORD}",
    Content_Type => 'application/json',
    Content => $json,
  );
  $response
}

# Exported additions for motd_bot by morb

# post_media 
# 
# this was my solution; @shunn.net came up with a better one :)
#
# https://betterprogramming.pub/posting-images-to-bluesky-social-with-perl-ea5351dfa2c1

sub post_media {
  my $args = shift || {};
  my $account = $args->{account} || die "bluesky account missing\n";
  my $fn = $args->{fn} || die "no filename\n";
  my $text = $args->{text} || "";
  my $filetype = "jpeg";
    if ($fn =~ /png$/i ) { $filetype = "png"; }
    if ($fn =~ /gif$/i ) { $filetype = "gif"; }
  my $blobref = post_blob({ account => $account, fn => $fn, filetype => $filetype }) || die "blobref\n";
  my $blobret = decode_json($blobref->decoded_content) || die "json\n";
  my $link = $blobret->{blob}{ref}{'$link'} || die "link\n";
  my $bs = get_connection({ account => $account });
  my $facets = get_facets({ text => $text, bs => $bs });
  my $json = encode_json({
    repo => $bs->{did},
    collection => FEEDPOST,
    record => {
      text => $text,
      facets => $facets,
      createdAt => &get_iso_string,
      embed => { 
         '$type' => "app.bsky.embed.images", 
        'images' => [ 
              { 'alt' => "", 'image' => {'$type' => 'blob', 
                'ref' => { '$link' => $link }, 
                 mimeType => "image/$filetype", size => 0 } 
              } 
        ]
      }, 
    },
  });
  my $response = $bs->{ua}->post(
    "https://$bs->{host}/xrpc/${\CREATERECORD}",
    Content_Type => 'application/json',
    Content => $json,
  );
  $response
}

# post_avatar - change the account's avatar

sub post_avatar {
  my $args = shift || {};
  my $account = $args->{account} || die "bluesky account missing\n";
  my $cfg = get_config({ file => BSCONFIGFILE, key => $account });
  my $fn = $args->{fn} || die "no filename\n";
  my $filetype = "jpeg";
    if ($fn =~ /png$/i ) { $filetype = "png"; }
    if ($fn =~ /gif$/i ) { $filetype = "gif"; }
  my $blobref = post_blob({ account => $account, fn => $fn, filetype => $filetype }) || die "blobref\n";
  my $blobret = decode_json($blobref->decoded_content) || die "json\n";
  my $link = $blobret->{blob}{ref}{'$link'} || die "link\n";
  my $bs = get_connection({ account => $account });
  my $facets = get_facets({ bs => $bs });
  my $prev = get_profile({ account => $account, 
        actor => $cfg->{uid}});
  my $json = encode_json({
    collection => "app.bsky.actor.profile",
    record => {
      '$type' => "app.bsky.actor.profile",
      avatar => { '$type' => "blob", 
                mimeType => "image/$filetype", 
                ref => { '$link' => $link },
                size => 0
      },
      banner => { '$type' => "blob",
            mimeType => "image/jpeg",
            ref => { '$link' => $prev->{banner} },
            size => 0
      },
      description => $prev->{description},
      displayName => $prev->{displayName},
    },
    repo => $bs->{did},
    rkey => "self"
  });
  my $response = $bs->{ua}->post(
    "https://$bs->{host}/xrpc/${\PUTRECORD}",
    Content_Type => 'application/json',
    Content => $json,
  );
  $response
}

### PRIVATE METHODS ###


# get_connection( $args )
# Initialize a LWP::UserAgent object authorized to access Bluesky host
# $args: hash reference
#    account => string, name of field group from config file
# return: hash reference
#    ua => ref to LWP::UserAgent initialized with default auth header
#    did => DID string identifying target account
#    host => domain name of host server

sub get_connection {
  my $args = shift || {};
  my $account = $args->{account};

  # get info from config file and build login JSON
  my $cfg = get_config({ file => BSCONFIGFILE, key => $account })
    || die "config not found for $account\n";
  my $json = encode_json({
    identifier => $cfg->{uid},
    password => $cfg->{pwd},
  });

  # initialize new LWP::UserAgent and open new session with host
  my $ua = LWP::UserAgent->new( agent => BSUSERAGENT );
  my $response = $ua->post(
    "https://$cfg->{host}/xrpc/${\CREATESESSION}",
    Content_Type => 'application/json',
    Content => $json
  );
  die $response->status_line . "\n" if !$response->is_success;

  # parse relevant fields from response content
  my $content = decode_json($response->decoded_content);
  my $did = $content->{did};
  my $access_jwt = $content->{accessJwt};

  # add access JWT to agent as default auth header and return hash ref
  $ua->default_header('Authorization' => 'Bearer ' . $access_jwt);
  {
    ua => $ua,
    did => $did,
    host => $cfg->{host},
  }
}

# get_config( $args )
# Convenience wrapper for Config::File::read_config_file()
# $args: hash reference
#    file => string (req), full path to configuration file
#    key => string (req), identifier of field group from config file 
# return: hash reference containing all fields in target group

sub get_config {
  my $args = shift || {};
  my $file = $args->{file} || return;
  my $key = $args->{key} || return;

  # read configuration file but only return requested field group
  my $cfg = read_config_file($file);
  $cfg->{$key}
}

# get_iso_string()
# Generate properly formatted ISO 8601 string for current date/time
# return: string in ISO 8601 format

sub get_iso_string {
  # proper ISO 8610 format required 'Z' appended to indicate UTC
  DateTime->now->iso8601 . 'Z'
}

# get_facets( $args )
# Generate valid app.bsky.richtext.facet record from posted text
# $args: hash reference
#    text => string (req), text being posted to Bluesky
#    bs => hash ref from get_connection(), needed only if parsing mentions
# return: array reference representing app.bsky.richtext.facet record

sub get_facets {
  my $args = shift || {};
  my $output = [];
  my $text = $args->{text} || return $output;
  my $bs = $args->{bs};
  my $pos = 0;
  my $idx = 0;
  # split text string into tokens by white space
  # and loop thru, checking for URIs and mentions
  foreach my $w (split /\s+/, $text) {
    my ($type, $attrib, $val);
    $w =~ s/[\.,:;'"!\?]+$//; # strip selected ending punctuation
    if ($w =~ /^https?\:\/\//) {
      # token begins like a URI so add link to facets array
      $type = FACETLINK;
      $attrib = 'uri';
      $val = $w;
    } elsif (defined $bs && $w =~ /^@/) {
      # token begins with @ so look up account DID and add mention
      $val = lookup_repo({ bs => $bs, account => substr($w, 1) });
      if (defined $val) {
        $type = FACETMENTION;
        $attrib = 'did';
      }
    } elsif ( $w =~ /^#/) {
      $type = FACETTAG;
      $attrib = 'tag';
      $val = w;
    }
    if (defined $type) {
      # if we have a match, find its index in the original string,
      # then build its data record and add it to our output hash
      $pos = index($text, $w, $pos);
      my $end = $pos + length($w);
      # push new element to output array ref
      push @$output, {
        features => [{
          '$type' => $type,
          $attrib => $val,
        }],
        index => {
          byteStart => $pos,
          byteEnd => $end,
        },
      };
      $pos = $end;
      $idx++;
    }
  }
  $output
}

# lookup_repo( $args )
# Look up DID for a given account handle
# $args: hash reference
#    bs => hash ref from get_connection() (req)
#    account => string (req), account handle to look up
# return: undef on error, DID string identifying input account on success

sub lookup_repo {
  my $args = shift || {};
  my $bs = $args->{bs} || return;
  my $account = $args->{account} || return;

  # execute GET on com.atproto.identity.resolveHandle endpoint
  my $uri = URI->new("https://$bs->{host}/xrpc/${\RESOLVEHANDLE}");
  $uri->query_form( handle => $account );
  my $response = $bs->{ua}->get($uri);
  return if !$response->is_success;

  # parse DID string from response content
  my $content = decode_json($response->decoded_content);
  $content->{did}
}

# Private additions for motd_bot

# post_blob - POST an image's binary blob 

sub post_blob {
  my $args = shift || {};
  my $account = $args->{account} || die "bluesky account missing\n";
  my $filetype = $args->{filetype} || die "bluesky account missing\n";
  my $fn = $args->{fn} || die "no filename provided\n";
  my $fs   = -s $fn;

  my $bs = get_connection({ account => $account });
  open(IMAGE, $fn); binmode IMAGE; read(IMAGE, my $blob, $fs); close(IMAGE);
 
  my $response = $bs->{ua}->post(
    "https://$bs->{host}/xrpc/${\POSTBLOB}",
    Content_Type => 'image/'.$filetype,
    Content => $blob,
  );
  $response
}


# get_profile - get an actor's profile information

sub get_profile {
  my $args = shift || {};
  my $account = $args->{account} || die "bluesky account missing\n";
  my $actor = $args->{actor} || die "need to pass an actor\n";
  my $bs = get_connection({ account => $account });

  my $uri = URI->new("https://$bs->{host}/xrpc/${\GETPROFILE}");
  $uri->query_form ( actor => $actor );
  my $response = $bs->{ua}->get($uri);
  return if !$response->is_success;
  
  my $content = decode_json($response->decoded_content);
  # specific to motd bot; strip uri elements for the $link we care about
  $content->{banner} =~ (s/(.*plain\/|\@jpeg|did:plc.*\/)//g);
  return $content;
}

1;
