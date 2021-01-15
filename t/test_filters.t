#!/usr/bin/perl -w
#
# Run lots of filter programs on lots of inputs and check the output
# is as expected.  Stderr is checked if there is an 'expected_err'
# file but we do not allow for filters that return an error code.  In
# fact, they're not filters at all: we assume that each can take an
# input filename and the --output option.
#
# -- Ed Avis, ed@membled.com, 2002-02-14

use strict;
use Getopt::Long;
use File::Copy;
use XMLTV::Usage <<END
$0: test suite for filter programs
usage: $0 [--tests-dir DIR] [--cmds-dir DIR] [--verbose] [--full] [cmd_regexp...]
END
;

sub run( $$$$ );
sub read_file( $ );

# tv_to_latex depends on Lingua::Preferred and that module's behaviour
# is influenced by the current language.
#
$ENV{LANG} = 'C';

my $tests_dir = 't/data';     # directory test files live in
die "no directory $tests_dir" if not -d $tests_dir;
my $cmds_dir = 'blib/script'; # directory filter programs live in
die "no directory $cmds_dir" if not -d $cmds_dir;
my $verbose = 0;

# Whether to run the full tests, or just a few.
my $full = 0;

GetOptions('tests-dir=s' => \$tests_dir, 'cmds-dir=s' => \$cmds_dir,
	   'verbose' => \$verbose, 'full' => \$full)
  or usage(0);

if (not $full) {
    warn "running small test suite, use $0 --full for the whole lot\n";
}

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
     [ [ 'tv_cat'                                                ], 1 ],
     [ [ 'tv_extractinfo_en'                                     ], 1 ],
     # We assume that most usages of tv_grep are idempotent on the sample
     # files given.  But see BUGS section of manual page.
     [ [ 'tv_grep', '--channel-name', 'd'                        ], 1 ],
     [ [ 'tv_grep', '--not', '--channel-name', 'd'               ], 1 ],
     [ [ 'tv_sort'                                               ], 1 ],
     [ [ 'tv_sort', '--by-channel'                               ], 1 ],
     [ [ 'tv_to_latex'                                           ], 0 ],
     [ [ 'tv_to_text',                                           ], 0 ],
     [ [ 'tv_remove_some_overlapping'                            ], 1 ],
     [ [ 'tv_grep', '--on-after', '200302161330 UTC'             ], 1 ],
     [ [ 'tv_grep', '--on-before', '200302161330 UTC'            ], 1 ],
    );

if ($full) {
    push @cmds,
      (
       [ [ 'tv_grep', '--channel', 'xyz', '--or', '--channel', 'b' ], 1 ],
       [ [ 'tv_grep', '--channel', 'xyz', '--or', '--not', '--channel', 'b' ], 1 ],
       [ [ 'tv_grep', '--previously-shown', ''                     ], 1 ],
       [ [ 'tv_grep', 'a'                                          ], 1 ],
       [ [ 'tv_grep', '--category', 'b'                            ], 1 ],
       [ [ 'tv_grep', '-i', '--last-chance', 'c'                   ], 1 ],
       [ [ 'tv_grep', '--premiere', ''                             ], 1 ],
       [ [ 'tv_grep', '--new'                                      ], 1 ],
       [ [ 'tv_grep', '--channel-id', 'channel4.com'               ], 1 ],
       [ [ 'tv_grep', '--not', '--channel-id', 'channel4.com'      ], 1 ],
       [ [ 'tv_grep', '--on-after', '2002-02-05 UTC'               ], 1 ],
       [ [ 'tv_grep', '--eval', 'scalar keys %$_ > 5'              ], 0 ],
       [ [ 'tv_grep', '--category', 'e', '--and', '--title', 'f'   ], 1 ],
       [ [ 'tv_grep', '--category', 'g', '--or', '--title', 'h'    ], 1 ],
       [ [ 'tv_grep', '-i', '--category', 'i', '--title', 'j'      ], 1 ],
       [ [ 'tv_grep', '-i', '--category', 'i', '--title', 'h'      ], 1 ],
       [ [ 'tv_grep', '--channel-id-exp', 'sat'                    ], 1 ],
      );
}

