# Generate Supplement.pm from Supplement.pm.in and set the share directory
# correctly.

use strict;

use IO::File;
my( $out, $share ) = @ARGV;

die "no output file given" if not defined $out;
die "no share-dir given" if not defined $share;

my $in = 'lib/Supplement.pm.in';
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $seen = 0;
while (<$in_fh>) {
    print $out_fh $_;
}
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";
