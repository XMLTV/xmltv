# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for http://www.iltapulu.fi
#
###############################################################################
#
# Setup
#
# VERSION: $Id$
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

# Description
sub description { 'iltapulu.fi' }

# Grab channel list
sub channels {
  my %channels;

  # Fetch & parse HTML
  my $root = fetchTree("http://www.iltapulu.fi/?&all=1");
  if ($root) {
    #
    # Channel list can be found in table rows
    #
    #  <table class="channel-row">
    #   <tbody>
    #    <tr>
    #     <td class="channel-name">...</td>
    #     <td class="channel-name">...</td>
    #     ...
    #    </tr>
    #   </tbody>
    #   ...
    #  </table>
    #  ...
    #
    if (my @tables = $root->look_down("class" => "channel-row")) {
      foreach my $table (@tables) {
	if (my @cells = $table->look_down("class" => "channel-name")) {
	  foreach my $cell (@cells) {
	    if (my $image = $cell->find("img")) {
	      my $name = $image->attr("alt");
	      $name =~ s/\s+tv-ohjelmat$//;

	      if (defined($name) && length($name)) {
		my $channel_id = (scalar(keys %channels) + 1) . ".iltapulu.fi";
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
  my $root = fetchTree("http://www.iltapulu.fi/?all=1&date=" . $today->ymdd());
  if ($root) {
    my $count = 0;
    my @objects;

    #
    # Programme data is contained inside a div class="<full-row>"
    #
    #  <table class="channel-row">
    #   <tbody>
    #    <tr>
    #     <td class="channel-name">...</td>
    #     <td class="channel-name">...</td>
    #     ...
    #    </tr>
    #    <tr class="full-row...">
    #     <td>
    #      <div class="schedule">
    #       <div class="full-row" data-starttime="1424643300" data-endtime="1424656800">
    #        <table>
    #         <tr>
    #          <td class="time">00.15</td>
    #          <td class="title[ movie]">
    #           <a class="program-open..." ... title="... description ...">
    #            Uutisikkuna
    #           </a>
    #          </td>
    #         </tr>
    #        </table>
    #       </div>
    #      </div>
    #      ...
    #     </td>
    #     ...
    #    </tr>
    #    ...
    #   </tbody>
    #  </table>
    #  ...
    #
    if (my @tables = $root->look_down("class" => "channel-row")) {

     TABLES:
      foreach my $table (@tables) {
	if (my @cells = $table->look_down("class" => "channel-name")) {

	  # Channel in this table?
	  my $index = $channel - $count - 1;
	  $count   += @cells;
	  if ($channel <= $count) {

	    # Extract from each row the div's from the same index
	    my @divs;
	    if (my @rows = $table->look_down("_tag"  => "tr",
					     "class" => qr/full-row/)) {
	      foreach my $row (@rows) {
		my $children = $row->content_array_ref;
		if ($children) {
		  my $td = $children->[$index];
		  push(@divs, $td->look_down("class" => qr/full-row/))
		    if defined($td);
		}
	      }
	    }

	    for my $div (@divs) {
	      my $start = $div->attr("data-starttime");
	      my $end   = $div->attr("data-endtime");
	      my $link  = $div->look_down("class" => qr/program-open/);

	      if ($start && $end && $link) {
		my $title = $link->as_text();

		if (length($title)) {
		  my $desc     = $link->attr("title");
		  my $category = ($link->parent()->attr("class") =~ /movie/) ? "elokuvat" : undef;

		  debug(3, "List entry ${id} ($start -> $end) $title");
		  debug(4, $desc)     if $desc;
		  debug(4, $category) if defined $category;

		  # Create program object
		  my $object = fi::programme->new($id, "fi", $title, $start, $end);
		  $object->category($category);
		  $object->description($desc);
		  push(@objects, $object);
		}
	      }
	    }

	    # skip the rest of the data
	    last TABLES;
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
