# Generate tv_grab_se_tvzon from tv_grab_se_swedb.in.
#

use strict;

use IO::File;
my $out = shift @ARGV; die "no output file given" if not defined $out;
my $in = 'grab/se_swedb/tv_grab_se_swedb.in';
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
my $seen = 0;
while (<$in_fh>) {
    s/\@\@name/tv_grab_se_tvzon/;
    s/\@\@nspc/                /;
    s/\@\@country/Sweden/;
    s/\@\@desc/Sweden (DEPRECATED, TVZon)/;
    s%\@\@url%http://xmltv.xmltv.se/channels.xml.gz%;
    s%\@\@site%http://xmltv.xmltv.se/%;
    print $out_fh $_;
}
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";