if (@ARGV) {
    # Remaining arguments are regexps to match commands to run.
    my @new_cmds;
    my %seen;
    foreach my $arg (@ARGV) {
	foreach my $cmd (@cmds) {
	    for (join(' ', @{$cmd->[0]})) {
		push @new_cmds, $cmd if /$arg/ and not $seen{$_}++;
	    }
	}
    }
    die "no commands matched regexps: @ARGV" if not @new_cmds;
    @cmds = @new_cmds;
    print "running commands:\n", join("\n", map { join(' ', @{$_->[0]}) } @cmds), "\n";
}

# Input files we could use to build test command lines.
my @inputs = <$tests_dir/*.xml>;
my @inputs_gz = <$tests_dir/*.xml.gz>; s/\.gz$// foreach @inputs_gz;
@inputs = sort (@inputs, @inputs_gz);
die "no test cases (*.xml, *.xml.gz) found in $tests_dir"
  if not @inputs;
foreach (@inputs) {
    s!^\Q$tests_dir\E/!!o or die;
}

# We want to test multiple input files.  But it would be way OTT to
# test all permutations of all input files up to some length.  Instead
# we pick all single files and a handful of pairs.
#
my @tests;

# The input file empty.xml is special: we particularly like to use it
# in tests.  Then there are another two files we refer to by name.
#
my $empty_input = 'empty.xml';
foreach ($empty_input, 'simple.xml', 'x-whatever.xml') {
    die "file $tests_dir/$_ not found" if not -f "$tests_dir/$_";
}

# We need to track the encoding of each input file so we don't try to
# mix them on the same command line (not allowed).
#
my %input_encoding;
foreach (@inputs) {
    $input_encoding{$_} = ($_ eq 'test_livre.xml') ? 'ISO-8859-1' : 'UTF-8';
}
my %all_encodings = reverse %input_encoding;

# For historical reasons we like to have certain files at the front of
# the list.  Aargh, this is so horrible.
#
sub move_to_front( \@$ ) {
    our @l; local *l = shift;
    my $elem = shift;
    my @r;
    foreach (@l) {
	if ($_ eq $elem) {
	    unshift @r, $_;
	}
	else {
	    push @r, $_;
	}
    }
    @l = @r;
}
foreach ('dups.xml', 'clump.xml', 'amp.xml', $empty_input) {
    move_to_front @inputs, $_;
}

# Add a test to the list.  Arguments are listref of filenames, and
# optional name for this set of files.
#
sub add_test( $;$ ) {
    my ($files, $name) = @_;
    $name = join('_', @$files) if not defined $name;
    my $enc;
    foreach (@$files) {
	if (defined $enc and $enc ne $input_encoding{$_}) {
	    die 'trying to add test with two different encodings';
	}
	else {
	    $enc = $input_encoding{$_};
	}
    }
    push @tests, { inputs => $files, name => $name };
}

# A quick and effective test for each command is to run it on all the
# input files at once.  But we have to segregate them by encoding.
#
my %used_enc_name;
foreach my $enc (sort keys %all_encodings) {
    (my $enc_name = $enc) =~ tr/[A-Za-z0-9]//dc;
    die "cannot make name for encoding $enc"
      if $enc_name eq '';
    die "two encodings go to same name $enc_name"
      if $used_enc_name{$enc_name}++;
    my @files = grep { $input_encoding{$_} eq $enc } @inputs;
    if (@files == 0) {
	# Shouldn't happen.
	die "strange, no files for $enc";
    }
    elsif (@files == 1) {
	# No point adding this as it will be run as an individual
	# test.
	#
    }
    else {
	add_test(\@files, "all_$enc_name");
    }
}

# One important test is two empty files in the middle of the list.
add_test([ $inputs[1], $empty_input, $empty_input, $inputs[2] ]);

# Another special case we want to run every time.
add_test([ 'simple.xml', 'x-whatever.xml' ]);

# Another - check that duplicate channels are removed.
add_test([ 'test.xml', 'test.xml' ]);

if ($full) {
    # Test some pairs of files, but not all possible pairs.
    my $pair_limit = 4; die "too few inputs" if $pair_limit > @inputs;
    foreach my $i (0 .. $pair_limit - 1) {
	foreach my $j (0 .. $pair_limit - 1) {
	    add_test([ $inputs[$i], $inputs[$j] ]);
	}
    }

    # Then all the single files.
    add_test([ $_ ]) foreach @inputs;
}
else {
    # Check overlapping warning from tv_sort.  This ends up giving the
    # input file to every command, not just tv_sort; oh well.
    #
    # Not needed in the case when $full is true because we test every
    # individual file then.
    #
    add_test([ 'overlap.xml' ]);
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
	my @test_inputs = @{$test->{inputs}};
	++ $test_num;
	my $test_name = join('_', @$cmd, $test->{name});
	$test_name =~ tr/A-Za-z0-9/_/sc;
	die "two tests munge to $test_name"
	  if $seen{$test_name}++;

	my @cmd = @$cmd;
	my $base     = "$tests_dir/$test_name";
	my $expected = "$base.expected";
	my $out      = "$base.out";
	my $err      = "$base.err";

	# Gunzip automatically before testing, gzip back again
	# afterwards.  Keys matter, values do not.
	#
	my (%to_gzip, %to_gunzip);
	foreach (@test_inputs, $expected) {
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

        # TODO File::Spec
	$cmd[0] = "$cmds_dir/$cmd[0]";
	$cmd[0] =~ s!/!\\!g if $^O eq 'MSWin32';
	if ($verbose) {
	    print STDERR "test $test_num: @cmd @test_inputs\n";
	}

	my @in = map { "$tests_dir/$_" } @test_inputs;
	my $okay = run(\@cmd, \@in, $out, $err);
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
		warn "failure for @cmd @in, see $base.*\n";
		print "not ok $test_num\n";
		$okay = 0;
		delete $to_unlink{$out}; delete $to_unlink{$err};
	    }
	    else {
		# The output was correct: if there's also an 'expected
		# error' file check that.  Otherwise we do not check
		# what was printed on stderr.
		#
		my $expected_err = "$base.expected_err";
		if (-e $expected_err) {
		    my $err_content = read_file($err);
		    my $expected_content = read_file($expected_err);

		    if ($err_content ne $expected_content) {
			warn "failure for stderr of @cmd @in, see $base.*\n";
			print "not ok $test_num\n";
			$okay = 0;
			delete $to_unlink{$out}; delete $to_unlink{$err};
		    }
		    else {
			print "ok $test_num\n";
		    }
		}
		else {
		    # Don't check stderr.
		    print "ok $test_num\n";
		}
	    }
	}
	else { die }

	if ($idem) {
	    ++ $test_num;
	    if ($verbose) {
		print STDERR "test $test_num: ";
		print STDERR "check that @cmd is idempotent on this input\n";
	    }
	    if ($okay) {
		die if not -e $out;
		# Run the command again, on its own output.
		my $twice_out = "$base.twice_out";
		my $twice_err = "$base.twice_err";
		$to_unlink{$twice_out} = $to_unlink{$twice_err} = undef;

		my $twice_okay = run(\@cmd, [ $out ], $twice_out, $twice_err);
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
		warn "skipping idempotence test for @cmd on @test_inputs\n";
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
# Run a Perl command redirecting input and output.  This is not fully
# general - it relies on the --output option working for redirecting
# output.  (Don't know why I decided this, but it does.)
#
# Parameters:
#   (ref to) list of command and arguments
#   (ref to) list of input filenames
#   output filename
#   error output filename
#
# This routine is specialized to Perl stuff running during the test
# suite; it has the necessary -Iwhatever arguments.
#
# Dies if error opening or closing files, or if the command is killed
# by a signal.  Otherwise creates the output files, and returns
# success or failure of the command.
#
sub run( $$$$ ) {
    my ($cmd, $in, $out, $err) = @_; die if not defined $cmd;
    my @cmd = (qw(perl -Iblib/arch -Iblib/lib), @$cmd,
	       @$in,
	       '--output', $out);

    # Redirect stderr to file $err.
    open(OLDERR, '>&STDERR') or die "cannot dup stderr: $!\n";
    if (not open(STDERR, ">$err")) {
	print OLDERR "cannot write to $err: $!\n";
	exit(1);
    }

    # Run the command.
    my $r = system(@cmd);

    # Restore old stderr.
    if (not close(STDERR)) {
	print OLDERR "cannot close $err: $!\n";
	exit(1);
    }
    if (not open(STDERR, ">&OLDERR")) {
	print OLDERR "cannot dup stderr back again: $!\n";
	exit(1);
    }

    # Check command return status.
    if ($r) {
	my ($status, $sig, $core) = ($? >> 8, $? & 127, $? & 128);
	if ($sig) {
	    die "@cmd killed by signal $sig, aborting";
	}
	warn "@cmd failed: $status, $sig, $core\n";
	return 0;
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
