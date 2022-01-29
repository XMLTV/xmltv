#!perl -w
#
# This is a simple script to generate options so PerlApp can make the EXE
#
# Robert Eden rmeden@yahoo.com

use File::Spec;

#
# output constants
#
print '
-M XMLTV::
-M Date::Manip::
-M DateTime::
-M Params::Validate::
-M Date::Language::
-M Class::MethodMaker::
-X JSON::PP58
-X Test::Builder::IO::Scalar
-X Win32::Console
-a exe_files.txt
';
