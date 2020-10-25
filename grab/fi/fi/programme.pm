# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: programme class
#
###############################################################################
#
# Setup
#
# INSERT FROM HERE ############################################################
package fi::programme;
use strict;
use warnings;
use Carp;
use POSIX qw(strftime);
use URI::Escape qw(uri_unescape);

# Import from internal modules
fi::common->import();

sub _trim {
  return unless defined($_[0]);
  $_[0] =~ s/^\s+//;
  $_[0] =~ s/\s+$//;
}

# Constructor
sub new {
  my($class, $channel, $language, $title, $start, $stop) = @_;
  _trim($title);
  croak "${class}::new called without valid title or start"
    unless defined($channel) && defined($title) && (length($title) > 0) &&
           defined($start);

  my $self = {
	      channel  => $channel,
	      language => $language,
	      title    => $title,
	      start    => $start,
	      stop     => $stop,
	     };

  return(bless($self, $class));
}

# instance methods
sub category {
  my($self, $category) = @_;
  _trim($category);
  $self->{category} = $category
    if defined($category) && length($category);
}
sub description {
  my($self, $description) = @_;
  _trim($description);
  $self->{description} = $description
    if defined($description) && length($description);
}
sub episode {
  my($self, $episode, $language) = @_;
  _trim($episode);
  if (defined($episode) && length($episode)) {
    $episode =~ s/\.$//;
    push(@{ $self->{episode} }, [$episode, $language]);
  }
}
sub episode_number {
  my($self, $episode_number) = @_;
  # only accept valid, positive integers
  if (defined($episode_number)) {
    $episode_number = int($episode_number);
    if ($episode_number > 0) {
      $self->{episode_number} = $episode_number;
    }
  }
}
sub episode_total {
  my($self, $episode_total) = @_;
  # only accept valid, positive integers
  if (defined($episode_total)) {
    $episode_total = int($episode_total);
    if ($episode_total > 0) {
      $self->{episode_total} = $episode_total;
    }
  }
}
sub season {
  my($self, $season) = @_;
  # only accept valid, positive integers
  if (defined($season)) {
    $season = int($season);
    if ($season > 0) {
      $self->{season} = $season;
    }
  }
}
sub start {
  my($self, $start) = @_;
  $self->{start} = $start
    if defined($start) && length($start);
  $start = $self->{start};
  croak "${self}::start: object without valid start time"
    unless defined($start);
  return($start);
}
sub stop {
  my($self, $stop) = @_;
  $self->{stop} = $stop
    if defined($stop) && length($stop);
  $stop = $self->{stop};
  croak "${self}::stop: object without valid stop time"
    unless defined($stop);
  return($stop);
}

# read-only
sub language { $_[0]->{language} }
sub title    { $_[0]->{title}    }

# Convert seconds since Epoch to XMLTV time stamp
#
# NOTE: We have to generate the time stamp using local time plus time zone as
#       some XMLTV users, e.g. mythtv in the default configuration, ignore the
#       XMLTV time zone value.
#
sub _epoch_to_xmltv_time($) {
  my($time) = @_;

  # Unfortunately strftime()'s %z is not portable...
  #
  # return(strftime("%Y%m%d%H%M%S %z", localtime($time));
  #
  # ...so we have to roll our own:
  #
  my @time = localtime($time); #               is_dst
  return(strftime("%Y%m%d%H%M%S +0", @time) . ($time[8] ? "3": "2") . "00");
}

# Configuration data
my %series_description;
my %series_title;
my @title_map;
my $title_strip_parental;

# Common regular expressions
# ($left, $special, $right) = ($description =~ $match_description)
my $match_description = qr/^\s*([^.!?]+[.!?])([.!?]+\s+)?\s*(.*)/;

