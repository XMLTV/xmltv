package XMLTV::Date;
use warnings;
use strict;
use Carp qw(croak);
use base 'Exporter';
our @EXPORT = qw(parse_date);
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
	croak "cannot parse date '$raw'" if not length $parsed;
	return $parsed;
    }

    # Year not specified, see which fits best.
    if (not defined $now) {
	$now = ParseDate('now');
	die if not length $now;
	$this_year = UnixDate($now, '%Y');
	die if $this_year !~ /^\d{4}$/;
    }
    my @poss = grep length, map { ParseDate("$raw $_") }
      ($this_year - 1 .. $this_year + 1);

    if (not @poss) {
	# Well, tacking on a year didn't work, perhaps we'll have to
	# just parse the string as supplied.
	#
	$parsed = ParseDate($raw);
	croak "cannot parse date '$raw'" if not length $parsed;
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

1;
