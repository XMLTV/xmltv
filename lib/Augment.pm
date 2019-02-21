=pod

=head1 NAME

XMLTV::Augment - Augment XMLTV listings files with automatic and user-defined rules.

=head1 DESCRIPTION

Augment an XMLTV xml file by applying corrections ("fixups") to programmes
matching defined criteria ("rules").

Two types of rules are actioned: (i) automatic, (ii) user-defined.

Automatic rules use pre-programmed input and output to modify the input
programmes. E.g. removing a "title" where it is repeated in a "sub-title"
(e.g. "Horizon" / "Horizon: Star Wars"), or trying to identify and extract
series/episode numbers from the programme"s title, sub-title or description.

User-defined rules use the content of a "rules" file which allows programmes
matching certain user-defined criteria to be corrected/enhanced with the user
data supplied (e.g. adding/changing categories for all episodes of "Horizon",
or fixing misspellings in titles, etc.)


By setting appropriate options in the "config" file, the "rules" file can be
automatically downloaded using XMLTV::Supplement.


=head1 EXPORTED FUNCTIONS

=over

=item B<B<setEncoding>>

Set the assumed encoding of the rules file.

=item B<B<inputChannel>>

Store each channel found in the input programmes file for later processing by "stats".

=item B<B<augmentProgramme>>

Augment a programme using (i) pre-determined rules and (ii) user-defined rules.
Which rules are processed is determined by the options set in the "config" file.

=item B<B<printInfo>>

Print the lists of actions taken and suggestions for further fixups.

=item B<B<end>>

Do any final processing before exit (e.g. close the log file if necessary).

=back

=head1 INSTANTIATION

    new XMLTV::Augment( { ...parameters...} );

Possible parameters:
      rule       => filename of file containing fixup rules (if omitted then no user-defined rules will be actioned) (overrides auto-fetch Supplement if that is defined; see sample options file)
      config     => filename of config file to read (if omitted then no config file will be used)
      encoding   => assumed encoding of the rules file (default = UTF-8)
      stats      => whether to print the audit stats in the log (values = 0,1) (default = 1)
      log        => filename of output log
      debug      => debug level (values 0-10) (default = no debug)
                        note debug level > 3 is not likely to be of much use unless you are developing code


=head1 TYPICAL USAGE

 1) Create the XMLTV::Augment object
 2) Pass each channel to inputChannel()
 3) Pass each programme to augmentProgramme()
 4) Tidy up using printInfo() & end()

        #instantiate the object
        my $augment = new XMLTV::Augment(
                  "rule"       => "myrules.txt",
                  "config"     => "myconfig.txt",
                  "log"        => "augment.log",
                  );
        die "failed to create XMLTV::Augment object" if !$augment;

        for each channel... {
          # store the channel details
          $augment->inputChannel( $ch );
        }

        for each programme... {
          # augmentProgramme will now do any requested processing of the input xml
          $prog = $augment->augmentProgramme( $prog );
        }

        # log the stats
        $augment->printInfo();

        # close the log file if necessary
        $augment->end();

Note: you are responsible for reading/writing to the XMLTV .xml file; the package
will not do that for you.

=head1 RULES

=over

=cut



# TODO
# ====
#
# Handle multiple 'title' in the $prog
#
# Routine to validate 'rules' file and report errors / inconsistencies
#
# Modify rule #3 processing - currently we have to check every type 3 fixup for every programme!
#
# ? Add a rule to prioritise the categories. Use case: some grabbers generate multiple categories for a programme,
# but some downstream apps (e.g. MythTV) can only handle 1 category. This means the "best" category may not be
# visible to Myth users (i.e. they just see the first one in the list which may not be the most appropriate one).
#




package XMLTV::Augment;

use XMLTV::Date 0.005066 qw( time_xmltv_to_epoch );

use Encode;

our $VERSION = 0.006001;

use base 'Exporter';
our @EXPORT = qw(setEncoding inputChannel augmentProgramme printInfo end);


# use XMLTV::Supplement qw/GetSupplement SetSupplementRoot/;



my $debug = 0;
my $logh;


# Use Log::TraceMessages if installed.
BEGIN {
	eval { require Log::TraceMessages };
	if ($@) {
		*t = sub { print STDERR @_ . "\n"; };
		*d = sub { '' };
	}
	else {
		*t = \&Log::TraceMessages::t;
		*d = \&Log::TraceMessages::d;
	}
}


# Constructor.
# Takes an array of params+value.
#
#	'rule'       => file containing fixup rules
#	'config'     => config file to read
#   'encoding'   => assumed encoding of the rules file
#	'stats'      => whether to print the 'audit' stats in the log
#	'log'        => filename of output log
#	'debug'      => debug level
#
sub new
{
    my ($class) = shift;
    my $self={ @_ };            # remaining args become attributes

	# check we have required arguments
    #for ('rule', 'config') {
	#	die "invalid usage - no $_" if !defined($self->{$_});
    #}

	# Encoding of the rules file
	$self->{'encoding'} = 'UTF-8' if !defined($self->{'encoding'});

	# Does user want stats printed in the log file?
    $self->{'stats'} = 1          if !defined($self->{'stats'});

	bless($self, $class);

	# Turn on debug. Note: debug is a 'level between 1-10.
    $debug = ( $self->{'debug'} || 0 );

	if (exists $self->{'log'} && defined $self->{'log'} && $self->{'log'} ne '') {
		open_log( $self->{'log'} );
	}
	else {
		$self->{'stats'} = 0;
	}

	# Load the requested options from the config file
	$self->{'options_all'} = 1;
	$self->{'options'} = {};
	$self->load_config($self->{'config'}) if defined($self->{'config'}) && $self->{'config'} ne '';
	$self->{'options_all'} = 0 if defined $self->{'options'}->{'enable_all_options'} && $self->{'options'}->{'enable_all_options'} == 0;

	$self->{'language_code'} = $self->{'options'}{'language_code'};  # e.g. 'en' or undef

	l("\n".'Data shown in brackets after each processing entry refers to the rule type'."\n".' and line number in the rules file, e.g. "(#3.103)" means rule type 3 on line 103 was applied.'."\n");

	# Hash to store the loaded rules
	$self->{'rules'} = {};
	# Read in the 'rules' file. Barf on error.
	if ( $self->load_rules( $self->{'rule'} ) > 0 ){ return undef; }

	# Hash to store the augmentation results
	$self->{'audit'} = {};

    return $self;
}


# Do any final processing before we exit.
#
sub end () {
	close_log();
}


# Set the assumed encoding of the rules file.
#
sub setEncoding () {
	my ($self, $encoding) = @_;

	$self->{'encoding'} = ($encoding ne '') ? $encoding : 'UTF-8';
}


# Store each channel found in the input programmes file
# for later processing by 'stats'.
#
sub inputChannel () {
	my ($self, $channel) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $value = 'input_channels';

	my $key = $channel->{'id'};
	my $ch_name = ( defined $channel->{'display-name'} ? $channel->{'display-name'}[0][0] : '' );

	$self->{'audit'}{$value}{$key}{'display_name'} = $ch_name;
}


# Augment a programme using (i) pre-determined rules and (ii) user-defined rules.
# Which rules are processed is determined by the options set in the 'config' file.
#
sub augmentProgramme () {
	my ($self, $prog) = @_;

	_d(3,'Prog in:',dd(3,$prog));

	l("Processing title~~~episode : {" . $prog->{'title'}[0][0] . '~~~'
	       . (defined $prog->{'sub-title'} ? $prog->{'sub-title'}[0][0] : '') . "}" );

	# Remove "New $title" if seen in episode field (rule A1)
    $self->remove_duplicated_new_title_in_ep($prog);

	# Remove a duplicated programme title/ep if seen in episode field (rule A2)
	$self->remove_duplicated_title_and_ep_in_ep($prog);

	# Remove a duplicated programme title if seen in episode field (rule A3)
	$self->remove_duplicated_title_in_ep($prog);

	# Check description for possible premiere/repeat hints (rule A4)
	$self->update_premiere_repeat_flags_from_desc($prog);

	# Look for series/episode/part numbering in programme title/subtitle/description (rule A5)
	$self->check_potential_numbering_in_text($prog);

	# Title and episode processing. (user rules)
	# We process titles if the user has
	# not explicitly disabled title processing during configuration
	# and we have supplement data to process programmes against.
	$self->process_user_rules($prog);

	# Look again for series/episode/part numbering in programme title/subtitle/description (rule A5)
	# This is to allow any new series/episode/part numbering added via a user rule to be extracted.
	$self->check_potential_numbering_in_text($prog);


	# Tidy <title> text after title processing
	$self->tidy_title_text($prog);

	# Tidy <sub-title> (episode) text after title processing
	$self->tidy_episode_text($prog);

	# Tidy $desc text after title processing
	$self->tidy_desc_text($prog);

    # Add missing language codes to <title>, <sub-title> and <desc> elements
    $self->add_missing_language_codes($prog);

	l("\t Post-processing title/episode: {" . $prog->{'title'}[0][0] . '~~~'
	       . (defined $prog->{'sub-title'} ? $prog->{'sub-title'}[0][0] : '') . "}" );


	# Store title debug info for later analysis
	#  (printed out in the log for manual inspection -
	#    allows you to check for new rule requirements)
	$self->store_title_debug_info($prog);

	# Store genre debug info for later analysis
	$self->store_genre_debug_info($prog);


	_d(3,'Prog out:',dd(3,$prog));
	return $prog;
}



# Tidy <title>
sub tidy_title_text () {
	my ($self, $prog) = @_;

    if (defined $prog->{'title'}) {
		for (my $i=0; $i < scalar @{$prog->{'title'}}; $i++) {

			# replace repeated spaces
			$prog->{'title'}[$i][0] =~ s/\s+/ /g;

			# remove trailing character if any of .,:;-| and not ellipsis
			# bug #503 : don't remove trailing period if it could be an abbreviation, e.g. 'M.I.A.'
			$prog->{'title'}[$i][0] =~ s/[|\.,:;-]$//  if $prog->{'title'}[$i][0] !~ m/\.{3}$/ && $prog->{'title'}[$i][0] !~ m/\..\.$/;
		}
    }
}


# Tidy <sub-title>
# Remove <sub-title> if empty/whitespace
sub tidy_episode_text () {
	my ($self, $prog) = @_;

	if (defined $prog->{'sub-title'}) {
		for (my $i=0; $i < scalar @{$prog->{'sub-title'}}; $i++) {

			# replace repeated spaces
			$prog->{'sub-title'}[$i][0] =~ s/\s+/ /g;

			# remove trailing character if any of .,:;-| and not ellipsis
			# bug #503 : don't remove trailing period if it could be an abbreviation, e.g. 'In the U.S.'
			$prog->{'sub-title'}[$i][0] =~ s/[|\.,:;-]$//g  if $prog->{'sub-title'}[$i][0] !~ m/\.{3}$/ && $prog->{'sub-title'}[$i][0] !~ m/\..\.$/;
		}
	}

	# delete sub-title if now empty
	# TODO: needs modifying to properly handle multiple sub-titles
	if (defined $prog->{'sub-title'}) {
		if ( $prog->{'sub-title'}[0][0] =~ m/^\s*$/ ) {
			splice(@{$prog->{'sub-title'}},0,1);
			if (scalar @{$prog->{'sub-title'}} == 0) {
				delete $prog->{'sub-title'};
			}
		}
	}
}


# Tidy <desc> description text
# Remove <desc> if empty/whitespace
sub tidy_desc_text () {
	my ($self, $prog) = @_;

    if (defined $prog->{'desc'}) {
		for (my $i=0; $i < scalar @{$prog->{'desc'}}; $i++) {

			# replace repeated spaces
			$prog->{'desc'}[$i][0] =~ s/\s+/ /g;

			# remove trailing character if any of ,:;-|
			$prog->{'desc'}[$i][0] =~ s/[|,:;-]$//g;
		}
    }

    # delete desc if now empty
    # TODO: needs modifying to properly handle multiple descriptions
    if (defined $prog->{'desc'}) {
        if ( $prog->{'desc'}[0][0] =~ m/^\s*$/ ) {
            splice(@{$prog->{'desc'}},0,1);
            if (scalar @{$prog->{'desc'}} == 0) {
                delete $prog->{'desc'};
            }
        }
    }
}


# Add missing language codes to <title>, <sub-title> and <desc> elements
sub add_missing_language_codes () {
    _d(3,self());
    my ($self, $prog) = @_;

    my @elems = ('title', 'sub-title', 'desc');
    foreach my $elem (@elems) {
        if (defined $prog->{$elem}) {
            dd(3,$prog->{$elem});
            for (my $i=0; $i < scalar @{$prog->{$elem}}; $i++) {

                # add language code if missing (leave existing codes alone)
                # my $v = $prog->{$elem}[$i][0];
                # $prog->{$elem}[$i] = [ $v, $self->{'language_code'} ];
                push @{$prog->{$elem}[$i]}, $self->{'language_code'}
                        if (scalar @{$prog->{$elem}[$i]} == 1);
            }
        }
    }
}


=item B<remove_duplicated_new_title_in_ep>

Rule #A1

Remove "New $title :" from <sub-title>

  If sub-title starts with "New" + <title> + separator, then it will be removed from the sub-title
  "separator" can be any of .,:;-

  in : "Antiques Roadshow / New Antiques Roadshow: Doncaster"
  out: "Antiques Roadshow / Doncaster"

=cut

# Rule A1
#
# Remove "New $title" from episode field
#
# Listings may contain "New $title" duplicated at the start of the episode field
#
sub remove_duplicated_new_title_in_ep () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 'A1';

    if (defined $prog->{'sub-title'}) {
        my $tmp_title = $prog->{'title'}[0][0];
        my $tmp_episode = $prog->{'sub-title'}[0][0];
        my $key = $tmp_title . "|" . $tmp_episode;

        # Remove the "New $title" text from episode field if we find it
        if ( $tmp_episode =~ m/^New \Q$tmp_title\E\s*[\.,:;-]\s*(.+)$/i ) {
            $prog->{'sub-title'}[0][0] = $1;
            l(sprintf("\t Removing 'New \$title' text from beginning of episode field (#%s)", $ruletype));
			$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode })
        }
    }
}


=item B<remove_duplicated_title_and_ep_in_ep>

Rule #A2

Remove duplicated programme title *and* episode from <sub-title>

  If sub-title starts with <title> + separator + <episode> + separator + <episode>, then it will be removed from the sub-title
  "separator" can be any of .,:;-

  in : "Antiques Roadshow / Antiques Roadshow: Doncaster: Doncaster"
  out: "Antiques Roadshow / Doncaster"

=cut

# Rule A2
#
# Remove duplicated programme title *and* episode from episode field
#
# Listings may contain the programme title *and* episode duplicated in the episode field:
# i) at the start separated from the episode by colon - "$title: $episode: $episode"
#
sub remove_duplicated_title_and_ep_in_ep () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 'A2';

    if (defined $prog->{'sub-title'}) {
        my $tmp_title = $prog->{'title'}[0][0];
        my $tmp_episode = $prog->{'sub-title'}[0][0];
        my $key = $tmp_title . "|" . $tmp_episode;

        # Remove the duplicated title/ep from episode field if we find it
        # Use a backreference to match the second occurence of the episode text
        if ( $tmp_episode =~ m/^\Q$tmp_title\E\s*[\.,:;-]\s*(.+)\s*[\.,:;-]\s*\1$/i ) {
            $prog->{'sub-title'}[0][0] = $1;
            l(sprintf("\t Removing duplicated title/ep text from episode field (#%s)", $ruletype));
			$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode })
        }
    }
}


