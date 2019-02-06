# Generate XMLTV.pm from XMLTV.pm.PL.  This is to generate part of
# the pod documentation from the list of handlers.

use strict;
sub print_list( $$ );

my $out = shift @ARGV; die "no output file given" if not defined $out;
my $in = './lib/XMLTV.pm.in';

require $in;

open(IN_FH, $in) or die "cannot read $in: $!";
die if not @XMLTV::Channel_Handlers; die if not @XMLTV::Programme_Handlers;

# Vaguely sane so far, let's create the output file and hope it works.
open(OUT_FH, ">$out") or die "cannot write to $out: $!";
while (<IN_FH>) {
    if (/^\s*\@CHANNEL_HANDLERS\s*$/) {
	print_list(\*OUT_FH, \@XMLTV::Channel_Handlers);
    }
    elsif (/^\s*\@PROGRAMME_HANDLERS\s*$/) {
	print_list(\*OUT_FH, \@XMLTV::Programme_Handlers);
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
