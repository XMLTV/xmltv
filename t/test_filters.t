#!/usr/bin/perl -w
#
# Run lots of filter programs on lots of inputs and check the output
# is as expected.  We do not check the stderr messages, and we do not
# allow for filters that return an error code.  In fact, they're not
# filters at all: we assume that each can take an input filename and
# the --output option.
#
# -- Ed Avis, epa98@doc.ic.ac.uk, 2002-02-14
#

use strict;
use Getopt::Long;
use XMLTV::Usage <<END
$0: test suite for filter programs
usage: $0 [--tests-dir DIR] [--cmds-dir DIR] [--verbose]
END
;

my @cmds
  = (
     [ 'tv_cat' ],
     [ 'tv_extractinfo_en' ],
     [ 'tv_grep', 'a' ],
     [ 'tv_grep', '--category', 'b' ],
     [ 'tv_grep', '-i', '--last-chance', 'c' ],
     [ 'tv_grep', '--new' ],
     [ 'tv_grep', '--channel-name', 'd' ],
     [ 'tv_grep', '--channel-id', 'channel4.com' ],
     [ 'tv_grep', '--on-after', '2002-02-05' ],
     [ 'tv_grep', '--eval', 'scalar keys %$_ > 5' ],
     [ 'tv_grep', '--category', 'e', '--and', '--title', 'f' ],
     [ 'tv_grep', '--category', 'g', '--or', '--title', 'h' ],
     [ 'tv_grep', '-i', '--category', 'i', '--title', 'j' ],
     [ 'tv_grep', '-i', '--category', 'i', '--title', 'h' ],
     [ 'tv_sort' ],
     [ 'tv_sort', '--by-channel' ],
     [ 'tv_to_latex' ],
    );

my $tests_dir = 't/data';     # directory test files live in
die "no directory $tests_dir" if not -d $tests_dir;
my $cmds_dir = 'blib/script'; # directory filter programs live in
die "no directory $cmds_dir" if not -d $cmds_dir;
my $verbose = 0;
GetOptions('tests-dir=s' => \$tests_dir, 'cmds-dir=s' => \$cmds_dir,
	   'verbose' => \$verbose)
  or usage(0);
my @tests = <$tests_dir/*.xml>;
die "no test cases (*.xml) found in $tests_dir"
  if not @tests;
foreach (@tests) {
    s!^\Q$tests_dir\E/!!o or die;
}

# Any other environment needed (relative to $tests_dir)
$ENV{PERL5LIB} .= ":..";

my %seen;
my $num_tests = (scalar @cmds) * (scalar @tests);
print "1..$num_tests\n";
my $test_num = 0;
foreach my $cmd (@cmds) {
    foreach my $test (@tests) {
	++ $test_num;
	my $test_name = join('_', @$cmd, $test);
	$test_name =~ tr/A-Za-z0-9/_/sc;
	die "two tests munge to $test_name"
	  if $seen{$test_name}++;

	my $in       = "$tests_dir/$test";
	my $base     = "$tests_dir/$test_name";
	my $expected = "$base.expected";
	my $out      = "$base.out";
	my $err      = "$base.err";

	my @cmd = (@$cmd, $in, '--output', $out);
	$cmd[0] = "$cmds_dir/$cmd[0]";
	if ($verbose) {
	    print STDERR "test $test_num: @cmd\n";
	}

	# Redirect stderr to file $err.
	open(OLDERR, '>&STDERR') or die "cannot dup stderr: $!\n";
	if (not open(STDERR, ">$err")) {
	    print OLDERR "cannot write to $err: $!\n";
	    exit(1);
	}

	# Run the command.
	if (system(@cmd)) {
	    my ($status, $sig, $core) = ($? >> 8, $? & 127, $? & 128);
	    if ($sig) {
		die "@cmd killed by signal $sig, aborting";
	    }
	    warn "@cmd failed: $status, $sig, $core\n";
	    print "not ok $test_num\n";
	}

	# Restore old stderr.
	if (not close(STDERR)) {
	    print OLDERR "cannot close $err: $!\n";
	    exit(1);
	}
	if (not open(STDERR, ">&OLDERR")) {
	    print OLDERR "cannot dup stderr back again: $!\n";
	    exit(1);
	}

	if (-e $expected) {
	    if (-e $out) {
		open(OUT, $out) or die "cannot open $out: $!";
		open(EXPECTED, $expected) or die "cannot open $expected: $!";
		local $/ = undef;
		my $out_content = <OUT>;
		my $expected_content = <EXPECTED>;
		
		if ($out_content ne $expected_content) {
		    warn "failure for @cmd, see $base.*\n";
		    print "not ok $test_num\n";
		}
		else {
		    print "ok $test_num\n";
		    unlink $out or warn "cannot unlink $out: $!";
		    unlink $err or warn "cannot unlink $err: $!";
		}
	    }
	    else {
		warn "failure for @cmd, failed to produce output $out, see $base.err\n";
		print "not ok $test_num\n";
	    }
	}
	else {
	    # This should happen after adding a new test case, never
	    # when just running the tests.
	    #
	    warn "creating $expected\n";
	    rename($out, $expected)
	      or die "cannot rename $out to $expected: $!";
	    unlink $err or warn "cannot unlink $err: $!";
	}
    }
}
die if $test_num != $num_tests;
