package XMLTV::Config_file;
use strict;

# First argument is an explicit config filename or undef.  The second
# argument is the name of the current program (probably best not to
# use $0 for this).  Returns the config filename to use (the file may
# not necessarily exist).
#
# May do other magic things like migrating a config file to a new
# location.
#
sub filename( $$ ) {
    my ($explicit, $progname) = @_;
    return $explicit if defined $explicit;

    my $home = $ENV{HOME};
    $home = '.' if not defined $home;
    my $conf_dir = "$home/.xmltv";
    (-d $conf_dir) or mkdir($conf_dir, 0777)
      or die "cannot mkdir $conf_dir: $!";
    my $new = "$conf_dir/$progname.conf";
    my $old = "$conf_dir/$progname";

    if (-f $old and not -e $new) {
	warn "migrating config file $old -> $new\n";
	rename($old, $new)
	  or die "cannot rename $old to $new: $!";
    }

    return $new;
}

1;
