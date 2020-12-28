# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.yle.fi
#
###############################################################################
#
# Setup
#
# INSERT FROM HERE ############################################################
package fi::source::yle;
use strict;
use warnings;
use Date::Manip;

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();

# Description
sub description { 'yle.fi' }

our %languages = (
    "fi" => [ "areena", "opas"  ],
    "sv" => [ "arenan", "guide" ],
);

# Grab channel list
sub channels {
  my %channels;

  # yle.fi offers program guides in multiple languages
  foreach my $code (sort keys %languages) {

    # Fetch & parse HTML (do not ignore HTML5 <time>)
    my $root = fetchTree("https://$languages{$code}[0].yle.fi/tv/$languages{$code}[1]",
                         undef, undef, 1);
    if ($root) {

      #
      # Channel list can be found from this list:
      #
      #   <ul class="guide-channels">
      #    <li class="guide-channels__channel">
      #	    <h2 class="channel-header">
      #      <a>...<div class="channel-header__logo " ... aria-label="Yle TV1"></div></a>
      #	    </h2>
      #     ...
      #    </li>
      #	   ...
      #   </ul>
      #
      if (my @divs = $root->look_down("_tag"       => "div",
                                      "aria-label" => qr/^.+$/)) {
	debug(2, "Source ${code}.yle.fi found " . scalar(@divs) . " channels");
	foreach my $div (@divs) {
	  my $name = $div->attr("aria-label");

	  if (defined($name) && length($name)) {
	    # replace space with hyphen
	    my $id;
	    ($id = $name) =~ s/ /-/g;

	    debug(3, "channel '$name' ($id)");
	    $channels{"${id}.${code}.yle.fi"} = "$code $name";
	  }
	}
      }

      # Done with the HTML tree
      $root->delete();

    } else {
      return;
    }
  }

  debug(2, "Source yle.fi parsed " . scalar(keys %channels) . " channels");
  return(\%channels);
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel, $code) = ($id =~ /^([^.]+)\.([^.]+)\.yle\.fi$/);
  $channel =~ s/-/ /g;

  # Fetch & parse HTML (do not ignore HTML5 <time>)
  my $root = fetchTree("https://$languages{$code}[0].yle.fi/tv/$languages{$code}[1]?t=" . $today->ymdd(),
		       undef, undef, 1);
  if ($root) {
    my @objects;

    #
    # Each programme can be found in a separate <li> node
    #
    #   <ul class="guide-channels">
    #    <li class="guide-channels__channel">
    #	  <h2 class="channel-header">
    #      <a>...<div class="channel-header__logo " ... aria-label="Yle TV1"></div></a>
    #	  </h2>
    #     <ul class="schedule-list">
    #      <li class="schedule-card ..." ... itemtype="http://schema.org/Movie">
    #       ...
    #       <time datetime="2017-07-11T06:25:00+03:00" itemprop="startDate">06.25</time>
    #       <time datetime="2017-07-11T06:55:00+03:00" itemprop="endDate"></time>
    #       ...
    #       <span itemprop="name">Mikä meitä lihottaa?</span>
    #       ...
    #       <span itemprop="description">1/8. Lihavuusepidemia. ...</span>
    #       ...
    #      </li>
    #      ...
    #     </ul>
    #    </li>
    #	 ...
    #   </ul>
    #
    if (my $div = $root->look_down("_tag"       => "div",
                                   "aria-label" => qr/^${channel}$/)) {
      if (my $parent = $div->look_up("class" => qr/guide-channels__channel/)) {
	if (my @programmes = $parent->look_down("class" => qr/^schedule-card\s+/)) {
	  foreach my $programme (@programmes) {
	    my $start = $programme->look_down("itemprop", "startDate");
	    my $end   = $programme->look_down("itemprop", "endDate");
	    my $title = $programme->look_down("itemprop", "name");
	    my $desc  = $programme->look_down("itemprop", "description");

	    if ($start && $end && $title && $desc) {
	      $start = UnixDate($start->attr("datetime"), "%s");
	      $end   = UnixDate($end->attr("datetime"),   "%s");

	      my $category = $programme->attr("itemtype") =~ /Movie/ ? "elokuvat" : undef;

	      # NOTE: entries with same start and end time are invalid
	      if ($start && $end && ($start != $end)) {

		$title = $title->as_text();
		$title =~ s/^\s+//;
		$title =~ s/\s+$//;

		if (length($title)) {

		  $desc = $desc->as_text();
		  $desc =~ s/^\s+//;
		  $desc =~ s/\s+$//;

		  debug(3, "List entry $channel ($start -> $end) $title");
		  debug(4, $desc);
		  debug(4, $category) if defined $category;

		  # Create program object
		  my $object = fi::programme->new($id, $code, $title, $start, $end);
		  $object->category($category);
		  $object->description($desc);
		  push(@objects, $object);
		}
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
