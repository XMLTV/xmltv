# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.telsu.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::telsu;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();

# Description
sub description { 'telsu.fi' }

# Grab channel list
sub channels {
  my %channels;

  # Fetch & parse HTML
  my $root = fetchTree("https://www.telsu.fi/tanaan/kaikki");

  if ($root) {

    #
    # Channel list can be found from <div class="ch">:
    #
    #   <div id="prg">
    #    <div class="ch" rel="yle1">
    #     <a href="/perjantai/yle1" title="Yle TV1">
    #      <div>...</div>
    #     </a>
    #     ...
    #    </div>
    #    ...
    #   </div>
    #
    if (my $container = $root->look_down("id" => "prg")) {
      if (my @channels = $container->look_down("class" => "ch")) {
	foreach my $channel (@channels) {
	  if (my $link = $channel->find("a")) {
	    my $id   = $channel->attr("rel");
	    my $name = $link->attr("title");

	    if (defined($id)   && length($id) &&
		defined($name) && length($name)) {
	      debug(3, "channel '$name' ($id)");
	      $channels{"${id}.telsu.fi"} = "fi $name";
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

  } else {
    return;
  }

  debug(2, "Source telsu.fi parsed " . scalar(keys %channels) . " channels");
  return(\%channels);
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel) = ($id =~ /^([^.]+)\.telsu\.fi$/);

  # Fetch & parse HTML
  my $root = fetchTree("https://www.telsu.fi/" . $today->ymd() . "/$channel");
  if ($root) {
    my @objects;

    #
    # Each programme can be found in a separate <div class="dets stat"> node
    #
    #   <div class="dets stat" rel="...">
    #    <div class="c">
    #     <div class="h">
    #      <h1>
    #       <b>Uutisikkuna</b>
    #       <em class="k0" title="Ohjelma on sallittu kaikenikäisille.">S</em>
    #      </h1>
    #      <h2>
    #       <i>ma 24.07.2017</i> 04:00 - 06:50 <img src="...">
    #       <div class="rate" ...>...</div>
    #      </h2>
    #     </div>
    #     <div class="t">
    #      <div>Uutisikkuna</div>
    #     </div>
    #     ...
    #    </div>
    #   </div>
    #
    if (my @programmes = $root->look_down("class" => "dets stat")) {
      my @offsets = ($yesterday, $today, $tomorrow);
      my $current = ''; # never matches -> $yesterday will be removed first

      foreach my $programme (@programmes) {
	my $title = $programme->find("b");
	my $time  = $programme->find("h2");
	my $desc  = $programme->look_down("class" => "t");

	if ($title && $time && $desc) {
	  if (my($new, $start_h, $start_m, $end_h, $end_m) =
	      $time->as_text() =~ /^(.+)\s(\d{2}):(\d{2})\s-\s(\d{2}):(\d{2})/) {
	    $title = $title->as_text();
	    $desc  = $desc->as_text();

	    # Detect day change
	    if ($new ne $current) {
	      $current = $new;
	      shift(@offsets);
	    }
	    my $start = timeToEpoch($offsets[0], $start_h, $start_m);
	    my $end   = timeToEpoch($offsets[0], $end_h,   $end_m);

	    # Detect end time on next day
	    $end = timeToEpoch($offsets[1], $end_h, $end_m)
	      if ($end < $start);

	    debug(3, "List entry ${id} ($start -> $end) $title");
	    debug(4, $desc) if $desc;

	    # Create program object
	    my $object = fi::programme->new($id, "fi", $title, $start, $end);
	    $object->description($desc);
	    push(@objects, $object);
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
