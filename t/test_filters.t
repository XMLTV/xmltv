#!/usr/bin/perl -w
#
# Run lots of filter programs on lots of inputs and check the output
# is as expected.  We do not check the stderr messages, and we do not
# allow for filters that return an error code.  In fact, they're not
# filters at all: we assume that each can take an input filename and
# the --output option.
#
# -- Ed Avis, ed@membled.com, 2002-02-14
#

use strict;
use Getopt::Long;
use File::Copy;
use XMLTV::Usage <<END
$0: test suite for filter programs
usage: $0 [--tests-dir DIR] [--cmds-dir DIR] [--verbose]
END
;

sub run( $$$$ );
sub read_file( $ );

# Commands to run.  For each command and input file we have an
# 'expected output' file to compare against.  Also each command has an
# 'idempotent' flag.  If this is true then we check that (for example)
# tv_cat | tv_cat has the same effect as tv_cat, for all input files.
#
# A list of pairs: the first element of the pair is a list of command
# and arguments, the second is the idempotent flag.
#
my @cmds
  = (
     [ [ 'tv_cat'                                              ], 1 ],
     [ [ 'tv_extractinfo_en'                                   ], 1 ],
# We assume that most usages of tv_grep are idempotent on the sample
# files given.  But see BUGS section of manual page.
     [ [ 'tv_grep', 'a'                                        ], 1 ],
     [ [ 'tv_grep', '--category', 'b'                          ], 1 ],
     [ [ 'tv_grep', '-i', '--last-chance', 'c'                 ], 1 ],
     [ [ 'tv_grep', '--premiere', ''                           ], 1 ],
     [ [ 'tv_grep', '--new'                                    ], 1 ],
     [ [ 'tv_grep', '--channel-name', 'd'                      ], 1 ],
     [ [ 'tv_grep', '--channel-id', 'channel4.com'             ], 1 ],
     [ [ 'tv_grep', '--on-after', '2002-02-05'                 ], 1 ],
     [ [ 'tv_grep', '--eval', 'scalar keys %$_ > 5'            ], 0 ],
     [ [ 'tv_grep', '--category', 'e', '--and', '--title', 'f' ], 1 ],
     [ [ 'tv_grep', '--category', 'g', '--or', '--title', 'h'  ], 1 ],
     [ [ 'tv_grep', '-i', '--category', 'i', '--title', 'j'    ], 1 ],
     [ [ 'tv_grep', '-i', '--category', 'i', '--title', 'h'    ], 1 ],
     [ [ 'tv_sort'                                             ], 1 ],
     [ [ 'tv_sort', '--by-channel'                             ], 1 ],
     [ [ 'tv_to_latex'                                         ], 0 ],
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
my @tests_gz = <$tests_dir/*.xml.gz>; s/\.gz$// foreach @tests_gz;
@tests = (@tests, @tests_gz);
die "no test cases (*.xml, *.xml.gz) found in $tests_dir"
  if not @tests;
foreach (@tests) {
    s!^\Q$tests_dir\E/!!o or die;
}

# Any other environment needed (relative to $tests_dir)
$ENV{PERL5LIB} .= ":..";

my %seen;

# Count total number of tests to run.
my $num_tests = 0;
foreach (@cmds) {
    $num_tests += scalar @tests;
    $num_tests += scalar @tests if $_->[1]; # idem. test
}
print "1..$num_tests\n";
my $test_num = 0;
foreach my $pair (@cmds) {
    my ($cmd, $idem) = @$pair;
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

	# Gunzip automatically before testing, gzip back again
	# afterwards.  Keys matter, values do not.
	#
	my (%to_gzip, %to_gunzip);
	foreach ($in, $expected) {
	    my $gz = "$_.gz";
	    if (not -e and -e $gz) {
		$to_gunzip{$gz}++ && die "$gz seen twice";
		$to_gzip{$_}++ && die "$_ seen twice";
	    }
	}
	system 'gzip', '-d', keys %to_gunzip if %to_gunzip;

	# To unlink when tests are done - this hash can change.
	# Again, only keys are important.  (FIXME should encapsulate
	# as 'Set' datatype.)
	#
	my %to_unlink = ($out => undef, $err => undef);

	my $out_content; # contents of $out, to be filled in later

	my @cmd = @$cmd;
	$cmd[0] = "$cmds_dir/$cmd[0]";
	$cmd[0] =~ s!/!\\!g if $^O eq 'MSWin32';
	if ($verbose) {
	    print STDERR "test $test_num: @cmd\n";
	}
	my $okay = run(\@cmd, $in, $out, $err);
	# assume: if $okay then -e $out.

	my $have_expected = -e $expected;
	if (not $okay) {
	    print "not ok $test_num\n";
	    delete $to_unlink{$out}; delete $to_unlink{$err};
	}
	elsif ($okay and not $have_expected) {
	    # This should happen after adding a new test case, never
	    # when just running the tests.
	    #
	    warn "creating $expected\n";
	    copy($out, $expected)
	      or die "cannot copy $out to $expected: $!";
	    # Don't print any message - the test just 'did not run'.
	}
	elsif ($okay and $have_expected) {
	    $out_content = read_file($out);
	    my $expected_content = read_file($expected);

	    if ($out_content ne $expected_content) {
		warn "failure for @cmd, see $base.*\n";
		print "not ok $test_num\n";
		$okay = 0;
		delete $to_unlink{$out}; delete $to_unlink{$err};
	    }
	    else {
		print "ok $test_num\n";
	    }
	}
	else { die }

	if ($idem) {
	    ++ $test_num;
	    if ($okay) {
		die if not -e $out;
		# Run the command again, on its own output.
		my $twice_out = "$base.twice_out";
		my $twice_err = "$base.twice_err";
		$to_unlink{$twice_out} = $to_unlink{$twice_err} = undef;
		
		my $twice_okay = run(\@cmd, $out, $twice_out, $twice_err);
		# assume: if $twice_okay then -e $twice_out.

		if (not $twice_okay) {
		    print "not ok $test_num\n";
		    delete $to_unlink{$out};
		    delete $to_unlink{$twice_out};
		    delete $to_unlink{$twice_err};
		}
		else {
		    my $twice_out_content = read_file($twice_out);
		    my $ok;
		    if (not defined $out_content) {
			warn "cannot run idempotence test for @cmd\n";
			$ok = 0;
		    }
		    elsif ($twice_out_content ne $out_content) {
			warn "failure for idempotence of @cmd, see $base.*\n";
			$ok = 0;
		    }
		    else { $ok = 1 }

		    if (not $ok) {
			print "not ok $test_num\n";
			delete $to_unlink{$out};
			delete $to_unlink{$twice_out};
			delete $to_unlink{$twice_err};
		    }
		    else {
			print "ok $test_num\n";
		    }
		}
	    }
	    else {
		warn "skipping idempotence test for @cmd on $in\n";
		# Do not print 'ok' or 'not ok'.
	    }
	}

	foreach (keys %to_unlink) {
	    (not -e) or unlink or warn "cannot unlink $_: $!";
	}
	system 'gzip', keys %to_gzip if %to_gzip;
    }
}
die "ran $test_num tests, expected to run $num_tests"
  if $test_num != $num_tests;


# run()
#
# Run a command redirecting input and output.  This is not fully
# general - it relies on the --output option working for redirecting
# output.  (Don't know why I decided this, but it does.)
#
# Parameters:
#   (ref to) list of command and arguments
#   input filename
#   output filename
#   error output filename
#
# Dies if error opening or closing files, or if the command is killed
# by a signal.  Otherwise creates the output files, and returns
# success or failure of the command.
#
sub run( $$$$ ) {
    my ($cmd, $in, $out, $err) = @_; die if not defined $cmd;
    my @cmd = (@$cmd, $in, '--output', $out);

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
	return 0;
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

    return 1;
}


sub read_file( $ ) {
    my $f = shift;
    local $/ = undef;
    local *FH;
    open(FH, $f) or die "cannot open $f: $!";
    my $content = <FH>;
    close FH or die "cannot close $f: $!";
    return $content;
}
