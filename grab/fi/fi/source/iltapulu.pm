# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.iltapulu.fi
#
###############################################################################
#
# Setup
#
# INSERT FROM HERE ############################################################
package fi::source::iltapulu;
use strict;
use warnings;

#
# NOTE: this data source was earlier known as http://tv.hs.fi
# NOTE: this data source was earlier known as http://tv.tvnyt.fi
#
BEGIN {
  our $ENABLED = 1;
}

use Carp;

# Import from internal modules
fi::common->import();
fi::programmeStartOnly->import();

# Category mapping
our %categories = (
  e  => "elokuvat",
  f   => "fakta",
  kf  => "kotimainen fiktio",
  l   => "lapsi",
  nan => undef, # ??? e.g. "Astral TV"
  u   => "uutiset",
  ur  => "urheilu",
  us  => "ulkomaiset sarjat",
  vm  => "viihde", # "ja musiiki"???
);

# Description
sub description { 'iltapulu.fi' }

# Grab channel list
sub channels {
  my %channels;

  # Fetch & parse HTML
  my $root = fetchTree("https://www.iltapulu.fi/kaikki-kanavat",
                       undef, undef, 1);
  if ($root) {
    #
    # Channel list can be found in sections
    #
    #  <div id="content">
    #   <div id="programtable" class="programtable-running">
    #    <section id="channel-1" ...>
    #     <a href="/kanava/yle-tv1">
    #      <h2 class="channel-logo">
    #       <img src="/static/img/kanava/yle_tv1.png" alt="YLE TV1 tv-ohjelmat 26.12.2020">
    #      </h2>
    #     </a>
    #     ...
    #    </section>
    #    ...
    #   </div>
    #  </div>
    #
    if (my $table = $root->look_down("id" => "programtable")) {
      if (my @sections = $table->look_down("_tag" => "section",
					   "id" => qr/^channel-\d+$/)) {
	foreach my $section (@sections) {
	  if (my $header = $section->look_down("class" => "channel-logo")) {
	    if (my $image = $header->find("img")) {
	      my $name = $image->attr("alt");
	      $name =~ s/\s+tv-ohjelmat.*$//;

	      if (defined($name) && length($name)) {
		my($channel_id) = $section->attr("id") =~ /(\d+)$/;
		$channel_id .= ".iltapulu.fi";
		debug(3, "channel '$name' ($channel_id)");
		$channels{$channel_id} = "fi $name";
	      }
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();
  }

  debug(2, "Source iltapulu.fi parsed " . scalar(keys %channels) . " channels");
  return(\%channels);
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel) = ($id =~ /^([-\w]+)\.iltapulu\.fi$/);

  # Fetch & parse HTML
  my $root = fetchTree("https://www.iltapulu.fi/" . $today->ymdd(),
		       undef, undef, 1);
  if ($root) {
    my $opaque = startProgrammeList($id, "fi");

    #
    # Programme data is contained inside a li class="g-<category>"
    #
    #  <div id="content">
    #   <div id="programtable" class="programtable-running">
    #    <section id="channel-1" ...>
    #     <a href="/kanava/yle-tv1">
    #      <h2 class="channel-logo">
    #       <img src="/static/img/kanava/yle_tv1.png" alt="YLE TV1 tv-ohjelmat 26.12.2020">
    #      </h2>
    #     </a>
    #     <ul>
    #      <li class="running g-e">
    #       <time datetime="2020-12-26T15:20:00+02:00">15.20</time>
    #       <b class="pl">
    #        <a href="/joulumaa" class="op" ... title="... description ...">
    #         Joulumaa
    #        </a>
    #        ...
    #       </b>
    #       ...
    #      </li>
    #      ...
    #     </ul>
    #     <ul>
    #
    if (my $table = $root->look_down("id" => "programtable")) {
      if (my $section = $table->look_down("_tag" => "section",
					  "id" => qr/^channel-${channel}/)) {
	if (my @entries = $section->look_down("_tag" => "li")) {
	  foreach my $entry (@entries) {
	    my $start = $entry->look_down("_tag" => "time");
	    my $link  = $entry->look_down("class" => "op");

	    if ($start && $link) {
	      if (my($hour, $minute) =
		  $start->as_text() =~ /^(\d{2})[:.](\d{2})$/) {
	        my $title = $link->as_text();

	        if (length($title)) {
		  my $desc      = $link->attr("title");
		  my($category) = ($entry->attr("class") =~ /g-(\w+)$/);
		  $category = $categories{$category} if $category;

		  debug(3, "List entry ${id} ($hour:$minute) $title");
		  debug(4, $desc)     if $desc;
		  debug(4, $category) if defined $category;

		  my $object = appendProgramme($opaque, $hour, $minute, $title);
		  $object->description($desc);
		  $object->category($category);
		}
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
    # First entry always starts on $yesteday
    # Last entry always ends on $tomorrow.
    return(convertProgrammeList($opaque, $yesterday, $today, $tomorrow));
  }

  return;
}

# That's all folks
1;