=item B<remove_duplicated_title_in_ep>

Rule #A3

Remove duplicated programme title from <sub-title>

  i) If sub-title starts with <title> + separator, then it will be removed from the sub-title
  ii) If sub-title ends with separator + <title>, then it will be removed from the sub-title
  iii) If sub-title starts with <title>(...), then the sub-title will be set to the text in brackets
  iv) If sub-title equals <title>, then the sub-title will be removed
  "separator" can be any of .,:;-

  in : "Antiques Roadshow / Antiques Roadshow: Doncaster"
  out: "Antiques Roadshow / Doncaster"

  in : "Antiques Roadshow / Antiques Roadshow (Doncaster)"
  out: "Antiques Roadshow / Doncaster"

  in : "Antiques Roadshow / Antiques Roadshow"
  out: "Antiques Roadshow / "

=cut

# Rule A3
#
# Remove duplicated programme title from episode field
#
# Listings may contain the programme title duplicated in the episode field, either:
# i) at the start followed  by the 'real' episode in parentheses (rare),
# ii) at the start separated from the episode by a colon/hyphen,
# iii) at the end separated from the episode by a colon/hyphen,
# iv) no episode at all (e.g. "Teleshopping" / "Teleshopping")
#
sub remove_duplicated_title_in_ep () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 'A3';

    if (defined $prog->{'sub-title'}) {
        my $tmp_title = $prog->{'title'}[0][0];
        my $tmp_episode = $prog->{'sub-title'}[0][0];
        my $key = $tmp_title . "|" . $tmp_episode;

        # Remove the duplicated title from episode field if we find it
        if ($tmp_episode =~ m/^\Q$tmp_title\E\s*[\.,:;-]\s*(.+)?$/i
			|| $tmp_episode =~ m/^\Q$tmp_title\E\s+\((.+)\)$/i
			|| $tmp_episode =~ m/^\Q$tmp_title\E\s*$/i ) {
            $prog->{'sub-title'}[0][0] = defined $1 ? $1 : '';
            l(sprintf("\t Removing title text from beginning of episode field (#%s)", $ruletype));
			$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode })
        }
        # Look for title appearing at end of episode field
        elsif ($tmp_episode =~ m/^(.+?)\s*[\.,:;-]\s*\Q$tmp_title\E$/i ) {
            $prog->{'sub-title'}[0][0] = $1;
            l(sprintf("\t Removing title text from end of episode field (#%s)", $ruletype));
			$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode })
        }
    }
}


=item B<update_premiere_repeat_flags_from_desc>

Rule #A4

Set the <premiere> element and remove any <previously-shown> element if <desc> starts with "Premiere." or "New series". Remove the "Premiere." text.
Set the <previously-shown> element and remove any <premiere> element if <desc> starts with "Another chance" or "Rerun" or "Repeat"

=cut

# Rule A4
#
# Update the premiere/repeat flags based on contents of programme desc
# Do this before check_potential_numbering_in_text()
#
sub update_premiere_repeat_flags_from_desc () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 'A4';

	my $tmp_title = $prog->{'title'}[0][0];
	my $tmp_episode = (defined $prog->{'sub-title'} ? $prog->{'sub-title'}[0][0] : '');

	#(always remove the "Premiere." text even if <premiere> is already set)
	#if (!defined $prog->{'premiere'}) {

		if (defined $prog->{'desc'}) {

			my $key = $prog->{'title'}[0][0];

			# Check if desc start with "Premiere.". Remove if found and set flag
			if ($prog->{'desc'}[0][0] =~ s/^Premiere\.\s*//i ) {
				l("\t Setting premiere flag based on description (Premiere. )");
				$prog->{'premiere'} = [];
				delete $prog->{'previously-shown'};
				$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode })
			}

			# Check if desc starts with "New series..."
			elsif ($prog->{'desc'}[0][0] =~ m/^New series/i ) {
				l("\t Setting premiere flag based on description (New series...)");
				$prog->{'premiere'} = [];
				delete $prog->{'previously-shown'};
				$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode })
			}

		}

	#}

	if (!defined $prog->{'previously-shown'}) {

		if (defined $prog->{'desc'}) {

			my $key = $prog->{'title'}[0][0];

			# Flag showings described as repeats
			if ($prog->{'desc'}[0][0] =~ m/^(Another chance|Rerun|Repeat)/i ) {
				l("\t Setting repeat flag based on description (Another chance...)");
				$prog->{'previously-shown'} = {};
				delete $prog->{'premiere'};
				$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode })
			}

		}

	}
}



=item B<check_potential_numbering_in_text>

Rule #A5

Check for potential series, episode and part numbering in the title, episode and description fields.

=cut

# Rule A5
#
# Check for potential episode numbering in the title
# or episode or description fields
#
sub check_potential_numbering_in_text () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());
	_d(5,'Prog, before potential numbering:',dd(5,$prog));

	# extract the existing episode-num
	my $xmltv_ns = '';
	my $episode_num = $self->extract_ns_epnum($prog, \$xmltv_ns);

	# make a work copy of $prog
	my $_prog = {'_title'  			=> (defined $prog->{'title'} ? $prog->{'title'}[0][0] : undef),
				 '_episode' 		=> (defined $prog->{'sub-title'} ? $prog->{'sub-title'}[0][0] : undef),
				 '_desc' 			=> (defined $prog->{'desc'} ? $prog->{'desc'}[0][0] : undef),
				 '_series_num' 		=> $episode_num->{'season'},
				 '_series_total' 	=> $episode_num->{'season_total'},
				 '_episode_num' 	=> $episode_num->{'episode'},
				 '_episode_total' 	=> $episode_num->{'episode_total'},
				 '_part_num' 		=> $episode_num->{'part'},
				 '_part_total' 		=> $episode_num->{'part_total'},
				 };

	_d(4,'_Prog, before numbering:',dd(4,$_prog));
	my $t_title = $_prog->{'_title'}.' / '.($_prog->{'_episode'} || 'undef');

    $self->extract_numbering_from_episode($_prog);
    $self->extract_numbering_from_title($_prog);
    $self->extract_numbering_from_desc($_prog);

	$self->make_episode_from_part_numbers($_prog);

	_d(4,'_Prog, after numbering:',dd(4,$_prog));
	# Writer will barf if the title is empty
	if (!defined $_prog->{'_title'} || $_prog->{'_title'} eq '') {
		_d(0,"Prog title is now empty! Was \{$t_title\}  Now {",$_prog->{'_title'},' / ',($_prog->{'_episode'} || 'undef').'}');
		$_prog->{'_title'} = '(no title)';
	}

	# update the title and sub-title and description in the programme
	$prog->{'title'}[0][0] 			= $_prog->{'_title'}   if defined $_prog->{'_title'};
	$prog->{'sub-title'}[0][0] 		= $_prog->{'_episode'} if defined $_prog->{'_episode'};
	$prog->{'desc'}[0][0] 			= $_prog->{'_desc'}    if defined $_prog->{'_desc'};

	# update the episode-num
	$episode_num->{'season'} 		= $_prog->{'_series_num'};
	$episode_num->{'season_total'} 	= $_prog->{'_series_total'};
	$episode_num->{'episode'} 		= $_prog->{'_episode_num'};
	$episode_num->{'episode_total'} = $_prog->{'_episode_total'};
	$episode_num->{'part'} 			= $_prog->{'_part_num'};
	$episode_num->{'part_total'} 	= $_prog->{'_part_total'};

	# remake the episode-num
	my $xmltv_ns_new = $self->make_ns_epnum($prog, $episode_num);

	if ($xmltv_ns_new ne $xmltv_ns) {
		$key = $_prog->{'_title'};
		$self->add_to_audit ($me, $key, $_prog);
	}

	_d(5,'Prog, after potential numbering:',dd(5,$prog));
}


=item B<extract_numbering_from_title>

Rule #A5.1

Extract series/episode numbering found in <title>.

=cut

# Rule A5.1
#
# Check for potential season numbering in <title>
#
sub extract_numbering_from_title () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

    if (defined $prog->{'_title'}) {
		_d(3,'Checking <title> for numbering');
		$self->extract_numbering($prog, 'title');
    }
}


=item B<extract_numbering_from_episode>

Rule #A5.2

Extract series/episode numbering found in <sub-title>.

=cut

# Rule A5.2
#
# Extract series/episode numbering found in <sub-title>. Series
# and episode numbering are parsed out of the text and eventually made
# available in the <episode-num> element.
#
sub extract_numbering_from_episode () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

    if (defined $prog->{'_episode'}) {
		_d(3,'Checking <sub-title> for numbering');
		$self->extract_numbering($prog, 'episode');
    }
}


=item B<extract_numbering_from_desc>

Rule #A5.3

Extract series/episode numbering found in <desc>.

=cut

# Rule A5.3
#
# Check for potential season/episode numbering in description. Only
# use numbering found in the desc if we have not already found it
# elsewhere (i.e. prefer data provided in the subtitle field of the
# raw data).
#
sub extract_numbering_from_desc () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	if (defined $prog->{'_desc'}) {
		_d(3,'Checking <desc> for numbering');
		$self->extract_numbering($prog, 'desc');
    }
}


