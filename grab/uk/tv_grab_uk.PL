# Generate tv_grab_uk from tv_grab_uk.in.  This is to set the path to
# the files in /usr/local/share/xmltv or wherever.
#
# The second argument is the share directory for the final
# installation.
#
# $Id$
#
use vars '$in'; $in = 'grab/uk/tv_grab_uk.in';
require 'lib/set_share_dir.pl';
