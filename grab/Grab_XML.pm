package XMLTV::Grab_XML;
use strict;
use Getopt::Long;
use Date::Manip;
use XMLTV;
use XMLTV::Usage;
use XMLTV::Memoize;
use XMLTV::ProgressBar;
use XMLTV::Ask;
use XMLTV::TZ qw(parse_local_date);
use XMLTV::Get_nice qw();
use XMLTV::Date;

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
	Log::TraceMessages::check_argv();
    }
}

=pod

=head1 NAME

XMLTV::Grab_XML - Perl extension to fetch raw XMLTV data from a site

=head1 SYNOPSIS

    package Grab_XML_rur;
    use base 'XMLTV::Grab_XML';
    sub urls_by_date( $ ) { my $pkg = shift; ... }
    sub country( $ ) { my $pkg = shift; return 'Ruritania' }
    # Maybe override a couple of other methods as described below...
    Grab_XML_rur->go();

=head1 DESCRIPTION

This module helps to write grabbers which fetch pages in XMLTV format
from some website and output the data.  It is not used for grabbers
which scrape human-readable sites.

It consists of several class methods (package methods).  The way to
use it is to subclass it and override some of these.

=head1 METHODS

=over

=item XMLTV::Grab_XML->date_init()

Called at the start of the program to set up Date::Manip.  You might
want to override this with a method that sets the timezone.

=cut
sub date_init( $ ) {
    my $pkg = shift;
    Date_Init();
}

=pod

=item XMLTV::Grab_XML->urls_by_date()

Returns a hash mapping YYYYMMDD dates to a URL where listings for that
date can be downloaded.  This method is abstract, you must override
it.

Arguments: the command line options for --config-file and --quiet.

=cut
sub urls_by_date( $$$ ) {
    my $pkg = shift;
    die 'abstract class method: override in subclass';
}

=pod

=item XMLTV::Grab_XML->xml_from_data(data)

Given page data for a particular day, turn it into XML.  The default
implementation just returns the data unchanged, but you might override
it if you need to decompress the data or patch it up.

=cut
sub xml_from_data( $$ ) {
    my $pkg = shift;
    t 'Grab_XML::xml_from_data()';
    return shift; # leave unchanged
}

=pod

=item XMLTV::Grab_XML->configure()

Configure the grabber if needed.  Arguments are --config-file option
(or undef) and --quiet flag (or undef).

This method is not provided in the base class; if you don't provide it
then attempts to --configure will give a message that configuration is
not necessary.

=item XMLTV::Grab_XML->nextday(day)

Bump a YYYYMMDD date by one.  You probably shouldnE<39>t override this.

=cut
sub nextday( $$ ) {
    my $pkg = shift;
    my $d = shift; $d =~ /^\d{8}$/ or die;
    my $p = parse_date($d);
    my $n = DateCalc($p, '+ 1 day'); die if not defined $n;
    return UnixDate($n, '%Q');
}

=item XMLTV::Grab_XML->country()

Return the name of the country youE<39>re grabbing for, used in usage
messages.  Abstract.

=cut
sub country( $ ) {
    my $pkg = shift;
    die 'abstract class method: override in subclass';
}

=item XMLTV::Grab_XML->usage_msg()

Return a command-line usage message.  This calls C<country()>, so you
probably need to override only that method.

=cut
sub usage_msg( $ ) {
    my $pkg = shift;
    my $country = $pkg->country();
    if ($pkg->can('configure')) {
        return <<END
$0: get $country television listings in XMLTV format
usage: $0 --configure [--config-file FILE]
       $0 [--output FILE] [--days N] [--offset N] [--quiet] [--config-file FILE]
       $0 --help
END
      ;
    }
    else {
        return <<END
$0: get $country television listings in XMLTV format
usage: $0 [--output FILE] [--days N] [--offset N] [--quiet]
       $0 --help
END
      ;
    }
}

=item XMLTV::Grab_XML->get()

