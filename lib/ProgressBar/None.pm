# The lack of a progress bar

package XMLTV::ProgressBar::None;
use strict;

sub new {
        my $class = shift;
        my $self = {};
        
        my $args = shift;
        print STDERR "$args->{name}\n";
        
        return bless $self, $class;
}

sub AUTOLOAD {
        # Do nothing
}

1;
