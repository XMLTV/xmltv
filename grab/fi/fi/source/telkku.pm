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

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();

# Description
sub description { 'telkku.com' }

our %categories = (
  SPORT  => "urheilu",
  MOVIE  => "elokuvat",
);

#
# Use the JSON API endpoints from the web application.
#
sub _getJSON($) {
  my($api_path) = @_;

  # Fetch JSON object from API endpoint and return contents of "response" property
  return fetchJSON("https://il-telkku-api.prod.il.fi/v1/channel-groups/$api_path", "response");
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
  #      id       => "d63736b5-7f72-45d4-8f9e-6505f1bac855"
  #      slug     => "peruskanavat",
  #      channels => [
  #                    {
  #                      id   => "391",
  #                      name => "YLE TV1",
  #                      slug => "yle-tv-1",
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

          # initialize group/channel name to API ID map
          my %channel2id;
          $group2id{$group} = {
            id       => $api_id,
            channels => \%channel2id,
          };

          foreach my $channel (@{$channels}) {
            if (ref($channel) eq "HASH") {
              my($id, $slug, $name) = @{$channel}{qw(id slug name)};

              if (defined($id)  && length($id)    &&
                  (not exists $duplicates{$id})   &&
                  defined($slug) && length($slug) &&
                  length($name)) {
                debug(3, "channel '$name' '$slug' ($id)");
                $channels{"${slug}.${group}.telkku.com"} = "fi $name";

                # Same ID can appear in multiple groups - avoid duplicates
                $duplicates{$id}++;

                # add channel to group mapping
                $channel2id{$slug} = $id;
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

sub _group2id($$) {
  my($channel, $group) = @_;

  # Make sure group to ID map is initialized
  channels() unless %group2id;

  my $href = $group2id{$group};
  return () unless defined($href);

  return ($href->{id}, $href->{channels}->{$channel});
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel, $group) = ($id =~ /^([\w-]+)\.([\w-]+)\.telkku\.com$/);

  # Map group name to API & channel ID
  return unless my($api_id, $channel_id) = _group2id($channel, $group);
  return unless defined($channel_id);

  #
  # API parameters:
  #
  #  - startTime= is $today,    date part of ISO-8601 format
  #  - endTime=   is $tomorrow, date part of ISO-8601 format
  #
  # Response will include programmes from $yesterday that end $today, to
  # $tomorrow where a programme of $today ends.
  #
  my $data = _getJSON("$api_id/offering?startTime=" . $today->ymdd() . "&endTime=" . $tomorrow->ymdd());

  #
  # Programme data has the following structure
  #
  #  [
  #    {
  #      channelId   => "391",
  #      channelName => "YLE TV1".
  #      ...
  #      programs => {
  #        21_01_last_day: [
  #                          {
  #                             programName   => "Lomittajat",
  #                             startTime     => "2025-09-03T06:30:00.000Z",
  #                             endTime       => "2025-09-03T07:00:00.000Z",
  #                             description   => "1/8. Jouki löytää kadonneen vasikan ...",
  #                             format        => "EPISODIC",
  #                             seasonNumber  => 1,
  #                             episodeNumber => 1,
  #                             ...
  #                          },
  #                          ...
  #       ],
  #       ...
  #    },
  #    ...
  #  ]
  #
  if (ref($data) eq "ARRAY") {
    my @objects;

    foreach my $item (@{ $data }) {
      if ((ref($item)             eq "HASH")      &&
          ($item->{channelId}     eq $channel_id) &&
          (ref($item->{programs}) eq "HASH")) {

        # NOTE: hash doesn't retain chronological order of the slots!
        foreach my $programmes (values %{ $item->{programs} }) {
          if (ref($programmes) eq "ARRAY") {

            foreach my $programme (@{$programmes}) {
              if (ref($programme) eq "HASH") {

              my($start, $end, $title, $desc) =
                @{$programme}{qw(startTime endTime programName description)};

                # NOTE: description can be an empty string
                if ($start && $end && $title && defined($desc)) {
                  $start = UnixDate($start, "%s");
                  $end   = UnixDate($end,   "%s");

                  # NOTE: entries with same start and end time are invalid
                  if ($start && $end && ($start != $end)) {
                    my($category, $season, $episode_number) =
                      @{$programme}{qw(format seasonNumber episodeNumber)};
                    $category = $categories{$category};

                    # drop empty description
                    undef $desc if $desc eq '';

                    debug(3, "List entry $channel.$group ($start -> $end) $title");
                    debug(4, $desc)     if defined $desc;
                    debug(4, $category) if defined $category;
                    debug(4, sprintf("s%02de%02d", $season, $episode_number))
                      if (defined($season) && defined($episode_number));

                    # Create program object
                    my $object = fi::programme->new($id, "fi", $title, $start, $end);
                    $object->category($category);
                    $object->description($desc);
                    $object->season($season);
                    $object->episode_number($episode_number);
                    push(@objects, $object);
                  }
                }
              }
            }
          }
        }
      }
    }

    # Overlap check requies programmes to be sorted by ascending start time
    @objects = sort { $a->start() <=> $b->start() } @objects;

    # Fix overlapping programmes
    fi::programme->fixOverlaps(\@objects);

    return(\@objects);
  }

  return;
}

# That's all folks
1;
