# Generate tv_grab_se_swedb from tv_grab_se_swedb.in. This is done
# to allow grabbers for other countries to use the same code.
#

use strict;

use IO::File;
my $out = shift @ARGV; die "no output file given" if not defined $out;
my $in = 'grab/se_swedb/tv_grab_se_swedb.in';
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $seen = 0;
while (<$in_fh>) {
    s/\@\@name/tv_grab_se_swedb/;
    s/\@\@nspc/                /;
    s/\@\@country/Sweden/;
    s/\@\@desc/Sweden (tv.swedb.se)/;
    s%\@\@url%http://tv.swedb.se/xmltv/channels.xml.gz%;
    s%\@\@site%http://tv.swedb.se/%;
    print $out_fh $_;
}
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";

