# Add a --version argument to your program, eg
#
# use XMLTV::Version '$Id$';
#
# Best to put that before other module imports, so that even if they
# fail --version will still work.
#

package XMLTV::Version;

my $opt = '--version';
sub import( $$ ) {
    die "usage: use $_[0] <version-string>" if @_ != 2;
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
	require XMLTV;
	print "XMLTV module version $XMLTV::VERSION\n";
    };
    print "could not load XMLTV module, xmltv is not properly installed\n"
      if $@;
    for ($_[1]) {
	if (m!\$Id: ([^,]+),v (\S+) ([0-9/: -]+)!) {
	    print "This is $1 version $2, $3\n";
	}
	else {
	    print "This program version $_\n";
	}
    }

    exit();
}

1;
