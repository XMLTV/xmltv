#!perl -w
#
# This is a simple script to generate options so PerlApp can make the EXE
# it needs time values, so might as well put it in a perl script!
# (windows has a limited date function)
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
';

#-l C:/strawberry/c/bin/libexpat-1__.dll
#-l C:/strawberry/c/bin/libxml2-2__.dll
#-l C:/strawberry/c/bin/libiconv-2__.dll
#-l C:/strawberry/c/bin/liblzma-5__.dll
#-l C:/strawberry/c/bin/zlib1__.dll

# not found
#-l C:/strawberry/perl/bin/libgcc__x86__470.dll
#-l C:/strawberry/c/bin/libeay32__.dll
#-l C:/strawberry/c/bin/SSLeay32__.dll
#-M arybase

# add executable scripts
open(FILE,"exe_files.txt");
foreach (split(/ /,<FILE>)) {
  chomp;
  next unless $_;
#  print "-a $_\n";  
#  print "-c $_\n";  # -a doesn't scan for dependancies
}
close FILE;

#-info CompanyName="XMLTV Project http://www.xmltv.org"
#-info FileDescription="EXE bundle of XMLTV tools to manage TV Listings"
#-info InternalName=xmltv.exe
#-info OriginalFilename=xmltv.exe
#-info ProductName=xmltv
#-info LegalCopyright="GNU General Public License http://www.gnu.org/licenses/gpl.txt"
#-icon xmltv_logo.ico
#-l libexpat-1_.dll[file=C:\strawberry\c\bin\libexpat-1_.dll
#-l libxml2-2_.dll[file=C:\strawberry\c\bin\libxml2-2_.dll
#-l libiconv-2_.dll[file=C:\strawberry\c\bin\libiconv-2_.dll
#-l liblzma-5_.dll[file=C:\strawberry\c\bin\liblzma-5_.dll
#-l zlib1_.dll[file=C:\strawberry\c\bin\zlib1_.dll
#-l libgcc_x86_470.dll[file=C:\strawberry\perl\bin\libgcc_x86_470.dll
#-l libeay32_.dll[file=C:\strawberry\c\bin\libeay32_.dll
#-l SSLeay32_.dll[file=C:\strawberry\c\bin\SSLeay32_.dll
#-bind DateTime/Format/Builder/Parser/Regex.pm[file=c:\Strawberry\Perl\site\lib\DateTime\Format\Builder\Parser\Regex.pm

#
# Add XML\Parser\encodings
#
@Encoding_Path = (grep(-d $_,
                         map(File::Spec->catdir($_, qw(XML Parser Encodings)),
                             @INC)
                      ));
foreach $dir (@Encoding_Path) {
    opendir DIR,$dir || die "Can't open encoding path directory\n";
    while ($file = readdir DIR)
    {
       next unless $file =~ /.enc$/i;
#       print "-l XML/Parser/Encodings/${file}[file=$dir/${file}\n";
#       print "-a c:/Strawberry/perl/vendor/lib/XML/Parser/Encodings/${file}\n";
    }
}

##
## put date in file version field
##
#@date=localtime; $date[4]++; $date[5]+=1900;
#printf "-info FileVersion=%4d.%d.%d.%d\n",@date[5,4,3,2];

##
## last fields in product version should ommitable, but it doesn't work.
##
#$version=shift;
#@_=split(/\./,$version);
#map {$_=0 unless defined $_} @_[0..4];
#printf "-info ProductVersion=%d.%d.%d.%d\n",@_;
