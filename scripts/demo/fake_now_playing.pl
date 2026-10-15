#!/usr/bin/perl
# Stand-in for the Now Playing helper, for screenshots and videos: reports a made-up song with a made-up cover, playing
# in a browser, and then stays quiet like the real helper does. Nothing is played.
#
#   NOTCHOLINO_NOW_PLAYING_SCRIPT=scripts/demo/fake_now_playing.pl /Applications/Notcholino.app/Contents/MacOS/Notcholino
use strict; use warnings; use Time::HiRes qw(time); use MIME::Base64; use File::Basename; $| = 1;
my $cover = dirname(__FILE__) . "/cover.png";
my $art = "";
if (open(my $fh, "<:raw", $cover)) { local $/; $art = encode_base64(<$fh>, ""); close $fh; }
my $now = int(time() * 1e6);
print qq({"type":"data","diff":false,"payload":{}}\n);
sleep 1;
print qq({"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome","playing":true,"title":"Midnight Drive","artist":"The Neon Lights","album":"Afterglow","durationMicros":215000000,"elapsedTimeMicros":61000000,"timestampEpochMicros":$now,"playbackRate":1,"artworkData":"$art"}}\n);
sleep 100000;