# used by: extract_numbering_from_title(), extract_numbering_from_episode(), extract_numbering_from_desc()
# 2 params: 1) working program hash  2) type: 'title', 'episode' or 'desc'
sub extract_numbering () {
    my ($self, $prog, $field) = @_;

    my %elems = ( 'title' => '_title', 'episode' => '_episode', 'desc' => '_desc', 'description' => '_desc' );
    my $elem = $elems{$field};

    my ($s, $stot, $e, $etot, $p, $ptot);
    my $int;
    # TODO: set $lang_words according to 'language_code' option
    #        also the 'series', 'season' and 'episode' text in the regexs
    my $lang_words = qr/one|two|three|four|five|six|seven|eight|nine/i;

    # By default, we do not update existing numbering if also extracted from
    # series/episode/part fields
    $self->{'options'}{'update_existing_numbering'} = 0
            unless exists $self->{'options'}{'update_existing_numbering'};

    _d(4,"\t extract_numbering: $field : in  : ","<$prog->{$elem}>");

    # Theoretically it's possible to do this in one regex but it gets too unwieldy when we start catering
    # for "series" at the front as well as the back, and it's not easy to maintain
    # so we'll parse out the values in separate passes

    # First, remove any part numbering from the *end* of the element

    # Should match --v
    #   Dead Man's Eleven
    #   Dead Man's Eleven: 1
    #   Dead Man's Eleven (Part 1)
    #   Dead Man's Eleven - (Part 1)
    #   Dead Man's Eleven - (Part 1/2)
    #   Dead Man's Eleven (Pt 1)
    #   Dead Man's Eleven - (Pt. 1)
    #   Dead Man's Eleven - (Pt. 1/2)
    #   Dead Man's Eleven - Part 1
    #   Dead Man's Eleven: Part 1
    #   Dead Man's Eleven; Pt 1
    #   Dead Man's Eleven, Pt. 1
    #   Dead Man's Eleven Part 1
    #   Dead Man's Eleven Pt 1
    #   Dead Man's Eleven Pt 1/2
    #   Dead Man's Eleven Pt. 1
    #   Dead Man's Eleven - Part One
    #   Dead Man's Eleven: Part One
    #   Dead Man's Eleven; Pt One
    #   Dead Man's Eleven, Pt. One
    #   Dead Man's Eleven Part One
    #   Dead Man's Eleven Pt One
    #   Dead Man's Eleven Pt. One
    #   Dead Man's Eleven (Part One)
    #   Dead Man's Eleven - (Part One)
    #   Dead Man's Eleven (Pt One)
    #   Dead Man's Eleven - (Pt. One)
    #   Part One
    #   Pt Two
    #   Pt. Three
    #   Part One of Two
    #   Pt Two / Three
    #   Pt. Three of Four
    #   Part 1
    #   Part 1/3
    #   Pt 2
    #   Pt 2/3
    #   Pt. 3
    #
    # Should not match --v
    #   Burnley v Preston North End: 2006/07

    if ( $prog->{$elem} =~
            s{
                (?:
                        [\s,:;-]*
                        \(?
                    (?:
                        part|pt\.?
                    )
                        \s*
                        (?! (?:19|20)\d\d ) (\d+ | ${lang_words})   # $1
                        \s*
                    (?:
                      (?:
                        /|of
                      )
                        \s*
                        (\d+ | ${lang_words})                       # $2
                    )?
                        \)?
                            |
                        :
                        \s*
                        (\d+)                                       # $3
                )

                        [\s.,:;-]*
                        $
            }
            { }ix
        )
    {
        _d(4,"\t matched 'part' regex");
        $int = word_to_digit($3 || $1);				# $3 is in use case "Dead Man's Eleven: 1"
        $p = $int  if defined $int and $int > 0;
        $int = word_to_digit($2) if defined $2;
        $ptot = $int if defined $2 && defined $int and $int > 0;
    }

    # Next, extract and strip "series x/y"
    #
    # Should match --v
    #   Series 1
    #   Series one :
    #   Series 2/4
    #   Series 12. Abc
    #   Series 1.
    #   Wheeler Dealers - (Series 1)
    #   Wheeler Dealers, - (Series 1.)
    #   Wheeler Dealers (Series 1, Episode 4)
    #   Wheeler Dealers Series 1, Episode 4.
    #   Series 8. Abc
    #   Series 8/10. Abc
    #   Wheeler Dealers - (Series 1)
    #   Wheeler Dealers (Season 1)
    #   Wheeler Dealers Series 1
    #   Wheeler Dealers Series 1, 3
    #
    # Does not match --v
    #   Series 4/7. Part one. Abc
    #   Series 6, Episode 4/7. Part one. Abc

    if ( $prog->{$elem} =~
            s{
                (?:
                    [\s.,:;-]*
                    \(?
                )
                (?:
                    series|season
                )
                    \s*
                    ( \d+ | ${lang_words} )     # $1
                (?:
                    [\s/]*
                    ( \d+ )                     # $2
                )?
                    [.,]?
                    \)?
                    [\s\.,:;-]*
            }
            { }ix
        )
    {
        _d(4,"\t matched 'series' regex");
        $int = word_to_digit($1);
        $s = $int  if defined $int and $int > 0;
        $stot = $2 if defined $2;
    }

    # Extract and strip the "episode"
    #
    # i) check for "Episode x/x" format covering following formats:
    #
    # Should match --v
    #   Episode one :
    #   Episode 2/4
    #   Episode 12. Abc
    #   Episode 1.
    #   Wheeler Dealers - (Episode 1)
    #   Wheeler Dealers, - (Episode 1.)
    #   Wheeler Dealers (Series 1, Episode 4)
    #   Wheeler Dealers Series 1, Episode 4.
    #
    # Should not match --v
    #   Series 8. Abc
    #   Series 8/10. Abc
    #   1/6 - Abc
    #   1/6, series 1 - Abc
    #   1, series 1 - Abc
    #   1/6, series one - Abc
    #   1/6. Abc
    #   1/6; series one
    #   1, series one - Abc
    #
    # Does not match --v
    #   Episode 4/7. Part one. Abc
    #   Series 6, Episode 4/7. Part one. Abc

    if ( $prog->{$elem} =~
            s{
                (?:
                    [\s.,:;-]*
                    \(?
                )
                (?:
                    episode
                )
                    \s*
                    (\d+ | ${lang_words})       # $1
                (?:
                    [\s/]*
                    (\d+)                       # $2
                )?
                    [.,]?
                    \)?
                    [\s.,:;-]*
            }
            { }ix
        )
    {
        _d(4,"\t matched 'episode' regex");
        $int = word_to_digit($1);
        $e = $int  if defined $int and $int > 0;
        $etot = $2 if defined $2;
    }

    # Extract and strip the episode "x/y" if number at start of data
    #
    # Note: beware of false positives with e.g. "10, Rillington Place" or "1984".
    # Those entries below tagged "<-- cannot match" are not matched to avoid
    # false positives c.f. "10, Rillington Place")
    #
    # I'm not convinced we should be matching things like "1." - can we be sure
    # this is an ep number?
    #
    # Should match --v
    #   1/6 - Abc
    #   1/6, series 1 - Abc
    #   1/6, series one - Abc
    #   1/6. Abc
    #   1/6; series one
    #   4/25 Wirral v Alicante, Spain
    #   1/6 - Abc
    #   1/6, Abc
    #   1/6. Abc
    #   1/6;
    #   (1/6)
    #   [1/6]
    #   1.
    #   1,
    #   2/25 Female Problems
    #
    # Should not match --v
    #   1, series 1 - Abc       <-- cannot match
    #   1, series one - Abc     <-- cannot match
    #   1, Abc                  <-- cannot match
    #   3rd Rock
    #   3 rd Rock
    #   10, Rillington Place
    #   10 Rillington Place
    #   1984
    #   1984.                   <-- false positive
    #   Episode 1
    #   Episode one
    #   Episode 2/4
    #   {Premier League Years~~~1999/00}

    elsif ( $prog->{$elem} =~

            # note we insist on the "/" unless the title is just "number." or "number,"
            # this is to avoid false matching on "1984" but even here we will falsely match "1984."
            #
            s{
                    ^
                    [([]*
                    (?! (?:19|20)\d\d ) (\d+)   # $1
                    \s*
                (?:
                    /
                    \s*
                        |
                    [.,]
                    $
                )
                    (\d*)                       # $2
                    [.,]?
                    [)\]]*
                    \s?
                (?:
                    [\s.,:;-]+
                    \s*
                        |
                    \s*
                    $
                )
            }
            {}ix
        )
    {
        _d(4,"\t matched 'leading episode' regex");
        $int = word_to_digit($1);
        $e = $int  if defined $int and $int > 0;
        $etot = $2 if defined $2;
    }

    # Extract and strip the episode "x/y" if number at end of data
    #
    # Should match --v
    #   1/6
    #   1/6.
    #   (1/6)
    #   [1/6]
    #   1 / 6
    #   ( 1/6 )
    #   In the Mix. 2 / 6
    #   In the Mix. ( 2/6 ).
    #
    # Should not match --v
    #   £20,000.
    #   20,000
    #   the 24.
    #   go 24.
    #   24
    #   1984
    #   2015/16
    #   2015/2016 (could theoretically be ok but statistically unlikely)
    #   2015/3000 (could be ok but the likes of Eastenders don't have a 'total' so again this is unlikely)

    elsif ( $prog->{$elem} =~
            s{
                (?:
                    ^
                        |
                    [\s(\[]+
                )
                    (?! (?:19|20)\d\d ) (\d+)       # $1
                    \s*
                    \/
                    \s*
                    (\d+)                           # $2
                    [\s.,]?
                    [)\]]*
                    [\s.]*
                    $
            }
            {}ix
        )
    {
        _d(4,"\t matched 'trailing episode' regex");
        $int = word_to_digit($1);
        $e = $int  if defined $int and $int > 0;
        $etot = $2 if defined $2;
    }

    # Extract and strip the series/episode "sXeY" at end of data
    #
    # Should match --v
    #   e6
    #   [E6]
    #   s1e6
    #   (s1e6)
    #   In the Mix. S1E6
    #   In the Mix. ( S1E6 ).

    elsif ( $prog->{$elem} =~
            s{
                (?:
                    ^
                        |
                    [\s([]+
                )
                    s?
                    (\d+)?      # $1
                    \s*
                    e
                    \s*
                    (\d+)       # $2
                    [\s.,]?
                    [)\]]*
                    [\s.]*
                    $
            }
            {}ix
        )
    {
        _d(4,"\t matched 'trailing series/episode' regex");
        $s = $1 if defined $1 and $1 > 0;
        $e = $2 if defined $2 and $2 > 0;
    }


	# tidy any leading/trailing spaces we've left behind
	trim($prog->{$elem});

	#
	_d(4,"\t extract_numbering: $field : out : ","<$prog->{$elem}>");



	my @vals = ( [ 'series',  '_series_num',  $s ], [ 'series total',  '_series_total',  $stot ],
				 [ 'episode', '_episode_num', $e ], [ 'episode total', '_episode_total', $etot ],
				 [ 'part',    '_part_num',    $p ], [ 'part total',    '_part_total',    $ptot ]
			   );

	foreach (@vals) {
		my ($text, $key, $val) = @$_;
		if (defined $val && $val ne '' && $val > 0) {
			# do we already have a number?
			if (defined $prog->{$key} && $prog->{$key} != $val) {
                if ($self->{'options'}{'update_existing_numbering'}) {
                    l(sprintf("\t %s number (%s) already defined. Updating with new %s number (%s) in %s.", ucfirst($text), $prog->{$key}, $text, $val, $field));
                    $prog->{$key} = $val;
                }
                else {
                    l(sprintf("\t %s number (%s) already defined. Ignoring different %s number (%s) in %s.", ucfirst($text), $prog->{$key}, $text, $val, $field));
                }
			} else {
				l(sprintf("\t %s number found: %s %s (from %s)", ucfirst($text), $text, $val, $field));
				$prog->{$key} = $val;
			}
		}
	}


	# Check that a programme's given series/episode/part number is not greater than
    # the total number of series/episodes/parts.
    #
	# Rather than discard the given number, we discard the total instead, which
	# is more likely to be incorrect based on observation.
	#
    my @comps = ( [ 'series',  '_series_num',  '_series_total',  ],
                  [ 'episode', '_episode_num', '_episode_total', ],
                  [ 'part',    '_part_num',    '_part_total',    ],
                );

    foreach (@comps) {
        my ($key, $key_num, $key_total) = @$_;
        if (defined $prog->{$key_num} && defined $prog->{$key_total}) {
            if ($prog->{$key_num} > $prog->{$key_total}) {
                l(sprintf("\t Bad %s total found: %s %s of %s, discarding total (from %s)", $key, $key, $prog->{$key_num}, $prog->{$key_total}, $field));
                $prog->{$key_total} = 0;
            }
        }
    }

}


=item B<make_episode_from_part_numbers>

Rule #A5.4

If no <sub-title> then make one from "part" numbers.

  in : "Panorama / "  desc = "Part 1/2..."
  out: "Panorama / Part 1 of 2"

=cut

# Rule A5.4
#
# if no episode title then make one from part numbers
#
sub make_episode_from_part_numbers () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

    if (!defined $prog->{'_episode'}
             || $prog->{'_episode'} =~ m/^\s*$/ ) {

		if (defined $prog->{'_part_num'} ) {

			_d(4,"\t creating 'episode' from part number(s)");

			# no episode title so make one
			$prog->{'_episode'} = "Part $prog->{'_part_num'}" . ($prog->{'_part_total'} ? ' of '.$prog->{'_part_total'} : '');

			l(sprintf("\t Created episode from part number(s): %s", $prog->{'_episode'}));
			$self->add_to_audit ($me, $prog->{'_title'}, $prog);
		}

	}
}


=item B<process_user_rules>

Rule #user

Process programme against user-defined fixups

The individual rules each have their own option to run or not; consider this like an on/off switch for all of them. I.e. if this option is off then no user rules will be run (irrespective of any other option flags).

=cut

# Rule user
#
# Process programme against user-defined title fixups
#
sub process_user_rules () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());
	_d(5,'Prog, before title fixups:',dd(5,$prog));

	# extract the existing episode-num
	my $xmltv_ns = '';
	my $episode_num = $self->extract_ns_epnum($prog, \$xmltv_ns);

	# make a work copy of $prog
	#  (this is mainly for ease of use with the _uk_rt code on which this class is based)
	#
	my $_prog = {'_title'  			=> (defined $prog->{'title'} ? $prog->{'title'}[0][0] : undef),
				 '_episode' 		=> (defined $prog->{'sub-title'} ? $prog->{'sub-title'}[0][0] : undef),
				 '_desc' 			=> (defined $prog->{'desc'} ? $prog->{'desc'}[0][0] : undef),
				 '_genres'			=> (defined $prog->{'category'} ? $prog->{'category'} : undef),
				 '_channel'			=> (defined $prog->{'channel'} ? $prog->{'channel'} : undef),
				 '_series_num' 		=> $episode_num->{'season'},
				 '_series_total' 	=> $episode_num->{'season_total'},
				 '_episode_num' 	=> $episode_num->{'episode'},
				 '_episode_total' 	=> $episode_num->{'episode_total'},
				 '_part_num' 		=> $episode_num->{'part'},
				 '_part_total' 		=> $episode_num->{'part_total'},
                 '_has_numbering'   => (defined $episode_num ? 1 : 0),
				 };

	_d(4,'_Prog, before title fixups:',dd(4,$_prog));


	# TODO : the user rules are not processed in numerical order - there's no clues
	#        in uk_rt grabber (on whch this class is based) as to why the following
	#        order was chosen or even if it matters (since most of the rules are
	#        not cumulative)

    # Remove non-title text found in programme title (type = 1)
    $self->process_non_title_info($_prog);

    # Track when titles/subtitles have been updated -
	# allows skip certain rules if the programme has already been processed by another rule.
	# (NOTE: this means the rules are not cumulative)
    $_prog->{'_titles_processed'} = 0;
    $_prog->{'_subtitles_processed'} = 0;


	# Next, process titles to make them consistent

    # One-off demoted title replacements (type = 11)
    $self->process_demoted_titles($_prog)  if (! $_prog->{'_titles_processed'});

    # One-off title and episode replacements (type = 10)
    $self->process_replacement_titles_desc($_prog)  if (! $_prog->{'_titles_processed'});

    # One-off title and episode replacements (type = 8)
    $self->process_replacement_titles_episodes($_prog)  if (! $_prog->{'_titles_processed'});

    # Look for $title:$episode in source title (type = 2)
    $self->process_mixed_title_subtitle($_prog)  if (! $_prog->{'_titles_processed'});

    # Look for $episode:$title in source title (type = 3)
    $self->process_mixed_subtitle_title($_prog)  if (! $_prog->{'_titles_processed'});

    # Look for reversed title and subtitle information (type = 4)
    $self->process_reversed_title_subtitle($_prog)  if (! $_prog->{'_titles_processed'});

    # Look for inconsistent programme titles (type = 5)
    #
    # This fixup is applied to all titles (processed or not) to handle
    # titles split out in fixups of types 2-4 above
    $self->process_replacement_titles($_prog);

    # Remove programme numbering for a 'corrected' title
    # (optionally limited to a specified channel identifier)
    $self->process_remove_numbering_from_programmes($_prog); # (type=16)


    # Next, process subtitles to make them consistent

    # Remove text from programme subtitles (type = 13)
    $self->process_subtitle_remove_text($_prog)  if (! $_prog->{'_subtitles_processed'});

	# Look for inconsistent programme subtitles (type = 7)
    $self->process_replacement_episodes($_prog)  if (! $_prog->{'_subtitles_processed'});

    # Replace subtitle based on description (type = 9)
    $self->process_replacement_ep_from_desc($_prog)  if (! $_prog->{'_subtitles_processed'});


    # Insert/update a programme's category based on 'corrected' title
    $self->process_replacement_genres($_prog);          # (type=6)
    $self->process_replacement_film_genres($_prog);     # (type=12)

	# Replace specified categories with another
	$self->process_translate_genres($_prog);		    # (type=14)

	# Add specified categories to all progs on a channel
	$self->process_add_genres_to_channel($_prog);       # (type=15)

	_d(4,'_Prog, after title fixups:',dd(4,$_prog));

	# update the title and sub-title and description in the programme
	$prog->{'title'}[0][0] 			= $_prog->{'_title'}   if defined $_prog->{'_title'};
	$prog->{'sub-title'}[0][0] 		= $_prog->{'_episode'} if defined $_prog->{'_episode'};
	$prog->{'desc'}[0][0] 			= $_prog->{'_desc'}    if defined $_prog->{'_desc'};
	$prog->{'category'}				= $_prog->{'_genres'}  if defined $_prog->{'_genres'};

	# update the episode-num
	$episode_num->{'season'} 		= $_prog->{'_series_num'};
	$episode_num->{'season_total'} 	= $_prog->{'_series_total'};
	$episode_num->{'episode'} 		= $_prog->{'_episode_num'};
	$episode_num->{'episode_total'} = $_prog->{'_episode_total'};
	$episode_num->{'part'} 			= $_prog->{'_part_num'};
	$episode_num->{'part_total'} 	= $_prog->{'_part_total'};

	# remake the episode-num
	$xmltv_ns = $self->make_ns_epnum($prog, $episode_num);

	_d(5,'Prog, after title fixups:',dd(5,$prog));
}


=item B<process_non_title_info>

Rule #1

Remove specified non-title text from <title>.

  If title starts with text + separator, then it will be removed from the title
  "separator" can be any of :;-

  rule: 1|Python Night
  in : "Python Night: Monty Python - Live at the Hollywood Bowl / "
  out: "Monty Python - Live at the Hollywood Bowl / "

=cut

# Rule 1
#
# Remove non-title text found in programme title.
#
# Listings may contain channel teasers (e.g. "Python Night", "Arnie Season") in the programme title
#
# Data type 1
#     The text in the second field is non-title text that is to be removed from
#     any programme titles found containing this text at the beginning of the
#     <title> element, separated from the actual title with a colon.
#
sub process_non_title_info () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 1;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

    if ( defined $prog->{'_title'} && $prog->{'_title'} =~ m/[:;-]/ ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ( $prog->{'_title'} =~ s/^\Q$key\E\s*[:;-]\s*//i ) {
                l(sprintf("\t Removed '%s' from title. New title '%s' (#%s.%s)",
						  $key, $prog->{'_title'}, $ruletype, $line));
				$self->add_to_audit ($me, $key, $prog);
                last LOOP;
            }
        }

	}
}


=item B<process_demoted_titles>

Rule #11

