# Generate tv_grab_it from tv_grab_it.in.  This is to set the path to
# the files in /usr/local/share/xmltv or wherever.
#
# The second argument is the share directory for the final
# installation.
#
# $Id$
#
use vars '$in'; $in = 'grab/it/tv_grab_it.in';
require 'lib/set_share_dir.pl';
