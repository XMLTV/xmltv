=pod

=head1 NAME

    XMLTV::Gunzip - Wrapper to Compress::Zlib or gzip(1)

=head1 SYNOPSIS

    use XMLTV::Gunzip;
    my $decompressed = gunzip($gzdata);
    my $fh = gunzip_open('file.gz') or die;
    while (<$fh>) { print }

Compress::Zlib will be used if installed, otherwise an external gzip
will be spawned.  gunzip() returns the decompressed data and throws an
exception if things go wrong; gunzip_open() returns a filehandle, or
undef.

=head1 AUTHOR

Ed Avis, ed@membled.com.  Distributed as part of the xmltv package.

=head1 SEE ALSO

L<Compress::Zlib>, L<gzip(1)>, L<XMLTV>.

=cut

use warnings;
use strict;

package XMLTV::Gunzip;
use base 'Exporter';
our @EXPORT; @EXPORT = qw(gunzip gunzip_open);
use File::Temp;

# Implementations of gunzip().
#
sub zlib_gunzip( $ ) {
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
my $gunzip_f;
sub gunzip( $ ) { return $gunzip_f->(shift) }


# Implementations of gunzip_open().
#
sub perlio_gunzip_open( $ ) {
    my $fname = shift;
    # Use PerlIO::gzip.
    local *FH;
    open FH, '<:gzip', $fname
      or die "cannot open $fname via PerlIO::gzip: $!";
    return *FH;
}
sub zlib_gunzip_open( $ ) {
    my $fname = shift;
    # Use the XMLTV::Zlib_handle package defined later in this file.
    local *FH;
    tie *FH, 'XMLTV::Zlib_handle', $fname, 'r'
      or die "cannot open $fname using XMLTV::Zlib_handle: $!";
    return *FH;
}
sub external_gunzip_open( $ ) {
    my $fname = shift;
    local *FH;
    if (not open(FH, "gzip -d <$fname |")) {
	warn "cannot run gzip: $!";
	return undef;
    }
    return *FH;
}
my $gunzip_open_f;
sub gunzip_open( $ ) { return $gunzip_open_f->(shift) }


# Switch between implementations depending on whether Compress::Zlib
# is available.
#
BEGIN {
    eval { require Compress::Zlib }; my $have_zlib = not $@;
    eval { require PerlIO::gzip }; my $have_perlio = not $@;

    if (not $have_zlib and not $have_perlio) {
	$gunzip_f = \&external_gunzip;
	$gunzip_open_f = \&external_gunzip_open;
    }
    elsif (not $have_zlib and $have_perlio) {
	# Could gunzip by writing to a file and reading that with
	# PerlIO, but won't bother yet.
	#
	$gunzip_f = \&external_gunzip;
	$gunzip_open_f = \&perlio_gunzip_open;
    }
    elsif ($have_zlib and not $have_perlio) {
	$gunzip_f = \&zlib_gunzip;
	$gunzip_open_f = \&zlib_gunzip_open;
    }
    elsif ($have_zlib and $have_perlio) {
	$gunzip_f = \&zlib_gunzip;
	$gunzip_open_f = \&perlio_gunzip_open;
    }
    else { die }
}


####
# This is a filehandle wrapper around Compress::Zlib, but supporting
# only read at the moment.
#
package XMLTV::Zlib_handle;
require Tie::Handle; use base 'Tie::Handle';
use Carp;

sub TIEHANDLE {
    croak 'usage: package->TIEHANDLE(file, mode)' if @_ != 3;
    my ($pkg, $file, $mode) = @_;

    croak "only mode 'r' is supported" if $mode ne 'r';

    # This object is a reference to a Compress::Zlib handle.  I did
    # try to inherit directly from Compress::Zlib, but got weird
    # errors of '(in cleanup) gzclose is not a valid Zlib macro'.
    #
    my $fh = Compress::Zlib::gzopen($file, $mode);
    if (not $fh) {
	warn "could not gzopen $file";
	return undef;
    }
    return bless(\$fh, $pkg);
}

# Assuming that WRITE() is like print(), not like syswrite().
sub WRITE {
    my ($self, $scalar, $length, $offset) = @_;
    return 1 if not $length;
    my $r = $$self->gzwrite(substr($scalar, $offset, $length));
    if ($r == 0) {
	warn "gzwrite() failed";
	return 0;
    }
    elsif (0 < $r and $r < $length) {
	warn "gzwrite() wrote only $r of $length bytes";
	return 0;
    }
    elsif ($r == $length) {
	return 1;
    }
    else { die }
}

# PRINT(), PRINTF() inherited from Tie::Handle

sub READ {
    my ($self, $scalar, $length, $offset) = @_;
    local $_;
    my $n = $$self->gzread($_, $length);
    if ($n == -1) {
	warn 'gzread() failed';
	return undef;
    }
    elsif ($n == 0) {
	# EOF.
	return 0;
    }
    elsif (0 < $n and $n <= $length) {
	die if $n != length;
	substr($scalar, $offset, $n) = $_;
	return $n;
    }
    else { die }
}

sub READLINE {
    my $self = shift;

    # When gzreadline() uses $/, this can be removed.
    die '$/ not supported' if $/ ne "\n";

    local $_;
    my $r = $$self->gzreadline($_);
    if ($r == -1) {
	warn 'gzreadline() failed';
	return undef;
    }
    elsif ($r == 0) {
	# EOF.
	die if length;
	return undef;
    }
    else {
	# Number of bytes read.
	die if $r != length;
	return $_;
    }
}

# GETC inherited from Tie::Handle

# This seems to segfault in my perl installation.
sub CLOSE {
    my $self = shift;
    gzclose $$self; # no meaningful return value?
    return 1;
}

sub OPEN {
    # Compress::Zlib doesn't support reopening.
    my $self = shift;
    die 'not yet implemented';
}

sub BINMODE {}

sub EOF {
    my $self = shift;
    return $$self->gzeof();
}

sub TELL {
    # Could track position manually.  But Compress::Zlib should do it.
    die 'not implemented';
}

sub SEEK {
    # Argh, fairly impossible.  Could simulate, but probably better to
    # throw.
    #
    die 'not implemented';
}

sub DESTROY { &CLOSE }

1;
