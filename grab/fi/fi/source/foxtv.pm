# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://www.foxtv.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::foxtv;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();
fi::programmeStartOnly->import();

# Cleanup filter regexes
my $cleanup_match = qr!\s*(?:(?:\d+\.\s+)?(?:Kausi|Jakso|Osa)\.?(?:\s+(:?\d+/)?\d+\.\s+)?){1,2}!i;

# Description
sub description { 'foxtv.fi' }

# Grab channel list - only one channel available, no need to fetch anything...
sub channels { { 'foxtv.fi' => 'fi FOX' } }

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless ($id eq "foxtv.fi");

  # Fetch & parse HTML (do not ignore HTML5 <section>)
  # Anything beyond 14 days results in 404 error -> ignore errors
  my $root = fetchTree("http://www.foxtv.fi/ohjelmaopas/fox/$today",
		       undef, 1, 1);
  if ($root) {

    #
    # Each page contains the programmes from current day to requested day.
    # All program info is contained within a section with class "row day"
    #
    #  <div id="scheduleContainer">
    #   <section class="row day" data-magellan-destination="day20160514" ...>
    #    <ul class="... scheduleGrid">
    #     <li ...>
    #      ...
    #      <h5>15:00</h5>
    #      ...
    #      <h3>Family Guy</h3>
    #      ...
    #      <h4>Maaseudun taikaa, Kausi 12 | Jakso 21</h4>
    #      <p>Kauden Suomen tv-ensiesitys. ...</p>
    #      ...
    #     </li>
    #     ...
    #    </ul>
    #   </section>
    #   ...
    #  </div>
    #
    my $opaque = startProgrammeList($id, "fi");
    if (my $container = $root->look_down("class"                     => "row day",
					 "data-magellan-destination" => "day$today")) {
      if (my @programmes = $container->look_down("_tag"  => "li",
						 "class" => qr/acilia-schedule-event/)) {
	foreach my $programme (@programmes) {
	  my $start = $programme->find("h5");
	  my $title = $programme->find("h3");

	  if ($start && $title) {
	    if (my($hour, $minute) =
		$start->as_text() =~ /^(\d{2})[:.](\d{2})$/) {
	      my $desc  = $programme->find("p");
	      my $extra = $programme->find("h4");

	      $title = $title->as_text();

	      my($episode_name, $season, $episode_number) =
		$extra->as_text() =~ /^(.*)?,\s+Kausi\s+(\d+)\s+\S\s+Jakso\s+(\d+)$/
		  if $extra;

	      # Cleanup some of the most common inconsistencies....
	      $episode_name =~ s/^$cleanup_match// if defined $episode_name;
	      if ($desc) {
	        ($desc = $desc->as_text()) =~ s/^$cleanup_match//;

		# Title can be first in description too
		$desc =~ s/^$title(?:\.\s+)?//;

		# Episode title can be first in description too
		$desc =~ s/^$episode_name(?:\.\s+)?// if defined $episode_name;

		# Description can be empty
		undef $desc if $desc eq '';
	      }

	      # Episode name can be the same as the title
	      undef $episode_name
		if defined($episode_name) &&
		   (($episode_name eq '') || ($episode_name eq $title));

	      debug(3, "List entry fox ($hour:$minute) $title");
	      debug(4, $episode_name) if defined $episode_name;
	      debug(4, $desc)         if defined $desc;
	      debug(4, sprintf("s%02de%02d", $season, $episode_number))
		if (defined($season) && defined($episode_number));

	      my $object = appendProgramme($opaque, $hour, $minute, $title);
	      $object->description($desc);
	      $object->episode($episode_name, "fi");
	      $object->season_episode($season, $episode_number);
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

    # Convert list to program objects
    #
    # First entry always starts on $today -> don't use $yesterday
    # Last entry always ends on $tomorrow.
    return(convertProgrammeList($opaque, undef, $today, $tomorrow));
  }

  return;
}

# That's all folks
1;
