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
       if    ($tz == -5 ) { $tz='EST5EDT' }
#
# this should not be necessary, but DATE::MANIP doesn't always deal with
# numeric time zones correctly.  This should hold us until the fix is widely
# distributed.
#
       elsif ($tz == -6 ) { $tz='CST6CDT' }
       elsif ($tz == -7 ) { $tz='MST7MDT' }
       elsif ($tz == -8 ) { $tz='PST8PDT' }
       else               { $tz= sprintf("%+03d00",$tz) };

       $ENV{TZ}= $tz;

} #timezone
print STDERR "Timezone is $ENV{TZ}\n";

#
# This hash maps a command name to a subroutine to run.  Most of the
# subroutines will end up being 'do "whatever"' to call another Perl
# program, but some of them could be other things for components that
# aren't written in Perl.
#
my %cmds;

#
# build file list - for Perl scripts to 'do'
#
$files=PerlApp::get_bound_file("exe_files.txt");
foreach my $exe (split(/ /,$files))
{
    next unless length($exe)>3; #ignore trash
    $_=$exe;
    s!^.+/!!g;

    $cmds{$_}=sub {do $exe};
}

#
# add tv_grab_nz which is a Python program
#
$cmds{tv_grab_nz}=sub {
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
# validate command 
#
$cmd=shift || "blank";
if (! exists $cmds{$cmd} )
{
    if ($cmd =~ /-/)
    {
	die "you must specify the program to run, for example: $0 tv_grab_fi --configure\n";
    }
    else
    {
	die "$cmd is not a valid command. Valid commands are:\n".join(" ",keys(%cmds))."\n";
    }
}

#
# some programs use a "share" directory
#
if ($cmd eq 'tv_grab_uk' or $cmd eq 'tv_grab_uk_rt')
{
    unless (grep(/^--share/i,@ARGV))  # don't add our --share if one supplied
    {
        my $dir = dirname(PerlApp::exe()); # get full program path
        $dir =~ s!\\!/!g;      # use / not \   
        $dir .= "/share/xmltv";
    	unless (-d $dir )
    	{
	        die "directory $dir not found\n If not kept with the executable, specify with --share\n"
	    }
        push @ARGV,"--share",$dir;
    }
} # special tv_grab_uk, tv_grab_uk_rt processing

#
# call the appropriate routine (note, ARGV was shifted above)
#
$return=$cmds{$cmd}->();

die "$cmd:$! $@" unless (defined $return);

exit $return;
