# Timezone stuff, including routines to guess timezones in European
# (and other) countries that have daylight saving time.
#
# Warning: this might break if Date::Manip is initialized to some
# timezone other than UTC: best to call Date_Init('TZ=+0000') first.

package XMLTV::DST;
use strict;
use Carp qw(croak);
use Date::Manip; # no Date_Init(), that can be done by the app
use XMLTV::TZ qw(gettz tz_to_num offset_to_gmt);
use XMLTV::Date;

# Three modes:
#   eur (default): Europe and elsewhere
#   na:            US (most states) and Canada
#   none:          places that don't observe DST
#
our $Mode = 'eur';

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

# Memoize some subroutines if possible.  FIXME commonize to
# XMLTV::Memoize.  We are memoizing our own routines plus gettz() from
# XMLTV::TZ, that too needs sorting out.
#
eval { require Memoize };
unless ($@) {
    foreach (qw(parse_local_date date_to_local dst_dates
		parse_date UnixDate DateCalc Date_Cmp
		gettz)) {
	Memoize::memoize($_) or die "cannot memoize $_: $!";
    }
}

use base 'Exporter';
our @EXPORT = qw(parse_local_date date_to_local utc_offset);

# parse_local_date()
#
# Wrapper for parse_date() that tries to guess what timezone a date is
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
# Returns: parsed date.  Throws exception if error.
#
sub parse_local_date($$) {
#    local $Log::TraceMessages::On = 1;
    my ($date, $base) = @_;
    croak 'usage: parse_local_date(unparsed date, base timeoffset)'
      if @_ != 2 or not defined $date or not defined $base;
    croak 'second parameter must be a time offset (+xxxx,-xxxx)'
      if( $base !~ /^[-+]\d{4}$/ );

    my $winter_tz = $base;
    my $summer_tz = sprintf('%+05d', $winter_tz + 100); # 'one hour'

    my $got_tz = gettz($date);
#    t "got timezone $got_tz from date $date";
    if (defined $got_tz) {
	# Need to work out whether the timezone is one of the two
	# allowable values (or UTC, that's always okay).
	#
	# I don't remember the reason for this check... perhaps it is
	# just paranoia.
	#
	my $got_tz_num = tz_to_num($got_tz);
	croak "got timezone $got_tz from $date, but it's not $winter_tz, $summer_tz or UTC\n"
	    if $got_tz_num ne $winter_tz and $got_tz_num ne $summer_tz
	      and $got_tz_num ne '+0000';

	# One thing we don't check is that the explicit timezone makes
	# sense for this time of year.  So you can specify summer
	# time even in January if you want.
	#

	# OK, the timezone is there and it looks sane, continue.
	return parse_date($date);
    }

    t 'no timezone present, we need to guess';
    my $dp = parse_date($date);
    t "parsed date string $date into: " . d $dp;

    # Start and end of summer time in that year, in UTC
    my $year = UnixDate($dp, '%Y');
    t "year of date is $year";
    die "cannot convert Date::Manip object $dp to year"
      if not defined $year;

    # Start and end dates of DST in local winter time.
    my ($start_dst, $end_dst);
    if ($Mode eq 'eur') {
	($start_dst, $end_dst) = @{dst_dates($year)};
    }
    elsif ($Mode eq 'na') {
	($start_dst, $end_dst) = @{dst_dates_na($year, $winter_tz)};
    }
    elsif ($Mode eq 'none') {
	return Date_ConvTZ($dp, offset_to_gmt($winter_tz), 'UTC');
    }
    else { die }

    foreach ($start_dst, $end_dst) {
	$_ = Date_ConvTZ($_, 'UTC', offset_to_gmt($winter_tz));
    }

    # The clocks shift backwards and forwards by one hour.
    my $clock_shift = "1 hour";

    # The times that the clocks go forward to in spring (local time)
    my $start_dst_skipto = DateCalc($start_dst, "+ $clock_shift");

    # The local time when the clocks go back
    my $end_dst_backfrom = DateCalc($end_dst, "+ $clock_shift");

    my $summer;
    if (Date_Cmp($dp, $start_dst) < 0) {
	# Before the start of summer time.
	$summer = 0;
    }
    elsif (Date_Cmp($dp, $start_dst) == 0) {
	# Exactly _at_ the start of summer time.  Really such a date
	# should not exist since the clocks skip forward an hour at
	# that point.  But we tolerate this fencepost error.
	#
	$summer = 0;
    }
    elsif (Date_Cmp($dp, $start_dst_skipto) < 0) {
	# This date is impossible, since the clocks skip forwards an
	# hour from $start_dst to $start_dst_skipto.  But some
	# listings sources seem to use it.  Assume it means winter
	# time.
	#
	$summer = 0;
    }
    elsif (Date_Cmp($dp, $end_dst) < 0) {
	# During summer time.
	$summer = 1;
    }
    elsif (Date_Cmp($dp, $end_dst_backfrom) < 0) {
#	warn("$date is ambiguous "
#	     . "(clocks go back from $end_dst_backfrom $summer_tz to $end_dst $winter_tz), "
#	     . "assuming $summer_tz" );

	$summer = 1;
    }
    else {
	# Definitely after the end of summer time.
	$summer = 0;
    }

    if ($summer) {
	t "summer time, converting $dp from $summer_tz to UTC";
	return Date_ConvTZ($dp, offset_to_gmt($summer_tz), 'UTC');
    }
    else {
	t "winter time, converting $dp from $winter_tz to UTC";
	return Date_ConvTZ($dp, offset_to_gmt($winter_tz), 'UTC');
    }
}


