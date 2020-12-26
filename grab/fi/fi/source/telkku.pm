# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.telkku.com
#
###############################################################################
#
# Setup
#
# INSERT FROM HERE ############################################################
package fi::source::telkku;
use strict;
use warnings;
use Date::Manip qw(UnixDate);
use JSON qw();

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();

# Description
sub description { 'telkku.com' }

our %categories = (
  SPORTS => "urheilu",
  MOVIE  => "elokuvat",
);

#
# Unfortunately the embedded JSON data generated into the HTML page by
# the server is (temporarily?) broken and unreliable. The web application
# is not affected by this, because it always updates its state via XHR
# calls to the JSON API endpoints.
#
sub _getJSON($) {
  my($api_path) = @_;

  # Fetch raw JSON text directly from API endpoint
  my $text = fetchRaw("https://www.telkku.com/api/channel-groups/$api_path");
  if ($text) {
    my $decoded = JSON->new->decode($text);

    if (ref($decoded) eq "HASH") {
      # debug(5, JSON->new->pretty->encode($decoded));
      return $decoded->{response};
    }
  }

  return;
}

# cache for group name to API ID mapping
our %group2id;

# Grab channel list
sub channels {

  # Fetch & extract JSON sub-part
  my $data = _getJSON("");

  #
  # channel-groups response has the following structure
  #
  #  [
  #    {
  #      id       => "default_builtin_channelgroup1"
  #      slug     => "peruskanavat",
  #      channels => [
  #                    {
  #                      id   => "yle-tv1",
  #                      name => "Yle TV1",
  #                      ...
  #                    },
  #                    ...
  #                  ],
  #      ...
  #    },
  #    ...
  #  ]
  #
  if (ref($data) eq "ARRAY") {
    my %channels;
    my %duplicates;

    foreach my $item (@{$data}) {
      if ((ref($item)             eq "HASH")  &&
	  (exists $item->{id})                &&
	  (exists $item->{slug})              &&
	  (exists $item->{channels})          &&
	  (ref($item->{channels}) eq "ARRAY")) {
	my($api_id, $group, $channels) = @{$item}{qw(id slug channels)};

	if (defined($api_id) && length($api_id) &&
	    defined($group)  && length($group)  &&
	    (ref($channels) eq "ARRAY")) {
	  debug(2, "Source telkku.com found group '$group' ($api_id) with " . scalar(@{$channels}) . " channels");

	  # initialize group name to API ID map
	  $group2id{$group} = $api_id;

	  foreach my $channel (@{$channels}) {
	    if (ref($channel) eq "HASH") {
	      my $id   = $channel->{id};
	      my $name = $channel->{name};

	      if (defined($id) && length($id)   &&
		  (not exists $duplicates{$id}) &&
		  length($name)) {
		debug(3, "channel '$name' ($id)");
		$channels{"${id}.${group}.telkku.com"} = "fi $name";

		# Same ID can appear in multiple groups - avoid duplicates
		$duplicates{$id}++;
	      }
	    }
	  }
	}
      }
    }

    debug(2, "Source telkku.com parsed " . scalar(keys %channels) . " channels");
    return(\%channels);
  }

  return;
}

sub _group2id($) {
  my($group) = @_;

  # Make sure group to ID map is initialized
  channels() unless %group2id;

  return $group2id{$group};
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel, $group) = ($id =~ /^([\w-]+)\.([\w-]+)\.telkku\.com$/);

  # Map group name to API ID
  return unless my $api_id = _group2id($group);

  #
  # API parameters:
  #
  #  - date is $today
  #  - range is 24 hours (start 00:00:00.000 - end 00:00:00.000)
  #  - max. 1000 entries per channel
  #  - detailed information
  #
  # Response will include programmes from $yesterday that end $today, to
  # $tomorrow where a programme of $today ends.
  #
  my $data = _getJSON("$api_id/offering?endTime=00:00:00.000&limit=1000&startTime=00:00:00.000&view=PublicationDetails&tvDate=" . $today->ymdd());

  #
  # Programme data has the following structure
  #
  #  publicationsByChannel => [
  #    {
  #      channel      => {
  #                        id => "yle-tv1",
  #                        ...
  #                      },
  #      publications => [
  #                        {
  #                           startTime     => "2016-08-18T06:25:00.000+03:00",
  #                           endTime       => "2016-08-18T06:55:00.000+03:00",
  #                           title         => "Helil kyläs",
  #                           description   => "Osa 9/10. Asiaohjelma, mikä ...",
  #                           programFormat => "MOVIE",
  #                           ...
  #                        },
  #                        ...
  #                      ]
  #    },
  #    ...
  #  ]
  #
  if ((ref($data)                          eq "HASH")  &&
      (ref($data->{publicationsByChannel}) eq "ARRAY")) {
    my @objects;

    foreach my $item (@{ $data->{publicationsByChannel} }) {
      if ((ref($item)                 eq "HASH")  &&
	  (ref($item->{channel})      eq "HASH")  &&
	  (ref($item->{publications}) eq "ARRAY") &&
	  ($item->{channel}->{id} eq $channel)) {

	foreach my $programme (@{$item->{publications}}) {
	   my($start, $end, $title, $desc) =
	     @{$programme}{qw(startTime endTime title description)};

	   #debug(5, JSON->new->pretty->encode($programme));

	   if ($start && $end && $title && $desc) {
             $start = UnixDate($start, "%s");
	     $end   = UnixDate($end,   "%s");

	     # NOTE: entries with same start and end time are invalid
	     if ($start && $end && ($start != $end)) {
	       my $category = $categories{$programme->{programFormat}};

	       debug(3, "List entry $channel.$group ($start -> $end) $title");
	       debug(4, $desc);
	       debug(4, $category) if defined $category;

	       # Create program object
	       my $object = fi::programme->new($id, "fi", $title, $start, $end);
	       $object->category($category);
	       $object->description($desc);
	       push(@objects, $object);
	     }
	   }
	}
      }
    }

    # Fix overlapping programmes
    fi::programme->fixOverlaps(\@objects);

    return(\@objects);
  }

  return;
}

# That's all folks
1;
