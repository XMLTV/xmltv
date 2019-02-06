package XMLTV::Summarize;
use strict;
use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw(summarize);
use Date::Manip;
use XMLTV;
use XMLTV::TZ qw(gettz ParseDate_PreservingTZ);

BEGIN {
    if (int(Date::Manip::DateManipVersion) >= 6) {
	Date::Manip::Date_Init("SetDate=now,UTC");
    } else {
	Date::Manip::Date_Init("TZ=UTC");
    }
}

=pod

=head1 NAME

XMLTV::Summarize - Perl extension to summarize XMLTV data

=head1 SYNOPSIS

    # First get some data from the XMLTV module, eg:
    use XMLTV;
    my $data = XMLTV::parsefile('tv_sorted.xml');
    my ($encoding, $credits, $ch, $progs) = @$data;

    # Now turn the sorted programmes into a printable summary.
    use XMLTV::Summarize qw(summarize);
    foreach (summarize($ch, $progs)) {
        if (not ref) {
            print "\nDay: $_\n\n";
        }
        else {
            my ($start, $stop, $title, $sub_title, $channel) = @$_;
            print "programme starts at $start, ";
            print "stops at $stop, " if defined $stop;
            print "has title $title ";
            print "and episode title $sub_title" if defined $sub_title;
            print ", on channel $channel.\n";
        }
    }

=head1 DESCRIPTION

This module processes programme and channel data from the XMLTV module
to help produce a human-readable summary or TV guide.  It takes care
of choosing the correct language (based on the LANG environment
variable) and of looking up the name of channels from their id.

There is one public routine, C<summarize()>.  This takes (references
to) a channels hash and a programmes list, the same format as those
returned by the XMLTV module.  It returns a list of 'summary' elements
where each element is a list of five items: start time, stop time,
title, 'sub-title', and channel name.  The stop time and sub-title may
be undef.

The times are formatted as hh:mm, with a timezone appended when the
timezone changes in the middle of listings.  For the titles and
channel name, the shortest string that is in an acceptable language is
chosen.

The list of acceptable languages normally contains just one element,
taken from LANG, but you can set it manually as
@XMLTV::Summarize::PREF_LANGS if wished.

=head1 AUTHOR

Ed Avis, ed@membled.com

=head1 SEE ALSO

L<XMLTV(1)>.

=cut

# List of preferred languages.  Hopefully the environment variable
# $LANG will be set.
#
# After loading this module you are free to change @PREF_LANGS.  It is
# just a list of language codes.
#
our @PREF_LANGS;
my $el = $ENV{LANG};
if (defined $el and $el =~ /\S/) {
    $el =~ s/\..+$//; # remove character set
    @PREF_LANGS = ($el);
}
else {
    @PREF_LANGS = ('en');
}

# Private.
sub shorter( $$ ) { length($_[0]) <=> length($_[1]) }

# Generate summary information of programmes, suitable for generating
# a terse printed listings guide.
#
# Parameters:
#   channels hash
#   programmes list
# (both these from XMLTV::parsefiles() or whatever)
#
# It works best if the programmes are sorted by date.
#
sub summarize( $$ ) {
    my ($ch, $progs) = @_;
    my @r;
    my $ch_name = find_channel_names($ch);

    my ($curr_date, $curr_tz);
    foreach (@$progs) {
	my ($start, $start_tz, $start_hhmm);
	$start = ParseDate_PreservingTZ($_->{start});
	$start_tz = gettz($_->{start}) || 'UTC';
	$start_hhmm = UnixDate($start, '%R');

	my ($stop, $stop_tz, $stop_hhmm);
	if (defined $_->{stop}) {
	    $stop = ParseDate_PreservingTZ($_->{stop});
	    $stop_tz = gettz($_->{stop}) || 'UTC';
	    $stop_hhmm = UnixDate($stop, '%R');
	}

	my $date = UnixDate($start, '%m-%d (%A)');
	if (not defined $curr_date or $curr_date ne $date) {
	    $curr_date = $date;
	    push @r, $date;
	}

	my $title = XMLTV::best_name(\@PREF_LANGS, $_->{title},
				     \&shorter)->[0];
	my $sub_title;
	if (defined $_->{'sub-title'}) {
	    $sub_title
	      = XMLTV::best_name(\@PREF_LANGS, $_->{'sub-title'},
				 \&shorter)->[0];
	}

	my $desc;
	if (defined $_->{'desc'}) {
		# No comparator, just get the first one in the preferred language (this is probably the best/shortest in most cases)
	    $desc
	      = XMLTV::best_name(\@PREF_LANGS, $_->{'desc'})->[0];
	    $desc =~ tr/\t\n/ /;	# remove tabs and newlines
	}

	if (not defined $curr_tz) {
	    # Assume that the first item in a listing doesn't need an
	    # explicit timezone.
	    #
	    $curr_tz = $start_tz;
	}

	if ((not defined $curr_tz)
	    or ($curr_tz ne $start_tz)
	    or (defined $stop_tz and $start_tz ne $stop_tz)) {
	    # The timezone has changed somehow - make it explicit.
	    $start_hhmm .= " $start_tz";
	    $stop_hhmm .= " $stop_tz" if defined $stop_hhmm;
	    undef $curr_tz;
	}

	unless (defined $stop_tz and $start_tz ne $stop_tz) {
	    # The programme probably starts and stops in the same TZ -
	    # we can assume that this is the one to use from now on.
	    #
	    $curr_tz = $start_tz;
	}

	# Look up pretty name of channel.
	my $channel = $ch_name->{$_->{channel}};
	if (not defined $channel) {
	    # No <channel> with this id.  That's okay, since the XMLTV
	    # format doesn't mandate it... yet.  We choose the XMLTV
	    # id instead.
	    #
	    $channel = $_->{channel};
	}

	push @r, [ $start_hhmm, $stop_hhmm, $title, $sub_title, $channel, $desc ];
    }
    return @r;
}


# find_channel_names()
#
# Parameter: refhash of channels data from parsefiles()
# Returns: ref to hash mapping channel id to printable channel name
#
sub find_channel_names( $ ) {
    my $h = shift;
    my %r;
    foreach my $id (keys %$h) {
	my @names = @{$h->{$id}->{'display-name'}};
	die "channels hash has no name for $id" if not @names;
	my $best = XMLTV::best_name(\@PREF_LANGS, \@names,
				    \&shorter)->[0];
	die "couldn't get name for channel $id" if not defined $best;

	# There's no need to warn about more than one channel having
	# the same human-readable name: that's deliberate (eg regional
	# variants of the same channel may all have the same number).
	# Maybe it could be checked when the channel id is actually
	# looked up to get the name, that the name hasn't been used
	# for a different channel id.  But we won't even do that for
	# now.
	#
	$r{$id} = $best;
    }
    return \%r;
}

1;
