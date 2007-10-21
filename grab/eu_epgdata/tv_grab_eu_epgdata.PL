# Generate tv_grab_eu_epgdata from tv_grab_eu_epgdata.in. This is done
# to allow grabbers for other countries to use the same code.
#
# This also sets the share directory  to /usr/local/share/xmltv or wherever
#
# Some parts of this script were taken from tv_grab_se_swedb.PL, other parts were taken from tv_grab_uk_bleb.PL

use strict;

use IO::File;
my $out = shift @ARGV; die "no output file given" if not defined $out;
my $share_dir = shift @ARGV;
die "no final share/ location given" if not defined $share_dir;
my $in = 'grab/eu_epgdata/tv_grab_eu_epgdata.in';
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $seen = 0;
while (<$in_fh>) {
    s/\@\@name/tv_grab_eu_epgdata/;
    s/\@\@nspc/                /;
    s/\@\@desc/Parts of Europe (commercial) (www.epgdata.com)/;
    print $out_fh $_;
}
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";

