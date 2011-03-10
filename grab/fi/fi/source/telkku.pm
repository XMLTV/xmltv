# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://www.telkku.com
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::telkku;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();
fi::programmeStartOnly->import();

# Description
sub description { 'telkku.com' }

# Grab channel list
sub channels {

  # Fetch & parse HTML
  my $root = fetchTree("http://www.telkku.com/channel");
  if ($root) {
    my %channels;

    #
    # Channel list can be found from the left sidebar
    #
    # <div id="channelList">
    #   ...
    #   <ul>
    #     <li><a href="http://www.telkku.com/channel/list/8/20101218">4 Sport</a></li>
    #     <li><a href="http://www.telkku.com/channel/list/24/20101218">4 Sport Pro</a></li>
    #     ...
    #	  <li><a href="http://www.telkku.com/channel/list/87/20101218">Viron ETV</a></li>
    #     <li><a href="http://www.telkku.com/channel/list/10/20101218">YLE Teema</a></li>
    #   </ul>
    # </div>
    #
    if (my $container = $root->look_down("id" => "channelList")) {
      if (my @list = $container->find("li")) {
	debug(2, "Source telkku.com found " . scalar(@list) . " channels");
	foreach my $list_entry (@list) {
	  if (my $link = $list_entry->find("a")) {
	    my $href = $link->attr("href");
	    my $name = $link->as_text();

	    if (defined($href) && length($name) &&
		(my($channel_no) = ($href =~ m,channel/list/(\d+)/,))) {
	      debug(3, "channel '$name' ($channel_no)");
	      $channels{"${channel_no}.telkku.com"} = "fi $name";
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

    debug(2, "Source telkku.com parsed " . scalar(keys %channels) . " channels");
    return(\%channels);
  }

  return;
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow) = @_;

  # Get channel number from XMLTV id
  return unless my($channel) = ($id =~ /^(\d+)\.telkku\.com$/);

  # Fetch & parse HTML
  my $root = fetchTree("http://www.telkku.com/channel/list/$channel/$today");
  if ($root) {

    #
    # All program info is contained within a unsorted list with class "programList"
    #
    #  <ul class="programList">
    #   <li>
    #    <span class="programDate"><a href="http://www.telkku.com/program/show/2010112621451">23:45&nbsp;Uutisikkuna</a></span><br />
    #    <span class="programDescription">...</span>
    #   </li>
    #   ...
    #  </ul>
    #
    my $opaque = startProgrammeList();
    if (my $container = $root->look_down("class" => "programList")) {
      if (my @list = $container->find("li")) {
	foreach my $list_entry (@list) {
	  my $date = $list_entry->look_down("class", "programDate");
	  my $desc = $list_entry->look_down("class", "programDescription");
	  if ($date && $desc) {
	    my $href = $date->find("a");
	    if ($href) {

	      # Extract texts from HTML elements. Entities are already decoded.
	      $date = $href->as_text();
	      $desc = $desc->as_text();

	      # Use "." to match &nbsp; character (it's not included in \s?)
	      if (my($hour, $minute, , $title) =
		  $date =~ /^(\d{2}):(\d{2}).(.+)/) {
		debug(3, "List entry $channel ($hour:$minute) $title");
		debug(4, $desc);

		# Only record entry if title isn't empty
		appendProgramme($opaque, $hour, $minute, $title, undef, $desc)
		  if length($title) > 0;
	      }
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

    # Each page on telkku.com contains the program information
    # for one channel for one whole day.
    #
    # Example (compiled from several pages for illustration):
    #
    #  /- start time             (day)
    #  |     /- program title
    #  |     |
    # [23:45 Uutisikkuna         (yesterday)]
    #  00:10 Uutisikkuna         (today    )
    #  ...
    #  23:31 Uusi päivä          (today    )
    #  00:00 Kova laki           (tomorrow )
    # [00:40 Piilosana           (tomorrow )]
    # [01:00 Tellus-tietovisa    (tomorrow )]
    #
    # The lines in [] don't appear on every page.
    #
    # Convert list to program objects
    return(convertProgrammeList($opaque, $id, "fi",
				$yesterday, $today, $tomorrow));
  }

  return;
}

# That's all folks
1;
