=pod

=head1 NAME

    XMLTV::GUI - Handles the choice of UI for XMLTV

=head1 SYNOPSIS

    use XMLTV::GUI;
    my $gui_type = get_gui_type($opt_gui);

    where $opt_gui is the commandline option given for --gui and $gui_type is
    one of 'term+progressbar', 'term' and 'tk'.

Determines the type of output the user has requested for XMLTV to communicate
through.

=head1 AUTHOR

Andy Balaam, axis3x3@users.sourceforge.net.  Distributed as part of the xmltv package.

=head1 SEE ALSO

L<XMLTV>

=cut

package XMLTV::GUI;
use strict;

use vars qw(@ISA @EXPORT_OK);

use Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(get_gui_type);

# Use Log::TraceMessages if installed, and choose graphical or not.
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

sub get_gui_type( $ ) {
    my $opt_gui = shift;

    # If the user passed in a --gui option, work on that basis, otherwise use
    # the environment variable
    if (defined $opt_gui) {
        return _get_specified_gui_type($opt_gui);
    } else {
        return _get_specified_gui_type($ENV{XMLTV_GUI});
    }
}

sub _get_specified_gui_type( $ ) {
    my $spec_gui = shift;

    # Return the best match to the specified gui if it is available

    # If we haven't got windows, or we were asked for terminal, we do
    # terminal stylee.
    if (    !_check_for_windowing_env()
            or !defined($spec_gui)
            or $spec_gui =~ /^term/i) {

        # Check whether we at least have the terminal progress bar
        if (defined($spec_gui) && $spec_gui =~ /^termnoprogressbar$/i
                or !eval{ require Term::ProgressBar }) {
            return 'term';
        } else {
            return 'term+progressbar';
        }
    # Now try Tk first
    } elsif ( $spec_gui eq '' or  $spec_gui =~ /^tk$/i or $spec_gui eq '1' ) {
        if ( _check_for_tk() ) {
            return 'tk';
        } else {
            warn "The Tk gui library is unavailable.  Reverting to terminal";
            return 'term';
        }
    # And finally give up and go to terminal
    } else {
        warn "Unknown gui type requested: '$spec_gui'.  Reverting to terminal";

        return 'term';
    }
}

sub _check_for_windowing_env() {
    return defined($ENV{DISPLAY}) || $^O eq 'MSWin32';
}

sub _check_for_tk() {
    return eval{ require Tk && require Tk::ProgressBar };
}

1;
