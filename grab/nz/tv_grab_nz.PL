# Generate tv_grab_nz from tv_grab_nz.in.  This is to set the path to
# the files in /usr/local/share/xmltv or wherever.
#
# The second argument is the share directory for the final
# installation.
#
die "usage: $_ output_file share_dir" if @ARGV != 2;
require 'lib/set_share_dir.pl';
set_share_dir('grab/nz/tv_grab_nz.in', $ARGV[0], $ARGV[1]);
