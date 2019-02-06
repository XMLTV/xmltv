#!perl -w
#
# This is a quick XMLTV shell routing to use with the windows exe
#
# A single EXE is needed to allow sharing of modules and dlls of all the
# programs.  If PerlAPP was run on each one, the total size would be more than
# 12MB, even leaving out PERL56.DLL!
#
# Perlapp allows you to attach pathed files, but you need the same path
# to access them.  The Makefile creates a text file of these files which is
# used to build a translation table, allowing users to just type the app name
# and not the development path.
#
# Robert Eden rmeden@yahoo.com
#

use File::Basename;
use Carp;

$Carp::MaxEvalLen=40; # limit confess output

#
# this check should not be done, at least not this way. it prevents some regular expressions!
#
## Check for error of running from 'Run' dialogue box with redirection,
## which Run doesn't understand,
##
#if (grep /[<>|]/, @ARGV) {
#    warn <<END
#The command line:
#
#$0 @ARGV
#
#contains redirections, so should be run from a command prompt window.
#In general, it's a good idea to always run xmltv from a command prompt
#so that you can see any errors and warnings produced.
#END
#      ;
#    sleep 10;
#    exit 1;
#}

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
my $VERSION = '0.5.70';
if (index('--version', $cmd) == 0 and length $cmd >= 3) {
    print "xmltv $VERSION\n";
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
        my $dir = dirname(PerlApp::exe()); # get full program path
        $dir =~ s!\\!/!g;      # use / not \
#       die "EXE path contains spaces.  This is known to cause problems.\nPlease move xmltv.exe to a different directory\n" if $dir =~ / /;
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
   do $exe;
   print STDERR $@ if length($@);
   exit 1 if length($@);
   exit 0;
}

#
# scan through attached files and execute program if found
#
$files=PerlApp::get_bound_file("exe_files.txt");
foreach my $exe (split(/ /,$files))
{
    next unless length($exe)>3; #ignore trash
    $_=$exe;
    s!^.+/!!g;
    $cmds{$_}=1;  # build command list (just in case)

    next unless $cmd eq $_;

#
# execute our command
#
    $0 = $_;        # set $0 to our script
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

