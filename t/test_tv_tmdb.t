#!/usr/bin/perl
#
# Run tv_tmdb on various input files and check the output is as expected.
#
# -- Geoff Westcott <honir999@gmail.com>, 2021-12-21
# -- Nick Morrott <knowledgejunkie@gmail.com>, 2019-02-28

use warnings;
use strict;
use Getopt::Long;
use Cwd;
use File::Temp qw(tempdir);
use File::Copy;
use XMLTV::Usage <<END
$0: test suite for tv_tmdb
usage: $0 [--tests-dir DIR] [--cmds-dir DIR] [--verbose]
END
  ;

my $tests_dir = 't/data-tv_tmdb'; # where to find input XML files
die "no directory $tests_dir" if not -d $tests_dir;
my $cmds_dir = 'blib/script'; # directory tv_tmdb lives in
die "no directory $cmds_dir" if not -d $cmds_dir;
my $verbose = 0;

GetOptions('tests-dir=s' => \$tests_dir, 'cmds-dir=s' => \$cmds_dir,
	   'verbose' => \$verbose)
  or usage(0);
usage(0) if @ARGV;

my $tmpDir = tempdir(CLEANUP => 1);
#my $tmpDir = "/tmp/jv1"; mkdir($tmpDir);


my $apikey = '';
# does apikey file exist?
my $f = "$cmds_dir/apikey";
if (-f -r "$f") { 
	open(my $fh, $f) or die "Could not open file '$f' $!";
	$apikey = <$fh>;
	chomp($apikey) if $apikey;
	close($fh);
}
if ( not $apikey ) { print STDERR "no api key found - $cmds_dir/apikey - run aborted \n"; exit(0); }


my @inputs = <$tests_dir/*.xml>;
my @inputs_gz = <$tests_dir/*.xml.gz>; s/\.gz$// foreach @inputs_gz;
@inputs = sort (@inputs, @inputs_gz);
die "no test cases (*.xml, *.xml.gz) found in $tests_dir"
  if not @inputs;

print '1..', (scalar(@inputs)), "\n";

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

    use File::Basename;
    my $input_basename = File::Basename::basename($input,  ".xml");
    my $output="$tmpDir/".File::Basename::basename($input)."-output.xml";

    # Build command line for test
    my $cmd="$cmds_dir/tv_tmdb --apikey $apikey --quiet --config-file $tests_dir/configs/$input_basename.conf --output '$output' '$input' 2>&1";
      
    #print STDERR "\nRUN:$cmd\n";
    my $r = system($cmd);

    # Check command return status.
    if ($r) {
	my ($status, $sig, $core) = ($? >> 8, $? & 127, $? & 128);
	if ($sig) {
	    die "$cmd killed by signal $sig, aborting";
	}
	warn "$cmd failed: $status, $sig, $core\n";
	print "not ok $n\n";
	next;
    }

    open(FD, "$input-expected") || die "$input-expected:$!";
    open(OD, "$output") || die "$output:$!";
    while(<FD>) {
	my $in=$_;
	my $out=<OD>;
	chomp($in);
	chomp($out);

	if ( $in ne $out ) {
	    #system("cp $dir/output.xml /tmp/$n-output");
	    #system("cp $input-expected /tmp/$n-expected");
	    warn "$input failed to match expected ('$in' != '$out')\n";
	    print "not ok $n\n";
	    last;
	}
    }
    close(FD);
    close(OD);

    print "ok $n\n";
}

