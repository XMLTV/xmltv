# A few routines for asking the user questions.  Used in --configure
# and also by Makefile.PL, so this file should not depend on any
# nonstandard libraries.
#

package XMLTV::Ask;
use strict;
use Carp qw(croak carp);

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

    # For now we do graphical configuration only if the undocumented
    # XMLTV_TK environment variable is set to a true value.
    #
    if ($ENV{XMLTV_TK}
	and (defined($ENV{DISPLAY}) || $^O eq 'MSWin32')
	and eval { require Tk }) {
	require XMLTV::AskTk; XMLTV::AskTk->import;
	*XMLTV::Ask:: = *XMLTV::AskTk::;
    }
    else {
	require XMLTV::AskTerm; XMLTV::AskTerm->import;
	*XMLTV::Ask:: = *XMLTV::AskTerm::;
    }
}



1;
