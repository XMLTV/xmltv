package XMLTV::Config_file;
use strict;
use XMLTV::Ask;

# First argument is an explicit config filename or undef.  The second
# argument is the name of the current program (probably best not to
# use $0 for this).  Returns the config filename to use (the file may
# not necessarily exist).  Third argument is a 'quiet' flag (default
# false).
#
# May do other magic things like migrating a config file to a new
# location; you can specify the old program name as an optional fourth
# argument if your program has recently been renamed.
#
sub filename( $$;$$ ) {
    my ($explicit, $progname, $quiet, $old_progname) = @_;
    return $explicit if defined $explicit;
    $quiet = 0 if not defined $quiet;

    my $home = $ENV{HOME};
    $home = '.' if not defined $home;
    my $conf_dir = "$home/.xmltv";
    (-d $conf_dir) or mkdir($conf_dir, 0777)
      or die "cannot mkdir $conf_dir: $!";
    my $new = "$conf_dir/$progname.conf";

    my @old;
    for ($old_progname) { push @old, "$conf_dir/$_.conf" if defined }
    foreach (@old) {
	if (-f and not -e $new) {
	    warn "migrating config file $_ -> $new\n";
	    rename($_, $new)
	      or die "cannot rename $_ to $new: $!";
	    last;
	}
    }

    print STDERR "using config filename $new\n" unless $quiet;
    return $new;
}

# If the given file exists, ask for confirmation of overwriting it;
# exit if no.
#
sub check_no_overwrite( $ ) {
    my $f = shift;
    if (-s $f) {
	if (not ask_boolean <<END
A nonempty configuration file $f
already exists.  There is currently no support for altering an
existing configuration: you have to reconfigure from scratch.

Do you wish to overwrite the old configuration?
END
	    , 0) {
	    say( "Exiting since you don't want to overwrite the old configuration." );
	    exit 0;
	}
    }
}

# Take a filename and return a list of lines with comments and
# leading/trailing whitespace stripped.  Blank lines are returned as
# undef, so the number of lines returned is the same as the original
# file.
#
# Dies ('run --configure') if the file doesn't exist.
#
# Arguments:
#   filename
#
#   (optional, default false) whether the file is created at xmltv
#     installation.  This controls the message given when it's not
#     found.  If false, you need to run --configure; if true, xmltv
#     was not correctly installed.
#
sub read_lines( $;$ ) {
    my ($f, $is_installed) = @_;
    $is_installed = 0 if not defined $is_installed;
    local *FH;
    if (not -e $f) {
	if ($is_installed) {
	    die "cannot find $f, xmltv was not installed correctly\n";
	}
	else {
	    die "config file $f does not exist, run me with --configure\n";
	}
    }
    open(FH, $f) or die "cannot read $f: $!\n";
    my @r;
    while (<FH>) {
	s/\#.*//; s/^\s+//; s/\s+$//;
	undef $_ if not length;
	push @r, $_;
    }
    close FH or die "cannot close $f: $!\n";
    die "config file $f is empty, please delete and run me with --configure\n"
      if not @r;
    return @r;
}

1;
