package XMLTV::ValidateGrabber;

use strict;

BEGIN {
    use Exporter   ();
    our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ConfigureGrabber ValidateGrabber/;
}
our @EXPORT_OK;

my $CMD_TIMEOUT = 600;

=head1 NAME

XMLTV::ValidateGrabber

=head1 DESCRIPTION

Utility library that validates that a grabber properly implements the
capabilities described at

http://membled.com/twiki/bin/view/Main/XmltvCapabilities

The ValidateGrabber call first asks the grabber which capabilities it
claims to support and then validates that it actually does support
these capabilities.

=head1 EXPORTED FUNCTIONS

All these functions are exported on demand.

=over 4

=cut

use XMLTV::ValidateFile qw/ValidateFile/;

use File::Slurp qw/read_file/;
use List::Util qw(min);

# Parameters to call grabbers with.
my $offset=1;
my $days=2;

my $runfh;

sub w;
sub run;
sub run_capture;

=item ConfigureGrabber

    ConfigureGrabber( "./tv_grab_new", "./tv_grab_new.conf" )

=cut

sub ConfigureGrabber
{
    my( $exe, $conf ) = @_;

    if ( not system( "$exe --configure --config-file $conf" ) )
    {
	w "Error returned from grabber during configure.";
	return 1;
    }
    
    return 1;
}

=item ValidateGrabber

Run the validation for a grabber.

    ValidateGrabber( "./tv_grab_new", "./tv_grab_new.conf", "/tmp/new_",
                     "./blib/share", 0, 1 )

=cut

