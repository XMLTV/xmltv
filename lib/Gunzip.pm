=pod

=head1 NAME

    XMLTV::Gunzip - wrapper to Compress::Zlib or gzip(1)

=head1 SYNOPSIS

    use XMLTV::Gunzip;
    my $decompressed = gunzip($gzdata);

Compress::Zlib will be used if installed, otherwise an external gzip
will be spawned.  An exception is thrown if things go wrong.

=head1 AUTHOR

Ed Avis, ed@membled.com.  Distributed as part of the xmltv package.

=head1 SEE ALSO

L<Compress::Zlib>, L<gzip(1)>, L<XMLTV>.

=cut

package XMLTV::Gunzip;
use base 'Exporter'; use vars '@EXPORT'; @EXPORT = qw(gunzip);
use File::Temp;

sub use_zlib( $ ) {
    for (Compress::Zlib::memGunzip(shift)) {
	die 'memGunzip() failed' if not defined;
	return $_;
    }
}
sub external_gunzip( $ ) {
    my ($fh, $fname) = File::Temp::tempfile();
    print $fh shift or die "cannot write to $fname: $!";
    close $fh or die "cannot close $fname: $!";
    open(GZIP, "gzip -d <$fname |") or die "cannot run gzip: $!";
    local $/ = undef;
    my $r = <GZIP>;
    close GZIP or die "cannot close pipe from gzip: $!";
    unlink $fname or die "cannot unlink $fname: $!";
    return $r;
}
my $f;
BEGIN {
    eval { require Compress::Zlib; die };
    $f = $@ ? \&external_gunzip : \&use_zlib;
}
sub gunzip( $ ) { return $f->(shift) }

1;
