# A few routines for asking the user questions.  Used in --configure
# and also by Makefile.PL, so this file should not depend on any
# nonstandard libraries.
#

package XMLTV::ProgressBar;
use strict;
use XMLTV::GUI;

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

my $real_class = 'XMLTV::ProgressBar::None';
my $bar;

# Must be called before we use this module if we want to use a gui.
sub init( $ ) {
    my $opt_gui = shift;

    # Ask the XMLTV::GUI module for the graphics type we will use
    my $gui_type = XMLTV::GUI::get_gui_type($opt_gui);

    if ($gui_type eq 'term') {
        $real_class = 'XMLTV::ProgressBar::None';
    } elsif ($gui_type eq 'term+progressbar') {
        $real_class = 'XMLTV::ProgressBar::Term';
    } elsif ($gui_type eq 'tk') {
        $real_class = 'XMLTV::ProgressBar::Tk';
    } else {
        die "Unknown gui type: '$gui_type'.";
    }
}

# Create and return a new progress bar.
# Parameters:
#   text to display
#   maximum value
# Or the syntax for Term::ProgressBar may be used, but much of it will be
# ignored in some of the implementations.
sub new {
    my $class = shift;

    ((my $real_class_path = $real_class.".pm") =~ s/::/\//g);

    require $real_class_path;
    import $real_class_path;

    $bar = $real_class->new(@_);

    my $self = {};
    return bless $self, $class;
}

# Alter the value displayed in this progress bar
# Parameters:
#   the value to change this bar to display (optional)
# If no value is given, the value will be incremented by 1.
sub update {
    my $self = shift;
    return $bar->update( @_ );
}

# Close the progress bar.
sub finish {

    # Only does anything for the GUI ones.
    if ($real_class eq 'XMLTV::ProgressBar::Tk') {
        return $bar->finish();
    }
}

1;