Given a URL, fetch the content at that URL.  The default
implementation calls XMLTV::Get_nice::get_nice() but you might want to
override it if you need to do wacky things with http requests, like
cookies.

Note that while this method fetches a page, C<xml_from_data()> does
any further processing of the result to turn it into XML.

=cut
sub get( $$ ) {
    my $pkg = shift;
    my $url = shift;
    return XMLTV::Get_nice::get_nice($url);
}

=item XMLTV::Grab_XML->go()

The main program.  Parse command line options, fetch and write data.

Most of the options are fairly self-explanatory but this routine also
calls the XMLTV::Memoize module to look for a B<--cache> argument.
The functions memoized are those given by the C<cachables()> method.

=cut
sub go( $ ) {
    my $pkg = shift;
    XMLTV::Memoize::check_argv($pkg->cachables());
    my ($opt_days,
	$opt_help,
	$opt_output,
	$opt_share,
	$opt_gui,
	$opt_offset,
	$opt_quiet,
	$opt_configure,
	$opt_config_file,
	$opt_list_channels,
       );
    $opt_offset = 0;		# default
    $opt_quiet = 0;		# default
    GetOptions('days=i'        => \$opt_days,
	       'help'          => \$opt_help,
	       'output=s'      => \$opt_output,
	       'share=s'       => \$opt_share, # undocumented
	       'gui:s'         => \$opt_gui,
	       'offset=i'      => \$opt_offset,
	       'quiet'         => \$opt_quiet,
	       'configure'     => \$opt_configure,
	       'config-file=s' => \$opt_config_file,
	       'list-channels' => \$opt_list_channels,
	      )
      or usage(0, $pkg->usage_msg());
    die 'number of days must not be negative'
      if (defined $opt_days && $opt_days < 0);
    usage(1, $pkg->usage_msg()) if $opt_help;
    usage(0, $pkg->usage_msg()) if @ARGV;

    XMLTV::Ask::init($opt_gui);
    if ($opt_share) {
        if ($pkg->can('set_share_dir')) {
            $pkg->set_share_dir($opt_share);
        }
        else {
            print STDERR "share directory not in use\n";
        }
    }

    my $has_config = $pkg->can('configure');
    if ($opt_configure) {
        if ($has_config) {
            $pkg->configure($opt_config_file, $opt_quiet);
        }
        else {
            print STDERR "no configuration necessary\n";
        }
        exit;
    }

    for ($opt_config_file) {
        warn("this grabber has no configuration, so ignoring --config-file\n"), undef $_
          if defined and not $has_config;
    }

    # Need to call parse_local_date() before any resetting of
    # Date::Manip's timezone.
    #
    my $now = DateCalc(parse_local_date('now'), "$opt_offset days");
    die if not defined $now;
    $pkg->date_init();
    my $today = UnixDate($now, '%Q');

    my %urls = $pkg->urls_by_date($opt_config_file, $opt_quiet);
    t 'URLs by date: ' . d \%urls;

    my @to_get;
    if ($opt_list_channels) {
	# We won't bother to do an exhaustive check for every option
	# that is ignored with --list-channels.
	#
	die "useless to give --days or --offset with --list-channels\n"
	    if defined $opt_days or $opt_offset != 0;

	# For now, assume that the upstream site doesn't provide any
	# way to get just the channels, so we'll have to pick a
	# listings file and then discard most of it.
	#
	my @dates = sort keys %urls;
	die 'no dates found on site' if not @dates;
	my $latest = $dates[-1];
	@to_get = $urls{$latest};
    }
    else {
	# Getting programme listings.
	my $days_left = $opt_days;
	t '$days_left starts at ' . d $days_left;
	t '$today=' . d $today;
	for (my $day = $today; defined $urls{$day}; $day = $pkg->nextday($day)) {
	    t "\$urls{$day}=" . d $urls{$day};
	    if (defined $days_left and $days_left-- == 0) {
		t 'got to last day';
		last;
	    }
	    push @to_get, $urls{$day};
	}
	if (defined $days_left and $days_left > 0) {
	    warn "couldn't get all of $opt_days days, only "
		. ($opt_days - $days_left) . "\n";
	}
	elsif (not @to_get) {
	    warn "couldn't get any listings from the site for today or later\n";
	}
    }

    my $bar = new XMLTV::ProgressBar('downloading listings', scalar @to_get)
      if not $opt_quiet;
    my @listingses;
    foreach my $url (@to_get) {
	my $xml;

	# Set error handlers.  Strange bugs if you call warn() or
	# die() inside these, at least I have seen such bugs in
	# XMLTV.pm, so I'm avoiding it here.
	#
	local $SIG{__WARN__} = sub {
	    my $msg = shift;
	    $msg = "warning: something's wrong" if not defined $msg;
	    print STDERR "$url: $msg\n";
	};
 	local $SIG{__DIE__} = sub {
 	    my $msg = shift;
 	    $msg = 'died' if not defined $msg;
 	    print STDERR "$url: $msg, exiting\n";
 	    exit(1);
 	};

	my $got = $pkg->get($url);
	if (not defined $got) {
	    warn 'failed to download, skipping';
	    next;
	}

	$xml = $pkg->xml_from_data($got);
	t 'got XML: ' . d $xml;
	if (not defined $xml) {
	    warn 'could not get XML from page, skipping';
	    next;
	}

	push @listingses, XMLTV::parse($xml);
	update $bar if not $opt_quiet;
    }
    $bar->finish() if not $opt_quiet;

    my %w_args = ();
    if (defined $opt_output) {
	my $fh = new IO::File ">$opt_output";
	die "cannot write to $opt_output\n" if not $fh;
	%w_args = (OUTPUT => $fh);
    }

    if ($opt_list_channels) {
	die if @listingses != 1;
	my $l = $listingses[0];
	undef $l->[3];                  # blank out programme data
	XMLTV::write_data($l, %w_args);
    }
    else {
	XMLTV::write_data(XMLTV::cat(@listingses), %w_args);
    }
}

