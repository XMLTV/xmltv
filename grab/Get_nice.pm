# Library to wrap LWP::Simple to put in a random delay between
# requests.  We really should be using LWP::RobotUI but this is better
# than nothing.
#
# get_nice() is the function to call, however
# XMLTV::Get_nice::get_nice_aux() is the one to cache with
# XMLTV::Memoize or whatever.
#

package XMLTV::Get_nice;
use base 'Exporter';
our @EXPORT = qw(get_nice);
use LWP::Simple;

sub get_nice( $ ) {
    # This is to ensure scalar context, to work around weirdnesses
    # with Memoize (I just can't figure out how SCALAR_CACHE and
    # LIST_CACHE relate to each other, with or without MERGE).
    #
    return scalar get_nice_aux($_[0]);
}
sub get_nice_aux( $ ) {
    my $url = shift;
    my $r = LWP::Simple::get($url);

    # At the moment download failures seem rare, so the script dies if
    # any page cannot be fetched.  We could later change this routine
    # to return undef on failure.  But dying here makes sure that a
    # failed page fetch doesn't get stored in XMLTV::Memoize's cache.
    #
    die "could not fetch $url, aborting\n" if not defined $r;

    # Be nice to the server.  Technically we don't need to do this
    # after the very last fetch, but sleeping every time is simpler.
    #
    sleep(rand 5);

    return $r;
}
1;
