# A few routines for asking the user questions.  Used in --configure
# and also by Makefile.PL, so this file should not depend on any
# nonstandard libraries.
#
#
package XMLTV::Ask::Term;
use strict;
use base 'Exporter';
our @EXPORT = qw(ask
                 askQuestion
                 askBooleanQuestion
                 askManyBooleanQuestions
                 say
                );
use Carp qw(croak carp);

# Use Log::TraceMessages if installed.
BEGIN {
    eval { require Log::TraceMessages };
    if ($@) {
	*t = sub {};
	*d = sub { '' };
    }
    else {
	*t = \&Log::TraceMessages::t;
	*d = \&Log::TraceMessages::d;
    }
}

sub ask( $ );
sub askQuestion( $$@ );
sub askBooleanQuestion( $$ );
sub askManyBooleanQuestions( $@ );
sub say( $ );

sub ask( $ )
{
    my $prompt = shift;
    chomp $prompt;
    $prompt .= ' ' if $prompt !~ /\s$/;
    print STDERR $prompt;
    my $r = <STDIN>;
    for ($r) {
	return undef if not defined;
	s/^\s+//;
	s/\s+$//;
	return $_;
    }
}

# Check for exact match, then for substring matching.
sub match( $@ ) {
    my ($choice, @options) = @_;
    foreach (@options) {
	return $_ if $_ eq $choice;
    }
    my @poss;
    foreach (@options) {
	push @poss, $_ if /\Q$choice\E/i;
    }
    if (@poss == 1) {
	# Unambiguous substring match.
	return $poss[0];
    }
    return undef;
}

# Ask a question where the answer is one of a set of alternatives.
#
# Parameters:
#   question text
#   default choice
#   Remaining arguments are the choices available.
#
# Returns one of the choices, or undef if input could not be read.
#
sub askQuestion( $$@ )
{
    my $question=shift(@_); die if not defined $question;
    chomp $question;
    my $default=shift(@_); die if not defined $default;
    my @options=@_; die if not @options;
    t "asking question $question, default $default";
    croak "default $default not in options"
      if not grep { $_ eq $default } @options;

    # If there is only one option, don't bother asking.
    if (@options == 1) {
	say("$question - assuming $default");
	return $default;
    }

    # Check no duplicates (required for later processing, maybe).
    my %seen;
    foreach (@options) { die "duplicate option $_" if $seen{$_}++ }

    my $options_size = length("@options");
    t "size of options: $options_size";
    my $all_digits = not ((my $tmp = join('', @options)) =~ tr/0-9//c);
    t "all digits? $all_digits";
    if ($options_size < 20 or $all_digits) {
	# Simple style, one line question.
	my $str = "$question [".join(',',@options)." (default=$default)] ";
	while ( 1 ) {
	    my $res=ask($str);
	    return undef if not defined $res;
	    return $default if $res eq '';
	    for (match($res, @options)) {
		return $_ if defined;
	    }
	    print STDERR "invalid response, please choose one of ".join(',', @options)."\n\n";
	}
    }
    else {
	# Long list of options, present as numbered multiple choice.
	print STDERR "$question\n";
	my $optnum = 0;
	my (%num_to_choice, %choice_to_num);

	# If any of the option strings happen to be numbers, and
	# within the range of option numbers, arrange it so they're
	# with the matching number.
	#
	my (@numbers, @others);
	foreach (@options) {
	    if (/^\d+$/ && $_ < @options) { push @numbers, $_ }
	    else { push @others, $_ }
	}
	@options = ();
	foreach (sort { $a <=> $b } @numbers) {
	    push @options, splice @others, 0, $_ - @options;
	    push @options, $_;
	}
	push @options, @others;

	foreach (@options) {
	    $num_to_choice{$optnum} = $_;
	    $choice_to_num{$_} = $optnum;
	    ++ $optnum;
	}
	$optnum--;
	my $r=undef;
      ASK: for (;;) {
	    # Present a numbered list of options, but accept either
	    # numbers or the option names.
	    #
	    print STDERR "$_: $options[$_]\n" foreach 0 .. $#options;
	    my $res = ask("choose one (default=$choice_to_num{$default},$default): ");
	    return undef if not defined $res;
	    return $default if $res eq '';

	    foreach (0 .. $#options) {
		return $num_to_choice{$_} if $res eq $_;
	    }
	    for (match($res, @options)) {
		return $_ if defined;
	    }
	    print STDERR "invalid response, please choose one of the following:\n\n";
	}
    }
}

# Ask a yes/no question.
#
# Parameters: question text,
#             default (true or false)
#
# Returns true or false, or undef if input could not be read.
#
sub askBooleanQuestion( $$ )
{
    my ($text, $default) = @_;
    my $r = askQuestion($text, ($default ? 'yes' : 'no'), 'yes', 'no');
    return undef if not defined $r;
    return 1 if $r eq 'yes';
    return 0 if $r eq 'no';
    die;
}

# Ask yes/no questions with option 'default to all'.
#
# Parameters: default (true or false),
#             question texts (one per question).
#
# Returns: lots of booleans, one for each question.  If input cannot
# be read, then a partial list is returned.
#
sub askManyBooleanQuestions( $@ )
{
    my $default = shift;

    # Catch a common mistake - passing the answer string as default
    # instead of a Boolean.
    #
    carp "default is $default, should be 0 or 1"
      if $default ne '0' and $default ne '1';

    my @r;
    while (@_) {
	my $q = shift @_;
	my $r = askQuestion($q, ($default ? 'yes' : 'no'),
			    'yes', 'no', 'all', 'none');
	last if not defined $r;
	if ($r eq 'yes') {
	    push @r, 1;
	}
	elsif ($r eq 'no') {
	    push @r, 0;
	}
	elsif ($r eq 'all' or $r eq 'none') {
	    my $bool = ($r eq 'all');
	    push @r, $bool;
	    foreach (@_) {
		print STDERR "$_ ", ($bool ? 'yes' : 'no'), "\n";
		push @r, $bool;
	    }
	    last;
	}
	else { die }
    }
    return @r;
}

sub say( $ )
{
    my $question = shift;
    $question=~s/\n+$//o;
    print STDERR "$question\n";
}


1;
