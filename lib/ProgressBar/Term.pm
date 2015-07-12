# A wrapper around Term::ProgressBar

package XMLTV::ProgressBar::Term;
use strict;

use Exporter;
our @EXPORT = qw(close_bar);

sub new {

        my $class = shift;
		$ENV{LINES}=24   unless exists $ENV{LINES};
		$ENV{COLUMNS}=80 unless exists $ENV{COLUMNS};

        return Term::ProgressBar->new(@_);

}

sub close_bar() {

        # Do nothing

}

sub AUTOLOAD {

        use vars qw($AUTOLOAD);

        print STDERR "dog $AUTOLOAD\n";

        #return Term::ProgressBar->$AUTOLOAD(@_);

}

1;
