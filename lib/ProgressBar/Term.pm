# A wrapper around Term::ProgressBar

package XMLTV::ProgressBar::Term;
use strict;

use Exporter;
our @EXPORT = qw(close_bar);

sub new {
        
        my $class = shift;
        
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