Promote demoted title from <sub-title> to <title>.

  If title matches, and sub-title starts with text then remove matching text from sub-title and move it into the title.
  Any text after 'separator' in the sub-title is preserved. 'separator' can be any of .,:;-

  rule: 11|Blackadder~Blackadder II
  in : "Blackadder / Blackadder II: Potato"
  out: "Blackadder II / Potato"

=cut

# Rule 11
#
# Promote demoted title from subtitle field to title field, replacing whatever
# text is in the title field at the time. If the demoted title if followed by
# a colon and the subtitle text, that is preserved in the subtitle field.
#
# A title can be demoted to the subtitle field if the programme's "brand"
# is present in the title field, as can happen with data output from Atlas.
#
# Data type 11
#     The text in the second field contains a programme 'brand' and a new title to
#     be extracted from subtitle field and promoted to programme title, replacing
#     the brand title.
#
sub process_demoted_titles () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 11;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} && defined $prog->{'_episode'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {

				if ( $prog->{'_episode'} =~ s/^\Q$value\E(?:\s*[.,:;-]\s*)?//i ) {

					$prog->{'_title'} = $value;

					l(sprintf("\t Promoted title '%s' from subtitle for brand '%s'. New subtitle '%s' (#%s.%s)",
							  $value, $key, $prog->{'_episode'}, $ruletype, $line));
					$self->add_to_audit ($me, $key, $prog);

					$prog->{'_titles_processed'} = 1;
					$prog->{'_subtitles_processed'} = 1;
					last LOOP;
				}
            }
        }

	}
}



=item B<process_replacement_titles_desc>

Rule #10

Replace specified <title> / <sub-title> with title/episode pair supplied using <desc>.

  If title & sub-title match supplied data, then replace <title> and <sub-title> with new data supplied.

  rule: 10|Which Doctor~~Gunsmoke~Which Doctor~Festus and Doc go fishing, but are captured by a family that is feuding with the Haggens.
  in : "Which Doctor / " desc> = "  Festus and Doc go fishing, but are captured by a family that is feuding with the Haggens. ..."
  out: "Gunsmoke / Which Doctor"

=cut

# Rule 10
#
# Allow arbitrary replacement of one title/episode pair with another, based
# on a given description.
#
# Intended to be used where previous title/episode replacement routines
# do not allow a specific enough correction to the listings data (i.e. for
# one-off changes).
#
# *** THIS MUST BE USED WITH CARE! ***
#
# Data type 10
#     The text in the second field contains an old programme title, an old episode
#     value, a new programme title, a new episode value and the episode description.
#     The old and new titles and description MUST be given, the episode fields can
#     be left empty but the field itself must be present.
#
sub process_replacement_titles_desc () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 10;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {

				# $value comprises 'old episode', 'new title', 'new episode' and 'old description' separated by tilde
				my ($old_episode, $new_title, $new_episode, $old_desc) = split /~/, $value;

				# ensure we have an episode (to simplify the following code)
				$prog->{'_episode'} = ''  if !defined $prog->{'_episode'};

				# if the sub-title contains episode numbering then preserve it in the new episode title
				#  extract any episode numbering (x/y) (c.f. extract_numbering() )
				my ($epnum, $epnum_text) = ('', '');
                if ($prog->{'_episode'} =~ m/^([\(\[]*\d+(?:[\s\/]*\d+)?[\.,]?[\)\]]*[\s\.,:;-]*(?:(?:series|season)[\d\s\.,:;-]*)?)(.*)$/) {
					$epnum = $1;
					$prog->{'_episode'} =~ s/\Q$epnum\E//;
					$epnum_text = ' (preserved existing numbering)';
				}

				# check the other parts of the match triplet
				#
				# the original uk_rt grabber used an exact match
				#  - a 'startswith' match would be better
				#  - a 'fuzzy' (e.g. word count) match would be even better!
				#
				if ( $prog->{'_episode'} eq $old_episode && defined $prog->{'_desc'} && $prog->{'_desc'} =~ m/^\Q$old_desc\E/i ) {

					# update the title & episode
					my $old_title = $prog->{'_title'};
					$prog->{'_title'} = $new_title;
					$prog->{'_episode'} = $epnum . ' ' . $new_episode;

                    l(sprintf("\t Replaced old title/ep '%s / %s' with '%s / %s' using desc%s (#%s.%s)",
							  $old_title, $old_episode, $prog->{'_title'}, $prog->{'_episode'}, $epnum_text, $ruletype, $line));
					$self->add_to_audit ($me, $key, $prog);

					$prog->{'_titles_processed'} = 1;
                    last LOOP;
                }
            }
        }

	}
}


=item B<process_replacement_titles_episodes>

Rule #8

Replace specified <title> / <sub-title> with title/episode pair supplied.

  If title & sub-title match supplied data, then replace <title> and <sub-title> with new data supplied.

  rule: 8|Top Gear USA Special~Detroit~Top Gear~USA Special
  in : "Top Gear USA Special / Detroit"
  out: "Top Gear / USA Special"

  rule: 8|Top Gear USA Special~~Top Gear~USA Special
  in : "Top Gear USA Special / "
  out: "Top Gear / USA Special"
    or
  in : "Top Gear USA Special / 1/6."
  out: "Top Gear / 1/6. USA Special"

=cut

# Rule 8
#
# Allow arbitrary replacement of one title/episode pair with another.
# Intended to be used where previous title/episode replacement routines
# do not allow the desired correction (i.e. for one-off changes).
#
# *** THIS MUST BE USED WITH CARE! ***
#
# Data type 8
#     The text in the second field contains an old programme title, an old episode
#     value, a new programme title and a new episode value. The old and new titles
#     MUST be given, the episode fields can be left empty but the field itself
#     must be present.
#
sub process_replacement_titles_episodes () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 8;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {

				# $value comprises 'old episode', 'new title' and 'new episode' separated by tilde
				my ($old_episode, $new_title, $new_episode) = split /~/, $value;

				# ensure we have an episode (to simplify the following code)
				$prog->{'_episode'} = ''  if !defined $prog->{'_episode'};

				# if the sub-title contains episode numbering then preserve it in the new episode title
				#  extract any episode numbering (x/y) (c.f. extract_numbering() )
				my ($epnum, $epnum_text) = ('', '');
                if ($prog->{'_episode'} =~ m/^([\(\[]*\d+(?:[\s\/]*\d+)?[\.,]?[\)\]]*[\s\.,:;-]*(?:(?:series|season)[\d\s\.,:;-]*)?)(.*)$/) {
					$epnum = $1;
					$prog->{'_episode'} =~ s/\Q$epnum\E//;
					$epnum_text = ' (preserved existing numbering)';
				}

				# check the other part of the match pair
				if ( $prog->{'_episode'} eq $old_episode ) {

					# update the title & episode
					my $old_title = $prog->{'_title'};
					$prog->{'_title'} = $new_title;
					$prog->{'_episode'} = $epnum . ' ' . $new_episode;

                    l(sprintf("\t Replaced old title/ep '%s / %s' with '%s / %s'%s (#%s.%s)",
							  $old_title, $old_episode, $prog->{'_title'}, $prog->{'_episode'}, $epnum_text, $ruletype, $line));
					$self->add_to_audit ($me, $key, $prog);

					$prog->{'_titles_processed'} = 1;
                    last LOOP;
                }
            }
        }

	}
}


=item B<process_mixed_title_subtitle>

Rule #2

Extract sub-title from <title>.

  If title starts with text + separator, then the text after it will be moved into the sub-title
  "separator" can be any of :;-

  rule: 2|Blackadder II
  in : "Blackadder II: Potato / "
  out: "Blackadder II / Potato"

=cut

# Rule 2
#
# Some programme titles contain both the title and episode data,
# separated by a colon ($title:$episode), semicolon ($title; $episode)
# or a hyphen ($title - $episode).
#
# Here we reassign the episode to the $episode element, leaving only the
# programme's title in the $title element
#
# Data type 2
#     The text in the second field is the desired title of a programme when the
#     raw listings data contains both the programme's title _and_ episode in
#     the title ($title:$episode). We reassign the episode information to the
#     <episode> element, leaving only the programme title in the <title> element.
#
sub process_mixed_title_subtitle () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 2;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

    if ( defined $prog->{'_title'} && $prog->{'_title'} =~ m/[:;-]/ ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} =~ m/^(\Q$key\E)\s*[:;-]\s*(.*)$/i) {

                # store the captured text
                my $new_title = $1;
                my $new_episode = $2;

				# if no sub-title...
                if (! defined $prog->{'_episode'}) {
                    l(sprintf("\t Moved '%s' to sub-title, new title is '%s' (#%s.%s)",
							  $new_episode, $new_title, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                    $prog->{'_episode'} = $new_episode;
                }

				# sub-title already equals the captured text
                elsif ($prog->{'_episode'} eq $new_episode) {
                    l(sprintf("\t Sub-title '%s' seen in title already exists, new title is '%s' (#%s.%s)",
							  $new_episode, $new_title, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                }

				# already have a sub-title (and which contains episode numbering),
				#  merge the captured text after any episode numbering (x/y) (c.f. extract_numbering() )
                elsif ($prog->{'_episode'} =~ m/^([\(\[]*\d+(?:[\s\/]*\d+)?[\.,]?[\)\]]*[\s\.,:;-]*(?:(?:series|season)[\d\s\.,:;-]*)?)(.*)$/) {
                    l(sprintf("\t Merged sub-title '%s' seen in title after existing episode numbering '%s' (#%s.%s)",
							  $new_episode, $prog->{'_episode'}, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                    $prog->{'_episode'} = $1 . $new_episode . ': ' . $2;
                }

				# already have a sub-title, so prepend the captured text
                else {
                    l(sprintf("\t Joined sub-title '%s' seen in title with existing episode info '%s' (#%s.%s)",
							  $new_episode, $prog->{'_episode'}, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                    $prog->{'_episode'} = $new_episode . ": " . $prog->{'_episode'};
                }

				$self->add_to_audit ($me, $key, $prog);

                $prog->{'_titles_processed'} = 1;
                last LOOP;
            }
        }
    }
}


=item B<process_mixed_subtitle_title>

Rule #3

Extract sub-title from <title>.

  If title ends with separator + text, then the text before it will be moved into the sub-title
  "separator" can be any of :;-

  rule: 3|Storyville
  in : "Kings of Pastry :Storyville / "
  out: "Storyville / Kings of Pastry"

=cut

# Rule 3
#
# Some programme titles contain both the episode and title data,
# separated by a colon ($episode:$title), semicolon ($episode; $title) or a
# hyphen ($episode - $title).
#
# Here we reassign the episode to the $episode element, leaving only the
# programme's title in the $title element
#
# Data type 3
#     The text in the second field is the desired title of a programme when the
#     raw listings data contains both the programme's episode _and_ title in
#     the title ($episode:$title). We reassign the episode information to the
#     <episode> element, leaving only the programme title in the <title> element.
#
sub process_mixed_subtitle_title () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 3;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

    if ( defined $prog->{'_title'} && $prog->{'_title'} =~ m/[:;-]/ ) {

		# can't use the index for this one since we don't know what the incoming title begins with
		#  (i.e. the rule doesn't specify it)

        LOOP:
        foreach my $k (keys %{ $self->{'rules'}->{$ruletype} }) {
        foreach (@{ $self->{'rules'}->{$ruletype}->{$k} }) {

			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} =~ m/^(.*?)\s*[:;-]\s*(\Q$key\E)$/i) {

                # store the captured text
                my $new_title = $2;
                my $new_episode = $1;

				# if no sub-title...
                if (! defined $prog->{'_episode'}) {
                    l(sprintf("\t Moved '%s' to sub-title, new title is '%s' (#%s.%s)",
							  $new_episode, $new_title, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                    $prog->{'_episode'} = $new_episode;
                }

				# sub-title already equals the captured text
                elsif ($prog->{'_episode'} eq $new_episode) {
                    l(sprintf("\t Sub-title '%s' seen in title already exists, new title is '%s' (#%s.%s)",
							  $new_episode, $new_title, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                }

				# already have a sub-title (and which contains episode numbering),
				#  merge the captured text after any episode numbering (x/y) (c.f. extract_numbering() )
                elsif ($prog->{'_episode'} =~ m/^([\(\[]*\d+(?:[\s\/]*\d+)?[\.,]?[\)\]]*[\s\.,:;-]*(?:(?:series|season)[\d\s\.,:;-]*)?)(.*)$/) {
                    l(sprintf("\t Merged sub-title '%s' seen in title after existing episode numbering '%s' (#%s.%s)",
							  $new_episode, $prog->{'_episode'}, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                    $prog->{'_episode'} = $1 . $new_episode . ': ' . $2;
                }

				# already have a sub-title, so prepend the captured text
                else {
                    l(sprintf("\t Joined sub-title '%s' seen in title with existing episode info '%s' (#%s.%s)",
							  $new_episode, $prog->{'_episode'}, $ruletype, $line));
                    $prog->{'_title'} = $new_title;
                    $prog->{'_episode'} = $new_episode . ": " . $prog->{'_episode'};
                }

				$self->add_to_audit ($me, $key, $prog);

                $prog->{'_titles_processed'} = 1;
                last LOOP;
            }
        }
		}
    }
}


=item B<process_reversed_title_subtitle>

Rule #4

Reverse <title> and <sub-title>

  If sub-title matches the rule's text, then swap the title and sub-title

  rule: 4|Storyville
  in : "Kings of Pastry / Storyville"
  out: "Storyville / Kings of Pastry"

=cut

# Rule 4
#
# Listings for some programmes may have reversed title and sub-title information
# ($title = 'real' episode and $episode = 'real' title. Here we everse the given
# title and sub-title when found.
#
# Data type 4
#     The text in the second field is the desired title of a programme which is
#     listed in the raw listings data as the programme's episode (i.e. the title
#     and episode details have been reversed). We therefore reverse the
#     assignment to ensure the <title> and <episode> elements contain the correct
#     information.
#
sub process_reversed_title_subtitle () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 4;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_episode'} ) {

        my $idx = lc(substr $prog->{'_episode'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_episode'} eq $key) {

				$prog->{'_episode'} = $prog->{'_title'};
				$prog->{'_title'} = $key;

				l(sprintf("\t Reversed title-subtitle for '%s / %s'. New title is '%s' (#%s.%s)",
						  $prog->{'_episode'}, $prog->{'_title'}, $prog->{'_title'}, $ruletype, $line));
				$self->add_to_audit ($me, $key, $prog);

				$prog->{'_titles_processed'} = 1;
				last LOOP;
            }
        }

	}
}


=item B<process_replacement_titles>

Rule #5

Replace <title> with supplied text.

  If title matches the rule's text, then use the replacement text supplied

  rule: 5|A Time Team Special~Time Team
  in : "A Time Team Special / Doncaster"
  out: "Time Team / Doncaster"

This is the one which you will probably use most. It can be used to fix most incorrect titles -
e.g. spelling mistakes; punctuation; character case; etc.

=cut

# Rule 5
#
# Process inconsistent titles, replacing any flagged bad titles with good titles.
#
# Data type 5
#     The text in the second field contains two programme titles, separated by a
#     tilde (~). The first title is the inconsistent programme title to search
#     for during processing, and the second title is a consistent title to
#     as a replacement in the listings output. Programme titles can be
#     inconsistent across channels (e.g. Law and Order vs Law & Order) or use
#     inconsistent grammar (xxxx's vs xxxxs'), so we provide a consistent
#     title, obtained from the programme itself, its website or other media,
#     to use instead.
#
sub process_replacement_titles () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 5;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {

				$prog->{'_title'} = $value;

				l(sprintf("\t Replaced title '%s' with '%s' (#%s.%s)",
						  $key, $prog->{'_title'}, $ruletype, $line));
				$self->add_to_audit ($me, $key, $prog);

				$prog->{'_titles_processed'} = 1;
				last LOOP;
            }
        }

	}
}


=item B<process_subtitle_remove_text>

Rule #13

Remove specified text from <sub-title> for a given <title>.

  If sub-title starts with text + separator, or ends with separator + text,
  then it will be removed from the sub-title.
  "separator" can be any of .,:;- and is optional.

  rule: 13|Time Team~A Time Team Special
  in : "Time Team / Doncaster : A Time Team Special "
  out: "Time Team / Doncaster"

=cut

# Rule 13
#
# Process text to remove from subtitles.
#
# Data type 13
#     The text in the second field contains a programme title and arbitrary text to
#     be removed from the start/end of the programme's subtitle, separated by a
#     tilde (~). If the text to be removed precedes or follows a colon/hyphen, the
#     colon/hyphen is removed also.
#
sub process_subtitle_remove_text () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 13;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} && defined $prog->{'_episode'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {

                if ( $prog->{'_episode'} =~ s/^\Q$value\E\s*[.,:;-]?\s*//i
				 ||  $prog->{'_episode'} =~ s/\s*[.,:;-]?\s*\Q$value\E$//i ) {

                    $prog->{'_episode'} = ucfirst($prog->{'_episode'});

                    l(sprintf("\t Removed text '%s' from subtitle. New subtitle is '%s' (#%s.%s)",
							  $value, $prog->{'_episode'}, $ruletype, $line));
					$self->add_to_audit ($me, $key, $prog);

                    $prog->{'_subtitles_processed'} = 1;
                    last LOOP;
                }
            }
        }

	}
}


