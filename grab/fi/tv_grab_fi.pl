#!/usr/bin/perl -w
# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# Setup
#
###############################################################################
use 5.008; # we process Unicode texts
use strict;
use warnings;

use XMLTV;
use constant VERSION => "$XMLTV::VERSION";

###############################################################################
# INSERT: SOURCES
###############################################################################
package main;

# Perl core modules
use Getopt::Long;
use List::Util qw(shuffle);
use Pod::Usage;

# CUT CODE START
###############################################################################
# Load internal modules
use FindBin qw($Bin);
BEGIN {
  foreach my $source (<$Bin/fi/*.pm>, <$Bin/fi/source/*.pm>) {
    require "$source";
  }
}
###############################################################################
# CUT CODE END

# Generate source module list
my @sources;
BEGIN {
  @sources = map { s/::$//; $_ }
    map { "fi::source::" . $_ }
    sort
    grep { ${ $::{'fi::'}->{'source::'}->{$_}->{ENABLED} } }
    keys %{ $::{'fi::'}->{'source::'} };
  die "$0: couldn't find any source modules?" unless @sources;
}

# Import from internal modules
fi::common->import(':main');

# Basic XMLTV modules
use XMLTV::Version VERSION;
use XMLTV::Capabilities qw(baseline manualconfig cache);
use XMLTV::Description 'Finland (' .
  join(', ', map { $_->description() } @sources ) .
  ')';

# NOTE: We will only reach the rest of the code only when the script is called
#       without --version, --capabilities or --description
# Reminder of XMLTV modules
use XMLTV::Get_nice;
use XMLTV::Memoize;

###############################################################################
#
# Main program
#
###############################################################################
# Forward declarations
sub doConfigure();
sub doListChannels();
sub doGrab();

# Command line option default values
my %Option = (
	      days   => 14,
	      quiet  =>  0,
	      debug  =>  0,
	      offset =>  0,
	     );

# Enable caching. This will remove "--cache [file]" from @ARGV
XMLTV::Memoize::check_argv('XMLTV::Get_nice::get_nice_aux');

# Process command line options
if (GetOptions(\%Option,
	       "configure",
	       "config-file=s",
	       "days=i",
	       "debug|d+",
	       "gui:s",
	       "help|h|?",
	       "list-channels",
	       "no-randomize",
	       "offset=i",
	       "output=s",
	       "quiet",
	       "test-mode")) {

  pod2usage(-exitstatus => 0,
	    -verbose => 2)
    if $Option{help};

  setDebug($Option{debug});
  setQuiet($Option{quiet});

  if ($Option{configure}) {
    # Configure mode
    doConfigure();

  } elsif ($Option{'list-channels'}) {
    # List channels mode
    doListChannels();

  } else {
    # Grab mode (default)
    doGrab();
  }
} else {
  pod2usage(2);
}

# That's all folks
exit 0;

###############################################################################
#
# Utility functions for the different modes
#
###############################################################################
sub _getConfigFile() {
  require XMLTV::Config_file;
  return(XMLTV::Config_file::filename($Option{'config-file'},
				      "tv_grab_fi",
				      $Option{quiet}));
}

{
  my $ofh;

  sub _createXMLTVWriter() {

    # Output file handling
    $ofh = \*STDOUT;
    if (defined $Option{output}) {
      open($ofh, ">", $Option{output})
	or die "$0: cannot open file '$Option{output}' for writing: $!";
    }

    # Create XMLTV writer for UTF-8 encoded text
    binmode($ofh, ":utf8");
    my $writer = XMLTV::Writer->new(
				    encoding => 'UTF-8',
				    OUTPUT   => \*STDOUT,
				   );

    #### HACK CODE ####
    $writer->start({
		    "generator-info-name" => "XMLTV",
		    "generator-info-url"  => "http://xmltv.org/",
		    "source-info-url"     => "multiple", # TBA
		    "source-data-url"     => "multiple", # TBA
		   });
    #### HACK CODE ####

    return($writer);
  }

  sub _closeXMLTVWriter($) {
    my($writer) = @_;
    $writer->end();

    # close output file
    if ($Option{output}) {
      close($ofh) or die "$0: write error on file '$Option{output}': $!";
    }
    message("DONE");
  }
}

sub _addChannel($$$$) {
  my($writer, $id, $name, $language) = @_;
  $writer->write_channel({
			  id             => $id,
			  'display-name' => [[$name, $language]],
			 });
}

{
  my $bar;

  sub _createProgressBar($$) {
    my($label, $count) = @_;
    return if $Option{quiet};

    require XMLTV::Ask;
    require XMLTV::ProgressBar;
    XMLTV::Ask::init($Option{gui});
    $bar = XMLTV::ProgressBar->new({
				    name  => $label,
				    count => $count,
				   });
  }

  sub _updateProgressBar()  { $bar->update() if defined $bar }
  sub _destroyProgressBar() { $bar->finish() if defined $bar }
}

sub _getChannels($$) {
  my($callback, $opaque) = @_;

  # Get channels from all sources
  _createProgressBar("getting list of channels", @sources);
  foreach my $source (@sources) {
    debug(1, "requesting channel list from source '" . $source->description ."'");
    if (my $list = $source->channels()) {
      die "test failure: source '" . $source->description . "' didn't find any channels!\n"
	if ($Option{'test-mode'} && (keys %{$list} == 0));

      while (my($id, $value) = each %{ $list }) {
	my($language, $name) = split(" ", $value, 2);
	$callback->($opaque, $id, $name, $language);
      }
    }
    _updateProgressBar();
  }
  _destroyProgressBar();
}

###############################################################################
#
# Configure Mode
#
###############################################################################
sub doConfigure() {
  # Get configuration file name
  my $file = _getConfigFile();
  XMLTV::Config_file::check_no_overwrite($file);

  # Open configuration file. Assume UTF-8 encoding
  open(my $fh, ">:utf8", $file)
      or die "$0: can't open configuration file '$file': $!";
  print $fh "# -*- coding: utf-8 -*-\n";

  # Get channels
  my %channels;
  _getChannels(sub {
		 # We only need name and ID
		 my(undef, $id, $name) = @_;
		 $channels{$id} = $name;
	       },
	       undef);

  # Query user
  my @sorted  = sort keys %channels;
  my @answers = XMLTV::Ask::ask_many_boolean(1, map { "add channel $channels{$_} ($_)?" } @sorted);

  # Generate configuration file contents from answers
  foreach my $id (@sorted) {
    warn("\nunexpected end of input reached\n"), last
      unless @answers;

    # Write selection to configuration file
    my $answer = shift(@answers);
    print $fh ($answer ? "" : "#"), "channel $id $channels{$id}\n";
  }

  # Check for write errors
  close($fh)
    or die "$0: can't write to configuration file '$file': $!";
  message("DONE");
}

###############################################################################
#
# List Channels Mode
#
###############################################################################
sub doListChannels() {
  # Create XMLTV writer
  my $writer = _createXMLTVWriter();

  # Get channels
  _getChannels(sub {
		 my($writer, $id, $name, $language) = @_;
		 _addChannel($writer, $id, $name, $language);
		 },
	       $writer);

  # Done writing
  _closeXMLTVWriter($writer);
}

###############################################################################
#
# Grab Mode
#
###############################################################################
sub doGrab() {
  # Sanity check
  die "$0: --offset must be a non-negative integer"
    unless $Option{offset} >= 0;
  die "$0: --days must be an integer larger than 0"
    unless $Option{days} > 0;

  # Get configuation
  my %channels;
  {
    # Get configuration file name
    my $file = _getConfigFile();

    # Open configuration file. Assume UTF-8 encoding
    open(my $fh, "<:utf8", $file)
      or die "$0: can't open configuration file '$file': $!";

    # Process configuration information
    while (<$fh>) {

      # Comment removal, white space trimming and compressing
      s/\#.*//;
      s/^\s+//;
      s/\s+$//;
      next unless length;	# skip empty lines
      s/\s+/ /;

      # Channel definition
      if (my($id, $name) = /^channel (\S+) (.+)/) {
	debug(1, "duplicate channel definion in line $.:$id ($name)")
	  if exists $channels{$id};
	$channels{$id} = $name;

      # Programme definition
      } elsif (fi::programme->parseConfigLine($_)) {
	# Nothing to be done here

      } else {
	warn("bad configuration line in file '$file', line $.: $_\n");
      }
    }

    close($fh);
  }

  # Generate list of days
  my $dates = fi::day->generate($Option{offset}, $Option{days});

  # Set up time zone
  setTimeZone();

  # Create XMLTV writer
  my $writer = _createXMLTVWriter();

  # Generate task list with one task per channel and day
  my @tasklist;
  foreach my $id (sort keys %channels) {
    for (my $i = 1; $i < $#{ $dates }; $i++) {
      push(@tasklist, [$id,
		       @{ $dates }[$i - 1..$i + 1],
		       $Option{offset} + $i - 1]);
    }
  }

  # Randomize the task list in order to create a random access pattern
  # NOTE: if you use only one source, then this is basically a no-op
  if (not $Option{'no-randomize'}) {
    debug(1, "Randomizing task list");
    @tasklist = shuffle(@tasklist);
  }

  # For each entry in the task list
  my %seen;
  my @programmes;
  _createProgressBar("getting listings", @tasklist);
  foreach my $task (@tasklist) {
    my($id, $yesterday, $today, $tomorrow, $offset) = @{$task};
    debug(1, "XMLTV channel ID '$id' fetching day $today");
    foreach my $source (@sources) {
      if (my $programmes = $source->grab($id,
					 $yesterday, $today, $tomorrow,
					 $offset)) {

	if (@{ $programmes }) {
	  # Add channel ID & name (once)
	  _addChannel($writer, $id, $channels{$id},
		      $programmes->[0]->language())
	    unless $seen{$id}++;

	  # Add programmes to list
	  push(@programmes, @{ $programmes });
	} elsif ($Option{'test-mode'}) {
	  die "test failure: source '" . $source->description . "' didn't retrieve any programmes for '$id'!\n";
	}
      }
    }
    _updateProgressBar();
  }
  _destroyProgressBar();

  # Dump programs
  message("writing XMLTV programme data");
  $_->dump($writer) foreach (@programmes);

  # Done writing
  _closeXMLTVWriter($writer);
}

