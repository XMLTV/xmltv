# Timezone stuff, including routines to guess timezones in European
# countries that have daylight saving time.
#
# Warning: this might break if Date::Manip is initialized to some
# timezone other than UTC: best to call Date_Init('UTC') first.
#

package XMLTV::Europe_TZ;
use strict;
use Date::Manip; # no Date_Init(), that can be done by the app
use XMLTV::TZ qw(gettz tz_to_num);

# Memoize some subroutines if possible.  FIXME commonize to
# XMLTV::Memoize.  We are memoizing our own routines plus gettz() from
# XMLTV::TZ, that too needs sorting out.
#
eval { require Memoize };
unless ($@) {
    foreach (qw(parse_eur_date date_to_eur dst_dates
		ParseDate UnixDate DateCalc Date_Cmp
		ParseDateDelta gettz)) {
	Memoize::memoize($_) or die "cannot memoize $_: $!";
    }
}

use base 'Exporter'; use vars '@EXPORT';
@EXPORT = qw(parse_eur_date date_to_eur);

# parse_eur_date()
#
# Wrapper for ParseDate() that tries to guess what timezone a date is
# in.  You must pass in the 'base' timezone as the second argument:
# this base timezone gives winter time, and summer time is one hour
# ahead.  So the base will be UTC for Britain, Ireland and Portugal,
# UTC+1 for many other countries.
#
# If the date already has a timezone it is left alone, but undef is
# returned if the explicit timezone doesn't match winter or
# summer time for the base passed in.
#
# The switchover from winter to summer time gives a one hour window of
# 'impossible' times when the clock goes forward; those give undef.
# Putting the clocks back in autumn gives one hour of ambiguous times;
# we assume summer time for those.
#
# Parameters:
#   unparsed date from some country following EU DST conventions
#   base timezone giving winter time in that country
#
# Returns: parsed date, or undef if error
#
sub parse_eur_date($$) {
    my ($date, $base) = @_;
    my $winter_tz = tz_to_num($base);
    die "bad timezone $base" if not defined $winter_tz;
    my $summer_tz = sprintf('%+05d', $winter_tz + 100); # 'one hour'

    my $got_tz = gettz($date);
    if (defined $got_tz) {
	# Need to work out whether the timezone is one of the two
	# allowable values.
	#
	my $got_tz_num = tz_to_num($got_tz);
	return undef if not defined $got_tz_num;
	if ($got_tz_num ne $winter_tz and $got_tz_num ne $summer_tz) {
	    return undef;
	}

	# One thing we don't check is that the explicit timezone makes
	# sense for this time of year.  So you can specify summer
	# time even in January if you want.
	#

	# OK, the timezone is there and it looks sane, continue.
	return ParseDate($date);
    }

    # No timezone present, we need to guess.
    my $dp = ParseDate($date);
    return undef if not defined $dp;

    # Start and end of summer time in that year, in UTC
    my ($start_dst, $end_dst) = @{dst_dates(UnixDate($dp, '%Y'))};

    # The clocks shift backwards and forwards by one hour.
    my $clock_shift = "1 hour";

    # The times that the clocks go forward to in spring (local time)
    my $start_dst_skipto = DateCalc($start_dst, "+ $clock_shift");

    # The local time when the clocks go back
    my $end_dst_backfrom = DateCalc($end_dst, "+ $clock_shift");

    if (Date_Cmp($dp, $start_dst) < 0) {
	# Before the start of summer time.
	return $dp;
    }
    elsif (Date_Cmp($dp, $start_dst) == 0) {
	# Exactly _at_ the start of summer time.  Really such a date
	# should not exist since the clocks skip forward an hour at
	# that point.  But we tolerate this fencepost error.
	#
	return $dp;
    }
    elsif (Date_Cmp($dp, $start_dst_skipto) < 0) {
	# Date is impossible (time goes from from $start_dst UTC to
	# $start_dst_skipto DST).
	#
	return undef;
    }
    elsif (Date_Cmp($dp, $end_dst) < 0) {
	# During summer time.
	return Date_ConvTZ($dp, $summer_tz, 'UTC');
    }
    elsif (Date_Cmp($dp, $end_dst_backfrom) <= 0) {
#	warn("$date is ambiguous "
#	     . "(clocks go back from $end_dst_backfrom $summer_tz to $end_dst $winter_tz), "
#	     . "assuming $summer_tz" );

	return Date_ConvTZ($dp, $summer_tz, 'UTC');
    }
    else {
	# Definitely after the end of summer time.
	return $dp;
    }
}


