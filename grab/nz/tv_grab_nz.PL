# Generate tv_grab_nz from tv_grab_nz.in.  This is to set the path to
# the files in /usr/local/share/xmltv or wherever.
#
# The second argument is the share directory for the final
# installation.
#
use vars '$in'; $in = 'grab/nz/tv_grab_nz.in';
require 'lib/set_share_dir.pl';