=item B<process_replacement_episodes>

Rule #7

Replace <sub-title> with supplied text.

  If sub-title matches the rule's text, then use the replacement text supplied

  rule: 7|Time Team~Time Team Special: Doncaster~Doncaster
  in : "Time Team / Time Team Special: Doncaster"
  out: "Time Team / Doncaster"

=cut

# Rule 7
#
# Process inconsistent episodes, replacing any flagged bad episodes with good episodes.
#
# Data type 7
#     The text in the second field contains a programme title, an old episode
#     value and a new episode value, all separated by tildes (~).
#
sub process_replacement_episodes () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 7;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} && defined $prog->{'_episode'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {

				# $value comprises 'old episode' & 'new episode' separated by tilde
				my ($old_episode, $new_episode) = split /~/, $value;

                if ( $prog->{'_episode'} eq $old_episode ) {

					$prog->{'_episode'} = $new_episode;
                    l(sprintf("\t Replaced episode '%s' with '%s' (#%s.%s)",
							  $old_episode, $prog->{'_episode'}, $ruletype, $line));
					$self->add_to_audit ($me, $key, $prog);

                    $prog->{'_subtitles_processed'} = 1;
                    last LOOP;
                }
            }
        }

	}
}


=item B<process_replacement_ep_from_desc>

Rule #9

Replace <sub-title> with supplied text when the <desc> matches that given.

  If sub-title matches the rule's text, then use the replacement text supplied

  rule: 9|Heroes of Comedy~The Goons~The series celebrating great British comics pays tribute to the Goons.
  in : "Heroes of Comedy / "
  out: "Heroes of Comedy / The Goons"
    or
  in : "Heroes of Comedy / Spike Milligan"
  out: "Heroes of Comedy / The Goons"

=cut

# Rule 9
#
# Replace an inconsistent or missing episode subtitle based a given description.
# The description should therefore be unique for each episode of the programme.
#
# Data type 9
#     The text in the second field contains a programme title, a new episode
#     value to update, and a description to match against.
#
sub process_replacement_ep_from_desc () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 9;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} && defined $prog->{'_desc'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {

				# $value comprises 'new episode' & 'description' separated by tilde
				my ($new_episode, $old_desc) = split /~/, $value;

				# the original uk_rt grabber used an exact match
				#  - a 'startswith' match would be better
				#  - a 'fuzzy' (e.g. word count) match would be even better!
				#
                ##if ( $prog->{'_desc'} eq $old_desc ) {
				if ( $prog->{'_desc'} =~ m/^\Q$old_desc\E/ ) {

					my $old = $prog->{'_episode'} || '';
					$prog->{'_episode'} = $new_episode;
                    l(sprintf("\t Replaced episode '%s' with '%s' (#%s.%s)",
							  $old, $prog->{'_episode'}, $ruletype, $line));
					$self->add_to_audit ($me, $key, $prog);

                    $prog->{'_subtitles_processed'} = 1;
                    last LOOP;
                }
            }
        }

	}
}


=item B<process_replacement_genres>

Rule #6

Replace <category> with supplied text.

  If title matches the rule's text, then use the replacement category(-ies) supplied
  (note ALL existing categories are replaced)

  rule: 6|Antiques Roadshow~Entertainment~Arts~Shopping
  in : "Antiques Roadshow / " category "Reality"
  out: "Antiques Roadshow / " category "Entertainment" + "Arts" + "Shopping"

You can specify a wildcard with the title by using %% which represents any number
of characters.
So for example "News%%" will match "News", "News and Weather", "Newsnight", etc.
But be careful; "%%News%%" will also match "John Craven's Newsround", "Eurosport News",
"Election Newsroom Live", "Have I Got News For You", "Scuzz Meets Jason Newsted", etc.

=cut

# Rule 6
#
# Process programmes that may not be categorised, or are categorised with
# various categories in the source data.
# See rule type 12 for films.
#
# Data type 6
#     The text in the second field contains a programme title and a programme
#     category (genre), separated by a tilde (~). Categories can be assigned
#     to uncategorised programmes.
#
sub process_replacement_genres () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 6;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        #  append any rules which start with a wildcard
        #  (todo: this doesn't work for "x%%...")
        foreach ( @{ $self->{'rules'}->{$ruletype}->{$idx} } , @{ $self->{'rules'}->{$ruletype}->{'%%'} } ) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

			my $qr_key = $self->replace_wild($key);
            _d(5,"\t $line, $qr_key, $value");

      if ($prog->{'_title'} =~ $qr_key ) {
				#_d(4,dd(4,$prog->{'_genres'}));

				my $old = '';
				if (defined $prog->{'_genres'}) {
					foreach my $genre (@{ $prog->{'_genres'} }) {
						$old .= $genre->[0] . ',';
					}
					chop $old;
				}
				my $new = $value; $new =~ s/~/, /g;

				$prog->{'_genres'} = undef;

				# the original uk_rt grabber only allowed one genre, but let's enhance that
				# and allow multiple genres separated by tilde
				my @values = split /~/, $value;

				my $i=0;
				foreach (@values) {
					$prog->{'_genres'}[$i++] = [ $_, $self->{'language_code'} ];
				}

				l(sprintf("\t Replaced genre(s) '%s' with '%s' (#%s.%s)",
						  $old, $new, $ruletype, $line));
				# if using a wildcard, we could mod many progs with this one rule so let's report all of them
				if ($key =~ m/%%/) {
					$self->add_to_audit ($me, $key.'~'.$prog->{'_title'}, $prog);
				} else {
				$self->add_to_audit ($me, $key, $prog);
				}

				$prog->{'_subtitles_processed'} = 1;
				last LOOP;

            }
        }

	}
}


=item B<process_replacement_film_genres>

Rule #12

Replace "Film"/"Films" <category> with supplied text.

  If title matches the rule's text and the prog has category "Film" or "Films", then use the replacement category(-ies) supplied
  (note ALL categories are replaced, not just "Film")

  rule: 12|The Hobbit Special~Entertainment~Interview
  in : "The Hobbit Special / " category "Film" + "Drama"
  out: "The Hobbit Special / " category "Entertainment" + "Interview"

=cut

# Rule 12
#
# Process programmes incorrectly categorised as films with replacement categories (genres)
# See rule type 6 for non-films.
#
# Data type 12
#     The text in the second field contains a film title and a programme
#     category (genre), separated by a tilde (~). Some film-related programmes are
#     incorrectly flagged as films and should to be re-assigned to a more suitable
#     genre.
#
sub process_replacement_film_genres () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 12;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} && defined $prog->{'_genres'} ) {

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {
				#_d(4,dd(4,$prog->{'_genres'}));

				my $isfilm = 0;

				my $old = '';
                foreach my $genre (@{ $prog->{'_genres'} }) {
                    $old .= $genre->[0] . ',';

                    # is it a film?
                    if ( $genre->[0] =~ m/films?/i ) {
                        $isfilm = 1;
                    }

                }
                chop $old;

				if (!$isfilm) {
					last LOOP;
				}

				my $new = $value; $new =~ s/~/, /g;

				$prog->{'_genres'} = undef;

				# the original uk_rt grabber only allowed one genre, but let's enhance that
				# and allow multiple genres separated by tilde
				my @values = split /~/, $value;

				my $i=0;
				foreach (@values) {
					$prog->{'_genres'}[$i++] = [ $_, $self->{'language_code'} ];
				}

				l(sprintf("\t Replaced genre(s) '%s' with '%s' (#%s.%s)",
						  $old, $new, $ruletype, $line));
				$self->add_to_audit ($me, $key, $prog);

				$prog->{'_subtitles_processed'} = 1;
				last LOOP;

            }
        }

	}
}


=item B<process_translate_genres>

Rule #14

Replace <category> with supplied value(s).

  If category matches one found in the prog, then replace it with the category(-ies) supplied
  (note any other categories are left alone)

  rule: 14|Soccer~Football
  in : "Leeds v Arsenal" category "Soccer"
  out: "Leeds v Arsenal" category "Football"

  rule: 14|Adventure/War~Action Adventure~War
  in : "Leeds v Arsenal" category "Adventure/War"
  out: "Leeds v Arsenal" category "Action Adventure" + "War"

=cut

# Rule 14
#
# Replace any occurrence of one genre with another. The replacement may be a single or multiple genres.
#
# Data type 14
#     The content contains a category (genre) value followed by replacement
#     category(-ies) separated by a tilde (~).
#     Use case: useful if your PVR doesn't understand some of the category
#     values in the incoming data; you can translate them to another value.
#
sub process_translate_genres () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 14;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} && defined $prog->{'_genres'} ) {
		#_d(4,dd(4,$prog->{'_genres'}));

		# To ensure the replacements are NOT iterative, we'll store the new values separate for now
		$prog->{'_newgenres'} = undef;
		my $storenewgenres = 0;

		foreach my $genre (@{ $prog->{'_genres'} }) {
			my $haschanged = 0;
			my $old = $genre->[0];

			my $idx = lc(substr $genre->[0], 0, 2);

			LOOP:
			foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
				my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
				_d(4,"\t $line, $key, $value");

				if ($genre->[0] eq $key) {

					my $new = $value; $new =~ s/~/, /g;

					my @values = split /~/, $value;
					foreach (@values) {
						push @{$prog->{'_newgenres'}}, [ $_, $self->{'language_code'} ];
					}

					l(sprintf("\t Replaced genre(s) '%s' with '%s' (#%s.%s)",
							  $old, $new, $ruletype, $line));
					$self->add_to_audit ($me, $key, $prog);

					$haschanged = 1; $storenewgenres = 1;
					last LOOP;
				}
			}

			if (!$haschanged) {
				push @{$prog->{'_newgenres'}}, $genre;
			}

		}

		if ($storenewgenres) {
			# store the new categories
			$prog->{'_genres'} = $prog->{'_newgenres'};
		}

	}
}


=item B<process_add_genres_to_channel>

Rule #15

Add a category to all programmes on a specified channel.

  If channel matches this prog, the add the supplied category(-ies) to the programme
  (note any other categories are left alone)

  rule: 15|travelchannel.co.uk~Travel
  in : "World's Greatest Motorcycle Rides" category "Motoring"
  out: "World's Greatest Motorcycle Rides" category "Motoring" + "Travel"

  rule: 15|cnbc.com~News~Business
  in : "Investing in India" category ""
  out: "Investing in India" category "News" + "Business"

You should be very careful with this one as it will add the category you specify
to EVERY programme broadcast on that channel. This may not be what you always
want (e.g. Teleshopping isn't really "music" even if it is on MTV!)

=cut

# Rule 15
#
# Add a genre to all programmes on a specified channel.. The addition may be a single or multiple genres.
#
# Data type 15
#     The content contains a channel value followed by
#     category(-ies) separated by a tilde (~).
#     Use case: can add a category if data from your supplier is always missing; e.g. add "News" to a news channel, or "Music" to a music vid channel.
#
sub process_add_genres_to_channel () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
	_d(3,self());

	my $ruletype = 15;
	if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

	if ( defined $prog->{'_title'} && defined $prog->{'_channel'} ) {
		#_d(4,dd(4,$prog->{'_channel'}));

        my $idx = lc(substr $prog->{'_channel'}, 0, 2);

		LOOP:
		foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
			my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
			_d(4,"\t $line, $key, $value");

			if ($prog->{'_channel'} eq $key) {
				#_d(4,dd(4,$prog->{'_genres'}));

				my %h_old = ();
				my $old = '';
				if (defined $prog->{'_genres'}) {
					foreach my $genre (@{ $prog->{'_genres'} }) {
						$old .= $genre->[0] . ',';
						$h_old{$genre->[0]} = 1;
					}
					chop $old;
				}
				my $new = $value; $new =~ s/~/, /g;

				# allow multiple genres separated by tilde
				my @values = split /~/, $value;

				my $i = defined $prog->{'_genres'} ? scalar( @{ $prog->{'_genres'} } ) : 0;
				my $msgdone = 0;
				foreach (@values) {
				    if ( ! exists( $h_old{$_} ) ) {
						$prog->{'_genres'}[$i++] = [ $_, $self->{'language_code'} ];
						l(sprintf("\t Added genre(s) '%s' to '%s' (#%s.%s)",
								$new, $old, $ruletype, $line))  if !$msgdone; $msgdone = 1;
						#(we could mod many progs with this one rule so let's report all of them)
						#$self->add_to_audit ($me, $key, $prog);
						$self->add_to_audit ($me, $key.'~'.$prog->{'_title'}, $prog);
					}
				}

				last LOOP;
            }
		}

	}
}


=item B<process_remove_numbering_from_programmes>

Rule #16

Remove episode numbering from a given programme title (on an optionally-specified channel).

  If title matches the one in the prog, all programme numbering for the programme
  is removed, on any channel. An optional channel identifier can be provided to
  restrict the removal of programme numbering to the given channel.

  rule: 16|Bedtime Story
  in : "CBeebies Bedtime Story" episode-num ".700."
  out: "CBeebies Bedtime Story" episode-num ""

  rule: 16|CBeebies Bedtime Story~cbeebies.bbc.co.uk
  in : "CBeebies Bedtime Story" episode-num ".700."
  out: "CBeebies Bedtime Story" episode-num ""

