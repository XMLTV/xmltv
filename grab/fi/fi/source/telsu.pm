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
  my $root = fetchTree("https://www.telsu.fi/");

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
  return;
}

# That's all folks
1;
