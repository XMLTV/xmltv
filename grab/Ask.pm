# A few routines for asking the user questions in --configure.

package XMLTV::Ask;
use strict;
use base 'Exporter';
use vars '@EXPORT'; @EXPORT = qw(ask askMyQuestion askQuestion askQuestionWithoutValidation);

sub ask($)
{
    print "$_[0]";
    my $result=<>;
    chop($result) if ( defined($result) );
    return($result);
}

sub askMyQuestion
{
    my $question=shift(@_);
    my $default=shift(@_);
    my $validate=shift(@_);
    my @options=@_;

    my $str="$question [".join(',',@options)." (default=$default)] ";

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

sub askQuestion
{
    my $question=shift(@_);
    my $default=shift(@_);
    return(askMyQuestion($question, $default, 1, @_));
}

sub askQuestionWithoutValidation
{
    my $question=shift(@_);
    my $default=shift(@_);
    return(askMyQuestion($question, $default, 0, @_));
}

1;
