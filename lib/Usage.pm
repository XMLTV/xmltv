# A simple package to provide usage messages.  Example
#
# use XMLTV::Usage <<END
# usage: $0 [--help] [--whatever] FILES...
# END
# ;
#
# Then the usage() subroutine will print the message you gave to
# stderr and exit with failure.  An optional Boolean argument to
# usage(), if true, will make it a 'help message', which is the same
# except it prints to stdout and exits successfully.
#
# It's up to you to call the usage() subroutine, I've thought about
# processing --help with a check_argv() routine in this module, but
# some programs have different help messages depending on what other
# options were given.
#

package XMLTV::Usage;
use base 'Exporter'; use vars '@EXPORT'; @EXPORT = qw(usage);
my $msg;

sub import( @ ) {
    die "usage: use XMLTV::Usage 'usage-message'" if @_ != 2;
    $msg = pop;
    goto &Exporter::import;
}

sub usage( ;$ ) {
    my $is_help = shift;
    die "need to 'import' this module to set message"
      if not defined $msg;

    if ($is_help) {
	print $msg;
	exit(0);
    }
    else {
	print STDERR $msg;
	exit(1);
    }
}

1;
