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

# Check for error of running from 'Run' dialogue box with redirection,
# which Run doesn't understand,
#
if (grep /[<>|]/, @ARGV) {
    warn <<END
The command line:

$0 @ARGV

contains redirections, so should be run from a command prompt window.
In general, it's a good idea to always run xmltv from a command prompt
so that you can see any errors and warnings produced.
END
      ;
    sleep 10;
    exit 1;
}

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

# --version (and abbreviations thereof)
my $VERSION = '0.5.31';
if (index('--version', $cmd) == 0 and length $cmd >= 3) {
    print "xmltv $VERSION\n";
    exit;
}

#
# some grabbers aren't included
#
if ($cmd =~ /^tv_grab_(?:nz|jp|se)$/) {
    die <<END
Sorry, $cmd is not available in this Windows binary release, although
it is included in xmltv source releases.

END
  ;
};

#
# some programs use a "share" directory
#
if ($cmd eq 'tv_grab_uk_rt'
 or $cmd eq 'tv_grab_it'
 or $cmd eq 'tv_grab_nl'
 or $cmd eq 'tv_grab_de_tvtoday'
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
        print STDERR "adding '--share=$dir'\n";
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
    $cmds{$_}=1;  # build command list (just in case)

    next unless $cmd eq $_;

#
# execute our command
#
    $0 = $_;        # set $0 to our script

    # Would like to use do() but there is no reliable way to check for
    # errors.
    #
    undef $/;
    open EXE, $exe or die "cannot open $exe: $!";
    my $code = <EXE>;
    eval $code;
    die $@ if $@;
    exit;
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