###############################################################################
#
# Man page
#
###############################################################################
__END__
=pod

=head1 NAME

tv_grab_fi - Grab TV listings for Finland

=head1 SYNOPSIS

tv_grab_fi [--cache E<lt>FILEE<gt>]
           [--config-file E<lt>FILEE<gt>]
           [--days E<lt>NE<gt>]
           [--gui [E<lt>OPTIONE<gt>]]
           [--no-randomize]
           [--offset E<lt>NE<gt>]
           [--output E<lt>FILEE<gt>]
           [--quiet]

tv_grab_fi  --capabilities

tv_grab_fi  --configure
           [--cache E<lt>FILEE<gt>]
           [--config-file E<lt>FILEE<gt>]
           [--gui [E<lt>OPTIONE<gt>]]
           [--quiet]

tv_grab_fi  --description

tv_grab_fi  --help|-h|-?

tv_grab_fi  --list-channels
           [--cache E<lt>FILEE<gt>]
           [--gui [E<lt>OPTIONE<gt>]]
           [--quiet]

tv_grab_fi  --version

=head1 DESCRIPTION

Grab TV listings for several channels available in Finland. The data comes
from various sources, e.g. www.telkku.com. The grabber relies on parsing HTML,
so it might stop working when the web page layout is changed.

You need to run C<tv_grab_fi --configure> first to create the channel
configuration for your setup. Subsequently runs of C<tv_grab_fi> will grab
the latest data, process them and produce XML data on the standard output.