Remember to specify the optional channel limiter if you have good programme numbering
for a given programme title on some channels but not others.

=cut

# Rule 16
#
# Remove episode numbering from a given programme title (on an optionally-specified channel).
#
# Data type 16
#     The content contains a title value, followed by an optional channel (separated by a tilde (~)).
#     Use case: can remove programme numbering from a specific title if it is regularly wrong or inconsistent over time.
#
sub process_remove_numbering_from_programmes () {
    my ($self, $prog) = @_;
    my $me = self();
    if ( ! $self->{'options_all'} && ! $self->{'options'}{$me} ) { return 0; }
    _d(3,self());

    my $ruletype = 16;
    if (!defined $self->{'rules'}->{$ruletype}) { return 0; }

    if ( defined $prog->{'_title'} && $prog->{'_has_numbering'} ) {
        #_d(4,dd(4,$prog->{'_title'}));

        my $idx = lc(substr $prog->{'_title'}, 0, 2);

        LOOP:
        foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
            my ( $line, $key, $value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );
            _d(4,"\t $line, $key, $value");

            if ($prog->{'_title'} eq $key) {
                #_d(4,dd(4,$prog->{'_channel'}));

                my @num_keys = ( '_series_num',  '_series_total',
                                 '_episode_num', '_episode_total',
                                 '_part_num',    '_part_total',
                               );
                # if an optional channel is not specified in the rule definition,
                # $value will be the empty string
                if ($value ne '') {
                    if ($prog->{'_channel'} eq $value) {
                        $prog->{$_} = '' foreach @num_keys;
                        delete $prog->{'_has_numbering'};
                        l(sprintf("\t Removed all programme numbering for title '%s' on channel '%s' (#%s.%s)",
                                $key, $value, $ruletype, $line));
                    }
                }
                else {
                    $prog->{$_} = '' foreach @num_keys;
                    delete $prog->{'_has_numbering'};
                    l(sprintf("\t Removed all programme numbering for title '%s' (#%s.%s)",
                            $key, $ruletype, $line));
                }

                last LOOP;
            }
        }
    }
}



# Store a variety of title debugging information for later analysis
# and debug output
#
# (Note no changes are made to the incoming records)
#
sub store_title_debug_info () {
	my ($self, $prog) = @_;
	my $me = self();
	_d(3,self());

    if ($self->{'stats'}) {

		my $tmp_prog = {};

		$tmp_prog->{'_title'}   = defined $prog->{'title'} ? $prog->{'title'}[0][0] : '';
		$tmp_prog->{'_episode'} = defined $prog->{'sub-title'} ? $prog->{'sub-title'}[0][0] : '';
		$tmp_prog->{'_genres'}  = defined $prog->{'category'} ? $prog->{'category'} : '';
		$tmp_prog->{'_channel'} = defined $prog->{'channel'} ? $prog->{'channel'} : '';

		_d(4,dd(4,$tmp_prog));

		$self->check_numbering_in_text ($tmp_prog);
		$self->check_title_in_subtitle ($tmp_prog);
		$self->check_titles_with_colons ($tmp_prog);
		$self->check_titles_with_hyphens ($tmp_prog);
		$self->check_subtitles_with_hyphens ($tmp_prog);
		$self->check_uc_titles_post ($tmp_prog);
		$self->check_new_titles ($tmp_prog);

		$self->check_titles_with_years ($tmp_prog);
		$self->check_titles_with_bbfc_ratings ($tmp_prog);
		$self->check_titles_with_mpaa_ratings ($tmp_prog);

		$self->check_flagged_title_eps ($tmp_prog);
		$self->check_dotdotdot_titles ($tmp_prog);

		$self->make_frequency_distribution ($tmp_prog);
		$self->count_progs_by_channel ($tmp_prog);

	}

}


# Monitor for case/punctuation-insensitive title variations
# Build a hash of variations for a title. Will be processed after
# we have read all the progs in the input file, to create a list
# of progs which may need a new title fixup.
#
sub make_frequency_distribution () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	# remove some punctuation, etc from title
	my $title_nopunc = lc $prog->{'_title'};
	$title_nopunc =~ s/^the\s+//;
	$title_nopunc =~ s/(\s+and\s+|\s+&\s+)/ /g;
	$title_nopunc =~ s/\s+No 1'?s$//g;
	$title_nopunc =~ s/\s+Number Ones$//g;
	$title_nopunc =~ s/' //g;
	$title_nopunc =~ s/'s/s/g;
	$title_nopunc =~ s/\W//g;

	my $value = 'case_insens_titles';
	my $key = $title_nopunc;

	# count number of each variant by genre and channel name
	if ( (!defined $prog->{'_genres'}) || (ref $prog->{'_genres'} ne 'ARRAY') ) {
		$prog->{'_genres'} = [ [ '(no genre)' ] ];
	}

	foreach (@{ $prog->{'_genres'} }) {
		my $genre = $_->[0];
		$self->{'audit'}{$value}{$key}{ $prog->{'_title'} }{$genre}{ $prog->{'_channel'} }++;
	}

	$self->{'audit'}{$value}{$key}{ $prog->{'_title'} }{'count'}++;
}


# Count the programmes seen for each channel
sub count_progs_by_channel () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $value = 'input_channels';

	my $key = $prog->{'_channel'};

	# frequency count of progs for each channel
	$self->{'audit'}{$value}{$key}{'count'}++;
}


# Process the titles previously stored by make_frequency_distribution()
# Look for possible title variants: i.e. where 2 incoming progs have
# different title but may be the same
# (e.g. one of them is misspelt / capitalisation / etc.)
#
sub check_title_variants {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $value = 'case_insens_titles';

    if (!defined $self->{'audit'}{$value}) { return 0; }

	# temp hash to avoid too many mods to following code
	my $case_insens_titles = $self->{'audit'}{$value};

	# iterate over each 'unique' title (i.e. the title without punctuation etc)
	foreach my $title_nopunc (sort keys %{$case_insens_titles}) {

		if (scalar keys %{$case_insens_titles->{$title_nopunc}} > 1) {
			my %variants;

			# iterate over each actual title seen in listings
			foreach my $title (sort keys %{$case_insens_titles->{$title_nopunc}}) {

				# need to remove 'count' key before genre processing later
				my $title_cnt = delete $case_insens_titles->{$title_nopunc}{$title}{'count'};
				# hash lists of title variants keyed on frequency
				push @{$variants{$title_cnt}}, $title;

				my $line = "$title (";
				# iterate over each title's genres
				foreach my $genre (sort keys %{$case_insens_titles->{$title_nopunc}{$title}}) {
					# iterate over each title's channel availability by genre
					foreach my $chan (sort keys %{$case_insens_titles->{$title_nopunc}{$title}{$genre}}) {
						$line .= $genre . "/" . $chan . " [" . $case_insens_titles->{$title_nopunc}{$title}{$genre}{$chan} . " times], ";
					}
				}
				$line =~ s/,\s*$//; # remove last comma
				$line .= ")";
				$self->add_to_audit ('possible_title_variants', $title, { '_title' => $line });

			}

			# now find list of titles with highest freq and check if it contains
			# a single entry to use in suggested fixups
			my @title_freqs = sort {$b <=> $a} keys %variants;
            my $highest_freq = $title_freqs[0];
			if (scalar @{$variants{$highest_freq}} == 1) {

				# extract title with highest frequency and remove key from $case_insens_titles{$unique_title}
				my $best_title = shift @{$variants{$highest_freq}};
				delete $case_insens_titles->{$title_nopunc}{$best_title};

				# now iterate over remaining variations of title and generate fixups
				foreach (keys %{$case_insens_titles->{$title_nopunc}}) {
					my $fixup = "5|" . $_ . "~" . $best_title;
					push @{ $self->{'audit'}{'possible_title_variants_fixups'} }, $fixup;
				}

			}
		}
	}

}


# Check to see if prog contains possible series,episode or part numbering
#   (c.f. rule A5 check_potential_numbering_in_text() )
#
sub check_numbering_in_text () {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	# audit the quality of extraction rule A5

	my $key = $prog->{'_title'};

    # check if $title still contains "season" text
    if ($prog->{'_title'} =~ m/(season|series|episode)/i ) {
        l("\t Check title text for possible series/episode text:  " . $prog->{'_title'});
		$self->add_to_audit ('title_text_to_remove', $key, $prog);
    }

    # check for potential series numbering left unprocessed
	if ($prog->{'_episode'} =~ m/(season|series)/i ) {
        l("\t Possible series numbering still seen:  " . $prog->{'_episode'});
		$self->add_to_audit ('possible_series_nums', $key, $prog);
    }

	# check for potential part numbering left unprocessed (i.e. the regex missed it)
	#  TODO: don't run this test if we created episode with make_episode_from_part_numbers()
	if ($prog->{'_episode'} =~ m/\b(Part|Pt(\.)?)(\d+|\s+\w+)/i ) {
		l("\t Possible part numbering still seen: " . $prog->{'_episode'});
		$self->add_to_audit ('possible_part_nums', $key, $prog);
	}
    # check for potential episode numbering left unprocessed
    elsif ($prog->{'_episode'} =~ m/(^\d{1,2}\D|\D\d{1,2}\.?$)/
		|| $prog->{'_episode'} =~ m/episode/i ) {
        l("\t Possible episode numbering still seen: " . $prog->{'_episode'});
		$self->add_to_audit ('possible_episode_nums', $key, $prog);
    }
}


# Check for title text still present in episode details
#
sub check_title_in_subtitle {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	if (defined $prog->{'_episode'}) {

		if ($prog->{'_episode'} =~ m/^\Q$prog->{'_title'}\E/) {
			l("\t Possible title in subtitle:  " . $prog->{'_episode'});
			$self->add_to_audit ('title_in_subtitle_notfixed', $key, $prog);
        }

	}

}


# Check to see if title contains a colon
# - this may indicate a 'title:sub-title' which should be extracted
#
sub check_titles_with_colons {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# match a colon or semi-colon
	if ($prog->{'_title'} =~ m/^(.*?)\s*[:;]\s*(.*)$/ ) {
		my ($pre, $post) = ($1, $2);
        l("\t Title contains colon:  " . $prog->{'_title'});
		$self->add_to_audit ('colon_in_title', $key, $prog);

		# the uk_rt code only generated a fixup hint when there was >1 prog with the same
		#  value before or after the colon. Doeesn't say why: presumably to reduce false positives.
		#  I'm not sure this works as expected though, e.g. it doesn't account for repeats of the same prog
		#
		if ( defined $self->{'audit'}{'colon_in_title_pre'}{$pre} ) {
			$self->{'audit'}{'colon_in_title_pre'}{$pre}++;
			# only print each fixup once!
			if ($self->{'audit'}{'colon_in_title_pre'}{$pre} == 2) {
				my $fixup = "2|" . $pre;
				push @{ $self->{'audit'}{'colon_in_title_fixups'} }, $fixup;
			}
		}
		else { $self->{'audit'}{'colon_in_title_pre'}{$pre} = 1; }


		if ( defined $self->{'audit'}{'colon_in_title_post'}{$post} ) {
			$self->{'audit'}{'colon_in_title_post'}{$post}++;
			# only print each fixup once!
			if ($self->{'audit'}{'colon_in_title_post'}{$post} == 2) {
				my $fixup = "3|" . $post;
				push @{ $self->{'audit'}{'colon_in_title_fixups'} }, $fixup;
			}
		}
		else { $self->{'audit'}{'colon_in_title_post'}{$post} = 1; }

    }

}


# Check to see if title contains hyphen
# - this may indicate a sub-title or ep numbering
#
sub check_titles_with_hyphens {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# match a hyphen not preceded by a colon
	if ($prog->{'_title'} =~ m/^(.*?)(?:\s?[^:]-\s|\s[^:]-\s?)(.*)$/ ) {
		my $fixup = "5|" . $prog->{'_title'} . '~' . "$1: $2";
        l("\t Possible hyphenated title:  " . $prog->{'_title'});
		$self->add_to_audit ('possible_hyphenated_title', $key, $prog);
		push @{ $self->{'audit'}{'possible_hyphenated_title_fixups'} }, $fixup;
    }

}


# Check for episode details that contain a colon or hyphen -
# - this may indicate a title in the episode field which needs
# to be moved into the title field
#
sub check_subtitles_with_hyphens {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	if (defined $prog->{'_episode'}) {

		# match a colon, or a hyphen if not a hyphenated word
		if ($prog->{'_episode'} =~ m/(:|\s-\s|-\s|\s-)/ ) {		# (note '\s-\s' is superfluous!)
			l("\t Possible hyphenated subtitle:  " . $prog->{'_episode'});
			$self->add_to_audit ('colon_in_subtitle', $key, $prog);
		}

	}

}


# Check if title is all upper case
#
sub check_uc_titles_post {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# title is all uppercase?
	if ($prog->{'_title'} eq uc($prog->{'_title'}) && $prog->{'_title'} !~ m/^\d+$/) {
		$self->add_to_audit ('uppercase_title', $key, $prog);
    }

}


