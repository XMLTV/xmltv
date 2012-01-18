# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://tv.nyt.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
#
# INSERT FROM HERE ############################################################
package fi::source::tvnyt;
use strict;
use warnings;

BEGIN {
  our $ENABLED = 1;
}

use Carp;

# Import from internal modules
fi::common->import();

# Description
sub description { 'tv.nyt.fi' }

# Grab channel list
sub channels {
  my %channels;
  my @groups = ( "free_air_fi" );
  my $added;

  # Next group
  while (defined(my $group = shift(@groups))) {

    # Fetch & parse HTML
    my $root = fetchTree("http://tv.nyt.fi/grid?service=tvnyt&grid_type=list&layout=false&group=$group");
    if ($root) {

      #
      # Group list can be found in dropdown
      #
      #  <select id="group_select" ...>
      #   <option value="tvnyt*today*free_air_fi*list" selected>...</option>
      #   <option value="tvnyt*today*sanoma_fi*list">...</option>
      #   ...
      #  </select>
      #
      unless ($added) {
	if (my $container = $root->look_down("id" => "group_select")) {
	  if (my @options = $container->find("option")) {
	    debug(2, "Source tv.nyt.fi found " . scalar(@options) . " groups");
            foreach my $option (@options) {
	      unless ($option->attr("selected")) {
		my $value = $option->attr("value");

		if (defined($value) &&
		    (my($tag) = ($value =~ /^tvnyt\*today\*(\w+)\*/))) {
		  debug(3, "group '$tag'");
		  push(@groups, $tag);
		}
	      }
	    }
	  }
	}
	$added++;
      }

      #
      # Channel list can be found in table headers
      #
      #  <table class="grid_table" cellspacing="0px">
      #   <thead>
      #    <tr>
      #     <th class="yle_tv1">...</th>
      #     <th class="yle_tv2">...</th>
      #     ...
      #    </tr>
      #   </thead>
      #   ...
      #  </table>
      #
      if (my $container = $root->look_down("class" => "grid_table")) {
	my $head = $container->find("thead");
	if ($head && (my @headers = $head->find("th"))) {
	  debug(2, "Source tv.nyt.fi found " . scalar(@headers) . " channels in group '$group'");
	  foreach my $header (@headers) {
	      if (my $image = $header->find("img")) {
		my $name = $image->attr("alt");
		my $channel_id = $header->attr("class");

		if (defined($channel_id) && length($channel_id) &&
		    defined($name)       && length($name)) {
		  debug(3, "channel '$name' ($channel_id)");
		  $channels{"${channel_id}.${group}.tv.nyt.fi"} = "fi $name";
		}
	      }
	    }
	}
      }

      # Done with the HTML tree
      $root->delete();
    }

  }

  debug(2, "Source tv.nyt.fi parsed " . scalar(keys %channels) . " channels");
  return(\%channels);
}

# Parse time and convert to seconds since midnight
sub _toEpoch($$$$) {
  my($today, $tomorrow, $time, $switch) = @_;
  my($hour, $minute) = ($time =~ /^(\d{2})(\d{2})$/);
  return(timeToEpoch($switch ? $tomorrow : $today, $hour, $minute));
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel, $group) = ($id =~ /^(\w+)\.(\w+)\.tv\.nyt\.fi$/);

  # Fetch & parse HTML
  my $root = fetchTree("http://tv.nyt.fi/grid?service=tvnyt&grid_type=list&layout=false&group=$group&date=" .
		       sprintf("%04d-%02d-%02d",
			       $today->year(), $today->month(), $today->day()));
  if ($root) {
    my @objects;

    #
    # Programme data is contained inside a table cells with class="<channel>"
    #
    #  <td class="yle_tv1">
    #   <table class="be_list_table">
    #    <tr class="s1210 e1230"> (start/end time, "+" for tomorrow)
    #     <td class="be_time">12:10</td>
    #     <td class="be_entry">
    #      <span class="thb1916041"></span>
    #      <span class="flw6390"></span>
    #      <a href="/programs/show/1916041" class="program_link colorbox tip">
    #       Hercules... (title)
    #      </a>
    #      <span class="tooltip">
    #       <span class="wl_actions">...</span>
    #       <span class="wl_synopsis">
    #        Dokumenttielokuva bulgarialaisen perheen... (long description)
    #       </span>
    #      </span>
    #      <span class="syn">
    #       Dokumenttielokuva bulgarialaisen... (short description)
    #      </span>
    #     </td>
    #    </tr>
    #   ...
    #   </table>
    #  </td>
    #
    if (my @cells = $root->look_down("class" => $channel,
				     "_tag"  => "td")) {
      foreach my $cell (@cells) {
	foreach my $row ($cell->find("tr")) {
	  my $start_stop = $row->attr("class");
	  my $entry      = $row->look_down("class" => "be_entry");
          if (defined($start_stop) && $entry &&
	      (my($start, $stomorrow, $end, $etomorrow) =
	       ($start_stop =~ /^s(\d{4})(\+?)\s+e(\d{4})(\+?)$/))) {
	    my $title = $entry->look_down("class" => qr/program_link/);
            my $desc  = $entry->look_down("class" => "wl_synopsis");
	    if ($title) {
	      $title = $title->as_text();
              if (length($title)) {
		$start = _toEpoch($today, $tomorrow, $start, $stomorrow);
		$end   = _toEpoch($today, $tomorrow, $end,   $etomorrow);
		$desc  = $desc->as_text() if $desc;

		debug(3, "List entry ${channel}.${group} ($start -> $end) $title");
		debug(4, $desc);

		# Create program object
		my $object = fi::programme->new($id, "fi", $title, $start, $end);
		$object->description($desc);
		push(@objects, $object);
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
