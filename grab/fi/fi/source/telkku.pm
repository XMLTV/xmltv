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
use Date::Manip qw(UnixDate);
use JSON qw();

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();
fi::programmeStartOnly->import();

# Description
sub description { 'telkku.com' }

my %categories = (
  SPORTS => "urheilu",
  MOVIE  => "elokuvat",
);

# Fetch raw HTML and extract & parse JSON
sub _getJSON($$$) {
  my($date, $page, $keys) = @_;

  # Fetch raw text
  my $text = fetchRaw("http://www.telkku.com/tv-ohjelmat/$date/patch/koko-paiva");
  if ($text) {
    #
    # All data is encoded in JSON in a script node
    #
    # <script>
    #    window.__INITIAL_STATE__ = {...};
    # </script>
    #
    my($match) = ($text =~ /window.__INITIAL_STATE__ = ({.+});/);

    if ($match) {
      my $decoded = JSON->new->decode($match);

      if (ref($decoded) eq "HASH") {
	my $data = $decoded;

        #debug(5, JSON->new->pretty->encode($decoded));

	# step through hashes using key sequence
	foreach my $key (@{$keys}) {
	  debug(5, "Looking for JSON key $key");
	  return unless exists $data->{$key};
	  $data = $data->{$key};
	}
	debug(5, "Found JSON data");

	#debug(5, JSON->new->pretty->encode($data));
	#debug(5, "KEYS: ", join(", ", sort keys %{$data}));
	return($data);
      }
    }
  }

  return;
}

# Grab channel list
sub channels {

  # Fetch & extract JSON sub-part
  my $data = _getJSON("tanaan", "peruskanavat",
		      ["channelGroups",
		       "channelGroupsArray"]);

  #
  # Channels data has the following structure
  #
  #  [
  #    {
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
	  (exists $item->{slug})              &&
	  (exists $item->{channels})          &&
	  (ref($item->{channels}) eq "ARRAY")) {
	my $group    = $item->{slug};
	my $channels = $item->{channels};

	if (defined($group) && length($group) &&
	    (ref($channels) eq "ARRAY")) {
	  debug(2, "Source telkku.com found group '$group' with " . scalar(@{$channels}) . " channels");

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

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel, $group) = ($id =~ /^([\w-]+)\.(\w+)\.telkku\.com$/);

  # Fetch & extract JSON sub-part
  my $data = _getJSON($today, $group,
		      ["offeringByChannelGroup",
		       $group,
		       "offering",
		       "publicationsByChannel"]);

  #
  # Programme data has the following structure
  #
  #  [
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
  if (ref($data) eq "ARRAY") {
    my @objects;

    foreach my $item (@{$data}) {
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
