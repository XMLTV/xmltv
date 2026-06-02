#!/usr/bin/perl -w
#
# Helper to re-generate test.conf from output of
#
#   tv_grab_fi --list-channels
#
use 5.040;
use strict;
use warnings;

# required for \*STDIN
use feature "refaliasing";

use File::Slurp qw(read_file);
use HTML::Entities qw(decode_entities);

my $contents = read_file(\*STDIN);
my @matches  = ($contents =~ m,id="([^"]+)">\s+<display-name lang="..">([^<]+)</,mg);

while (my($id, $name) = splice(@matches, 0, 2)) {
  $name = decode_entities($name);
  say "##channel ${id} ${name}";
}
