#!/usr/bin/perl
#
# tests the module for channel translation
#
# copyright 2000 by Gottfried Szing e9625460@stud3.tuwien.ac.at
#
# version 0.02

use Data::Dumper;
use xmltv::TVChannels;

my $channels = TVChannels->new("de");

print "Testing Language settings\n";
print "=========================\n";
print "\nDefault Language: ", $channels->getlanguage();
$channels->setlanguage("de");
print "\nAfter setlanguage: ", $channels->getlanguage();
$channels->setlanguage("en");


# testing override
$channels->loadfile('./channels1.xml');
#$channels->loadfile();

#print "\n\n", Dumper($channels->{CHANNELS});


print "\n\nTesting translations\n";
print "====================\n";

print "\n\nTesting translations from unique to pretty name\n";
print "\nsat1.de default      ", $channels->getdisplayname("sat1.de");
print "\nsat1.de en           ", $channels->getdisplayname("sat1.de", "en");
print "\nswr-online.de de     ", $channels->getdisplayname("swr-online.de", "de");
print "\nchannel1.de fr       ", $channels->getdisplayname("channel1.de", "fr");

print "\n\nTranslating long name to unique\n";
print "\n'TM3' [default]        ", $channels->getuniqename('TM3');
print "\n'PHOENIX' [de]         ", $channels->getuniqename('PHOENIX', 'de');
print "\n'PHOENIX' [en]         ", $channels->getuniqename('PHOENIX', 'en');
print "\n'VIVA II' [fr]         ", $channels->getuniqename('VIVA II', 'fr');

print "\n\nGet all translations for an id\n";
print "for id 'sat1.de':\n";
print Dumper($channels->getalldisplaynames("sat1.de"));