# Look for various text in the prog title
#
sub check_new_titles {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# match a title containing various text

	if ( $prog->{'_title'} =~ m/Special\b/i ) {
        l("\t Title contains 'Special':  " . $prog->{'_title'});
		$self->add_to_audit ('titles_word_special', $key, $prog);
    }

	if ( $prog->{'_title'} =~ m/^(All New|New)\b/i
	 ||  $prog->{'_title'} =~ m/(Premiere|Final|Finale|Anniversary)\b/i ) {
		my $match = $1;
        l("\t Title contains 'New/Premiere/Finale/etc.':  " . $prog->{'_title'});
		$self->add_to_audit ('titles_word_various1', $match.':::'.$key, $prog);
    }

	if ( $prog->{'_title'} =~ m/\b(Day|Night|Week)\b/i ) {
		my $match = $1;
        l("\t Title contains 'Day/Night/Week':  " . $prog->{'_title'});
		$self->add_to_audit ('titles_word_various2', $match.':::'.$key, $prog);
    }

	if ( $prog->{'_title'} =~ m/\b(Christmas|New\s+Year['s]?)\b/i ) {
		my $match = $1;
        l("\t Title contains 'Christmas/New Year':  " . $prog->{'_title'});
		$self->add_to_audit ('titles_word_various3', $match.':::'.$key, $prog);
    }

	if ( $prog->{'_title'} =~ m/\b(Best of|Highlights|Results|Top)\b/i ) {
		my $match = $1;
        l("\t Title contains 'Results/Best of/Highlights/Top':  " . $prog->{'_title'});
		$self->add_to_audit ('titles_word_various4', $match.':::'.$key, $prog);
    }

}


# Look for titles which include a possible year (e.g. for films)
#
sub check_titles_with_years {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# match a title containing what could be a year
	#
	if ( $prog->{'_title'} =~ m/\b(19|20)\d{2}\b/ ) {
        l("\t Title contains year:  " . $prog->{'_title'});
		$self->add_to_audit ('titles_with_years', $key, $prog);
    }

}


# Look for titles which may contain BBFC film rating
#
sub check_titles_with_bbfc_ratings {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# match a title containing a BBFC rating
	#
	if ( $prog->{'_title'} =~ m/\((E|U|PG|12|12A|15|18|R18)\)/ ) {
        l("\t Title contains possible BBFC rating:  " . $prog->{'_title'});
		$self->add_to_audit ('titles_with_bbfc', $key, $prog);
    }

}


# Look for titles which may contain MPAA film rating
#
sub check_titles_with_mpaa_ratings {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# match a title containing a MPAA rating
	#
	if ( $prog->{'_title'} =~ m/\((G|PG|PG-?13|R|NC-?17)\)/ ) {
        l("\t Title contains possible MPAA rating:  " . $prog->{'_title'});
		$self->add_to_audit ('titles_with_mpaa', $key, $prog);
    }

}


# I'm not sure what this is trying to check - I think it's trying to
# suggest if we already have a fixup (code 8) for this title then
# maybe we need another one for this 'new' prog? Bit nebulous I think!
#
sub check_flagged_title_eps {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	my $ruletype = 8;

	my $idx = lc(substr $prog->{'_title'}, 0, 2);

	LOOP:
	foreach (@{ $self->{'rules'}->{$ruletype}->{$idx} }) {
		my ( $_line, $_key, $_value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );

		if (lc $_key eq lc $prog->{'_title'}) {
			l("\t Title matches a rule $ruletype fixup:  " . $prog->{'_title'});
			$self->add_to_audit ('flagged_title_eps', $key, $prog);
			last LOOP;
		}
	}
}


# Here's another one which is somewhat obscure.
# If title contains ellipsis and we already have a fixup (code 8 or 10)
# containing ellipsis for this title in the *corrected* title then
# maybe we need another one for the 'new' prog?
# e.g.
#   8|All I Want For Christmas Is Katy Perry!~~All I Want For Christmas Is...~Katy Perry!
#   8|All I Want For Christmas Is Mariah Carey!~~All I Want For Christmas Is...~Mariah Carey!
#  then if incoming = '.*All I Want For Christmas Is.*' then print it
#
sub check_dotdotdot_titles {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $key = $prog->{'_title'};

	# create a hash of rule types 8 and 10 which contain ellipsis in the 'new title'
	if (!defined $self->{'rules'}->{'ellipsis'} ) {
		foreach my $ruletype (qw/8 10/) {
			foreach my $k (keys %{ $self->{'rules'}->{$ruletype} }) {
				foreach (@{ $self->{'rules'}->{$ruletype}->{$k} }) {
					my ( $_line, $_key, $_value ) = ( $_->{'line'}, $_->{'key'}, $_->{'value'} );

					# $value comprises
					#  type 8 : 'old episode', 'new title', 'new episode'
					#  type 10 : 'old episode', 'new title', 'new episode' and 'old description'
					# separated by tilde
					my ($old_episode, $new_title, $new_episode, $old_desc) = split /~/, $_value;

					# store titles that are being corrected with an existing "some title..." fixup
					# store the title without a leading "The" or "A" or the trailing "..."
					if ($new_title =~ m/^(?:The\s+|A\s+)?(.*)\.\.\.$/) {
						$self->{'rules'}{'ellipsis'}{$1} = $new_title;
					}
				}
			}
		}
		#_d(4,'Ellipsis hash',dd(4,$self->{'rules'}->{'ellipsis'}));
	}


	# if title does not contain ellipsis see if we already have a fixup for this title
	# which *does* contain an ellipsis
	if ( $prog->{'_title'} !~ m/\.{3}$/ ) {
		LOOP:
        foreach (keys %{ $self->{'rules'}{ellipsis} }) {
			my ($_k, $_v) = ($_, $self->{'rules'}->{ellipsis}->{$_} );
			if ( $prog->{'_title'} =~ m/\b\Q$_k\E\b/i) {
				l("\t Title may need to be fixed based on fixup '$_v' :  " . $prog->{'_title'});
				$prog->{'_msg'} = "based on fixup '$_v'";
				$self->add_to_audit ('dotdotdot_titles', $key, $prog);
				last LOOP;
			}
		}
	}

}


# Store details of uncategorised programmes, programmes having different
# genres throughout the listings, and films having a duration of less than
# 75 minutes for further analysis
sub store_genre_debug_info () {
	my ($self, $prog) = @_;
	my $me = self();
	_d(3,self());

    if ($self->{'stats'}) {

        my $tmp_title = $prog->{'title'}[0][0];
        my $tmp_episode = (defined $prog->{'sub-title'} ? $prog->{'sub-title'}[0][0] : '');
        my $key = $tmp_title . "|" . $tmp_episode;


		# store genres for this prog as well as all genres seen across all programmes
		if (defined $prog->{'category'}) {
			my $all_cats;
			foreach (@{ $prog->{'category'} }) {
				my $genre = $_->[0];
				$all_cats .= $genre .'~';
				$self->{'audit'}{'all_genres'}{$genre}++;
				$self->{'audit'}{'cats_per_prog'}{$tmp_title}{$genre}++;
			}
			if ($all_cats) {
				chop $all_cats;
				$self->{'audit'}{'allcats_per_prog'}{$tmp_title}{$all_cats}++;
			}
		}


		# explode the genres
		my $genres = '';
		if (defined $prog->{'category'}) {
			foreach (@{ $prog->{'category'} }) {
				$genres .= $_->[0] . ',';
			}
			chop $genres;
		}

		# Check for "Film" < 75 minutes long
		if ( $genres =~ m/Films?/i ) {
			if (defined $prog->{'stop'}) {
				my $start = time_xmltv_to_epoch($prog->{'start'});
				my $stop  = time_xmltv_to_epoch($prog->{'stop'});
				if (($stop - $start) < 60 * 75) {
					#'_duration_mins'} < 75))
					$me = 'short_films';
					$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode });
				}
			}
        }

		# Check for progs without any genre
		elsif ( $genres eq '' ) {
			if ($prog->{'title'} !~ m/^(To Be Announced|TBA|Close)\.?$/i ) {
				$me = 'uncategorised_progs';
				$self->add_to_audit ($me, $key, { '_title'=>$tmp_title, '_episode'=>$tmp_episode });
			}
        }

    }

}


# Process the genres previously stored by store_genre_debug_info()
# to print all categories seen across all programmes
#
sub check_categories {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $value = 'all_genres';

    if (!defined $self->{'audit'}{$value}) { return 0; }

	# sort the genre counts descending and format as a list ready for printing
	my @keys = sort { $self->{'audit'}{$value}->{$b} <=> $self->{'audit'}{$value}->{$a} } keys( %{$self->{'audit'}{$value}} );
	foreach my $key (@keys) {
		push @{$self->{'audit'}{'all_genres_sorted'}}, $key.' 'x(25-length $key).$self->{'audit'}{$value}->{$key}." times";
	}

}


# Process the genres previously stored by store_genre_debug_info()
# for each programme, to list progs with differing categories -
# i.e. the same prog occuring more than once but with different cats.
# Note this definition differs from that in uk_rt which only allowed
# one cat per prog, whereas here we allow multiple cats per prog
# (but it should be backwards compatible).
#
sub check_cats_per_prog {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $value = 'allcats_per_prog';

    if (!defined $self->{'audit'}{$value}) { return 0; }

	# temp hash to avoid too many mods to following code
	my $cats_per_prog = $self->{'audit'}{$value};

	# iterate over each title
	foreach my $title (sort keys %{$cats_per_prog}) {

		if (scalar keys %{$cats_per_prog->{$title}} > 1) {
            my ($best_cat, $best_cat_cnt);

            my $line = "$title is categorised as: ";

			foreach my $cat ( sort { $cats_per_prog->{$title}{$b} <=> $cats_per_prog->{$title}{$a} || $a cmp $b }
							( keys %{$cats_per_prog->{$title}} ) )
			{
				$line .= "\n\t    $cat [" . $cats_per_prog->{$title}{$cat} . " times]";
				if (!defined $best_cat) {
					$best_cat = $cat;
					$best_cat_cnt = $cats_per_prog->{$title}{$cat};
				}
				else {
					my $fixup = "6|" . $title . "~" . $best_cat;
					push @{ $self->{'audit'}{'categories_per_prog_fixups'} }, $fixup;
				}
			}

			$self->add_to_audit ('categories_per_prog', $title, { '_title' => $line });
		}

	}

}


# Process the hash of channels information to print
# 1) <channel> which have no programmes in the file
# 2) Channel names referenced in one or more progs, but missing <channel> element
#
sub print_empty_listings {
	my ($self, $prog) = @_;
	my $me = self();
	if ( ! $self->{'stats'} ) { return 0; }
	_d(4,self());

	my $value = 'input_channels';

    if (!defined $self->{'audit'}{$value}) { return 0; }

    foreach my $key (keys %{ $self->{'audit'}->{$value} }) {

		if ( !defined $self->{'audit'}->{$value}->{$key}->{'count'} ) {
			$self->add_to_audit ('empty_listings', $key, { '_title' => $key });
		}

		if ( !defined $self->{'audit'}->{$value}->{$key}->{'display_name'} ) {
			$self->add_to_audit ('listings_no_channel', $key, { '_title' => $key });
		}

	}
}


# Some of the stats analysis works on the whole file of programmes
# rather than just an individual prog.
# For these we store the data as each prog is presented, and then
# analyse them at time of printing the stats (i.e. after all the records
# have been received).
#
# (Note no changes are made to the incoming records)
#
sub process_title_debug_info () {
	my ($self, $prog) = @_;
	my $me = self();
	_d(3,self());

    if ($self->{'stats'}) {

		$self->check_title_variants ();
		$self->check_categories ();
		$self->check_cats_per_prog ();
		$self->print_empty_listings ();

	}
}


# Add to our stats analysis hash data
sub add_to_audit () {
	my ($self, $value, $key, $prog) = @_;
	# little bit of validation
	_d(0,'Missing $value in add_to_audit')   if !defined $value || $value eq '';
	_d(0,'Missing $key in add_to_audit'. " ($value)")   if !defined $key || $key eq '';
	_d(0,'Missing $prog->{_title} in add_to_audit')   if !defined $prog->{'_title'} || $prog->{'_title'} eq '';

	$self->{'audit'}{$value}{$key} = { 'title'    => $prog->{'_title'},
									   'episode'  => $prog->{'_episode'},
									   'msg'      => $prog->{'_msg'},
								     };
}


# Print the lists of actions taken and suggestions for further fixups
#
sub printInfo () {
	my ($self, $prog) = @_;
	my $me = self();
	_d(3,self());

	# Some of the stats analysis works on the whole file of programmes
	# rather than just an individual prog - we must do that analysis now
	$self->process_title_debug_info ();


    if ($self->{'stats'}) {

		my ($k,$v);

		l("\n".'++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++');

		# Actions taken
		@audits = (
			[ 'remove_duplicated_new_title_in_ep' , 'list of programmes where \'New \$title\' was removed from sub-title field (#A1)' ],
			[ 'remove_duplicated_title_and_ep_in_ep' , 'list of programmes where title/ep was removed from sub-title field (#A2)' ],
			[ 'remove_duplicated_title_in_ep' , 'list of programmes where title was removed from sub-title field (#A3)' ],
			[ 'update_premiere_repeat_flags_from_desc' , 'list of programmes where <premiere> or <previously-shown> was set from description content (#A4)' ],
			[ 'check_potential_numbering_in_text' , 'list of programmes where <episode-num was changed (#A5)' ],
			[ 'make_episode_from_part_numbers' , 'list of programmes where <sub-title> was created from \'part\' numbers (#A5.4)' ],
			[ 'process_non_title_info' , ': Remove specified non-title text from <title> (#1)' ],
			[ 'process_demoted_titles' , ': Promote demoted title from <sub-title> to <title> (#11)' ],
			[ 'process_replacement_titles_desc' , ': Replace specified <title> / <sub-title> with title/episode pair supplied using <desc> (#10)' ],
			[ 'process_replacement_titles_episodes' , ': Replace specified <title> / <sub-title> with title/episode pair supplied (#8)' ],
			[ 'process_mixed_title_subtitle' , ': Extract sub-title from <title> (#2)' ],
			[ 'process_mixed_subtitle_title' , ': Extract sub-title from <title> (#3)' ],
			[ 'process_reversed_title_subtitle' , ': Reverse <title> and <sub-title> (#4)' ],
			[ 'process_replacement_titles' , ': Replace <title> with supplied text (#5)' ],
			[ 'process_subtitle_remove_text' , ': Remove specified text from <sub-title> (#13)' ],
			[ 'process_replacement_episodes' , ': Replace <sub-title> with supplied text (#7)' ],
			[ 'process_replacement_ep_from_desc' , ': Replace <sub-title> with supplied text using <desc> (#9)' ],
			[ 'process_replacement_genres' , ': Replace <category> with supplied value(s) (#6)' ],
			[ 'process_replacement_film_genres' , ': Replace \'Film\'/\'Films\' <category> with supplied value(s) (#12)' ],
			[ 'process_translate_genres', ': Replace <category> with supplied value(s) (#14)' ],
			[ 'process_add_genres_to_channel', ': Add category to all programmes on <channel> (#15)' ],
			);

		foreach (@audits) {
			($k,$v) = @{$_};
			$self->print_audit( $k, $v );
		}

		##l('++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++');

		# Progs for possible modification
		@audits = (
			[ 'title_in_subtitle_notfixed' , 'list of programmes where title is still present in sub-title field' ],
			[ 'colon_in_subtitle' , 'list of programmes where sub-title contains colon/hyphen' ],
			[ 'possible_series_nums' , 'list of possible series numbering seen in listings' ],
			[ 'possible_episode_nums' , 'list of possible episode numbering seen in listings' ],
			[ 'possible_part_nums', 'list of possible part numbering seen in listings' ],
			[ 'title_text_to_remove', 'list of titles containing \'Season\'' ],
			[ 'colon_in_title', 'list of titles containing colons', '"title:episode"' ],
			[ 'possible_hyphenated_title', 'list of titles containing hyphens', 'hyphenated titles' ],
			[ 'uppercase_title', 'list of uppercase titles' ],
			[ 'titles_word_special', 'list of titles containing \'Special\'' ],
			[ 'titles_word_various1', 'list of titles containing \'New/Premiere/Finale/etc.\'' ],
			[ 'titles_word_various2', 'list of titles containing \'Day/Night/Week\'' ],
			[ 'titles_word_various3', 'list of titles containing \'Christmas/New Year\'' ],
			[ 'titles_word_various4', 'list of titles containing \'Results/Best of/Highlights/Top\'' ],

			[ 'titles_with_years', 'list of titles including possible years' ],
			[ 'titles_with_bbfc', 'list of film titles including possible BBFC ratings' ],
			[ 'titles_with_mpaa', 'list of film titles including possible MPAA ratings' ],

			[ 'flagged_title_eps', 'list of titles that may need fixing individually' ],
			[ 'dotdotdot_titles', 'list of potential \'...\' titles that may need fixing individually' ],

			[ 'possible_title_variants', 'possible title variations' ],

			[ 'categories_per_prog', 'list of programmes with multiple categories' ],
			[ 'uncategorised_progs' , 'list of programmes with no category' ],
			[ 'short_films' , 'films < 75 minutes long' ],

			[ 'empty_listings', 'list of channels providing no listings' ],
			[ 'listings_no_channel', 'list of channels with no channel details' ],

			[ 'all_genres_sorted', 'all categories' ],

			#[  ],
			);

		foreach (@audits) {
			($k,$v) = @{$_};
			$self->print_audit( $k, $v );
		}

	}

	l("\n".'++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'."\n\n");
}