sub dump {
  my($self, $writer) = @_;
  my $language    = $self->{language};
  my $title       = $self->{title};
  my $category    = $self->{category};
  my $description = $self->{description};
  my $episode     = $self->{episode_number};
  my $season      = $self->{season};
  my $subtitle    = $self->{episode};
  my $total       = $self->{episode_total};

  #
  # Programme post-processing
  #
  # Parental level removal (catch also the duplicates)
  $title =~ s/(?:\s+\(\s*(?:S|T|K?7|K?9|K?12|K?16|K?18)\s*\))+\s*$//
      if $title_strip_parental;
  #
  # Title mapping
  #
  foreach my $map (@title_map) {
    if ($map->($title)) {
      debug(3, "XMLTV title '$self->{title}' mapped to '$title'");
      last;
    }
  }

  #
  # Check 1: object already contains episode
  #
  my($left, $special, $right);
  if (defined($subtitle)) {
    # nothing to be done
  }
  #
  # Check 2: title contains episode name
  #
  # If title contains a colon (:), check to see if the string on the left-hand
  # side of the colon has been defined as a series in the configuration file.
  # If it has, assume that the string on the left-hand side of the colon is
  # the name of the series and the string on the right-hand side is the name
  # of the episode.
  #
  # Example:
  #
  #   config: series title Prisma
  #   title:  Prisma: Totuus tappajadinosauruksista
  #
  # This will generate a program with
  #
  #   title:     Prisma
  #   sub-title: Totuus tappajadinosauruksista
  #
  elsif ((($left, $right) = ($title =~ /([^:]+):\s*(.*)/)) &&
	 (exists $series_title{$left})) {
    debug(3, "XMLTV series title '$left' episode '$right'");
    ($title, $subtitle) = ($left, $right);
  }
  #
  # Check 3: description contains episode name
  #
  # Check if the program has a description. If so, also check if the title
  # of the program has been defined as a series in the configuration. If it
  # has, assume that the first sentence (i.e. the text before the first
  # period, question mark or exclamation mark) marks the name of the episode.
  #
  # Example:
  #
  #   config:      series description Batman
  #   description: Pingviinin paluu. Amerikkalainen animaatiosarja....
  #
  # This will generate a program with
  #
  #   title:       Batman
  #   sub-title:   Pingviinin paluu
  #   description: Amerikkalainen animaatiosarja....
  #
  # Special cases
  #
  #   text:        Pingviinin paluu?. Amerikkalainen animaatiosarja....
  #   sub-title:   Pingviinin paluu?
  #   description: Amerikkalainen animaatiosarja....
  #
  #   text:        Pingviinin paluu... Amerikkalainen animaatiosarja....
  #   sub-title:   Pingviinin paluu...
  #   description: Amerikkalainen animaatiosarja....
  #
  #   text:        Pingviinin paluu?!? Amerikkalainen animaatiosarja....
  #   sub-title:   Pingviinin paluu?!?
  #   description: Amerikkalainen animaatiosarja....
  #
  elsif ((defined($description))              &&
	 (exists $series_description{$title}) &&
	 (($left, $special, $right) = ($description =~ $match_description))) {
    my($desc_subtitle, $desc_total);

    # Check for "Kausi <season>, osa <episode>. <maybe sub-title>...."
    if (my($desc_season, $desc_episode, $remainder) =
	($description =~ m/^Kausi\s+(\d+),\s+osa\s+(\d+)\.\s*(.*)$/)) {
	$season  = $desc_season;
	$episode = $desc_episode;

	# Repeat the above match on remaining description
	($left, $special, $right) = ($remainder =~ $match_description);

	# Take a guess if we have a episode title in description or not
	my $words;
	$words++ while $left =~ /\S+/g;
	if ($words > 5) {
	    # More than 5 words probably means no episode title
	    undef $left;
	    undef $special;
	    $right = $remainder;
	}

    # Check for "Kausi <season>[.,] (Jakso )?<episode>/<# of episodes>. <sub-title>...."
    } elsif (($desc_season, $desc_episode, $desc_total, $remainder) =
	($description =~ m!^Kausi\s+(\d+)[.,]\s+(?:Jakso\s+)?(\d+)(?:/(\d+))?\.\s*(.*)$!)) {
	$season  = $desc_season;
	$episode = $desc_episode;
	$total   = $desc_total    if $desc_total;

	# Repeat the above match on remaining description
	($left, $special, $right) = ($remainder =~ $match_description);

    # Check for "<sub-title>. Kausi <season>, (jakso )?<episode>/<# of episodes>...."
    } elsif (($desc_subtitle, $desc_season, $desc_episode, $desc_total, $remainder) =
	     ($description =~ m!^(.+)\s+Kausi\s+(\d+),\s+(?:jakso\s+)?(\d+)(?:/(\d+))?\.\s*(.*)$!)) {
	$left    = $desc_subtitle;
	$season  = $desc_season;
	$episode = $desc_episode;
	$total   = $desc_total    if $desc_total;

	# Remainder is already the final episode description
	$right = $remainder;
	undef $special;

    # Check for "<episode>/<# of episodes>. <sub-title>...."
    } elsif (($desc_episode, $desc_total, $remainder) =
	     ($description =~ m!^(\d+)/(\d+)\.\s+(.*)$!)) {
	# default to season 1
	$season  = 1              unless defined($season);
	$episode = $desc_episode;
	$total   = $desc_total;

	# Repeat the above match on remaining description
	($left, $special, $right) = ($remainder =~ $match_description);
    }
    if (defined($left)) {
	unless (defined($special)) {
	    # We only remove period from episode title, preserve others
	    $left =~ s/\.$//;
	} elsif (($left    !~ /\.$/) &&
		 ($special =~ /^\.\s/)) {
	    # Ignore extraneous period after sentence
	} else {
	    # Preserve others, e.g. ellipsis
	    $special =~ s/\s+$//;
	    $left    .= $special;
	}
	debug(3, "XMLTV series title '$title' episode '$left'");
    }
    ($subtitle, $description) = ($left, $right);
  }

  # XMLTV programme desciptor (mandatory parts)
  my %xmltv = (
	       channel => $self->{channel},
	       start   => _epoch_to_xmltv_time($self->{start}),
	       stop    => _epoch_to_xmltv_time($self->{stop}),
	       title   => [[$title, $language]],
	      );
  debug(3, "XMLTV programme '$xmltv{channel}' '$xmltv{start} -> $xmltv{stop}' '$title'");

  # XMLTV programme descriptor (optional parts)
  if (defined($subtitle)) {
    $subtitle = [[$subtitle, $language]]
      unless ref($subtitle);
    $xmltv{'sub-title'} = $subtitle;
    debug(3, "XMLTV programme episode ($_->[1]): $_->[0]")
      foreach (@{ $xmltv{'sub-title'} });
  }
  if (defined($category) && length($category)) {
    $xmltv{category} = [[$category, $language]];
    debug(4, "XMLTV programme category: $category");
  }
  if (defined($description) && length($description)) {
    $xmltv{desc} = [[$description, $language]];
    debug(4, "XMLTV programme description: $description");
  }
  if (defined($season) && defined($episode)) {
    if (defined($total)) {
      $xmltv{'episode-num'} =  [[ ($season - 1) . '.' . ($episode - 1) . '/' . $total . '.', 'xmltv_ns' ]];
      debug(4, "XMLTV programme season/episode: $season/$episode of $total");
    } else {
      $xmltv{'episode-num'} =  [[ ($season - 1) . '.' . ($episode - 1) . '.', 'xmltv_ns' ]];
      debug(4, "XMLTV programme season/episode: $season/$episode");
    }
  }

  $writer->write_programme(\%xmltv);
}

