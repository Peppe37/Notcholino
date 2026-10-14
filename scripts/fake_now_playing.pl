#!/usr/bin/perl
# Stand-in for the Now Playing helper: reports a song playing in Chrome, then stays quiet like the real one
use strict; use warnings; use Time::HiRes qw(time); $| = 1;
my $now = int(time() * 1e6);
print qq({"type":"data","diff":false,"payload":{}}\n);
sleep 1;
print qq({"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome","playing":true,"title":"Benchmark Song","artist":"Notcholino","durationMicros":300000000,"elapsedTimeMicros":5000000,"timestampEpochMicros":$now,"playbackRate":1}}\n);
sleep 100000;
