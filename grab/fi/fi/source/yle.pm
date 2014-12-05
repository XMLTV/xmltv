# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://www.yle.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
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
fi::programmeStartOnly->import();

# Description
sub description { 'yle.fi' }

my %languages = (
    "fi" => "ohjelmaopas",
    "sv" => "programguide",
);

# Grab channel list
sub channels {
  my %channels;

  # yle.fi offers program guides in multiple languages
  foreach my $code (sort keys %languages) {

    # Fetch & parse HTML
    my $root = fetchTree("http://$languages{$code}.yle.fi/tv/opas", 'UTF-8');
    if ($root) {

      #
      # Channel list can be found from this list:
      #
      #  <ul class="channel-lists ...">
      #    <li><h1 id="yle-tv1">Yle TV1...</h1>...</li>
      #    <li><h1 id="yle-tv2">Yle TV2...</h1>...</li>
      #    ...
      #  </ul>
      #
      if (my $container = $root->look_down("class" => qr/^channel-lists\s+/)) {
	if (my @headers = $container->find("h1")) {
	  debug(2, "Source ${code}.yle.fi found " . scalar(@headers) . " channels");
	  foreach my $header (@headers) {
	    my $id   = $header->attr("id");
	    my $name = $header->as_text();

	    if (defined($id) && length($id) && length($name)) {
	      debug(3, "channel '$name' ($id)");
	      $channels{"${id}.${code}.yle.fi"} = "$code $name";
	    }
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

  # Fetch & parse HTML (do not ignore HTML5 <time>)
  my $root = fetchTree("http://$languages{$code}.yle.fi/tv/opas?t=" . $today->ymdd(),
		       'UTF-8', undef, 1);
  if ($root) {
    my @objects;

    #
    # Each programme can be found in a separate <li> node
    #
    #  <ul class="channel-lists ...">
    #    <li>
    #      <h1 id="yle-tv1">Yle TV1...</h1>
    #      <ul>
    #        <li class="program-entry ...">
    #          <div class="program-label">
    #            <time class="dtstart" datetime="2014-06-15T01:30:00.000+03:00">01:30</time>
    #            <time class="dtend" datetime="2014-06-15T04:30:00.000+03:00"></time>
    #            <div class="program-title">
    #              ...
    #              <a class="link-grey" href="...">Suunnistuksen Jukolan viesti</a>
    #              <span class="label movie">Elokuva</span>
    #              ...
    #            </div>
    #          </div>
    #          ...
    #          <div class="program-desc">
    #            <p>66. Jukolan viesti. Kolmas, neljäs ja viides osuus...
    #            ...
    #            </p>
    #          </div>
    #        </li>
    #        ...
    #      </ul>
    #      ...
    #    </li>
    #  </ul>
    #
    if (my $container = $root->look_down("class" => qr/^channel-lists\s+/)) {
      if (my $header = $container->look_down("_tag" => "h1",
					     "id"   => $channel)) {
	if (my $parent = $header->parent()) {
	  if (my @programmes = $parent->look_down("class" => qr/^program-entry\s+/)) {
	    foreach my $programme (@programmes) {
	      my $start = $programme->look_down("class", "dtstart");
	      my $end   = $programme->look_down("class", "dtend");
	      my $title  = $programme->look_down("class", "program-title");
	      my $desc  = $programme->look_down("class", "program-desc");

	      if ($start && $end && $title && $desc) {
		$start = UnixDate($start->attr("datetime"),qw/%s/);
		$end   = UnixDate($end->attr("datetime"),qw/%s/);

		my $link     = $title->find("a");
		my $category = $title->look_down("class" => "label movie") ? "elokuvat" : undef;

		# NOTE: entries with same start and end time are invalid
		if ($start && $end && $link && ($start != $end)) {

		  $title = $link->as_text();
		  $title =~ s/^\s+//;
		  $title =~ s/\s+$//;

		  if (length($title)) {

		    $desc = $desc->find("p");
		    $desc = $desc ? $desc->as_text() : "";
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
