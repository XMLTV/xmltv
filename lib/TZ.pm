# Miscellaneous timezone routines.  The code in Europe_TZ.pm builds on
# these for handling European summer time conventions.  This should
# probably be moved into Date::Manip somehow.
#

package XMLTV::TZ;
use Date::Manip; # no Date_Init(), that can be done by the app
# Won't Memoize, you can do that yourself.
use base 'Exporter'; use vars '@EXPORT_OK';
@EXPORT_OK = qw(gettz ParseDate_PreservingTZ tz_to_num);


# gettz()
#
# Parameters: unparsed date string
# Returns: timezone (a substring), or undef
#
# We just pick up anything that looks like a timezone.
#
sub gettz($) {
    die 'usage: gettz(unparsed date string)' if @_ != 1;
    local $_ = shift;
    die if not defined;

    /\s([A-Z]{1,4})$/        && return $1;
    /\s([+-]\d\d:?(\d\d)?)$/ && return $1;
    return undef;
}


# ParseDate_PreservingTZ()
#
# A wrapper for Date::Manip's ParseDate() that makes sure the date is
# stored in the timezone it was given in.  That's helpful when you
# want to produce human-readable output and the user expects to see
# the same timezone going out as went in.
#
sub ParseDate_PreservingTZ($) {
    die 'usage: ParseDate_PreservingTZ(unparsed date string)'
      if @_ != 1;
    my $u = shift;
    my $p = ParseDate($u); return undef if not defined $p;
    my $tz = gettz($u) || 'UTC';
#    print STDERR "date $u parsed to $p (timezone read as $tz)\n";
    $p = Date_ConvTZ($p, undef, $tz);
#    print STDERR "...converted to $p\n";
    return $p;
}


# tz_to_num()
#
# Turn a timezone string into a numeric form.  For example turns 'CET'
# into '+0100'.  If the timezone is already numeric it's unchanged.
#
# Returns undef if the timezone is not recognized.  (OK, throwing an
# exception would probably make more sense, but Date::Manip has its
# peculiar interface style where you have to manually check the result
# of every call and we might as well fit into that.)
#
sub tz_to_num( $ ) {
    my $tz = shift;

    # To convert to a number we parse a date with this timezone and
    # then compare against the same date with UTC.
    #
    my $date_str = '2000-01-01 00:00:00'; # arbitrary
    my $base = ParseDate("$date_str UTC"); die if not defined $base;
    my $d = ParseDate("$date_str $tz"); return undef if not defined $d;
    my $err;
    my $delta = DateCalc($d, $base, \$err);
    die "error code from DateCalc: $err" if defined $err;

    # A timezone difference must be less than one day, and must be a
    # whole number of minutes.
    #
    $delta =~ /^([+-])0:0:0:0:(\d\d?):(\d\d?):0$/ or die "bad delta $delta";
    return sprintf('%s%02d%02d', $1, $2, $3);
}

1;