# date_to_local()
#
# Take a date in UTC and convert it to one of two timezones, depending
# on when during the year it is.
#
# Parameters:
#   date in UTC (from parse_date())
#   base timezone (winter time)
#
# Returns ref to list of
#   new date
#   timezone of new date
#
# For example, date_to_local with a date of 13:00 on June 10th 2000 and
# a base timezone of UTC would be be 14:00 +0100 on the same day.  The
# input and output date are both in Date::Manip internal format.
#
sub date_to_local( $$ ) {
    my ($d, $base_tz) = @_;
    croak 'date_to_local() expects a Date::Manip object as first argument'
      if (not defined $d) or ($d !~ /\S/);

    my $year = UnixDate($d, '%Y');
    if ((not defined $year) or ($year !~ tr/0-9//)) {
	croak "cannot get year from '$d'";
    }

    # Find the start and end dates of summer time.
    my ($start_dst, $end_dst);
    if ($Mode eq 'eur') {
	($start_dst, $end_dst) = @{dst_dates($year)};
    }
    elsif ($Mode eq 'na') {
	($start_dst, $end_dst) = @{dst_dates_na($year, $base_tz)};
    }
    elsif ($Mode eq 'none') {
	return [ Date_ConvTZ($d, 'UTC', offset_to_gmt($base_tz)), $base_tz ];
    }
    else { die }

    my $use_tz;
    if (Date_Cmp($d, $start_dst) < 0) {
	# Before the start of summer time.
	$use_tz = $base_tz;
    }
    elsif (Date_Cmp($d, $end_dst) < 0) {
	# During summer time.
	my $base_tz_num = tz_to_num($base_tz);
	$use_tz = sprintf('%+05d', $base_tz_num + 100); # one hour
    }
    else {
	# After summer time.
	$use_tz = $base_tz;
    }
    die if not defined $use_tz;
    return [ Date_ConvTZ($d, 'UTC', offset_to_gmt($use_tz)), $use_tz ];
}

# utc_offset()
#
# Given a date/time string in a parse_date() compatible format
# (preferably YYYYMMDDhhmmss) and a 'base' timezone (eg '+0100'),
# return this time string with UTC offset appended. The 'base'
# timezone should be the non-DST timezone for the country ('winter
# time'). This function figures out (through parse_local_date() and
# date_to_local()) whether DST is in effect for the specified date, and
# adjusts the UTC offset appropriately.
#
sub utc_offset( $$ ) {
    my ($indate, $basetz) = @_;
    croak "empty date" if not defined $indate;
    croak "empty base TZ" if not defined $basetz;
    $basetz = tz_to_num( $basetz )
      if $basetz !~ /^[-+]\d{4}$/;

    my $d = date_to_local(parse_local_date($indate, $basetz), $basetz);
    return UnixDate($d->[0],"%Y%m%d%H%M%S") . " " . $d->[1];
}

# dst_dates()
#
# Return the dates (in UTC) when summer starts and ends in a given
# year.  Private.
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
sub dst_dates( $ ) {
    die "usage: dst_dates(year), got args: @_" if @_ != 1;
    my $year = shift;
    die "don't know about DST before 1998" if $year < 1998;

    my ($start_dst, $end_dst);
    foreach (25 .. 31) {
	my $mar = "$year-03-$_" . ' 01:00:00 +0000';
	my $mar_d = parse_date($mar);
	$start_dst = $mar_d if UnixDate($mar_d, "%A") =~ /Sunday/;

	# A time between '00:00' and '01:00' just before the last
	# Sunday in October is ambiguous.
	#
	my $oct = "$year-10-$_" . ' 01:00:00 +0000';
	my $oct_d = parse_date($oct);
	$end_dst = $oct_d if UnixDate($oct_d, "%A") =~ /Sunday/;
    }
    die if not defined $start_dst or not defined $end_dst;

    return [ $start_dst, $end_dst ];
}

sub dst_dates_na( $$ ) {
    die "usage: dst_dates(year, winter_tz), got args: @_" if @_ != 2;
    my ($year, $winter_tz) = @_;
    die "don't know about DST before 1988" if $year < 1988;
    return dst_dates_na_old($year, $winter_tz) if $year < 2007;
    return dst_dates_na_new($year, $winter_tz);
}

# Old North American daylight saving time, used before 2007.
sub dst_dates_na_old( $$ ) {
    my ($year, $winter_tz) = @_;
    $winter_tz =~ /^\s*-\s*(\d\d)(?:00)?\s*$/
      or die "bad North American winter time zone $winter_tz";
    my $hours = $1;

    my ($start_dst, $end_dst);
    foreach (1 .. 31) {
	if (not defined $start_dst and $_ < 31) {
	    my $date = "$year-04-$_";
	    my $day = UnixDate(parse_date($date), '%A');
	    if ($day =~ /Sunday/) {
		# First Sunday in April.  DST starts at 02:00 local
		# standard time.
		#
		$start_dst = Date_ConvTZ(parse_date("$date 02:00"),
					 offset("-$winter_tz"), 'UTC');
	    }
	}

	my $date = "$year-10-$_";
	my $day = UnixDate(parse_date($date), '%A');
	next unless $day =~ /Sunday/;
	# A Sunday in October (and the last one we see will be the
	# last Sunday).  DST ends at 01:00 local standard time.
	#
	$end_dst = Date_ConvTZ(parse_date("$date 01:00"),
			       offset_to_gmt("-$winter_tz"), 'UTC');
    }
    die if not defined $start_dst or not defined $end_dst;

    return [ $start_dst, $end_dst ];
}

# New US daylight saving time from 2007, also followed by most
# Canadian provinces.
#
sub dst_dates_na_new( $$ ) {
    my ($year, $winter_tz) = @_;
    $winter_tz =~ /^\s*-\s*(\d\d)(?:00)?\s*$/
      or die "bad North American winter time zone $winter_tz";
    my $hours = $1;

    my ($start_dst, $end_dst);
    my $seen_Sunday_in_March = 0;
    foreach (1 .. 31) {
	if (not defined $start_dst) {
	    my $date = "$year-03-$_";
	    my $day = UnixDate(parse_date($date), '%A');
	    if ($day =~ /Sunday/) {
		if ($seen_Sunday_in_March) {
		    # Second Sunday in March.  DST starts at 02:00
		    # local standard time.
		    #
		    $start_dst = Date_ConvTZ(parse_date("$date 02:00"),
					     offset_to_gmt("-$winter_tz"), 'UTC');
		}
		else {
		    $seen_Sunday_in_March = 1;
		}
	    }
	}

	next if defined $end_dst;
	my $date = "$year-11-$_";
	my $day = UnixDate(parse_date($date), '%A');
	next unless $day =~ /Sunday/;
	# A Sunday in November (and the first one we see).  DST ends
	# at 01:00 local standard time.
	#
	$end_dst = Date_ConvTZ(parse_date("$date 01:00"),
			       offset_to_gmt("-$winter_tz"), 'UTC');
    }
    die if not defined $start_dst or not defined $end_dst;

    return [ $start_dst, $end_dst ];
}


1;