# date_to_eur()
#
# Take a date in UTC and convert it to one of two timezones, depending
# on when during the year it is.
#
# Parameters:
#   date in UTC (from ParseDate())
#   base timezone (winter time)
#
# Returns ref to list of
#   new date
#   timezone of new date
#
# For example, date_to_eur with a date of 13:00 on June 10th 2000 and
# a base timezone of UTC would be be 14:00 +0100 on the same day.  The
# input and output date are both in Date::Manip internal format.
#
sub date_to_eur( $$ ) {
    my ($d, $base_tz) = @_;
    die if (not defined $d) or ($d !~ /\S/);

    my $year = UnixDate($d, '%Y');
    if ((not defined $year) or ($year !~ tr/0-9//)) {
	die "cannot get year from '$d'";
    }

    # Find the start and end dates of summer time.
    my ($start_dst, $end_dst) = @{dst_dates($year)};

    # The clocks shift backwards and forwards by one hour.
    my $clock_shift = "1 hour";

    my $use_tz;
    if (Date_Cmp($d, $start_dst) < 0) {
	# Before the start of summer time.
	$use_tz = $base_tz;
    }
    elsif (Date_Cmp($d, $end_dst) < 0) {
	# During summer time.
	my $base_tz_num = tz_to_num($base_tz);
	die "bad timezone $base_tz" if not defined $base_tz_num;
	$use_tz = sprintf('%+05d', $base_tz_num + 100); # one hour
    }
    else {
	# After summer time.
	$use_tz = $base_tz;
    }
    die if not defined $use_tz;
    return [ Date_ConvTZ($d, 'UTC', $use_tz), $use_tz ];
}


# dst_dates()
#
# Return the dates (in UTC) when summer starts and ends in a given
# year.
#
# According to <http://www.rog.nmm.ac.uk/leaflets/summer/summer.html>,
# summer time starts at 01:00 on the last Sunday in March, and ends at
# 01:00 on the last Sunday in October.  That's 01:00 UTC in both
# cases, irrespective of what the winter and summer timezones are.
# This has been the case throughout the European Union since 1998, and
# some other countries such as Norway follow the same rules.
#
# Parameters: year (only 1998 or later works)
#
# Returns: ref to list of
#   start time and date of summer time (in UTC)
#   end time and date of summer time (in UTC)
#
sub dst_dates($) {
    die 'usage: dst_dates(year)' if @_ != 1;
    my $year = shift;
    die "don't know about DST before 1998" if $year < 1998;

    my ($start_dst, $end_dst);
    foreach (1 .. 31) {
	my $mar = "$year-03-$_" . ' 01:00';
	my $mar_d = ParseDate($mar) or die "cannot parse $mar";
	$start_dst = $mar_d if UnixDate($mar_d, "%A") =~ /Sunday/;

	# A time between '00:00' and '01:00' just before the last
	# Sunday in October is ambiguous.
	#
	my $oct = "$year-10-$_" . ' 01:00';
	my $oct_d = ParseDate($oct) or die "cannot parse $oct";
	$end_dst = $oct_d if UnixDate($oct_d, "%A") =~ /Sunday/;
    }
    die if not defined $start_dst or not defined $end_dst;

    return [ $start_dst, $end_dst ];
}


1;
