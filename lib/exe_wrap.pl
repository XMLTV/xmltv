#!perl -w 
#
# $id$
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

#
# build file list
#
$files=PerlApp::get_bound_file("exe_files.txt");
foreach $exe (split(/ /,$files))
{
    next unless length($exe)>3; #ignore trash
    $_=$exe; 
    s!^.+/!!g;
#   print "Storing $_=$exe\n";
    $exe{$_}=$exe;
}
    
#
# validate command 
#
$cmd=shift || "blank";
if (! exists $exe{$cmd} )
{
    die "$cmd is not a valid command. Valid commands are:\n".join(" ",keys(%exe))."\n";
}


#
# call the appropriate routine (note, ARGV was shifted above)
#
$return = do $exe{$cmd};

die "$cmd:$! $@" unless (defined $return);

return $return;
