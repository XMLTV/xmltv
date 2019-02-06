#!/usr/bin/perl
#
# Run tv_split on some input files and check the output looks
# reasonable.  This is not done by diffing against expected output but
# by reading the files generated and making sure channels and dates
# seem to match.
#
# -- Ed Avis, ed@membled.com, 2003-10-04

use warnings;
use strict;
use Getopt::Long;
use Cwd;
use File::Temp qw(tempdir);
use File::Copy;
use XMLTV::Usage <<END
$0: test suite for tv_split
usage: $0 [--tests-dir DIR] [--verbose]
END
  ;

my $tests_dir = 't/data'; # where to find input XML files
die "no directory $tests_dir" if not -d $tests_dir;
my $cmds_dir = 'blib/script'; # directory tv_split lives in
die "no directory $cmds_dir" if not -d $cmds_dir;
my $verbose = 0;

GetOptions('tests-dir=s' => \$tests_dir, 'cmds-dir=s' => \$cmds_dir,
	   'verbose' => \$verbose)
  or usage(0);
usage(0) if @ARGV;

my @inputs = <$tests_dir/*.xml>;
my @inputs_gz = <$tests_dir/*.xml.gz>; s/\.gz$// foreach @inputs_gz;
@inputs = sort (@inputs, @inputs_gz);
die "no test cases (*.xml, *.xml.gz) found in $tests_dir"
  if not @inputs;

print '1..', (scalar @inputs), "\n";
my $n = 0;
my $old_cwd;
INPUT: foreach my $input (@inputs) {
    ++$n;

    if (defined $old_cwd) {
	chdir $old_cwd or die "cannot chdir to $old_cwd: $!";
    }
    else {
	$old_cwd = cwd;
    }

    # Quick and dirty checking of XML files.  Before we start, read
    # the input XML and note how many programmes of each kind.
    #
    my %input;
    open(FH, $input) or die "cannot open $input: $!";
    while (<FH>) {
	next unless /<programme/;

	/start="(.+?)"/ or die "$input:$.: no start\n";
	my $start = $1;
	$start =~ /^\d{4}(\d{2})/
	  or die "$input:$.: don't understand start time $start\n";
	my $month = $1;

	/channel="(.+?)"/ or die "$input:$.: no channel\n";
	my $channel = $1;
	++$input{"channel$channel-month$month"};
    }
    close FH or warn "cannot close $input: $!";

    # Make temporary directory and split into it.
    my $dir = tempdir(CLEANUP => 1);
    die if not -d $dir;
    die 'gzipped files not supported (could add)'
      if $input =~ /[.]gz$/;
    my @cmd = ("$cmds_dir/tv_split",
	       '--output', "$dir/channel%channel%-month%m.out",
	       $input);
    my $r = system @cmd;

    # Check command return status.
    if ($r) {
	my ($status, $sig, $core) = ($? >> 8, $? & 127, $? & 128);
	if ($sig) {
	    die "@cmd killed by signal $sig, aborting";
	}
	warn "@cmd failed: $status, $sig, $core\n";
	print "not ok $n\n";
	next;
    }

    # Read the files generated.
    chdir $dir or die "cannot chdir to $dir: $!";
    my %found;
    foreach my $f (<*.out>) {
	open(FH, $f) or die "cannot open $f: $!";
	(my $template = $f) =~ s/[.]out$// or die;
	my (%seen_channel_elem, %used_channel);
	while (<FH>) {
	    if (/<channel/) {
		/id="(.+?)"/ or die "$f:$.: no id\n";
		$seen_channel_elem{$1} = 1;
	    }
	    elsif (/<programme/) {
		/start="(.+?)"/ or die "$f:$.: no start\n";
		my $start = $1;
		$start =~ /^\d{4}(\d{2})/
		  or die "$f:$.: don't understand start time $start\n";
		my $month = $1;

		/channel="(.+?)"/ or die "$f:$.: no channel\n";
		my $channel = $1;
		$used_channel{$channel} = 1;

		if ("channel$channel-month$month" ne $template) {
		    warn "in $f saw what should be channel$channel-month$month\n";
		    print "not ok $n\n";
		    next INPUT;
		}

		++$found{$template};
	    }
	}
	close FH or warn "cannot close $f: $!";

	# We don't check that every channel used has a <channel>
	# element (it might not have been in the input files) but we
	# do check that every <channel> written is used for at least
	# one programme.
	#
	# (We shouldn't do this if tv_split has not been asked to
	# split by channel, but at present all the tests we run do
	# have %channel.)
	#
	foreach (sort keys %seen_channel_elem) {
	    if (not $used_channel{$_}) {
		warn "in $f saw <channel> for $_ but it's used for no programmes\n";
		print "not ok $n\n";
		next INPUT;
	    }
	}
    }


    # We've read each output file and checked the programmes it does
    # contain have the right times; now check that every programme in
    # the input has been given to an output file.
    #
    # (We don't check the contents of the programme elements or other
    # details of the XML - we assume that if XMLTV.pm had a serious
    # bug it would have been caught in the tests of other filter
    # programs.)
    #
    foreach (keys %input) {
	if ($input{$_} != $found{$_}) {
	    warn "different number of programmes for template $_\n";
	    print "not ok $n\n";
	    next INPUT;
	}
    }
    foreach (keys %found) {
	if (not exists $input{$_}) {
	    warn "generated template $_ not in input\n";
	    print "not ok $n\n";
	    next INPUT;
	}
    }

    print "ok $n\n";
}

