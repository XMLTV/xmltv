#!/usr/bin/perl
use warnings;
use strict;
use XMLTV::DST;

# These tests rely on the internal representation of dates, but what
# the heck.
#
print "1..2\n";
my $r = parse_local_date('20040127021000', '+0100');
print 'not ' if $r ne '2004012701:10:00';
print "ok 1\n";

my ($d, $tz) = @{date_to_local('2004012701:10:00', '+0100')};
print 'not ' if $d ne '2004012702:10:00' or $tz ne '+0100';
print "ok 2\n";

