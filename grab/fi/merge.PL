#!/usr/bin/perl -w
#
# Merger to generate tv_grab_fi
#
use 5.008;
use strict;
use warnings;

use File::Basename;

# output file name
my($outfile) = @ARGV
  or die "no output file specified!";

# working directory
my $dir = dirname($0);

# output file
open(my $ofh, ">", $outfile)
  or die "can't open output file: $!";

# source modules
my @sources = ( sort(<$dir/fi/*.pm>), sort(<$dir/fi/source/*.pm>));
print "Found modules: ", map({ basename($_) . " " } @sources), "\n";

# open main script
open(my $ifh, "<", "$dir/tv_grab_fi.pl")
  or die "can't open main script file: $!";

# Merge
my @versions;
while (<$ifh>) {

  # version marker
  if (my($version) = /^use constant VERSION => \'\$Id: (\S+ \S+ \S+ \S+)/) {
    push(@versions, $version);

  # insert marker for source modules
  } elsif (/^\# INSERT: SOURCES/) {

    print $ofh <<END_OF_MERGE_TEXT;
#
#                   This is the merged version of the script.
#
#                !!! DO NOT EDIT - YOUR CHANGES WILL BE LOST !!!
#
#          Any changes should be done to the original modules instead.
#
###############################################################################
END_OF_MERGE_TEXT

    foreach my $source (@sources) {
      open(my $sfh, "<", $source)
	or die "can't open source module '$source': $!";
      print "Inserting module '", basename($source), "'\n";
      while (<$sfh>) {
	push(@versions, $1) if /^\# VERSION: \$Id: (\S+ \S+ \S+ \S+)/;
	next if 1../^\# INSERT FROM HERE /;
	next if /^__END__/..0; # right side always false -> cut to the end
	print $ofh $_;

	# Don't insert the code if source module has been disabled
	print($ofh <<END_OF_DISABLED_TEXT), last
}

# THIS DATA SOURCE HAS BEEN DISABLED!

1;
END_OF_DISABLED_TEXT
	  if /^\s*our\s+\$ENABLED\s*=\s*0;/;

      }
      close($sfh);
      print $ofh "\n###############################################################################\n";
    }

  # delete marker for code
  } elsif (/^\# CUT CODE START/../^\# CUT CODE END/) {

  # insert version string
  } elsif (/^use XMLTV::Version /) {
    my $version = 'generated from\n\t' .
      join('\n\t', map {
	sprintf("%-25s  %-5s  %10s  %8s", /^(\S+),v (\S+) (\S+) (\S+)$/)
      } @versions);
    s/VERSION;$/"$version";/;
    print $ofh $_;
  # normal line
  } else {
    print $ofh $_;
  }
}

# check for write errors
close($ofh)
  or die "error while writing to output file: $!";

# set executable flag
chmod(0755, $outfile);

# That's all folks...
print "Merge done.\n";
exit 0;
