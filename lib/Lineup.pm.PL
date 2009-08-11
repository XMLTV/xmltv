# Generate Lineup.pm from Lineup.pm.in.  This is to generate part of
# the pod documentation from the list of handlers.
#
# $Id$
#

use strict;
sub print_list( $$ );

my $out = shift @ARGV; die "no output file given" if not defined $out;
my $in = 'lib/Lineup.pm.in';
require $in;
open(IN_FH, $in) or die "cannot read $in: $!";
# die if not @XMLTV::Lineup::Display_Name_Handlers;
die if not @XMLTV::Lineup::Channel_Handlers;

# Vaguely sane so far, let's create the output file and hope it works.
open(OUT_FH, ">$out") or die "cannot write to $out: $!";
while (<IN_FH>) {
    if (/^\s*\@DISPLAY_NAME_HANDLERS\s*$/) {
	print_list(\*OUT_FH, \@XMLTV::Lineup::Display_Name_Handlers);
    }
    elsif (/^\s*\@CHANNEL_HANDLERS\s*$/) {
	print_list(\*OUT_FH, \@XMLTV::Lineup::Channel_Handlers);
    }
    else {
	print OUT_FH $_;
    }
}
close OUT_FH or die "cannot close $out: $!";
close IN_FH or die "cannot close $in: $!";

sub print_list( $$ ) {
    local *FH = shift;
    my $l = shift;
    print FH "\n=over\n";
    foreach (@$l) {
	my ($elem_name, $h_name, $mult) = @$_;
	print FH "\n=item $elem_name, I<$h_name>, B<$mult>\n";
    }
    print FH "\n\n=back\n";
}
