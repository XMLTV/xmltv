# A few routines for asking the user questions in --configure.

package XMLTV::Ask;
use strict;
use base 'Exporter';
use vars '@EXPORT';
@EXPORT = qw(ask askMyQuestion askQuestion
	     askQuestionWithoutValidation askBooleanQuestion);

sub ask( $ )
{
    print "$_[0]";
    my $result=<>;
    chop($result) if ( defined($result) );
    return($result);
}

# Ask a question where the answer is one of a set of alternatives.
#
# Parameters:
#   question text
#   default choice
#   whether to validate the user's choice
#   Remaining arguments are the choices available.
#
sub askMyQuestion( $$$@ )
{
    my $question=shift(@_);
    my $default=shift(@_);
    my $validate=shift(@_);
    my @options=@_;

    my $options_size = length("@options");
    if ($options_size < 10 or not $validate) {
	# Simple style, one line question.
	my $str;
	if ((my $tmp = join('', @options)) =~ tr/0-9//c) {
	    $str="$question [".join(',',@options)." (default=$default)] ";
	}
	else {
	    # Just numbers, don't need to list them all.
	    $str="$question (default=$default) ";
	}
	
	while ( 1 ) {
	    my $res=ask($str);
	    if ( !defined($res) || $res eq "" ) {
		return($default);
	    }
	    for my $val (@options) {
		if ( $val=~m/$res/i ) {
		    return($val);
		}
	    }
	    if ( !$validate ) {
		return($res);
	    }
	    print STDERR "invalid response, please choose one of ".join(',', @options)."\n";
	    print STDERR "\n";
	}
    }
    else {
	# Long list of options, present as numbered multiple choice.
	die if not $validate;
	print "$question\n";
	my $optnum = 0;
	my (%num_to_choice, %choice_to_num);
	foreach (@options) {
	    print "$optnum: $_";
	    $num_to_choice{$optnum} = $_;
	    $choice_to_num{$_} = $optnum;
	    ++ $optnum;
	}
	my $r = askQuestion('Select one:', $choice_to_num{$default}, 0 .. $optnum);
	return $num_to_choice{$r};
    }
}

# Ask question with validation.
sub askQuestion( $$@ )
{
    my $question=shift(@_);
    my $default=shift(@_);
    return(askMyQuestion($question, $default, 1, @_));
}

sub askQuestionWithoutValidation( $$@ )
{
    my $question=shift(@_);
    my $default=shift(@_);
    return(askMyQuestion($question, $default, 0, @_));
}

# Ask a yes/no question.
#
# Parameters: question text,
#             default (true or false)
#
# Returns true or false.
#
sub askBooleanQuestion( $$ ) {
    my ($text, $default) = @_;
    my $r = askQuestion($text, ($default ? 'yes' : 'no'), 'yes', 'no');
    if ($r eq 'yes') {
	return 1;
    }
    elsif ($r eq 'no') {
	return 0;
    }
    else { die }
}

1;
