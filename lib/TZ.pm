# Miscellaneous timezone routines.  The code in UK_TZ.pm builds on
# these for handling UK (actually, EU) summer time conventions.  This
# should probably be moved into Date::Manip somehow.
#

package XMLTV::TZ;
use Date::Manip;
# Won't Memoize, you can do that yourself.
use base 'Exporter'; use vars '@EXPORT_OK';
@EXPORT_OK = qw(gettz ParseDate_PreservingTZ);


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
    my $tz = gettz($u) || 'UT';
#    print STDERR "date $u parsed to $p (timezone read as $tz)\n";
    $p = Date_ConvTZ($p, undef, $tz);
#    print STDERR "...converted to $p\n";
    return $p;
}


