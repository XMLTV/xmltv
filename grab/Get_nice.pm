# $Id$
#
# Library to wrap LWP::Simple to put in a random delay between
# requests and to set User-Agent.  We really should be using
# LWP::RobotUI but this is better than nothing.
#
# If you're sure your app doesn't need a random delay (because it is
# fetching from a site designed for that purpose) then set
# $XMLTV::Get_nice::Delay to zero, or a value in seconds.  This is the
# maximum delay - on average the sleep will be half that.
#
# get_nice() is the function to call, however
# XMLTV::Get_nice::get_nice_aux() is the one to cache with
# XMLTV::Memoize or whatever.
#
# If you want to change what function is called to get pages, set
# $XMLTV::Get_nice::get to a code reference that takes a URL and
# returns a page.  Perhaps the right thing would be to decouple the
# delay logic into a separate module, but at the moment fetching web
# pages is the only use of it.
#

package XMLTV::Get_nice;
use base 'Exporter';
our @EXPORT = qw(get_nice);
use LWP::Simple qw($ua);
use XMLTV;
$ua->agent("xmltv/$XMLTV::VERSION");
our $Delay = 5; # in seconds

our $get = \&LWP::Simple::get;

sub get_nice( $ ) {
    # This is to ensure scalar context, to work around weirdnesses
    # with Memoize (I just can't figure out how SCALAR_CACHE and
    # LIST_CACHE relate to each other, with or without MERGE).
    #
    return scalar get_nice_aux($_[0]);
}

my $last_get_time;
sub get_nice_aux( $ ) {
    my $url = shift;

    if (defined $last_get_time) {
        # A page has already been retrieved recently.  See if we need
        # to sleep for a while before getting the next page - being
        # nice to the server.
	#
        my $next_get_time = $last_get_time + (rand $Delay);
        my $sleep_time = $next_get_time - time();
        sleep $sleep_time if $sleep_time > 0;
    }

    my $r = $get->($url);

    # At the moment download failures seem rare, so the script dies if
    # any page cannot be fetched.  We could later change this routine
    # to return undef on failure.  But dying here makes sure that a
    # failed page fetch doesn't get stored in XMLTV::Memoize's cache.
    #
    die "could not fetch $url, aborting\n" if not defined $r;

    # Then start the delay from this time on the next fetch - so we
    # make the gap _between_ requests rather than from the start of
    # one request to the start of the next.  This punishes modem users
    # whose individual requests take longer, but it also punishes
    # downloads that take a long time for other reasons (large file,
    # slow server) so it's about right.
    #
    $last_get_time = time();
    return $r;
}
1;
