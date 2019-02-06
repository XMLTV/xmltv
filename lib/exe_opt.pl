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
print '-nologo
-force
-add=XMLTV::
-add=Date::Manip::
-add DateTime::
-add Params::Validate::**
-add Date::Language::
-add Class::MethodMaker::
-add Class::MethodMaker::Engine
-add arybase
-bind=libexpat-1_.dll[file=C:\strawberry\c\bin\libexpat-1_.dll,extract]
-bind=libxml2-2_.dll[file=C:\strawberry\c\bin\libxml2-2_.dll,extract]
-bind=libiconv-2_.dll[file=C:\strawberry\c\bin\libiconv-2_.dll,extract]
-bind=liblzma-5_.dll[file=C:\strawberry\c\bin\liblzma-5_.dll,extract]
-bind=zlib1_.dll[file=C:\strawberry\c\bin\zlib1_.dll,extract]
-bind=libgcc_x86_470.dll[file=C:\strawberry\perl\bin\libgcc_x86_470.dll,extract]
-bind=libeay32_.dll[file=C:\strawberry\c\bin\libeay32_.dll,extract]
-bind=SSLeay32_.dll[file=C:\strawberry\c\bin\SSLeay32_.dll,extract]
-bind DateTime/Format/Builder/Parser/Regex.pm[file=c:\Strawberry\Perl\site\lib\DateTime\Format\Builder\Parser\Regex.pm,extract]
-trim=Class::MethodMaker::Scalar
-trim=Class::MethodMaker::Engine
-trim=JSON::PP58
-trim=Test::Builder::IO::Scalar;
-trim=Win32::Console
-info CompanyName="XMLTV Project http://www.xmltv.org"
-info FileDescription="EXE bundle of XMLTV tools to manage TV Listings"
-info InternalName=xmltv.exe
-info OriginalFilename=xmltv.exe
-info ProductName=xmltv
-info LegalCopyright="GNU General Public License http://www.gnu.org/licenses/gpl.txt"
-icon xmltv_logo.ico
';

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
       print "-bind=XML/Parser/Encodings/${file}[file=$dir/${file},extract]\n";
    }
}

#
# put date in file version field
#
@date=localtime; $date[4]++; $date[5]+=1900;
printf "-info FileVersion=%4d.%d.%d.%d\n",@date[5,4,3,2];

#
# last fields in product version should ommitable, but it doesn't work.
#
$version=shift;
@_=split(/\./,$version);
map {$_=0 unless defined $_} @_[0..4];
printf "-info ProductVersion=%d.%d.%d.%d\n",@_;
