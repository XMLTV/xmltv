#!perl -w
#
# $Id$
#
# This is a simple script to generate options so PerlApp can make the EXE
# it needs time values, so might as well put it in a perl script!
# (windows has a limited date function)
#
# Robert Eden rmeden@yahoo.com
#

#
# output constants
#
print '-nologo
-force
-add="XMLTV::Ask::Term;XMLTV::Ask::Tk"
-bind=libexpat.dll[file=\perl\site\lib\auto\XML\Parser\Expat\libexpat.dll,extract]
-bind=libxml2.dll[file=\perl\bin\libxml2.dll,extract]
-trim="Convert::EBCDIC;DB_File;Encode;HASH;HTML::FromText;Text::Iconv;Unicode::Map8;v5;URI/urn::isbn.pm;URI/urn::oid.pm;PerlIO/gzip.pm;HTML::FormatText"
-info CompanyName="XMLTV Project http://membled.com/work/apps/xmltv/"
-info FileDescription="EXE bundle of XMLTV tools to manage TV Listings"
-info InternalName=xmltv.exe
-info OriginalFilename=xmltv.exe
-info ProductName=xmltv
-info LegalCopyright="GNU General Public License http://www.gnu.org/licenses/gpl.txt"
';

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
