#!perl -w
#
# This is a quick XMLTV shell routing to use with the windows exe
#
# A single EXE is needed to allow sharing of modules and dlls of all the
# programs.
#
# Now uses PAR::Packer to build the exe.  It takes a very long time on first run, which can
# appear to be a problem. 
#
# There currently isn't a way for PAR::Packer to warn users about a first time run.
# I've modified the boot.c file in Par::Packer to do that.  It's not great as it also
# displays when building, but it's good enough.  Here's what the change is (for documenation purposes)
# I'm trying to work  with the PAR::Packer folks for a better fix.
#
# boot.c:188
#    rc = my_mkdir(stmpdir, 0700);
#// 2021-01-18 rmeden hack to print a message on first run
#	if ( rc == 0 ) fprintf(stderr,"Note: This will take a while on first run\n");
#// rmeden
#    if ( rc == -1 && errno != EEXIST) {
#
#
# Robert Eden rmeden@yahoo.com
#

use File::Basename;
use Carp;
use XMLTV;
use Date::Manip;
use DateTime;
use Params::Validate;
use Date::Language;
use Class::MethodMaker;
use Class::MethodMaker::Engine;

$Carp::MaxEvalLen=40; # limit confess output

#
# check for --quiet
#
my $opt_quiet=0;
foreach (@ARGV) {$opt_quiet = 1 if /--quiet/i };

#
# get/check time zone
#
unless (exists $ENV{TZ})
{
    my $now    =  time();
    my $lhour  = (localtime($now))[2];
    my $ghour  = (   gmtime($now))[2];
    my $tz     = ($lhour - $ghour);
       $tz    -= 24 if $tz >  12;
       $tz    += 24 if $tz < -12;
       $tz= sprintf("%+03d00",$tz);

       $ENV{TZ}= $tz;

} #timezone
print STDERR "Timezone is $ENV{TZ}\n" unless $opt_quiet;


$cmd = shift || "";

# --version (and abbreviations thereof)
if (index('--version', $cmd) == 0 and length $cmd >= 3) {
    print "xmltv $XMLTV::VERSION\n";
    exit;
}

#
# some programs use a "share" directory
#
if ($cmd eq 'tv_grab_na_dd',
 or $cmd eq 'tv_grab_na_icons',
 )
{
    unless (grep(/^--share/i,@ARGV))  # don't add our --share if one supplied
    {
        my $dir = dirname($0); # get full program path
        $dir =~ s!\\!/!g;      # use / not \
        $dir .= "/share/xmltv";
    	unless (-d $dir )
    	    {
	        die "directory $dir not found\n If not kept with the executable, specify with --share\n"
	        }
        print STDERR "adding '--share=$dir'\n" unless $opt_quiet;
        push @ARGV,"--share",$dir;
    }
}

#
# special hack, allow "exec" to execute an arbitrary script
# This will be used to allow XMLTV.EXE modules to be used on beta code w/o an alpha exe
#
# Note, no extra modules are included in the EXE.  There is no guarantee this will work
# it is an unsupported hack.
#
# syntax XMLTV.EXE exec filename --options
#
if ($cmd eq 'exec')
{
   my $exe=shift;
   $0=$exe;
   print "doing $exe\n";
   print STDERR "STDERR doing $exe\n";
   do "./$exe";
   print STDERR $@ if length($@);
   print "STDOUT $@"  if length($@);
   exit 1 if length($@);
   exit 0;
}

#
# scan through attached files and execute program if found
#

#main thread!

$files=PAR::read_file("exe_files.txt");
foreach my $exe (split(/ /,$files))
{
    next unless length($exe)>3; #ignore trash
    $_=$exe;
    s!^.+/!!g;
    $cmds{$_}=1;  # build command list (just in case)

    next unless $cmd eq $_;

	$exe="script/$cmd";
	
#
# execute our command
#
    do $exe;
    print STDERR $@ if length($@);
    exit 1 if length($@);
    exit 0;
}

#
# command not found, print error
#
if ($cmd eq "" )
   {
	print STDERR "you must specify the program to run\n    for example: $0 tv_grab_fi --configure\n";
    }
else
   {
    print STDERR "$cmd is not a valid command.\n";
   }

print STDERR "Valid commands are:\n";
@cmds=sort keys %cmds;
$rows = int($#cmds / 3)+1;

map {$_='' unless defined $_} @cmds[0..($rows*3+2)];
unshift @cmds,undef;

foreach (1..$rows)
{
   printf STDERR "    %-20s %-20s %-20s\n",@cmds[$_,$rows+$_,2*$rows+$_];
}
exit 1;

