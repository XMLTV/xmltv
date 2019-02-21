#!/usr/bin/perl
#
# Run tv_augment against various input files and check the generated output
# is as expected.
#
# This framework (borrowed from test_tv_imdb.t) tests each type of automatic
# and user rule for tv_augment (lib/Augment.pm) by comparing the output
# generated from input data against the expected output for each rule type.
#
# -- Nick Morrott, knowledgejunkie@gmail.com, 2016-07-07

use warnings;
use strict;
use Getopt::Long;
use Cwd;
use File::Temp qw(tempdir);
use File::Copy;
use XMLTV::Usage <<END
$0: test suite for tv_augment
usage: $0 [--tests-dir DIR] [--cmds-dir DIR] [--verbose]
END
;

my $tests_dir = 't/data-tv_augment'; # where to find input XML files
die "no directory $tests_dir" if not -d $tests_dir;
my $cmds_dir = 'blib/script'; # directory tv_augment lives in
die "no directory $cmds_dir" if not -d $cmds_dir;
my $verbose = 0;

GetOptions('tests-dir=s' => \$tests_dir,
           'cmds-dir=s'  => \$cmds_dir,
           'verbose'     => \$verbose)
        or usage(0);

usage(0) if @ARGV;

my $tmpDir = tempdir(CLEANUP => 1);
# my $tmpDir = tempdir(CLEANUP => 0);

my @inputs = <$tests_dir/*.xml>;
@inputs = sort (@inputs);
die "no test cases (*.xml) found in $tests_dir"
  if not @inputs;

my $numtests = scalar @inputs;
print "1..$numtests\n";

my $n = 0;
INPUT:
foreach my $input (@inputs) {
    ++$n;

    use File::Basename;
    my $input_basename = File::Basename::basename($input);
    my $output="$tmpDir/".$input_basename."-output";

    my $cmd="$cmds_dir/tv_augment --rule $tests_dir/rules/test_tv_augment.rules --config $tests_dir/configs/$input_basename.conf --input $input --output $output 2>&1";
    # my $cmd="perl -I blib/lib $cmds_dir/tv_augment --rule $tests_dir/rules/test_tv_augment.rules --config $tests_dir/configs/$input_basename.conf --input $input --output $output --log $tmpDir/$input_basename.log --debug 5 >$tmpDir/$input_basename.debug 2>&1";

    my $r = system($cmd);

    # Check command return status.
    if ($r) {
        my ($status, $sig, $core) = ($? >> 8, $? & 127, $? & 128);
        if ($sig) {
            die "$cmd killed by signal $sig, aborting";
        }
        warn "$cmd failed: $status, $sig, $core\n";
        print "not ok $n\n";
        next INPUT;
    }

    open(FD, "$input-expected") || die "$input-expected:$!";
    open(OD, "$output") || die "$output:$!";
    my $line = 0;
    my $failed = 0;
    INPUT:
    while(<FD>) {
       my $in=$_;
       $line++;

       # ignore single line XML comments in "expected" data
       next INPUT if ($in =~ m/\s*<!--/);

       my $out=<OD>;
       chomp($in);
       chomp($out);

        if ( $in ne $out ) {
            warn "$input ($line) failed to match expected ('$in' != '$out')\n";
            $failed = 1;
            last INPUT;
        }
    }
    close(FD);
    close(OD);

    if ($failed) {
        print "not ok $n\n";
    }
    else {
        print "ok $n\n";
    }
}

