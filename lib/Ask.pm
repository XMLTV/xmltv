# A few routines for asking the user questions.  Used in --configure
# and also by Makefile.PL, so this file should not depend on any
# nonstandard libraries.

package XMLTV::Ask;
use strict;
use XMLTV::GUI;
use XMLTV::ProgressBar;

use vars qw(@ISA @EXPORT);
use Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(ask
             ask_password
             ask_choice
             ask_boolean
             ask_many_boolean
             say
             );

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

my $real_class = 'XMLTV::Ask::Term';

sub AUTOLOAD {
    use vars qw($AUTOLOAD);
    (my $method_name = $AUTOLOAD) =~ s/.*::(.*?)/$1/;
    (my $real_class_path = $real_class.".pm") =~ s/::/\//g;

    require $real_class_path;
    import $real_class_path;

    $real_class->$method_name(@_);
}


# Must be called before we use this module if we want to use a gui.
sub init( $ ) {
    my $opt_gui = shift;

    # Ask the XMLTV::GUI module for the graphics type we will use
    my $gui_type = XMLTV::GUI::get_gui_type($opt_gui);

    if ($gui_type =~ /^term/) {
        $real_class = 'XMLTV::Ask::Term';
    } elsif ($gui_type eq 'tk') {
        $real_class = 'XMLTV::Ask::Tk';
    } else {
        die "Unknown gui type: '$gui_type'.";
    }

    # Initialise the ProgressBar module
    XMLTV::ProgressBar::init($opt_gui);
}

1;
