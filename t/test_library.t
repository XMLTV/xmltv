#!/usr/bin/perl
use warnings;
use strict;
use File::Temp qw(tempdir);
use XMLTV;

print "1..1\n";

my $tempdir = tempdir('XXXXXXXX', CLEANUP => 1);
chdir $tempdir or die "cannot chdir to $tempdir: $!";

# Test for bug where write_programme would delete everything from the
# hash passed in.
#
my $scratch = 'scratch';
my $fh = new IO::File ">$scratch";
die "cannot write to $scratch\n" if not $fh;
my $w = new XMLTV::Writer(OUTPUT => $fh, encoding => 'UTF-8');
$w->start({});

my %prog = (start => '20000101000000',
	    channel => 'c',
	    title => [ [ 'Foo' ] ],
	   );
my %prog_bak = %prog;
$w->write_programme(\%prog);
my $ok;
if (keys %prog == keys %prog_bak) {
    foreach (keys %prog) {
	$ok = 0, last if $prog{$_} ne $prog_bak{$_};
    }
    $ok = 1;
}
else { $ok = 0 };
print 'not ' if not $ok;
print "ok 1\n";

$w->end();
close $fh or die "cannot close $scratch: $!";
