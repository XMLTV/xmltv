=head1 NAME

XMLTV::PreferredMethod - Adds a preferredmethod argument to XMLTV grabbers

=head1 DESCRIPTION

Add a --preferredmethod argument to your program, eg

  use XMLTV::PreferredMethod 'allatonce';

If a --preferredmethod parameter is supplied on the command-line, it will
be caught already by the "use" statement, the string supplied in the use-line
will be printed to STDOUT and the program will exit.

Don't forget to announce the preferredmethod capability as well.

=head1 SEE ALSO

L<XMLTV::Options>, L<XMLTV::Capabilities>.

=cut

package XMLTV::PreferredMethod;

my $opt = '--preferredmethod';
sub import( $$ ) {
    my( $class, $method ) = @_;
    die "usage: use $class 'method'" if scalar(@_) != 2;
    my $seen = 0;
    foreach (@ARGV) {
	# This doesn't handle abbreviations in the GNU style.
	last if $_ eq '--';
	if ($_ eq $opt) {
	    $seen++ && warn "seen '$opt' twice\n";
	}
    }
    return if not $seen;

    print $method . "\n";
    exit();
}

1;
