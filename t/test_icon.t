#!/usr/bin/perl
use warnings;
use strict;
use XMLTV;

# This checks only that the data can be written without crashing.
print "1..1\n";
my %p = (title => [ [ 'Foo' ] ],
	 start => '20000101000000 +0000',
	 channel => '1.foo.com',
	 rating => [ [ '18', 'BBFC', [ { src => 'img.png' } ] ] ],
	);
my $out = ($^O =~ /^win/i ? 'nul' : '/dev/null');
my $fh = new IO::File ">$out";
die "cannot write to $out\n" if not $fh;
my $w = new XMLTV::Writer(OUTPUT => $fh, encoding => 'UTF-8');
$w->start({});
$w->write_programme(\%p);
$w->end();
close $fh or warn "cannot close $out: $!";
print "ok 1\n";