=head1 COMMANDS

=over 8

=item B<NONE>

Grab mode.

=item B<--capabilities>

Show the capabilities this grabber supports. See also
L<http://wiki.xmltv.org/index.php/XmltvCapabilities>.

=item B<--configure>

Generate the configuration file by asking the users which channels to grab.

=item B<--description>

Print the description for this grabber.

=item B<--help|-h|-?>

Show this help page.

=item B<--list-channels>

Fetch all available channels from the various sources and write them to the
standard output.

=item B<--version>

Show the version of this grabber.

=back

=head1 GENERIC OPTIONS

=over 8

=item B<--cache F<FILE>>

File name to cache the fetched HTML data in. This speeds up subsequent runs
using the same data.

=item B<--gui [OPTION]>

Enable the graphical user interface. If you don't specify B<OPTION> then
XMLTV will automatically choose the best available GUI. Allowed values are:

=over 4

=item B<Term>

Terminal output with a progress bar

=item B<TermNoProgressBar>

Terminal output without progress bar

=item B<Tk>

Tk-based GUI

=back

=item B<--quiet>

Suppress any progress messages to the standard output.

=back

=head1 CONFIGURE MODE OPTIONS

=over 8

=item B<--config-file F<FILE>>

File name to write the configuration to.

Default is F<$HOME/.xmltv/tv_grab_fi.conf>.

