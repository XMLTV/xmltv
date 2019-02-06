# Generate tv_grab_ch_search from tv_grab_ch_search.in.  This is to set the path to
# the files in /usr/local/share/xmltv or wherever.
#
# The second argument is the share directory for the final
# installation.

use IO::File;
my $out = shift @ARGV; die "no output file given" if not defined $out;
my $share_dir = shift @ARGV;
die "no final share/ location given" if not defined $share_dir;
my $in = 'grab/ch_search/tv_grab_ch_search.in';
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $seen = 0;
while (<$in_fh>) {
    print $out_fh $_;
}
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";

