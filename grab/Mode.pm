# A simple library to handle mutually exclusive choices.  For example
#
# my $mode = XMLTV::Mode::mode('eat', # default
#                              $opt_walk => 'walk',
#                              $opt_sleep => 'sleep',
#                             );
#
# Only one of the choices can be active and mode() will die() with an
# error message if $opt_walk and $opt_sleep are both set.  It will
# otherwise return one of the strings 'eat', 'walk' or 'sleep'.
#
# TODO find some way of getting this cleanly into Getopt::Long.

package XMLTV::Mode;
sub mode( $@ ) {
    my $default = shift;
    die 'usage: mode(default, [COND => MODE, ...])' if @_ % 2;
    my $got_mode;
    my ($cond, $mode);
    while (@_) {
	($cond, $mode, @_) = @_;
	next if not $cond;
	die "cannot both $got_mode and $mode\n" if defined $got_mode;
	$got_mode = $mode;
    }
    $got_mode = $default if not defined $got_mode;
    return $got_mode;
}
1;