=back

=head1 GRAB MODE OPTIONS

=over 8

=item B<--config-file F<FILE>>

File name to read the configuration from.

Default is F<$HOME/.xmltv/tv_grab_fi.conf>.

=item B<--days C<N>>

Grab C<N> days of TV data.

Default is 14 days.

=item B<--no-randomize>

Grab TV data in deterministic order, i.e. first fetch channel 1, days 1 to N,
then channel 2, and so on.

Default is to use a random access pattern. If you only grab TV data from one
source then the randomizing is a no-op.

=item B<--offset C<N>>

Grab TV data starting at C<N> days in the future.

Default is 0, i.e. today.

=item B<--output F<FILE>>

Write the XML data to F<FILE> instead of the standard output.

=back

=head1 CONFIGURATION FILE SYNTAX

The configuration file is line oriented, each line can contain one command.
Empty lines and everything after the C<#> comment character is ignored.
Supported commands are:

=over 8

=item B<channel ID NAME>

Grab information for this channel. C<ID> depends on the source, C<NAME> is
ignored and forwarded as is to the XMLTV output file. This information can be
automatically generated using the grabber in the configuration mode.

=item B<series description NAME>

If a programme title matches C<NAME> then the first sentence of the
description, i.e. everything up to the first period (C<.>), question mark
(C<?>) or exclamation mark (C<!>), is removed from the description and is used
as the name of the episode.

=item B<series title NAME>

If a programme title contains a colon (C<:>) then the grabber checks if the
left-hand side of the colon matches C<NAME>. If it does then the left-hand
side is used as programme title and the right-hand side as the name of the
episode.

=item B<title map "FROM" 'TO'>

If the programme title starts with the string C<FROM> then replace this part
with the string C<TO>. The strings must be enclosed in single quotes (C<'>) or
double quotes (C<">). The title mapping occurs before the C<series> command
processing.

=item B<title strip parental level>

At the beginning of 2012 some programme descriptions started to include
parental levels at the end of the title, e.g. C<(S)>. With this command all
parental levels will be removed from the titles automatically. This removal
occurs before the title mapping.

=back

=head1 SEE ALSO

L<xmltv>.

=head1 AUTHORS

=head2 Current

=over

=item Stefan Becker C<chemobejk at gmail dot com>

=item Ville Ahonen C<ville dot ahonen at iki dot fi>

=back

=head2 Retired

=over

=item Matti Airas

=back

=head1 BUGS

The channels are identified by channel number rather than the RFC2838 form
recommended by the XMLTV DTD.

=cut
