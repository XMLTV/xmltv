# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://www.mtv3.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::mtv3;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();

# Description
sub description { 'mtv3.fi' }

# Grab channel list
sub channels {
  my %channels;

  # Fetch & parse HTML
  my $root = fetchTree("http://www.mtv3.fi/tvopas/", "iso-8859-1");
  if ($root) {

    #
    # Channel list can be found from the headers of this table:
    #
    #  <table class="ohjelmakartta" cellspacing="0" cellpadding="0" border="0">
    #   <thead>
    #    <tr class="logot">
    #     <th class="logo logo-old yle1"><span>yle1</span></th>
    #     <th class="logo logo-old yle2"><span>yle2</span></th>
    #     <th class="logo mtv3"><span>mtv3</span></th>
    #     ...
    #     <th class="logo logo-old jim"><span>jim</span></th>
    #    </thead>
    #    ...
    #  </table>
    #
    if (my $container = $root->look_down("class" => "ohjelmakartta")) {
      if (my @headers = $container->find("th")) {

	debug(2, "Source mtv3.fi found " . scalar(@headers) . " channels");

	foreach my $header (@headers) {
	  my $name = $header->as_text();

	  # Unfortunately the HTML code does not show the real channel name
	  if (defined($name) && length($name)) {
	    # Underscore is not a valid XMLTV channel ID character
	    (my $id = $name) =~ s/_/-/g;
	    debug(3, "channel '$id' ($name)");
	    $channels{"${id}.mtv3.fi"} = "fi $name";
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();
  }

  debug(2, "Source mtv3.fi parsed " . scalar(keys %channels) . " channels");
  return(\%channels);
}

# Parse time and convert to seconds since midnight
sub _toEpoch($$) {
  my($day, $time) = @_;
  my($hour, $minute) = ($time =~ /^(\d{2}):(\d{2})$/);
  return(timeToEpoch($day, $hour, $minute));
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel) = ($id =~ /^([^.]+)\.mtv3\.fi$/);

  # Replace Dash with Underscore for node search
  $channel =~ s/-/_/g;

  # Fetch & parse HTML
  my $root = fetchTree("http://www.mtv3.fi/tvopas/index.shtml/$today",
		       "iso-8859-1");
  if ($root) {
    my @objects;

    #
    # Programmes for a channel can be found in a separate <td> node
    #
    #  <table class="ohjelmakartta" ...>
    #   <tbody>
    #    ...
    #    <td class="yle1">
    #     <ul>
    #      <li class="program">
    #       <a href="#" name="mtv3etusivu_tvopas_ohjelmakartta">
    #        <span class="starttime">04:00</span>
    #        <span class="name">Uutisikkuna</span>
    #        <span class="popup">
    #         <span class="top">
    #          <span class="name">Uutisikkuna</span>
    #          <span class="times">
    #           <span class="date">20.11.2013 </span>
    #            klo 04:00 - 05:55
    #          </span>
    #          <span class="logo"></span>
    #         </span>
    #         <span class="description"></span>
    #         <span class="bottom">
    #          <span class="episodename"><b>Jakso:</b> Keskiviikko</span>
    #          <span class="duration"><b>Kesto:</b> 01:55</span>
    #         </span>
    #         ...
    #        </span>
    #       </a>
    #      </li>
    #      ...
    #     </ul>
    #    </td>
    #    ...
    #   </tbody>
    #  </table>
    #
    # First entry is always at $today.
    #
    # Each page contains the programmes for multiple channels. If you use the
    # grabber for more than one channel from the same channel package then it
    # is *HIGHLY* recommended to call the grabber with the --cache option to
    # reduce network traffic!
    #
    if (my $container = $root->look_down("class" => "ohjelmakartta")) {
      my $day = $today;

      if (my @cells = $container->look_down("_tag"  => "td",
					    "class" => $channel)) {

	foreach my $cell (@cells) {
	  if (my @programmes = $cell->find("li")) {
	    foreach my $programme (@programmes) {
	      my $title = $programme->look_down("class" => "name");
	      my $time  = $programme->look_down("class" => "times");

	      if ($title && $time &&
		  (my ($start, $end) =
		   ($time->as_text() =~ /klo\s+(\d{2}:\d{2})\s+-\s+(\d{2}:\d{2})/))) {
		$title = $title->as_text();

		# Strip "hd" and "live" from category
		my($category) = ($programme->attr("class") =~ /^program\s+(.+)/);
		$category =~ s/(?:hd|live)// if defined($category);

		my $desc = $programme->look_down("class" => "description");
		$desc    = $desc->as_text() if $desc;

		$start   = _toEpoch($day, $start);
		my $stop = _toEpoch($day, $end);
		# Sanity check: prevent day change on the first entry
		if (@objects && ($stop < $start)) {
		  $day  = $tomorrow;
		  $stop = _toEpoch($day, $end);
		}

		debug(3, "List entry ${channel} ($start -> $stop) $title");
		debug(4, $desc) if defined $desc;

		# Create program object
		my $object = fi::programme->new($id, "fi", $title, $start, $stop);
		$object->category($category);
		$object->description($desc);

		# Handle optional episode titles
		if (my $episode = $programme->look_down("class" => "episodename")) {

	          # Strip starting "Jakso:" text
		  ($episode = $episode->as_text()) =~ s/^Jakso:\s+//;

		  # Set episode title if it is NOT the same as the title
		  $object->episode($episode, "fi")
		    unless $episode eq $title;
		}

		push(@objects, $object);
	      }
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

    # Fix overlapping programmes
    fi::programme->fixOverlaps(\@objects);

    return(\@objects);
  }

  return;
}

# That's all folks
1;
