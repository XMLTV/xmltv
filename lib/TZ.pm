# Miscellaneous timezone routines.  The code in Europe_TZ.pm builds on
# these for handling European summer time conventions.  This should
# probably be moved into Date::Manip somehow.
#

package XMLTV::TZ;
use Carp;
use Date::Manip; # no Date_Init(), that can be done by the app
# Won't Memoize, you can do that yourself.
use base 'Exporter'; our @EXPORT_OK;
@EXPORT_OK = qw(gettz ParseDate_PreservingTZ tz_to_num parse_local_date);

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


# gettz()
#
# Parameters: unparsed date string
# Returns: timezone (a substring), or undef
#
# We just pick up anything that looks like a timezone.
#
sub gettz($) {
    croak 'usage: gettz(unparsed date string)' if @_ != 1;
    local $_ = shift;
    croak 'undef argument to gettz()' if not defined;

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
    croak 'usage: ParseDate_PreservingTZ(unparsed date string)'
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

    # It should be possible to use numeric timezones and have them
    # come out unchanged.  But due to a bug in Date::Manip, '+0100' is
    # treated as equivalent to 'UTC' by (WTF?) and we have to
    # special-case numeric timezones.
    #
    return $tz if $tz =~ /^[+-]?\d\d:?(?:\d\d)?$/;

    # To convert to a number we parse a date with this timezone and
    # then compare against the same date with UTC.
    #
    my $date_str = '2000-01-01 00:00:00'; # arbitrary
    my $base = ParseDate("$date_str UTC"); die if not defined $base;
    t "parsed '$date_str UTC' as $base";
    my $d = ParseDate("$date_str $tz"); return undef if not defined $d;
    t "parsed '$date_str $tz' as $base";
    my $err;
    my $delta = DateCalc($d, $base, \$err);
    die "error code from DateCalc: $err" if defined $err;

    # A timezone difference must be less than one day, and must be a
    # whole number of minutes.
    #
    $delta =~ /^([+-])0:0:0:0:(\d\d?):(\d\d?):0$/ or die "bad delta $delta";
    t "turned timezone $tz into delta $1 $2 $3";
    return sprintf('%s%02d%02d', $1, $2, $3);
}


# Date::Manip seems to have difficulty with changes of timezone: if
# you parse some dates in a local timezone then do
# Date_Init('TZ=UTC'), the existing dates are not changed, so
# comparisons with later parsed dates (in UTC) will be wrong.  Script
# to reproduce the bug:
#
# #!/usr/bin/perl -w
# use Date::Manip;
# # First parse a date in the timezone +0100.
# Date_Init('TZ=+0100');
# my $a = ParseDate('2000-01-01 00:00:00');
# # Now parse another one, in timezone +0000.
# Date_Init('TZ=+0000');
# my $b = ParseDate('2000-01-01 00:00:00');
# # The two dates should differ by one hour.
# print Date_Cmp($a, $b), "\n";
#
# The script should print -1 but it prints 0.
#
# NB, use this function _before_ changing the default timezone to UTC,
# if you want to parse some dates in the user's local timezone!
#
# Like ParseDate(), returns undef on error.
#
sub parse_local_date( $ ) {
    my $d = shift;
#    local $Log::TraceMessages::On = 1;
    t 'parse_local_date() parsing: ' . d $d;
    my $pd = ParseDate($d);
    t 'ParseDate() returned: ' . d $pd;
    return undef if not defined $pd;
    my $r = Date_ConvTZ($pd, Date_TimeZone(), 'UTC');
    t 'converted into UTC: ' . d $r;
    return $r;
}

1;