=item XMLTV::Grab_XML->cachables()

Returns a list of names of functions which could reasonably be
memoized between runs.  This will normally be whatever function
fetches the web pages - you memoize that to save on repeated
downloads.  A subclass might want to add things to this list
if it has its own way of fetching web pages.

=cut
sub cachables( $ ) {
    my $pkg = shift;
    return ('XMLTV::Get_nice::get_nice_aux');
}

=pod

=item XMLTV::Grab_XML->remove_early_stop_times()

Checks each stop time and removes it if it's before the start time.

Argument: the XML to correct
Returns: the corrected XML

=cut

my $warned_bad_stop_time = 0;
sub remove_early_stop_times( $$ ) {
    my $pkg = shift;
    my @lines = split /\n/, shift;
    foreach (@lines) {
	if (/<programme/) {
	    # First change to numeric timezones.
	    s{(start|stop)="(\d+) ([A-Z]+)"}
	    {qq'$1="$2 ' . tz_to_num($3) . '"'}eg;

	    # Now remove stop times before start.  Only worry about
	    # cases where the timezone is the same - we hope the
	    # upstream data will be fixed by the next TZ changeover.
	    #
	    /start="(\d+) (\S+)"/ or next;
	    my ($start, $tz) = ($1, $2);
	    /stop="(\d+) \Q$tz\E"/ or next;
	    my $stop = $1;

	    if ($stop lt $start) {
		warn "removing stop time before start time: $_"
		  unless $warned_bad_stop_time++;
		s/stop="[^""]+"\s*// or die;
	    }
	}
    }
    return join("\n", @lines);
}

=pod

=back

=head1 AUTHOR

Ed Avis, ed@membled.com

=head1 SEE ALSO

L<perl(1)>, L<XMLTV(3)>.

=cut
1;

