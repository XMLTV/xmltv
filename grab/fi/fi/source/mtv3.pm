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
    # Channel list can be found from this dropdown:
    #
    # <select onchange="window.open(this.options[this.selectedIndex].value,'_self')">
    #  <option value="#">Valitse kanava</option>
    #  <option value="/tvopas/index.shtml">YLE1</option>
    #  ...
    #  <option value="/tvopas/muutkanavat.shtml">KinoTV</option>
    #  <option value="/tvopas/muutkanavat.shtml">Digiviihde</option>
    # </select>
    #
    if (my $container = $root->look_down("onchange" => qr/^window.open/)) {
      if (my @options = $container->find("option")) {
	my $count;
	my $oldpage = "";

	debug(2, "Source mtv3.fi found " . scalar(@options) . " channels");
	foreach my $option (@options) {
	  my $id   = $option->attr("value");
	  my $name = $option->as_text();

	  if (defined($id) &&
	      (my($page) = ($id =~ m,^/tvopas/(\w+)\.shtml$,)) &&
	      length($name)) {
	    if ($page ne $oldpage) {
	      $count   = 0;
	      $oldpage = $page;
	    }
	    $count++;
	    debug(3, "channel '$name' (${count}.${page})");
	    $channels{"${count}.${page}.mtv3.fi"} = "fi $name";
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
  my($self, $id, $yesterday, $today, $tomorrow) = @_;

  # Get channel number from XMLTV id
  return unless my($channel, $page) = ($id =~ /^(\d+)\.([^.]+)\.mtv3\.fi$/);

  # Fetch & parse HTML
  my $root = fetchTree("http://www.mtv3.fi/tvopas/${page}.shtml/$today",
		       "iso-8859-1");
  if ($root) {
    my @objects;

    #
    # Programmes for a channel can be found in a separate <td> node
    #
    # <table ... class="ohjelmisto" id="ohjelmisto">
    #  <tr id="tvopas0400">
    #  <td ... class="kanava1">
    #   <div class="ohjelma uutiset"><span class="aika">04:00</span>
    #    <a class="nimi" href="http://www.mtv3.fi/tvopas/ohjelma.shtml/yle1/20110212/1/uutisikkuna">Uutisikkuna</a>
    #    <div class="clearall"></div>
    #    <div class="seloste">
    #     <div class="tvsel_aika">12.02.2011 klo 04:00-08:00</div>
    #     <div class="tvsel_sarjateksti"></div>
    #    </div>
    #   </div>
    #   ...
    #  </td>
    #
    # First entry is always at $today.
    #
    # Each page contains the programmes for multiple channels. If you use the
    # grabber for more than one channel from the same channel package then it
    # is *HIGHLY* recommended to call the grabber with the --cache option to
    # reduce network traffic!
    #
    if (my $container = $root->look_down("class" => "ohjelmisto")) {
      my $day = $today;

      if (my @cells = $container->look_down("_tag"  => "td",
					    "class" => qr/^kanava${channel}$/)) {
	foreach my $cell (@cells) {
	  if (my @programmes = $cell->look_down("class" => qr/^ohjelma/)) {
	    foreach my $programme (@programmes) {
	      my $title = $programme->look_down("class" => "nimi");
	      my $time  = $programme->look_down("class" => "tvsel_aika");

	      if ($title && $time &&
		  (my ($start, $end) =
		   ($time->as_text() =~ /(\d{2}:\d{2})-(\d{2}:\d{2})$/))) {
		$title = $title->as_text();

		my($category) = ($programme->attr("class") =~ /^ohjelma\s+(.+)/);

		my $desc = $programme->look_down("class" => "tvsel_kuvaus");
		$desc    = $desc->as_text() if $desc;

		$start   = _toEpoch($day, $start);
		my $stop = _toEpoch($day, $end);
		if ($stop < $start) {
		  $day  = $tomorrow;
		  $stop = _toEpoch($day, $end);
		}

		debug(3, "List entry ${channel}.${page} ($start -> $stop) $title");
		debug(4, $desc) if defined $desc;

		# Create program object
		my $object = fi::programme->new($id, "fi", $title, $start, $stop);
		$object->category($category);
		$object->description($desc);

		# Handle optional episode titles
		if (my @episodes = $programme->look_down("class" => "tvsel_jaksonimi")) {

		  # First episode title is in finnish, second is in english
		  foreach my $language (qw(fi en)) {
		    last unless my $episode = shift(@episodes);

		    # Strip trailing period or parenthesis
		    ($episode = $episode->as_text()) =~ s/\.\s*$//;
		    $episode = $1 if ($episode =~ /^\s*\(\s*(.+)\s*\)\s*$/);

		    # Set episode title if it is NOT the same as the title
		    $object->episode($episode, $language)
		      unless $episode eq $title;
		  }
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
