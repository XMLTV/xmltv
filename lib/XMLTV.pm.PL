# Generate XMLTV.pm from XMLTV.pm.PL.  This is to generate part of
# the pod documentation from the list of handlers.
#
# $Id$
#

use strict;
use diagnostics;
use IO::File;
sub print_list( $$ );

my $out = shift @ARGV; die "no output file given" if not defined $out;
my $in = 'lib/XMLTV.pm.in';
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
require $in;
die if not @XMLTV::Channel_Handlers; die if not @XMLTV::Programme_Handlers;
while (<$in_fh>) {
    if (/^\s*\@CHANNEL_HANDLERS\s*$/) {
	print_list($out_fh, \@XMLTV::Channel_Handlers);
    }
    elsif (/^\s*\@PROGRAMME_HANDLERS\s*$/) {
	print_list($out_fh, \@XMLTV::Programme_Handlers);
    }
    else {
	print $out_fh $_;
    }
}
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";

sub print_list( $$ ) {
    my ($fh, $l) = @_;
    print $fh "\n=over\n";
    foreach (@$l) {
	my ($elem_name, $h_name, $mult) = @$_;
	print $fh "\n=item $elem_name, I<$h_name>, B<$mult>\n";
    }
    print $fh "\n=back\n";
}
