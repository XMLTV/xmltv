# Generate tv_grab_hr from tv_grab_se_swedb.in. 
#

use strict;

use IO::File;
my $out = shift @ARGV; die "no output file given" if not defined $out;
my $in = 'grab/se_swedb/tv_grab_se_swedb.in';
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
my $seen = 0;
while (<$in_fh>) {
    s/\@\@name/tv_grab_hr/;
    s/\@\@nspc/          /;
    s/\@\@country/Croatia/;
    s/\@\@desc/Croatia/;
    s%\@\@url%http://www.gonix.net/xmltv/channels.xml.gz%;
    s%\@\@site%http://www.gonix.net/%;
    print $out_fh $_;
}
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";