# class methods
# Parse config line
sub parseConfigLine {
  my($class, $line) = @_;

  # Extract words
  my($command, $keyword, $param) = split(' ', $line, 3);

  # apply URI unescaping if string contains '%XX'
  if ($param =~ /%[0-9A-Fa-f]{2}/) {
      $param = uri_unescape($param);
  }

  if ($command eq "series") {
    if ($keyword eq "description") {
      $series_description{$param}++;
    } elsif ($keyword eq "title") {
      $series_title{$param}++;
    } else {
      # Unknown series configuration
      return;
    }
  } elsif ($command eq "title") {
      if (($keyword eq "map") &&
	  # Accept "title" and 'title' for each parameter - 2nd may be empty
	  (my(undef, $from, undef, $to) =
	   ($param =~ /^([\'\"])([^\1]+)\1\s+([\'\"])([^\3]*)\3/))) {
	  debug(3, "title mapping from '$from' to '$to'");
	  $from = qr/^\Q$from\E/;
	  push(@title_map, sub { $_[0] =~ s/$from/$to/ });
      } elsif (($keyword eq "strip") &&
	       ($param   =~ /parental\s+level/)) {
	  debug(3, "stripping parental level from titles");
	  $title_strip_parental++;
      } else {
	  # Unknown title configuration
	  return;
      }
  } else {
    # Unknown command
    return;
  }

  return(1);
}

# Fix overlapping programmes
sub fixOverlaps {
  my($class, $list) = @_;

  # No need to cleanup empty/one-entry lists
  return unless defined($list) && (@{ $list } >= 2);

  my $current = $list->[0];
  foreach my $next (@{ $list }[1..$#{ $list }]) {

    # Does next programme start before current one ends?
    if ($current->{stop} > $next->{start}) {
      debug(3, "Fixing overlapping programme '$current->{title}' $current->{stop} -> $next->{start}.");
      $current->{stop} = $next->{start};
    }

    # Next programme
    $current = $next;
  }
}

# That's all folks
1;
