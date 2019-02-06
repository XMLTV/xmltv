# Just some routines related to the Memoize module that are used in
# more than one place in XMLTV.  But not general enough to merge back
# into Memoize.

package XMLTV::Memoize;
use strict;
use File::Basename;
use Getopt::Long;

# Use Log::TraceMessages if installed.
BEGIN {
    eval { require Log::TraceMessages };
    if ($@) {
	*t = sub {};
	*d = sub { '' };
    }
    else {
	*t = \&Log::TraceMessages::t;
	*d = \&Log::TraceMessages::d;
    }
}

# Add an undocumented option to cache things in a DB_File database.
# You need to decide which subroutines should be cached: see
# XMLTV::Get_nice for how to memoize web page fetches.  Call like
# this:
#
# if (check_argv('fred', 'jim')) {
#     # The subs fred() and jim() are now memoized.
# }
#
# If the user passed a --cache option to your program, this will be
# removed from @ARGV and caching will be turned on.  The optional
# argument to --cache gives the filename to use.
#
# Currently it is assumed that the function gives the same result in
# both scalar and list context.
#
# Note that the Memoize module is not loaded unless --cache options
# are found.
#
# Returns a ref to a list of code references for the memoized
# versions, if memoization happened (but does install the memoized
# versions under the original names too).  Returns undef if no
# memoization was wanted.
#
sub check_argv( @ ) {
#    local $Log::TraceMessages::On = 1;
    my $yes = 0;
    my $p = new Getopt::Long::Parser(config => ['passthrough']);
    die if not $p;
    my $opt_cache;
    my $opt_quiet = 0;
    my $result = $p->getoptions('cache:s' => \$opt_cache,
                                'quiet' => \$opt_quiet );
    die "failure processing --cache option" if not $result;
    unshift @ARGV, "--quiet" if $opt_quiet;

    return undef if not defined $opt_cache;
    my $filename;
    if ($opt_cache eq '') {
	# --cache given, but no filename.  Guess one.
	my $basename = File::Basename::basename($0);
	$filename = "$basename.cache";
    }
    else {
	$filename = $opt_cache;
    }
    print STDERR "using cache $filename\n" unless $opt_quiet;

    require POSIX;
    require Memoize;
    require DB_File;
    # Annoyingly tie(%cache, @tie_args) doesn't work
    #my @tie_args = ('DB_File', $filename,
    #		    POSIX::O_RDWR() | POSIX::O_CREAT(), 0666);

    # $from_caller is a sub which converts a function name into one
    # seen from the caller's namespace.  Namespaces do not nest, so if
    # it already has :: it should be left alone.
    #
    my $caller = caller();
    t "caller: $caller";
    my $from_caller = sub( $ ) {
	for (shift) {
	    return $_ if /::/;
	    return "${caller}::$_";
	}
    };

    # Annoyingly tie(%cache, @tie_args) doesn't work
    my %cache;
    tie %cache, 'DB_File', $filename,
      POSIX::O_RDWR() | POSIX::O_CREAT(), 0666;
    my @r;
    foreach (@_) {
	my $r = Memoize::memoize($from_caller->($_),
				 SCALAR_CACHE => [ HASH => \%cache ],
				 #
				 # Memoize 1.03 broke tied SCALAR_CACHE with
				 # together with LIST_CACHE => 'MERGE'. See
				 # bug report on CPAN:
				 #
				 #  https://rt.cpan.org/Public/Bug/Display.html?id=91927
				 #
				 # As no user of this module calls memoized
				 # functions in list context, we can simply
				 # replace it with 'FAULT'.
				 #
				 #LIST_CACHE => 'MERGE');
				 LIST_CACHE => 'FAULT');
	die "could not memoize $_" if not $r;
	push @r, $r;
    }
    return \@r;
}

1;
