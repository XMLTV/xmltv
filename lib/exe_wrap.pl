#!perl -w
#
# $Id$
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
print STDERR "Timezone is $ENV{TZ}\n";


$cmd = shift || "";

#
# check for tv_grab_nz
#
if ($cmd eq 'tv_grab_nz') {
    die <<END
Sorry, tv_grab_nz is not available in this Windows binary release,
although if you have Python installed you will be able to get it from
the xmltv source distribution.

It is hoped that future Windows binaries for xmltv will include a way
to run tv_grab_nz.
END
  ;
};

#
# some programs use a "share" directory
#
if ($cmd eq 'tv_grab_uk'
 or $cmd eq 'tv_grab_uk_rt'
 or $cmd eq 'tv_grab_it'
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
        print "adding '--share=$dir'\n";
        push @ARGV,"--share",$dir;
    }
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
    push @cmds,$_;  # build command list (just in case)

    next unless $cmd eq $_;

#
# execute our command
#
    $0 = $_;        # set $0 to our script
    $r = require $exe;
    exit $r;
}

#
# command not found, print error
#
if ($cmd eq "" )
   {
	die "you must specify the program to run, for example: $0 tv_grab_fi --configure\n";
    }
else
   {
	die "$cmd is not a valid command. Valid commands are:\n".join(" ",@cmds)."\n";
   }