# Print the info stored in an 'audit' hash
sub print_audit () {
	my ($self, $k, $t) = @_;
	_d(4,$k);
    if ($self->{'audit'}{$k} && (
								(ref $self->{'audit'}{$k} eq 'HASH' && scalar keys %{$self->{'audit'}{$k}} > 0)
							 || (ref $self->{'audit'}{$k} eq 'ARRAY' && scalar $self->{'audit'}{$k} > 0) )) {
        l("\nStart of $t");

		if (ref $self->{'audit'}{$k} eq 'ARRAY') {

			foreach my $v (@{$self->{'audit'}{$k}}) {
				l("\t $v");
			}

		} else {

			foreach my $v (sort keys %{$self->{'audit'}{$k}} ) {
				l("\t $self->{'audit'}{$k}{$v}->{'title'}" . (defined($self->{'audit'}{$k}{$v}->{'episode'}) ? " / $self->{'audit'}{$k}{$v}->{'episode'}" : '') .
				  (defined $self->{'audit'}{$k}{$v}->{'msg'} ? '  -- '.$self->{'audit'}{$k}{$v}->{'msg'} : '')
				  );
			}

		}

		# see if there's a fixup hash for this audit
		my $k2 = $k . '_fixups';
		if ($self->{'audit'}{$k2} && scalar @{ $self->{'audit'}{$k2} } > 0) {
			l("\nPossible fixups ");
			foreach my $v2 (sort @{ $self->{'audit'}->{$k2} } ) {
				l("$v2");
			}
			l("");
		}

        l("End   of $t");
    }
}

=back

=cut

# Load the configuration file
sub load_config () {
	my ($self, $fn) = @_;

	if ( -e $fn ) {
		my $fhok = open my $fh, '<', $fn or v("Cannot open config file $fn");
		if ($fhok) {
			my $c = 0;
			while (my $line = <$fh>) {
				$c++;
				chomp $line;  chop($line) if ($line =~ m/\r$/);  trim($line);
				next if $line =~ /^#/ || $line eq '';

				my ($key, $value, $trash) = $line =~ /^(.*?)\s*=\s*(.*?)([\s\t]*#.*)?$/;
				$self->{'options'}{$key} = $value;
			}
			close $fh;
		}
	}
	else {
		v("File not found $fn");
		return 1;
	}

	_d(8,'Loaded options:',dd(8,$self->{'options'}));
}


# Load the augmentation rules
sub load_rules () {
	my ($self, $fn) = @_;

	# if filename is undefined then look to see if user wants us to fetch a grabber's Supplement file
	if ((!defined $fn) && $self->{'options'}{'use_supplement'}) {

		# Retrieve prog_titles_to_process via XMLTV::Supplement
		require XMLTV::Supplement;  XMLTV::Supplement->import(GetSupplement);
		my $rules_file = GetSupplement($self->{'options'}{'supplement_grabber_name'}, $self->{'options'}{'supplement_grabber_file'});

		if (!defined $rules_file) {
			v('Cannot fetch rules file: '.$self->{'options'}{'supplement_grabber_name'}.'/'.$self->{'options'}{'supplement_grabber_file'});
			return 1;
		}

        my @rules = split /[\n\r]+/, $rules_file;
		my $c = 0;
        foreach my $line (@rules) {
			$c++;
			chomp $line;  chop($line) if ($line =~ m/\r$/);  trim($line);
			if ( $line =~ /\$id:\s(.*?)(\sExp)+.*?\$/i ) {
				l("Using Supplement: $1 \n");
			}
			next if $line =~ /^#/ || $line eq '';

			$self->load_rule($c, $line);
		}
	}

	elsif ( defined $fn ) {

		if ( -e $fn ) {
			my $fhok = open my $fh, '<', $fn or v("Cannot open rules file $fn");
			if ($fhok) {
				my $c = 0;
				while (my $line = <$fh>) {
					$c++;
					chomp $line;  chop($line) if ($line =~ m/\r$/);  trim($line);
					next if $line =~ /^#/ || $line eq '';

					$self->load_rule($c, $line);
				}
				close $fh;
			}
		}
		else {
			v("File not found $fn");
			return 1;
		}

	} else {
		v("No rules file");
		return 1;
	}

	_d(9,'Loaded rules:',dd(9,$self->{'rules'}));
	return 0;
}


# Load an augmentation rule into a hash of rules
sub load_rule () {
	my ($self, $linenum, $rule) = @_;

	# Decode the rule data using the specified encoding (defaults to UTF-8)
	$rule = decode($self->{'encoding'}, $rule);

	# Each rule consists of rule 'type' followed by the rule itself, separated by | char
	my @f = split /\|/, $rule;
	if (scalar @f != 2) {
		v("Wrong number of fields on line $linenum \n");
		return 1;
	}
	my ($ruletype, $ruletext) = @f;

	# Do some basic validation
	if (!defined $ruletype || $ruletype eq '' || $ruletype !~ m/\d+/) {
		v("Invalid rule type on line $linenum \n");
		return 1;
	}

	if (!defined $ruletext || $ruletext eq '') {
		v("Invalid rule text on line $linenum \n");
		return 1;
	}


	# Text to try and match against the programme title is stored in a hash of arrays
	# to shortcut the list of possible matches to those beginning with the same
	# first two characters as the title. It would seem to be quicker to use a regex
	# to match some amount of text up to colon character in the programme title,
	# and then use a hash lookup against the matched text. However, there may be
	# colons in the rule text, so this approach cannot be used.


	# Each rule contains a number of elements (the exact number depends on the rule type) separated by ~ chars.
	# The first element will be a key to identify which data records will be processed for this rule type
	@f = split /~/, $ruletext;
	my ($k, $v) = ($ruletext . '~') =~ /^(.*?)~(.*)$/;
	chop $v;


	# (don't do any further validation on the rules; to do so would mean parsing each and every rule in the file even when
	#  only a few (if any) of them will be met for any given augmentation rule - i.e. very slow and generally pointless -
	#  we'll validate them later at time-of-use)
	# TODO: make a separate validation function to do this


	# Text-based rules are stored segregated by the first 2 chars of the key (to make subsequent list searching faster)
	my $idx = lc(substr ($k, 0, 2));

	# Store the rule
	my $data = { 'line' => $linenum, 'key' => $k, 'value' => $v };
	push @{ $self->{'rules'}->{$ruletype}->{$idx} }, $data;

}


# Replace our wildcards ("%%") in the rule's key
#
sub replace_wild () {
	my ($self, $key) = @_;
	if ($key =~ m/%%/) {
        $key = quotemeta($key);
        $key =~ s/\\%\\%/%%/g;
		$key =~ s/%%/\.\*\?/g;
        return qr/^$key$/;
	}
    else {
        return qr/^\Q$key\E$/;
    }
}


# Create an xmltv_ns compatible episode number.
# Automatically resets the base to zero on series/episode/part numbers
# (input should NOT be rebased - e.g. pass the actual episode enuember)
# Input = programme hash and hash of new data to be inserted
#
sub make_ns_epnum () {
	my ($self, $prog, $_prog) = @_;

	my $s 		= $_prog->{'season'}		if defined $_prog->{'season'} && $_prog->{'season'} ne '';
	my $s_tot 	= $_prog->{'season_total'}	if defined $_prog->{'season_total'} && $_prog->{'season_total'} ne '';
	my $e 		= $_prog->{'episode'}		if defined $_prog->{'episode'} && $_prog->{'episode'} ne '' && $_prog->{'episode'} ne 0;
	my $e_tot 	= $_prog->{'episode_total'}	if defined $_prog->{'episode_total'} && $_prog->{'episode_total'} ne '';
	my $p 		= $_prog->{'part'}			if defined $_prog->{'part'} && $_prog->{'part'} ne '';
	my $p_tot 	= $_prog->{'part_total'}	if defined $_prog->{'part_total'} && $_prog->{'part_total'} ne '';

	# sanity check
	undef($s) 		if defined $s     && $s     eq '0';
	undef($e) 		if defined $e     && $e     eq '0';
	undef($p) 		if defined $p     && $p     eq '0';
	undef($p_tot) 	if defined $p_tot && $p_tot eq '0';

	# re-base the series/episode/part numbers
	$s-- if (defined $s && $s ne '');
	$e-- if (defined $e && $e ne '');
	$p-- if (defined $p && $p ne '');

	# make the xmltv_ns compliant episode-num
	my $episode_ns = '';
	$episode_ns .= $s if (defined $s && $s ne '');
	$episode_ns .= '/'.$s_tot if (defined $s_tot && $s_tot ne '');
	$episode_ns .= '.';
	$episode_ns .= $e if (defined $e && $e ne '');
	$episode_ns .= '/'.$e_tot if (defined $e_tot && $e_tot ne '');
	$episode_ns .= '.';
	$episode_ns .= $p if (defined $p && $p ne '');
	$episode_ns .= '/'.$p_tot if (defined $p_tot && $p_tot ne '');

	_d(3,'Make <episode-num>:',$episode_ns);

    # delete existing 'xmltv_ns' details if no series/ep/part
    # details are available
	if ($episode_ns eq '..') {
        if (defined $prog->{'episode-num'}) {
            @{$prog->{'episode-num'}} = map { $prog->{'episode-num'}[$_][1] eq 'xmltv_ns'
                                            ? ()
                                            : $prog->{'episode-num'}[$_]
                                            } 0 .. $#{$prog->{'episode-num'}};
        }
		return '';
	}

	# otherwise, find the 'xmltv_ns' details in the prog
	my $xmltv_ns_old;
	if (defined $prog->{'episode-num'}) {
		foreach (@{$prog->{'episode-num'}}) {
			if ($_->[1] eq 'xmltv_ns') {
				# found it; insert our element
				$xmltv_ns_old = $_->[0];
				$_->[0] = $episode_ns;
				last;
			}
		}
	}

	# no 'xmltv_ns' attribute found; create a suitable element
    if (!defined $xmltv_ns_old) {
		push @{$prog->{'episode-num'}}, [ $episode_ns, 'xmltv_ns' ];
	}

	return $episode_ns;
}


# Parse an xmltv_ns <episode_num> element into its
# component parts
#
# Second param should be passed by reference and returns the
# text value of the <episode-num> (with spaces removed).
#
sub extract_ns_epnum () {
	my ($self, $prog, $xmltv_ns) = @_;

	if (defined $prog->{'episode-num'}) {

		# find the 'xmltv_ns' details
		##my $xmltv_ns;
		foreach (@{$prog->{'episode-num'}}) {
			if ($_->[1] eq 'xmltv_ns') {
				$$xmltv_ns = $_->[0];
				last;
			}
		}

		if (defined $$xmltv_ns) {
			# simplify the regex by stripping spaces
			$$xmltv_ns =~ s/\s//g;
			# extract the fields from the element
			# rebase appropriately
			if ( $$xmltv_ns =~ /^(\d+)?(?:\/(\d+))?(?:(?:\.(\d+)?(?:\/(\d+))?)(?:\.(\d+)?(?:\/(\d+))?)?)?$/ ) {
				my %episode_num;
				$episode_num{'season'} = $1 +1  	if defined $1;
				$episode_num{'season_total'} = $2  	if defined $2;
				$episode_num{'episode'} = $3 +1  	if defined $3;
				$episode_num{'episode_total'} = $4  if defined $4;
				$episode_num{'part'} = $5 +1  		if defined $5;
				$episode_num{'part_total'} = $6  	if defined $6;
				_d(5,'Decoded <episode-num>:',dd(5,\%episode_num));
				return \%episode_num;
			}
		}

	}

	_d(5,'No <episode-num> found');
	return undef;
}



###############################################
############ GENERAL SUBROUTINES ##############
###############################################

# Return the digit equivalent of its word, i.e. "one" -> "1",
# or return the word if it appears to consist of only digits
sub word_to_digit ($;$) {
    my $word = shift;

    return undef if ! defined $word;
    return $word if $word =~ m/^\d+$/;

	my $lang = shift;
	$lang = 'EN' if !defined $lang;

	my %nums;
	if ($lang eq 'EN') {
		# handle 1-9 in roman numberals
		%nums = ( one => 1, two => 2, three => 3, four => 4, five => 5, six => 6, seven => 7, eight => 8, nine => 9,
				  ten => 10, eleven => 11, twelve => 12, thirteen => 13, fourteen => 14, fifteen => 15, sixteen => 16,
				  seventeen => 17, eighteen => 18, nineteen => 19, twenty => 20,
				   i => 1, ii => 2, iii => 3, iv => 4, v => 5, vi => 6, vii => 7, viii => 8, ix => 9
			     );
	}

    for (lc $word) {
		return $nums{$_} if exists $nums{$_};
	}
	return undef;
}


# Remove leading & trailing spaces
sub trim {
	# Remove leading & trailing spaces
	$_[0] =~ s/^\s+|\s+$//g;
}

###############################################
############# DEBUG SUBROUTINES ###############
###############################################

# open log file
sub open_log (;$) {
	my $fn = shift;
	my $mode = ($debug ? '>>' : '>');	# open append while debugging - avoids issue with tail on truncated files
	open(my $fh, $mode, $fn)
			or die "cannot open $fn: $!";
	$logh = $fh;

	print $logh "\n" . ($debug ? '-'x80 ."\n\n\n" : '');
}

# close log file
sub close_log () {
	if ($logh) {
		close($logh)
				or warn "close failed on log file: $!";
	}
}

# write to log file
sub l ($) {
	my ($msg) = @_;
    print $logh $msg . "\n"  if $logh;
}

# print a message
sub v ($) {
	my ($msg) = @_;
    print STDERR $msg . "\n";
	l($msg . "\n");
}

# write a debug message
sub _d ($@) {
	my ($level, @msg) = @_;
	return if $debug < $level;
	foreach (@msg) {
		print STDERR $_ . " ";
	}
	print STDERR "\n";
}

# dump a variable (for use with _d)
sub dd ($$) {
	# don't call Dumper if we aren't going to be output!
    my $level = $_[0];
	return if $debug < $level;
    my $s = $_[1];
    require Data::Dumper;
    my $d = Data::Dumper::Dumper($s);
    $d =~ s/^\$VAR1 =\s*/        /;
    $d =~ s/;$//;
    chomp $d;
    return "\n".$d;
}

# get the caller's subroutine name
sub self () {
	my $self = (caller(1))[3];
	$self =~ s/(.*::)//;	# drop the package
	return $self;
}

###############################################

1;	# keep eval happy ;-)

__END__

=pod

=head1 AUTHOR

Geoff Westcott, honir.at.gmail.dot.com, Dec. 2014.

This code is based on the "fixup" method/code defined in tv_grab_uk_rt grabber
and credit is given to the author Nick Morrott.

=cut


