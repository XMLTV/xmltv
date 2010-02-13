# $Id$
#
# Library to wrap LWP::UserAgent to put in a random delay between
# requests and set the User-Agent string.  We really should be using
# LWP::RobotUI but this is better than nothing.
#
# If you're sure your app doesn't need a random delay (because it is
# fetching from a site designed for that purpose) then set
# $XMLTV::Get_nice::Delay to zero, or a value in seconds.  This is the
# maximum delay - on average the sleep will be half that.
#
# get_nice() is the function to call, however
# XMLTV::Get_nice::get_nice_aux() is the one to cache with
# XMLTV::Memoize or whatever.  If you want an HTML::Tree object use
# get_nice_tree().
#

use strict;

package XMLTV::Get_nice;
use base 'Exporter';
our @EXPORT = qw(get_nice get_nice_tree error_msg);
use LWP::UserAgent;
use XMLTV;
our $Delay = 5; # in seconds
our $FailOnError = 1; # Fail on fetch error


our $ua = LWP::UserAgent->new;
$ua->agent("xmltv/$XMLTV::VERSION");
$ua->env_proxy;
our %errors = ();


sub error_msg($) {
    my ($url) = @_;
    $errors{$url};
}
sub get_nice( $ ) {
    # This is to ensure scalar context, to work around weirdnesses
    # with Memoize (I just can't figure out how SCALAR_CACHE and
    # LIST_CACHE relate to each other, with or without MERGE).
    #
    return scalar get_nice_aux($_[0]);
}

# Fetch page and return as HTML::Tree object.  Optional argument is a
# function to put the page data through (eg, to clean up bad
# characters) before parsing.
#
sub get_nice_tree( $;$ ) {
    my ($uri, $filter) = @_;
    require HTML::TreeBuilder;
    my $content = get_nice $uri;
    $content = $filter->($content) if $filter;
    my $t = new HTML::TreeBuilder;
    $t->parse($content) or die "cannot parse content of $uri\n";
    $t->eof;
    return $t;
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

    my $r = $ua->get($url);

    # Then start the delay from this time on the next fetch - so we
    # make the gap _between_ requests rather than from the start of
    # one request to the start of the next.  This punishes modem users
    # whose individual requests take longer, but it also punishes
    # downloads that take a long time for other reasons (large file,
    # slow server) so it's about right.
    #
    $last_get_time = time();

    if ($r->is_error) {
        # At the moment download failures seem rare, so the script dies if
        # any page cannot be fetched.  We could later change this routine
        # to return undef on failure.  But dying here makes sure that a
        # failed page fetch doesn't get stored in XMLTV::Memoize's cache.
        #
        die "could not fetch $url, error: " . $r->status_line . ", aborting\n" if $FailOnError;
        $errors{$url} = $r->status_line;
        return undef;
    } else {
        return $r->content;
    }

}

1;
