# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://www.tvnyt.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::tvnyt;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

use Carp;
use HTML::Entities qw(decode_entities);
use JSON qw(-support_by_pp); # enable allow_barekey() for JSON:XS

# Import from internal modules
fi::common->import();

# Description
sub description { 'tvnyt.fi' }

# Copied from Javascript code. No idea why we should do this...
sub _timestamp() {
  # This obviously breaks caching. Use constant value instead
  #return("timestamp=" . int(rand(10000)));
  return("timestamp=0");
}

# Grab channel list
sub channels {

  # Fetch JavaScript code as raw file
  my $content = fetchRaw("http://www.tvnyt.fi/ohjelmaopas/wp_channels.js?" . _timestamp());
  if (length($content)) {
    my $count = 0;
    # 1) pattern match JS arrays (example: ["1","TV1","tv1.gif"] -> 1, "TV1")
    # 2) even entries in the list are converted to XMLTV ID
    # 3) fill hash from list (even -> key [id], odd -> value [name])
    my %channels = (
		    map { ($count++ % 2) == 0 ? "$_.tvnyt.fi" : "fi $_" }
		      $content =~ /\["(\d+)","([^\"]+)","[^\"]+"\]/g
		   );
    debug(2, "Source tvnyt.fi parsed " . scalar(keys %channels) . " channels");
    return(\%channels);
  }

  return;
}

# Parse time stamp and convert to Epoch using local time zone
#
# Example time stamp: 20101218040000
#
sub _toEpoch($) {
  my($string) = @_;
  return unless defined($string);
  return unless my($year, $month, $day, $hour, $minute) =
    ($string =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})\d{2}$/);
  return(fullTimeToEpoch($year, $month, $day, $hour, $minute));
}

# Category number to name map
my %category_map = (
		    0 => undef,
		    1 => "dokumentit",
		    2 => "draama",
		    3 => "lapset",
		    4 => "uutiset",
		    5 => "urheilu",
		    6 => "vapaa aika",
		   );

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow) = @_;

  # Get channel number from XMLTV id
  return unless my($channel) = ($id =~ /^(\d+)\.tvnyt\.fi$/);

  # Fetch JavaScript code as raw file
  my $content = fetchRaw("http://www.tvnyt.fi/ohjelmaopas/getChannelPrograms.aspx?channel=$channel&start=${today}0000&" . _timestamp());
  if (length($content)) {
    # Accept "x:.." instead of the correct "'x':..."
    my $parser = JSON->new()->allow_barekey();

    # Fixup data
    $content =~ s/\\/\\\\/g; # some string contain illegal escapes

    # Parse data
    my $data   = eval {
      $parser->decode($content)
    };
    croak "JSON parse error: $@" if $@;
    undef $parser;

    #
    # Program information is encoded in JSON:
    #
    # {
    #  1: [
    #      {
    #       id:       "17111541",
    #       desc:     "&#x20;",
    #       title:    "Uutisikkuna",
    #       category: "0",
    #       start:    "20101218040000",
    #       stop:     "20101218080000"
    #      },
    #      ...
    #     ]
    # }
    #
    # - the first entry always starts on $today.
    # - the last entry is a duplicate of the first entry on $tomorrow. We drop
    #   it to avoid duplicate programme entries.
    #
    # Category types:
    #
    #   0 - unknown
    #   1 - dokumentit (documentary)
    #   2 - draama     (drama)
    #   3 - lapset     (children)
    #   4 - uutiset    (news)
    #   5 - urheilu    (sports)
    #   6 - vapaa aika (recreational)
    #
    # Verify top-level of data structure
    if ((ref($data) eq "HASH") &&
	(exists $data->{1})    &&
	(ref($data->{1}) eq "ARRAY")) {

      my @objects;
      foreach my $array_entry (@{ $data->{1} }) {
	my $start = $array_entry->{start};
	my $stop  = $array_entry->{stop};
	my $title = decode_entities($array_entry->{title});
	my $desc  = decode_entities($array_entry->{desc});

	# Sanity check
	# Drop "no programm" entries
	if (($start = _toEpoch($start)) &&
	    ($stop  = _toEpoch($stop))  &&
	    length($title)              &&
	    ($title ne "Ei ohjelmaa.")) {
	  my $category = $array_entry->{category};

	  debug(3, "List entry $channel ($start -> $stop) $title");
	  debug(4, $desc);

	  # Map category number to name
	  $category = $category_map{$category} if defined($category);

	  # Create program object
	  my $object = fi::programme->new($id, "fi", $title, $start, $stop);
	  $object->category($category);
	  $object->description($desc);
	  push(@objects, $object);
	}
      }

      # Drop last entry
      pop(@objects);

      # Fix overlapping programmes
      fi::programme->fixOverlaps(\@objects);

      return(\@objects);
    }
  }

  return;
}

# That's all folks
1;
