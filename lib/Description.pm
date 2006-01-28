# Add a --description argument to your program, eg
#
# use XMLTV::Description "Sweden (tv.swedb.se)";
#

package XMLTV::Description;

my $opt = '--description';
sub import( $$ ) {
    die "usage: use $_[0] \"Sweden (tv.swedb.se)" if @_ != 2;
    my $seen = 0;
    foreach (@ARGV) {
	# This doesn't handle abbreviations in the GNU style.
	last if $_ eq '--';
	if ($_ eq $opt) {
	    $seen++ && warn "seen '$opt' twice\n";
	}
    }
    return if not $seen;

    print $_[1] . "\n";

    exit();
}

1;
