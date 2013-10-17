#!/usr/bin/perl -w
#
# params are 'offset' and 'hours'
#				or  'offset' and 'days'    in which case the offset is 'days' also (otherwise it's 'hours')
#				or  'date'			- fetch just this day
#
# optional params:
#			channel		- Atlas channel id to fetch  (if not specified then grabber .conf file is used as normal)
#			dst				- Add an extra hour(s) to the schedule fetched (default '1'  ('0' if no 'dst' param specficied))
#
#

# You may need to set $HOME if not same as command profile
#$ENV{'HOME'} = '?????';

use strict;
use warnings;
use Data::Dumper;
use CGI; 
use CGI::Carp qw(fatalsToBrowser);

my $query = CGI->new;

# Fetch the query string params
my $offset 	= $query->param('offset');			# offset from now to start fetch (hours/days)
my $hours 	= $query->param('hours');				# hours to fetch
my $days 		= $query->param('days');				# days to fetch
my $channel = $query->param('channel');			# channel id or label
my $date 		= $query->param('date');				# YYYYMMDD
my $dst 		= $query->param('dst');					# (no value)
my $hasdst	= (defined $query->param('dst') ? 1 : 0);


# Validate the params
if ( ($hours && $days) ||
		 ($date && ($offset || $hours || $days)) ) {
	
		if (0) {	
			print <<END_OF_HTML;
Status: 500 Invalid Parameters
Content-type: text/html

<HTML>
<HEAD><TITLE>500 Invalid Parameters</TITLE></HEAD>
<BODY>
  <H1>Error</H1>
  <P>Invalid Parameters</P>
</BODY>
</HTML>
END_OF_HTML
		}

		if (1) {	
			print <<END_OF_XML;
Status: 500 Invalid Parameters
Content-type: text/xml

<?xml version="1.0" encoding="UTF-8"?>
END_OF_XML
		}
		
		exit;
}


my $action = '';
if ($hours) {
	$action = "--hours $hours " . ($offset ? "--offset $offset" : '');
} elsif ($days) {
	$action = "--days $days " . ($offset ? "--offset $offset" : '');
} elsif ($date) {
	$action = "--date $date";
} else {
	$action = "--days 1";
}

$channel = "--channel $channel" if $channel;
$dst 		 = "--dst" 							if $hasdst;



# Must send HTTP Content-Type header
#print CGI->header('text/xml');
# ^^ caused errors:     Use of uninitialized value in string ne at (eval 3) line 29.
#


# debug
#print "Content-type: text/xml"."\n\n";
#print "Params: <br /> $offset <br /> $hours <br /> $action <br />";exit(0);


# run the grabber (& capture the output)
system("perl $ENV{'HOME'}/tv_grab_uk_atlas --quiet $action $channel $dst 1>/tmp/tv_grab_uk_atlas.stdout 2>/tmp/tv_grab_uk_atlas.stderr ");

my $result = '';
open(my $fh, '<', '/tmp/tv_grab_uk_atlas.stderr')
    or die "Unable to open file, $!";	
while(<$fh>) { 
   $result = $_ ;
   last;
}
close($fh)
    or warn "Unable to close the file handle: $!";

if ( $result =~ /^Status:/ ) {
	# grabber threw an error
	# assume it's a valid HTTP "Status: "
	print $result;
}
else {
	# validate the xml 
	system(' xmllint --noout --dtdvalid http://supplement.xmltv.org/xmltv.dtd /tmp/tv_grab_uk_atlas.stdout ');
	if ($? != 0) {
			print "Status: 500 Invalid XML \n\n";
			exit;
	}
}

# append the xml file (which is blank when an error occurs)
print "Content-type: text/xml"."\n\n";
system("cat /tmp/tv_grab_uk_atlas.stdout");
		

exit(0);

__END__


----------------------------------------------------------------------------------
# e.g. when error
stderr = 
---------------------------------------------------
Status: 400 Bad Request
---------------------------------------------------

stdout =
---------------------------------------------------
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tv SYSTEM "xmltv.dtd">

<tv generator-info-name="tv_grab_uk_atlas" generator-info-url="http://atlas.metabroadcast.com/3.0/">
  <channel id="xxxx">
    <display-name lang="en">xxxx</display-name>
  </channel>
</tv>
---------------------------------------------------

return = 
---------------------------------------------------
HTTP/1.1 400 Bad Request
Content-type: text/xml

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tv SYSTEM "xmltv.dtd">

<tv generator-info-name="tv_grab_uk_atlas" generator-info-url="http://atlas.metabroadcast.com/3.0/">
  <channel id="xxxx">
    <display-name lang="en">xxxx</display-name>
  </channel>
</tv>
---------------------------------------------------
