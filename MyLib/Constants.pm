#!/usr/bin/perl -w
#
# This is a modified version of the ATProto perl module by William Shunn
#
# https://betterprogramming.pub/building-a-perl-module-for-posting-to-bluesky-social-92fc732fc297 



package MyLib::Constants;
use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(
        CREATESESSION CREATERECORD PUTRECORD RESOLVEHANDLE
        POSTBLOB FEEDPOST MEDIAPOST FACETLINK FACETMENTION
        FACETTAG GETPROFILE BSCONFIGFILE BSUSERAGENT BSMAXLENGTH
);


use constant CREATESESSION => 'com.atproto.server.createSession';
use constant CREATERECORD  => 'com.atproto.repo.createRecord';
# PUTRECORD for profile handling
use constant PUTRECORD     => 'com.atproto.repo.putRecord';
use constant RESOLVEHANDLE => 'com.atproto.identity.resolveHandle';
# POSTBLOB for image binary blobs
use constant POSTBLOB      => 'com.atproto.repo.uploadBlob';
# GETPROFILE for profile content
use constant GETPROFILE    => 'app.bsky.actor.getProfile';
use constant FEEDPOST      => 'app.bsky.feed.post';
use constant FACETLINK     => 'app.bsky.richtext.facet#link';
use constant FACETMENTION  => 'app.bsky.richtext.facet#mention';
use constant FACETTAG      => 'app.bsky.richtext.facet#tag';


use constant BSCONFIGFILE => 'config.cfg';
use constant BSUSERAGENT  => 'Mozilla/5.0';
use constant BSMAXLENGTH  => 300;
