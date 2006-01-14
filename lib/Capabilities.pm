# Add a --capabilities argument to your program, eg
#
# use XMLTV::Version qw/baseline manualconfig/;
#

package XMLTV::Capabilities;

my $opt = '--capabilities';
sub import( $$ ) {
    die "usage: use $_[0] qw/<capabilities>/" if @_ < 2;
    my $seen = 0;
    foreach (@ARGV) {
	# This doesn't handle abbreviations in the GNU style.
	last if $_ eq '--';
	if ($_ eq $opt) {
	    $seen++ && warn "seen '$opt' twice\n";
	}
    }
    return if not $seen;

    eval {
	print join "\n", @_[1..$#_];
        print "\n";
    };

    exit();
}

1;
