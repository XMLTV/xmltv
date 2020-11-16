# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.ampparit.com
#
###############################################################################
#
# Setup
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
fi::programmeStartOnly->import();

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
    #       <a class="channel-title__logo" href="/tv/yle-tv1">
    # or    <a class="channel-title__name" href="/tv/yle-tv1">
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
					    "class" => qr/^channel-title__(?:logo|name)$/)) {
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
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel) = ($id =~ /^([^.]+)\.ampparit\.com$/);

  # Fetch & parse HTML (do not ignore HTML5 <time>)
  my $root = fetchTree("https://www.ampparit.com/tv/$channel?aika=paiva&pvm=" . $today->ymdd(),
		       undef, undef, 1);
  if ($root) {
    my $opaque = startProgrammeList($id, "fi");

    #
    # Each programme can be found in a separate <div class="program"> node
    #
    #   <div class="channel-container">
    #    ...
    #    <div class="programs">
    #     <div data-tip="..." data-for="..." class="program">
    #      <time class="program__start-time" title="ke 25.7. 6:00" datetime="2018-07-25T03:00:00.000Z">
    #       06:00
    #      </time>
    #      <div class="program__right">
    #       <div class="program__title">Aamun AVAus</div>
    #       <div class="program__description">
    #        ...
    #       </div>
    #      </div>
    #     </div>
    #     ...
    #    </div>
    #   </div>
    #
    if (my $container = $root->look_down("class" => "programs")) {
      if (my @programmes = $container->look_down("class" => "program")) {
	foreach my $programme (@programmes) {
	  my $start = $programme->look_down("_tag"  => "time",
					    "class" => "program__start-time");
	  my $title = $programme->look_down("class" => "program__title");
	  my $desc  = $programme->look_down("class" => "program__description");

	  if ($start && $title && $desc) {
	    if (my($hour, $minute) =
		$start->as_text() =~ /^(\d{2})[:.](\d{2})$/) {
	      $title = $title->as_text();

	      if (length($title)) {
		$desc  = $desc->as_text();

		debug(3, "List entry ${id} ($hour:$minute) $title");
		debug(4, $desc) if $desc;

		my $object = appendProgramme($opaque, $hour, $minute, $title);
		$object->description($desc);
	      }
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
