=pod

=head1 NAME

XMLTV::Date - Date parsing routines for the xmltv package

=head1 SEE ALSO

L<Date::Manip>

=cut

package XMLTV::Date;

# use version number for feature detection:
# 0.005066 : added time_xxx subs
our $VERSION = 0.005066;

use warnings;
use strict;
use Carp qw(croak);
use base 'Exporter';
our @EXPORT = qw(parse_date time_xmltv_to_iso time_iso_to_xmltv time_xmltv_to_epoch time_iso_to_epoch);
use Date::Manip;

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

# These are populated when needed with the current time but then
# reused later.
#
my $now;
my $this_year;

=pod

=head1 C<parse_date()>

Wrapper for C<Date::Manip::ParseDate()> that does two things: firstly,
if the year is not specified it chooses between last year, this year
and next year depending on which date would be closest to now.  (If
only one of those dates is valid, for example because day-of-week is
specified, then the valid one is chosen; if the time can only be
parsed without adding an explicit year then that is chosen.)
Secondly, an exception is thrown if the date cannot be parsed.

Argument is a single string.

=cut
sub parse_date( $ ) {
    my $raw = shift;
    my $parsed;
    # Assume any string of 4 digits means the year.
    if ($raw =~ /\d{4}/) {
	$parsed = ParseDate($raw);
	croak "cannot parse date '$raw'" if not $parsed;
	return $parsed;
    }

    # Year not specified, see which fits best.
    if (not defined $now) {
	$now = ParseDate('now');
	die if not $now;
	$this_year = UnixDate($now, '%Y');
	die if $this_year !~ /^\d{4}$/;
    }
    my @poss;
    foreach (map { ParseDate("$raw $_") } ($this_year - 1 .. $this_year + 1)) {
	push @poss, $_ if $_;
    }

    if (not @poss) {
	# Well, tacking on a year didn't work, perhaps we'll have to
	# just parse the string as supplied.
	#
	$parsed = ParseDate($raw);
	croak "cannot parse date '$raw'" if not $parsed;
	return $parsed;
    }

    my $best_distance;
    my $best;
    foreach (@poss) {
	die if not defined;

	my $delta = DateCalc($now, $_);
	my $seconds = Delta_Format($delta, 0, '%st');
	die "cannot get seconds for delta '$delta'"
	  if not length $seconds;
	$seconds = abs($seconds);

	if (not defined $best
	    or $seconds < $best_distance) {
	    $best = $_;
	    $best_distance = $seconds;
	}
    }
    die if not defined $best;
    return $best;
}



=pod

=head1 C<time_xmltv_to_iso()>

Converts a XMLTV time  e.g. "20140412090000 +0300"
to ISO format i.e. "2014-04-12T09:00:00.000+03:00"

Argument is string time to convert.

=cut
sub time_xmltv_to_iso ( $ )
{
		$_[0] =~ m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s([\+-])(\d{2})(\d{2})$/;
		return "$1-$2-$3T$4:$5:$6.000$7$8:$9";
}


=pod

=head1 C<time_iso_to_xmltv()>

Converts an ISO time e.g. "2014-04-12T09:00:00.000+03:00"
to XMLTV format, i.e.  "20140412090000 +0300"

Argument is string time to convert.

=cut
sub time_iso_to_xmltv ( $ )
{
    my $time = shift;
		$time =~ s/[:-]//g;
		$time =~ /^(\d{8})T(\d{6}).*(\+\d{4})$/;
		return $1.$2.' '.$3;
}


=pod

=head1 C<time_xmltv_to_epoch()>

Converts a XMLTV time  e.g. "20140412090000 +0300"
to seconds since the epoch

(uses POSIX::mktime rather than Date::Manip to avoid issues with the latter)

Alternatively you could use DateTime::Format::XMLTV on CPAN

Argument is string time to convert.
Optional 2nd argument: set to 1 ignore the tz offset in the calculation

=cut
sub time_xmltv_to_epoch ( $;$ )
{
		my $time = shift;
		my $ignoreoffset = shift;		# set to 1 to ignore tz offset (i.e. 'local' epoch; else will get utc)

		my ($y, $m, $d, $h, $i, $s, $t, $th, $tm) = $time =~
		  m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s([\+-])(\d{2})(\d{2})$/;
		$y -= 1900; $m -= 1;	# re-base for mktime()
		use POSIX qw(mktime);
		my $epoch = POSIX::mktime($s, $i, $h, $d, $m, $y);

		if (!defined $ignoreoffset || !$ignoreoffset) {
			# note this isn't exact since it doesn't account for leap seconds, etc
			my $offset = ($th * 3600) + ($tm * 60);
			$epoch += $offset  if $t eq '-';
			$epoch -= $offset  if $t eq '+';
		}
		return $epoch;

}


=pod

=head1 C<time_iso_to_epoch()>

Converts an iso time (e.g. "2014-04-12T09:00:00.000+03:00") to epoch time

(uses POSIX::mktime rather than Date::Manip to avoid issues with the latter)

Alternatively you could use DateTime::Format::XMLTV on CPAN

Argument is string time to convert.
Optional 2nd argument: set to 1 ignore the tz offset in the calculation

=cut
sub time_iso_to_epoch ( $;$ )
{
		my $time = shift;
		my $ignoreoffset = shift;		# set to 1 to ignore tz offset (i.e. 'local' epoch; else will get utc)

		my ($y, $m, $d, $h, $i, $s, $ms, $t, $th, $tm) = $time =~
		  m/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})([\+-])(\d{2}):(\d{2})$/;
		$y -= 1900; $m -= 1;	# re-base for mktime()
		use POSIX qw(mktime);
		my $epoch = POSIX::mktime($s, $i, $h, $d, $m, $y);

		if (!defined $ignoreoffset || !$ignoreoffset) {
			# note this isn't exact since it doesn't account for leap seconds, etc
			my $offset = ($th * 3600) + ($tm * 60);
			$epoch += $offset  if $t eq '-';
			$epoch -= $offset  if $t eq '+';
		}
		return $epoch;
}

1;
