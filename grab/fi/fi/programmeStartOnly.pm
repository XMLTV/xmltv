# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: generate programme list using start times only
#
###############################################################################
#
# Setup
#
# INSERT FROM HERE ############################################################
package fi::programmeStartOnly;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT = qw(startProgrammeList appendProgramme convertProgrammeList);

# Import from internal modules
fi::common->import();

sub startProgrammeList($$) {
  my($id, $language) = @_;
  return({
	  id         => $id,
	  language   => $language,
	  programmes => []
	 });

}

sub appendProgramme($$$$) {
  my($self, $hour, $minute, $title) = @_;

  # NOTE: start time in minutes from midnight -> must be converted to epoch
  my $object = fi::programme->new($self->{id}, $self->{language},
				  $title, $hour * 60 + $minute);

  push(@{ $self->{programmes} }, $object);
  return($object);
}

sub convertProgrammeList($$$$) {
  my($self, $yesterday, $today, $tomorrow) = @_;
  my $programmes = $self->{programmes};
  my $id         = $self->{id};

  # No data found -> return empty list to indicate failure
  return([]) unless @{ $programmes };

  # Check for day crossing between first and second entry
  my @dates = ($today, $tomorrow);
  if ((@{ $programmes } > 1) &&
      ($programmes->[0]->start() > $programmes->[1]->start())) {

    # Did caller specify yesterday?
    if (defined $yesterday) {
      unshift(@dates, $yesterday);
    } else {
      # No, assume the second entry is broken -> drop it
      splice(@{ $programmes }, 1, 1);
    }
  }

  my @objects;
  my $date          = shift(@dates);
  my $current       = shift(@{ $programmes });
  my $current_start = $current->start();
  my $current_epoch = timeToEpoch($date,
				  int($current_start / 60),
				  $current_start % 60);
  foreach my $next (@{ $programmes }) {

    # Start of next program might be on the next day
    my $next_start = $next->start();
    if ($current_start > $next_start) {

      #
      # Sanity check: try to detect fake day changes caused by broken data
      #
      # Incorrect date change example:
      #
      #   07:00 Voittovisa
      #   07:50 Ostoskanava
      #   07:20 F1 Ennakkolähetys       <-- INCORRECT DAY CHANGE
      #   07:50 Dino, pikku dinosaurus
      #   08:15 Superpahisten liiga
      #
      #   -> 07:50 (=  470) - 07:20 (=  440) =   30 minutes < 2 hours
      #
      # Correct date change example
      #
      #   22:35 Irene Huss: Tulitanssi
      #   00:30 Formula 1: Extra
      #
      #   -> 22:35 (= 1355) - 00:30 (=   30) = 1325 minutes > 2 hours
      #
      # I grabbed the 2 hour limit out of thin air...
      #
      if ($current_start - $next_start > 2 * 60) {
	$date = shift(@dates);

	# Sanity check
	unless ($date) {
	  message("WARNING: corrupted data for $id on $today: two date changes detected. Ignoring data!");
	  return([]);
	}
      } else {
	message("WARNING: corrupted data for $id on $today: fake date change detected. Ignoring.");
      }
    }

    my $next_epoch = timeToEpoch($date,
				 int($next_start / 60),
				 $next_start % 60);

    my $title = $current->title();
    debug(3, "Programme $id ($current_epoch -> $next_epoch) $title");

    # overwrite start & stop times with epoch: see appendProgramme()
    $current->start($current_epoch);
    $current->stop($next_epoch);

    push(@objects, $current);

    # Move to next program
    $current       = $next;
    $current_start = $next_start;
    $current_epoch = $next_epoch;
  }

  return(\@objects);
}

# That's all folks
1;
