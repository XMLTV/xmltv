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
my $cleanup_match = qr/\s*(?:\d+\.\s+Kausi\.\s+)?(?:Kausi\s+\d+\.\s+)?(?:Osa|Jakso)\s+\d+\.\s*/i;

# Description
sub description { 'foxtv.fi' }

# Grab channel list - only one channel available, no need to fetch anything...
sub channels { { 'foxtv.fi' => 'fi FOX' } }

# Extract programmes for one day
sub _programmes($$) {
  my($table_entries, $wday) = @_;
  return if ($wday > 6);

  my $entry = $table_entries->[$wday + 1];
  return unless $entry;

  return($entry->look_down("class" => qr/^itemListings/));
}

# Extract start time and return (hour, minute) or undef
sub _start($) {
  my($programme) = @_;

  my $start = $programme->look_down("rel" => "colorbox");
  return unless $start;

  $start = $start->find("span");
  return unless $start;

  return($start->as_text() =~ /^(\d{2}):(\d{2})/);
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless ($id eq "foxtv.fi");

  #
  # Only the weekly page contains all the information we need. Each of the 7
  # days in a week will return the same weekly information, although the URL
  # will be different. This will break XMLTV caching.
  #
  # The weekly page starts on Monday. We simply calculate what the Monday of
  # the week is that contains the day we want to grab.
  #
  my $wday;
  my $url;
  {
    # Epoch of today at 12:00
    my $epoch = timeToEpoch($today, 12, 0);

    # localtime weekday: 0: Sunday, 1: Monday,  ..., 6: Saturday
    # foxtv.fi weekday:  0: Monday, 1: Tuesday, ..., 6: Sunday
    $wday = ((localtime($epoch))[6] + 6) % 7;

    # Epoch of today (if it is Monday) or the previous Monday, at
    # 11:00 if Monday (standard time) -> today (daylight saving time)
    # 12:00 if no daylight saving change during the week
    # 13:00 if Monday (daylight saving time) -> today (standard time)
    my($mday, $mon, $year) = (localtime($epoch - $wday * 86400))[3..5];
    $mon  += 1;
    $year += 1900;

    # URL for weekly page
    $url = "http://www.foxtv.fi/ohjelmat/weekly/$mday.$mon.$year";
  }

  # Fetch & parse HTML
  my $root = fetchTree($url);
  if ($root) {
    my $opaque = startProgrammeList($id, "fi");

    #
    # All program info is contained in a table column *without* class
    #
    #  <table class="bloque-slider">
    #   <tr>
    #    <td class="calendarHours">      [Index 0]
    #    ... one list item per hour ...
    #    </td>
    #    <td>                            [Index 1: Monday -> $wday + 1]
    #      <div class="itemListings halfHour  ">
    #        <a href=... rel="colorbox">
    #          ...
    #          <span>00:55</span>
    #          ...
    #        </a>
    #        <div id="ShowDetailsOverlay" class="ShowDetails ">
    #          ...
    #          <div class="Content">
    #            <h4>Low Winter Sun</h4>
    #            ...
    #            <div class="Details colLeft">
    #              <h5 class="ShowTitle colLeft">Tuotantokausi 1</h5>
    #              <h5 class="ShowTitle colLeft">
    #                  Jakso 10
    #              </h5>
    #              <p>sunnuntain myöhäisilloissa </p>
    #              ...
    #            </div>
    #            <div class="ShowDescription colLeft">Murhien, petosten, koston ja korruption värittämän modernin draamasarjan päähenkilönä on etsivä Frank Agnew.</div>
    #            ...
    #          </div>
    #        </div>
    #      </div>
    #    </td>
    #    <td>                            [Index 2: Tuesday]
    #    ...
    #   </tr>
    #  </table>
    #
    if (my $container = $root->look_down("class" => "bloque-slider")) {
      if (my @table_entries = $container->find("td")) {
	my @programmes_today = _programmes(\@table_entries, $wday);
	my $first_tomorrow   = _programmes(\@table_entries, $wday + 1);

	if (@programmes_today) {
	  foreach my $programme (@programmes_today) {
	    my($hour, $minute) = _start($programme);
	    my $details        = $programme->look_down("class" => "Content");

	    if ($hour && $minute && $details) {
	      my $desc  = $details->look_down("class" => "ShowDescription colLeft");
	      my $title = $details->find("h4");

	      if ($desc && $title) {
		my($season, $episode_number) = $programme->look_down("class" => "ShowTitle colLeft");
		my $episode_name             = $programme->find("p");

		$title = $title->as_text();
		$desc  = $desc->as_text();

		# Season, episode number & episode name (optional)
		($season)         = ($season->as_text() =~ /(\d+)/)
		  if $season;
		($episode_number) = ($episode_number->as_text() =~ /(\d+)/)
		  if $episode_number;
		($episode_name)   = ($episode_name->as_text() =~ /^\s*(.+)$/)
		  if $episode_name;

		# Cleanup some of the most common inconsistencies....
		$desc =~ s/^$cleanup_match//o
		  if defined($desc);
		if (defined($episode_name)) {
		  $episode_name =~ s/$cleanup_match//o;
		  $episode_name =~ s/\s+$//;
		  if (defined($desc)) {
		    # Strip optional parental guidance to improve following match
		    my $tmp;
		    ($tmp = $episode_name) =~ s/\s+\((?:\d+|S)\)$//;
		    $desc =~ s/^$tmp\.\s+//;
		  }
		}

		# Description can be empty or "-"
		undef $desc if ($desc eq '') || ($desc eq '-');
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

	  # Get stop time for last entry in the table: first start
	  if ($first_tomorrow) {
	    my($hour, $minute) = _start($first_tomorrow);
	    appendProgramme($opaque, $hour, $minute, "DUMMY")
	      if ($hour && $minute);
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
    #
    # Unfortunately we don't have a stop time for the last entry. We fix this
    # (see above) by adding the start time of the first entry from tomorrow
    # as a DUMMY program. This works for Monday to Saturday, but not for
    # Sunday :-(
    return(convertProgrammeList($opaque, undef, $today, $tomorrow));
  }

  return;
}

# That's all folks
1;
