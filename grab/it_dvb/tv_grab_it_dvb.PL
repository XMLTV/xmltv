use IO::File;
my $out = shift @ARGV; die "no output file given" if not defined $out;
my $share_dir = shift @ARGV;
die "no final share/ location given" if not defined $share_dir;
my $in = 'grab/it_dvb/tv_grab_it_dvb.in';
my $in_fh = new IO::File "< $in" or die "cannot read $in: $!";
my $out_fh = new IO::File "> $out" or die "cannot write to $out: $!";
my $seen = 0;
while (<$in_fh>) {
    s/^my \$SHARE_DIR =.*/my \$SHARE_DIR='$share_dir'; \# by $0/ && $seen++;
    print $out_fh $_;
}
if ($seen == 0) {
    die "did not see SHARE_DIR line in $in";
}
elsif ($seen == 1) {
    # Okay.
}
elsif ($seen >= 2) {
    warn "more than one SHARE_DIR line in $in";
}
else { die }
close $out_fh or die "cannot close $out: $!";
close $in_fh or die "cannot close $in: $!";