sub ValidateGrabber
{
    my( $exe, $conf, $op, $sharedir, $usecache, $verbose ) = @_;

    $verbose = 0 if not defined $verbose;

    my $errors=0;
    open( $runfh, ">${op}commands.log" )
	or die "Failed to write to ${op}commands.log";

    if (not run( "$exe --ahdmegkeja > /dev/null 2>&1" ))
    {
      w "$exe --ahdmegkeja did not fail. The grabber seems to "
	  . "accept any command-line parameter without returning an error.";
      $errors++;
    }

    if (run( "$exe --version > /dev/null 2>&1" ))
    {
      w "$exe --version failed: $?, $!";
      $errors++;
    }

    my $cap = run_capture( "$exe --capabilities 2>/dev/null" );
    if ( not defined $cap )
    {
      w "$exe --capabilities failed: $?, $!";
      $errors++;
    }

    my @capabilities = split( /\s+/, $cap );
    my %capability;
    foreach my $c (@capabilities)
    {
	$capability{$c} = 1;
    }

    my $extraop = "";
    $extraop .= "--cache  ${op}cache " 
	if $capability{cache} and $usecache;
    $extraop .= "--share $sharedir "
	if $capability{share} and defined( $sharedir );

    if( not -f $conf )
    {
	w "Configuration file $conf does not exist. Aborting.";
	close( $runfh );
	return 1;
    }

    # Should we test for --list-channels?

    my $cmd = "$exe --config-file $conf --offset $offset --days $days " .
	"$extraop";

    my $output = "${op}${offset}_$days.xml";

    if (defined $cmd) {
	if (run "$cmd > $output 2>${op}1.log") {
	    w "$cmd failed: $?, $!";
	    $errors++;
	}

	# Run the same command again to see that --output and --quiet works.
	my $cmd2 = "$cmd --output ${output}2 2>${op}2.log";
	my $cmd3 = "$cmd --quiet > ${output}3 2>${op}3.log";
	my $cmd4 = "$cmd --quiet --output ${output}4 2>${op}4.log";

	if (run $cmd2) {
	    w "$cmd2 failed: $?, $!";
	    $errors++;
	}

	if (run $cmd3 ) {
	    w "$cmd3 failed: $?, $!";
	    $errors++;
	}

	if (run $cmd4 ) {
	    w "$cmd4 failed: $?, $!";
	    $errors++;
	}
        
	if( $errors )
	{
	    w "Errors found in basic behaviour. Aborting.";
	    close( $runfh );
	    return $errors;
	}

	# Check that the grabber was quiet when it should have been.
	if ( -s "${op}3.log" )
	{
	    w "$cmd3 produced output to STDERR when it shouldn't have. " 
		. "See ${op}3.log";
	    $errors++;
	}
	else
	{
	    unlink( "${op}3.log" );
	}

	if ( -s "${op}4.log" )
	{
	    w "$cmd4 produced output to STDERR when it shouldn't have. " 
		. "See ${op}4.log";
	    $errors++;
        }
	else
	{
	    unlink( "${op}4.log" );
	}

	if ( ! compare_files( $output, "${output}2" ) )
	{
	    w "$output and ${output}2 differ.";
	    $errors++;
	}

	if ( ! compare_files( $output, "${output}3" ) )
	{
	    w "$output and ${output}3 differ.";
	    $errors++;
	}

	if ( ! compare_files( $output, "${output}4" ) )
	{
	    w "$output and ${output}4 differ.";
	    $errors++;
	}

	# The output files were all equal. Remove all but one of them.
	unlink( "${output}2" );
	unlink( "${output}3" );
	unlink( "${output}4" );
    }

    # Okay, it ran, and we have the result in $output.  Validate.
    if (ValidateFile( $output )) {
	w "Errors found in $output";
	close( $runfh );
	$errors++;
	return $errors;
    }
    w "$output validates ok";

    # Run through tv_cat, which makes sure the data looks like XMLTV.
    # What kind of errors does this catch that ValidateFile misses?
    if (run "tv_cat $output >/dev/null") {
	w "$output makes tv_cat choke, so probably has semantic errors";
	next;
    }

    # Do tv_sort sanity checks.  One day it would be better to put
    # this stuff in a Perl library.
    my $sort_errors = "$output.sort_errors";
    if (run "tv_sort $output >$output.sorted 2>$sort_errors") {
	# This would indicate a bug in tv_sort.
	w "tv_sort failed on $output for some reason, see $sort_errors";
	$errors++;
    }

    if (my @lines = read_file $sort_errors) {
	w "$output has funny start or stop times: some errors are:\n"
	    . join('', @lines[0 .. min(9, $#lines)]);
	$errors++;
    }

    close( $runfh );
    return $errors;
}

sub w
{
    print "$_[0]\n";
}

# Run an external command. Exit if the command is interrupted with ctrl-c.
sub run {
    my( $cmd ) = @_;

    print $runfh "$cmd\n";

    my $killed = 0;

    # Set a timer and run the real command.
    eval {
	local $SIG{ALRM} =
            sub {
		# ignore SIGHUP here so the kill only affects children.
		local $SIG{HUP} = 'IGNORE';
		kill 1,(-$$);
		$killed = 1;
	    };
	alarm $CMD_TIMEOUT;
	system ( $cmd );
	alarm 0;
    };
    $SIG{HUP} = 'DEFAULT';    

    if( $killed )
    {
	w "Timeout";
	return 1;
    }

    if ($? == -1) {
	w "Failed to execute $cmd: $!";
	return 1;
    }
    elsif ($? & 127) {
	w "Terminated by signal " . ($? & 127);
	exit 1;
    }

    return $? >> 8;
}

# Run an external command and return the output. Exit if the command is 
# interrupted with ctrl-c.
sub run_capture {
    my( $cmd ) = @_;

#    print "Running $cmd\n";

    my $killed = 0;
    my $result;

    # Set a timer and run the real command.
    eval {
	local $SIG{ALRM} =
            sub {
		# ignore SIGHUP here so the kill only affects children.
		local $SIG{HUP} = 'IGNORE';
		kill 1,(-$$);
		$killed = 1;
	    };
	alarm $CMD_TIMEOUT;
	$result = qx/$cmd/;
	alarm 0;
    };
    $SIG{HUP} = 'DEFAULT';    

    if( $killed )
    {
	w "Timeout";
	return undef;
    }

    if ($? == -1) {
	w "Failed to execute $cmd: $!";
	return undef;
    }
    elsif ($? & 127) {
	w "Terminated by signal " . ($? & 127);
	exit 1;
    }

    if( $? >> 8 )
    {
	return $? >> 8;
    }
    else
    {
	return $result;
    }
}

# Compare two files. Return true if they have the same contents.
sub compare_files {
    my( $file1, $file2 ) = @_;

    run("diff $file1 $file2 > /dev/null");
    return $? ? 0 : 1;
}

1;

### Setup indentation in Emacs
## Local Variables:
## perl-indent-level: 4
## perl-continued-statement-offset: 4
## perl-continued-brace-offset: 0
## perl-brace-offset: -4
## perl-brace-imaginary-offset: 0
## perl-label-offset: -2
## cperl-indent-level: 4
## cperl-brace-offset: 0
## cperl-continued-brace-offset: 0
## cperl-label-offset: -2
## cperl-extra-newline-before-brace: t
## cperl-merge-trailing-else: nil
## cperl-continued-statement-offset: 2
## indent-tabs-mode: t
## End:
