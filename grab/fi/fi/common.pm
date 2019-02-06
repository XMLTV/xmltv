# -*- mode: perl; coding: utf-8 -*- ###########################################
#
# tv_grab_fi: common code
#
###############################################################################
#
# Setup
#
# INSERT FROM HERE ############################################################
package fi::common;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT      = qw(message debug fetchRaw fetchTree
		      timeToEpoch fullTimeToEpoch);
our @EXPORT_OK   = qw(setQuiet setDebug setTimeZone);
our %EXPORT_TAGS = (
		    main => [qw(message debug setQuiet setDebug setTimeZone)],
		   );

# Perl core modules
use Carp;
use Encode qw(decode);
use POSIX qw(tzset);
use Time::Local qw(timelocal);

# Other modules
use HTML::TreeBuilder;
use XMLTV::Get_nice;

#
# Work around <meta>-in-body bug in HTML::TreeBuilder, See
#
#    https://rt.cpan.org/Public/Bug/Display.html?id=76051
#
# Example:
#
#  <html>
#   <head>
#   </head>
#   <body>
#    <div>
#     <div>
#      <meta itemprop="test" content="test">
#      <div>
#      </div>
#     </div>
#    </div>
#   </body>
#  </html>
#
# is incorrectly parsed as ($tree->dump() output):
#
#  html
#   head
#    meta
#   body
#    div
#     div
#    div   <--- incorrect level for innermost <div>
#
# Enable <meta> as valid body element
$HTML::Tagset::isBodyElement{meta}++;
$HTML::Tagset::isHeadOrBodyElement{meta}++;

# Normal message, disabled with --quiet
{
  my $quiet = 0;
  sub message(@)  { print STDERR "@_\n" unless $quiet }
  sub setQuiet($) { ($quiet) = @_ }
}

# Debug message, enabled with --debug
{
  my $debug = 0;
  sub debug($@) {
    my $level = shift;
    print STDERR "@_\n" unless $debug < $level;
  }
  sub setDebug($) {
    if (($debug) = @_) {
      # Debug messages may contain Unicode
      binmode(STDERR, ":encoding(utf-8)");
      debug(1, "Debug level set to $debug.");
    }
  }
}

# Fetch URL as UTF-8 encoded string
sub fetchRaw($;$$) {
  my($url, $encoding, $nofail) = @_;
  debug(2, "Fetching URL '$url'");
  my $content;
  my $retries = 5; # this seems to be enough?
 RETRY:
  while (1) {
      eval {
	  local $SIG{ALRM} = sub { die "Timeout" };

	  # Default TCP timeouts are too long. If we don't get a response
	  # within 20 seconds, then that's usually an indication that
	  # something is really wrong on the server side.
	  alarm(20);
	  $content = get_nice($url);
	  alarm(0);
      };

      unless ($@) {
	  # Everything is OK
	  # NOTE: utf-8 means "strict UTF-8 standard encoding"
	  $content = decode($encoding || "utf-8", $content);
	  last RETRY;
      } elsif (($@ =~ /error: 500 Timeout/) && $retries--) {
	  # Let's try this one more time
	  carp "fetchRaw(): timeout. Retrying...";
      } elsif ($nofail) {
	  # Caller requested not to fail
	  $content = "";
	  last RETRY;
      } else {
	  # Fail on everything else
	  croak "fetchRaw(): $@";
      }
  }
  debug(5, $content);
  return($content);
}

# Fetch URL as parsed HTML::TreeBuilder
sub fetchTree($;$$$) {
  my($url, $encoding, $nofail, $unknown) = @_;
  my $content = fetchRaw($url, $encoding, $nofail);
  my $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(!$unknown);
  local $SIG{__WARN__} = sub { carp("fetchTree(): $_[0]") };
  $tree->parse($content) or croak("fetchTree() parse failure for '$url'");
  $tree->eof;
  return($tree);
}

#
# Time zone handling
#
# After setting up the day list we switch to a fixed time zone in order to
# interpret the program start times from finnish sources. In this case we of
# course use
#
#      Europe/Helsinki
#
# which can mean
#
#      EET  = GMT+02:00 (East European Time)
#      EEST = GMT+03:00 (East European Summer Time)
#
# depending on the day of the year. By using a fixed time zone this grabber
# will always be able to correctly calculate the program start time in UTC,
# no matter what the time zone of the local system is.
#
# Test program:
# ---------------------- CUT HERE ---------------------------------------------
# use Time::Local;
# use POSIX qw(strftime tzset);
#
# # DST test days for Europe 2010
# my @testdays = (
# 		# hour, minute, mday, month
# 		[    2,     00,    1,     1],
# 		[    2,     59,   28,     3],
# 		[    3,     00,   28,     3],
# 		[    3,     01,   28,     3],
# 		[    3,     00,    1,     7],
# 		[    3,     59,   31,    10],
# 		[    4,     00,   31,    10],
# 		[    4,     01,   31,    10],
# 		[    2,     00,    1,    12],
# 	       );
#
# print strftime("System time zone is: %Z\n", localtime(time()));
# if (@ARGV) {
#   $ENV{TZ} = "Europe/Helsinki";
#   tzset();
# }
# print strftime("Script time zone is: %Z\n", localtime(time()));
#
# foreach my $date (@testdays) {
#   my $time = timelocal(0, @{$date}[1, 0, 2], $date->[3] - 1, 2010);
#   print
#     "$time: ", strftime("%d-%b-%Y %T %z", localtime($time)),
#     " -> ",    strftime("%d-%b-%Y %T +0000", gmtime($time)), "\n";
# }
# ---------------------- CUT HERE ---------------------------------------------
#
# Test runs:
#
# 1) system on Europe/Helsinki time zone [REFERENCE]
#
# $ perl test.pl
# System time zone is: EET
# Script time zone is: EET
# 1262304000: 01-Jan-2010 02:00:00 +0200 -> 01-Jan-2010 00:00:00 +0000
# 1269737940: 28-Mar-2010 02:59:00 +0200 -> 28-Mar-2010 00:59:00 +0000
# 1269738000: 28-Mar-2010 04:00:00 +0300 -> 28-Mar-2010 01:00:00 +0000
# 1269738060: 28-Mar-2010 04:01:00 +0300 -> 28-Mar-2010 01:01:00 +0000
# 1277942400: 01-Jul-2010 03:00:00 +0300 -> 01-Jul-2010 00:00:00 +0000
# 1288486740: 31-Oct-2010 03:59:00 +0300 -> 31-Oct-2010 00:59:00 +0000
# 1288490400: 31-Oct-2010 04:00:00 +0200 -> 31-Oct-2010 02:00:00 +0000
# 1288490460: 31-Oct-2010 04:01:00 +0200 -> 31-Oct-2010 02:01:00 +0000
# 1291161600: 01-Dec-2010 02:00:00 +0200 -> 01-Dec-2010 00:00:00 +0000
#
# 2) system on America/New_York time zone
#
# $ TZ="America/New_York" perl test.pl
# System time zone is: EST
# Script time zone is: EST
# 1262329200: 01-Jan-2010 02:00:00 -0500 -> 01-Jan-2010 07:00:00 +0000
# 1269759540: 28-Mar-2010 02:59:00 -0400 -> 28-Mar-2010 06:59:00 +0000
# 1269759600: 28-Mar-2010 03:00:00 -0400 -> 28-Mar-2010 07:00:00 +0000
# 1269759660: 28-Mar-2010 03:01:00 -0400 -> 28-Mar-2010 07:01:00 +0000
# 1277967600: 01-Jul-2010 03:00:00 -0400 -> 01-Jul-2010 07:00:00 +0000
# 1288511940: 31-Oct-2010 03:59:00 -0400 -> 31-Oct-2010 07:59:00 +0000
# 1288512000: 31-Oct-2010 04:00:00 -0400 -> 31-Oct-2010 08:00:00 +0000
# 1288512060: 31-Oct-2010 04:01:00 -0400 -> 31-Oct-2010 08:01:00 +0000
# 1291186800: 01-Dec-2010 02:00:00 -0500 -> 01-Dec-2010 07:00:00 +0000
#
# 3) system on America/New_York time zone, script on Europe/Helsinki time zone
#    [compare to output from (1)]
#
# $ TZ="America/New_York" perl test.pl switch
# System time zone is: EST
# Script time zone is: EET
# 1262304000: 01-Jan-2010 02:00:00 +0200 -> 01-Jan-2010 00:00:00 +0000
# 1269737940: 28-Mar-2010 02:59:00 +0200 -> 28-Mar-2010 00:59:00 +0000
# 1269738000: 28-Mar-2010 04:00:00 +0300 -> 28-Mar-2010 01:00:00 +0000
# 1269738060: 28-Mar-2010 04:01:00 +0300 -> 28-Mar-2010 01:01:00 +0000
# 1277942400: 01-Jul-2010 03:00:00 +0300 -> 01-Jul-2010 00:00:00 +0000
# 1288486740: 31-Oct-2010 03:59:00 +0300 -> 31-Oct-2010 00:59:00 +0000
# 1288490400: 31-Oct-2010 04:00:00 +0200 -> 31-Oct-2010 02:00:00 +0000
# 1288490460: 31-Oct-2010 04:01:00 +0200 -> 31-Oct-2010 02:01:00 +0000
# 1291161600: 01-Dec-2010 02:00:00 +0200 -> 01-Dec-2010 00:00:00 +0000
#
# Setup fixed time zone for program start time interpretation
sub setTimeZone() {
  $ENV{TZ} = "Europe/Helsinki";
  tzset();
}

# Take a fi::day (day/month/year) and the program start time (hour/minute)
# and convert it to seconds since Epoch in the current time zone
sub timeToEpoch($$$) {
  my($date, $hour, $minute) = @_;
  return(timelocal(0, $minute, $hour,
		   $date->day(), $date->month() - 1, $date->year()));
}

# Same thing but without fi::day object
sub fullTimeToEpoch($$$$$) {
  my($year, $month, $day, $hour, $minute) = @_;
  return(timelocal(0, $minute, $hour, $day, $month - 1, $year));
}

# That's all folks
1;
