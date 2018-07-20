# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.ampparit.com
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::ampparit;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();

# Description
sub description { 'ampparit.com' }

# Grab channel list
sub channels {
  my %channels;

  # Fetch & parse HTML (do not ignore HTML5 <time>)
  my $root = fetchTree("https://www.ampparit.com/tv/");

  if ($root) {

    #
    # Channel list can be found from this list:
    #
    #   <div class="programming-container">
    #    ...
    #	 <div class="channel col-xs-6 col-sm-4 col-md-3 col-lg-3">
    #     <div class="channel-wrap">
    #      <div class="channel-header">
    #       <a class="logo" href="/tv/yle-tv1">
    #        <img src="..." alt="Yle TV1">
    #       </a>
    #       ...
    #      </div>
    #     </div>
    #     <div class="programs">...</div>
    #    </div>
    #    ,,,
    #   </div>
    #
    if (my $container = $root->look_down("class" => "programming-container")) {
      if (my @links = $container->look_down("_tag"  => "a",
					    "class" => qr/^(?:logo|name)$/)) {
	foreach my $link (@links) {
	  my $id = $link->attr("href");

	  # strip path
	  $id = (split("/", $id))[-1];

	  my $name;
	  if (my $img = $link->find("img")) {
	    $name = $img->attr("alt");
	  } else {
	    # no logo
	    $name = $link->as_text();
	  }
	  $name =~ s/\s+$//;

	  if (defined($id)   && length($id) &&
	      defined($name) && length($name)) {
	    debug(3, "channel '$name' ($id)");
	    $channels{"${id}.ampparit.com"} = "fi $name";
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

  } else {
    return;
  }

  debug(2, "Source ampparit.com parsed " . scalar(keys %channels) . " channels");
  return(\%channels);
}

# Grab one day
sub grab {
  return;
}

# That's all folks
1;
