# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://www.telkku.com
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::telkku;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();
fi::programmeStartOnly->import();

# Description
sub description { 'telkku.com' }

# Grab channel list
sub channels {

  # Fetch & parse HTML
  my $root = fetchTree("http://www.telkku.com/channel");
  if ($root) {
    my %channels;

    #
    # Channel list can be found from the left sidebar
    #
    # <div class="l-wrap l-grid--16" id="channelContainer">
    #   ...
    #   <ul>
    #     <li><a href="http://www.telkku.com/channel/list/8/20101218">4 Sport</a></li>
    #     <li><a href="http://www.telkku.com/channel/list/24/20101218">4 Sport Pro</a></li>
    #     ...
    #	  <li><a href="http://www.telkku.com/channel/list/87/20101218">Viron ETV</a></li>
    #     <li><a href="http://www.telkku.com/channel/list/10/20101218">YLE Teema</a></li>
    #   </ul>
    # </div>
    #
    if (my $container = $root->look_down("id" => "channelContainer")) {
      if (my @list = $container->find("li")) {
	debug(2, "Source telkku.com found " . scalar(@list) . " channels");
	foreach my $list_entry (@list) {
	  if (my $link = $list_entry->find("a")) {
	    my $href = $link->attr("href");
	    my $name = $link->as_text();

	    if (defined($href) && length($name) &&
		(my($channel_no) = ($href =~ m,channel/list/(\d+)/,))) {
	      debug(3, "channel '$name' ($channel_no)");
	      $channels{"${channel_no}.telkku.com"} = "fi $name";
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

    debug(2, "Source telkku.com parsed " . scalar(keys %channels) . " channels");
    return(\%channels);
  }

  return;
}

#
# http://www.telkku.com/movie contains information about (all?) movies for
# today and the next 7 days, i.e. offsets 0 to 7. We extract the URL to the
# detailed programme information (http://www.telkku.com/program/show/......)
# that can then be used to identify movies when processing programme entries.
#
{
  my %ids;

  sub _getMovieIDsForOffset($) {
    my($offset) = @_;

    # There is only data for the next 7 days
    return({}) if $offset > 7;

    # Reuse cached data
    return(\%ids) if %ids;

    # In order to reduce website traffic, we only try this once
    $ids{__DUMMY_ID_THAT_NEVER_MATCHES__}++;

    # Fetch & parse HTML (do not ignore HTML5 <section>)
    # This is entirely optional, so please don't abort on failure...
    my $root = fetchTree("http://www.telkku.com/movie", undef, 1, 1);
    if ($root) {
      my $test;

      #
      # Document structure for movie entries:
      #
      #  <li class="l-embed theme-hr program">
      #    ...
      #    <section class="l-embed__bd program__content">
      #      <a href="http://www.telkku.com/program/show/2014061910151">
      #        ...
      #      </a>
      #    </section>
      #  </li>
      #
      debug(2, "Source telkku.com provided movie data");
      if (my @list = $root->look_down("class" => qr/program__content/)) {
	debug(2, "Source telkku.com found " . scalar(@list) . " movies");
	foreach my $list_entry (@list) {
	  if (my $link = $list_entry->find("a")) {
	    my $href = $link->attr("href");
	    if (defined($href) && length($href)) {
	      debug(3, "movie ID: " . $href);
		$ids{$href}++;
	    }
	  }
	}
      }

      # Done with the HTML tree
      $root->delete();
    }

    debug(2, "Source telkku.com parsed " . (scalar(keys %ids) - 1) . " movies");
    return(\%ids);
  }
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel) = ($id =~ /^(\d+)\.telkku\.com$/);

  # Fetch & parse HTML
  my $root = fetchTree("http://www.telkku.com/channel/list/$channel/$today");
  if ($root) {
    my $movie_ids = _getMovieIDsForOffset($offset);

    #
    # All program info is contained within a unsorted list with class "programList"
    #
    #  <ul class="l-stack programList">
    #   <li>
    #    <a class="program" href="http://www.telkku.com/program/show/2012100920451">
    #     <div class="theme-hr program__content">
    #      <div class="program__desc">
    #       <div class="h4 program__title">23:45&nbsp;Uutisikkuna</div>
    #       <div class="progrram__desc">...</div>
    #      </div>
    #     </div>
    #    </a>
    #   </li>
    #   ...
    #  </ul>
    #
    my $opaque = startProgrammeList($id, "fi");
    if (my $container = $root->look_down("class" => "l-stack programList")) {
      if (my @list = $container->find("li")) {
	foreach my $list_entry (@list) {
	  my $link  = $list_entry->look_down("class", "program");
	  my $title = $list_entry->look_down("class", "h4 program__title");
	  my $desc  = $list_entry->look_down("class", "progrram__desc");
	  if ($link && $title && $desc) {
	    my $date;

	    # Extract texts from HTML elements. Entities are already decoded.
	    $date = $title->as_text();
	    $desc = $desc->as_text();

	    # Use "." to match &nbsp; character (it's not included in \s?)
	    if (my($hour, $minute, $title) =
		$date =~ /^(\d{2}):(\d{2}).(.+)/) {
	      my $href     = $link->attr("href");
	      my $category = (defined($href) && exists($movie_ids->{$href})) ?
		  "elokuvat" : undef;

	      debug(3, "List entry $channel ($hour:$minute) $title");
	      debug(4, $desc);
	      debug(4, $category) if defined $category;

	      # Only record entry if title isn't empty
	      if (length($title) > 0) {
		my $object = appendProgramme($opaque, $hour, $minute, $title);
		$object->category($category);
		$object->description($desc);
	      }
	    }
	  }
	}
      }
    }

    # Done with the HTML tree
    $root->delete();

    # Each page on telkku.com contains the program information
    # for one channel for one whole day.
    #
    # Example (compiled from several pages for illustration):
    #
    #  /- start time             (day)
    #  |     /- program title
    #  |     |
    # [23:45 Uutisikkuna         (yesterday)]
    #  00:10 Uutisikkuna         (today    )
    #  ...
    #  23:31 Uusi päivä          (today    )
    #  00:00 Kova laki           (tomorrow )
    # [00:40 Piilosana           (tomorrow )]
    # [01:00 Tellus-tietovisa    (tomorrow )]
    #
    # The lines in [] don't appear on every page.
    #
    # Convert list to program objects
    return(convertProgrammeList($opaque, $yesterday, $today, $tomorrow));
  }

  return;
}

# That's all folks
1;
