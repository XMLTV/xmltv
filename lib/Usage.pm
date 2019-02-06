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
# Alternatively, if your usage message is not known at compile time,
# you can pass it as a string to usage().  In this case you need two
# arguments: the 'is help' flag mentioned above, and the message.
#
# It's up to you to call the usage() subroutine, I've thought about
# processing --help with a check_argv() routine in this module, but
# some programs have different help messages depending on what other
# options were given.

package XMLTV::Usage;
use base 'Exporter'; our @EXPORT = qw(usage);
my $msg;

sub import( @ ) {
    if (@_ == 1) {
	# No message specifed at import.
    }
    elsif (@_ == 2) {
	$msg = pop;
    }
    else {
	die "usage: use XMLTV::Usage [usage-message]";
    }
    goto &Exporter::import;
}

sub usage( ;$$ ) {
    my $is_help = shift;
    my $got_msg = shift;
    my $m = (defined $got_msg) ? $got_msg : $msg;
    die "need to 'import' this module to set message"
      if not defined $m;

    if ($is_help) {
	print $m;
	exit(0);
    }
    else {
	print STDERR $m;
	exit(1);
    }
}

1;
