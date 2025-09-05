# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: source specific grabber code for https://www.yle.fi
#
###############################################################################
#
# Setup
#
# INSERT FROM HERE ############################################################
package fi::source::yle;
use strict;
use warnings;
use Carp;
use Date::Manip qw(UnixDate);
use JSON qw();

BEGIN {
  our $ENABLED = 1;
}

# Import from internal modules
fi::common->import();

# Description
sub description { 'yle.fi' }

our %languages = (
    "fi" => [ "areena", "opas"  ],
    "sv" => [ "arenan", "guide" ],
);

sub _getJSON($$$) {
  my($slug, $language, $date) = @_;

  # Options "app_id" & "app_key" are mandatory
  my $app_id  = fi::programme::getOption(description(), "app_id");
  my $app_key = fi::programme::getOption(description(), "app_key");
  croak("You must set yle.fi options 'app_id' & 'app_key' in the configuration")
    unless $app_id && $app_key;

  # Fetch JSON object from API endpoint and return contents of "data" property
  return fetchJSON("https://areena.api.yle.fi/v1/ui/schedules/${slug}/${date}.json?v=10&language=${language}&app_id=${app_id}&app_key=${app_key}", "data");
}

sub _set_ua_headers() {
  my($headers, $clone) = cloneUserAgentHeaders();

  # since a DDoS attack on yle.fi on 22-Oct-2022 this header is required
  $clone->header('Accept-Language', 'en');

  # Return old headers to restore them at the end
  return $headers;
}

# Grab channel list
sub channels {
  my %channels;

  # set up user agent default headers
  my $headers = _set_ua_headers();

  # yle.fi offers program guides in multiple languages
  foreach my $code (sort keys %languages) {

    # Fetch & parse HTML (do not ignore HTML5 <time>)
    my $root = fetchTree("https://$languages{$code}[0].yle.fi/tv/$languages{$code}[1]",
                         undef, undef, 1);
    if ($root) {

      #
      # Channel list can be found from Next.js JSON data
      #
      if (my $script = $root->look_down("_tag" => "script",
                                        "id"   => "__NEXT_DATA__",
                                        "type" => "application/json")) {
        my($json)   = $script->content_list();
        my $decoded = JSON->new->decode($json);

        if ((ref($decoded)                                       eq "HASH")  &&
            (ref($decoded->{props})                              eq "HASH")  &&
            (ref($decoded->{props}->{pageProps})                 eq "HASH")  &&
            (ref($decoded->{props}->{pageProps}->{view})         eq "HASH")  &&
            (ref($decoded->{props}->{pageProps}->{view}->{tabs}) eq "ARRAY")) {

          foreach my $tab (@{ $decoded->{props}->{pageProps}->{view}->{tabs} }) {
            if ((ref($tab)            eq "HASH")  &&
                (ref($tab->{content}) eq "ARRAY")) {
              my($content) = @{ $tab->{content} };

              if ((ref($content)           eq "HASH")  &&
                  (ref($content->{source}) eq "HASH")) {
                my $name = $tab->{title};
                my $uri  = $content->{source}->{uri};

                if ($name && length($name) && $uri) {
                  my($slug) = $uri =~ m,/ui/schedules/([^/]+)/[\d-]+\.json,;

                  if ($slug) {
                    debug(3, "channel '$name' ($slug)");
                    $channels{"${slug}.${code}.yle.fi"} = "$code $name";
                  }
                }
              }
            }
          }
        }
      }

      # Done with the HTML tree
      $root->delete();

    } else {
      restoreUserAgentHeaders($headers);
      return;
    }
  }

  debug(2, "Source yle.fi parsed " . scalar(keys %channels) . " channels");
  restoreUserAgentHeaders($headers);
  return(\%channels);
}

# Grab one day
sub grab {
  my($self, $id, $yesterday, $today, $tomorrow, $offset) = @_;

  # Get channel number from XMLTV id
  return unless my($channel, $code) = ($id =~ /^([^.]+)\.([^.]+)\.yle\.fi$/);

  # Fetch & parse HTML (do not ignore HTML5 <time>)
  my $data = _getJSON($channel, $code, $today->ymdd());

  #
  # Programme data has the following structure
  #
  #  [
  #    {
  #      type         => "card",
  #      presentation => "scheduleCard",
  #      labels       => [
  #        {
  #          type => "broadcastStartDate",
  #          raw  => "2023-07-09T07:00:00+03:00",
  #          ...
  #        },
  #        {
  #          type => "broadcastEndDate",
  #          raw  => "2023-07-09T07:55:26+03:00",
  #          ...
  #        },
  #        ...
  #      ],
  #      title        => "Suuri keramiikkakisa",
  #      description  => "Kausi 4, 2/10. Tiiliä ja laastia. ...",
  #      ...
  #    },
  #    ...
  #  ],
  #
  if ((ref($data) eq "ARRAY")) {
    my @objects;

    foreach my $item (@{ $data }) {
      if ((ref($item)                 eq "HASH")  &&
          ($item->{type}              eq "card")  &&
          (ref($item->{labels})       eq "ARRAY")) {
        my($title, $desc) = @{$item}{qw(title description)};
        my($category, $start, $end);

        foreach my $label (@{ $item->{labels} }) {
          if (ref($label) eq "HASH") {
            my($type, $raw) = @{$label}{qw(type raw)};

            if ($type && $raw) {
              if (     $type eq "broadcastStartDate") {
                $start    = UnixDate($raw, "%s");
              } elsif ($type eq "broadcastEndDate") {
                $end      = UnixDate($raw, "%s");
              } elsif ($type eq "highlight") {
                $category = "elokuvat" if $raw eq "movie";
              }
            }
          }
        }

        # NOTE: entries with same start and end time are invalid
        # NOTE: programme description is optional
        if ($start && $end && ($start != $end) && $title) {
          # drop empty description
          undef $desc if defined($desc) && $desc eq '';

          debug(3, "List entry $channel ($start -> $end) $title");
          debug(4, $desc)     if defined $desc;
          debug(4, $category) if defined $category;

          # Create program object
          my $object = fi::programme->new($id, $code, $title, $start, $end);
          $object->category($category);
          $object->description($desc);
          push(@objects, $object);
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
