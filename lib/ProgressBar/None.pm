# The lack of a progress bar

package XMLTV::ProgressBar::None;
use strict;

sub new {
        my $class = shift;
        my $self = {};
        
        my $message = shift;
        print STDERR "$message\n";
        
        return bless $self, $class;
}

sub AUTOLOAD {
        # Do nothing
}

1;
