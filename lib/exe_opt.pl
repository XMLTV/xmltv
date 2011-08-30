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

use File::Spec;

#
# output constants
#
print '-nologo
-force
-add="XMLTV::Ask::Term;XMLTV::Ask::Tk"
-add="XMLTV::ProgressBar::Term;XMLTV::ProgressBar::Tk;XMLTV::ProgressBar::None;"
-add="XMLTV::GUI"
-add="Class::MethodMaker::scalar"
-add "DateTime::Locale::en_US"
-add "DateTime::TimeZone::Europe::Copenhagen"
-add "DateTime::TimeZone::Europe::Helsinki"
-add "DateTime::TimeZone::Europe::Lisbon"
-add "DateTime::TimeZone::Asia::Jerusalem"
-add "DateTime::TimeZone::Asia::Kolkata"
-add="Tk::ProgressBar"
-trim="Net::FTP::A"
-trim="B"
-trim="Apache::Const;Apache::RequestIO;DIME::Payload;MIME::Entity;Apache::RequestRec;DIME::Message;I18N::Langinfo"
-trim="Apache2::RequestUtil;APR::Table;Apache2::Const;Apache2::RequestRec;Apache2::RequestIO"
-trim=DateTime::Format
-trim=grab/eu_epgdata/tv_grab_eu_epgdata
-info CompanyName="XMLTV Project http://www.xmltv.org"
-info FileDescription="EXE bundle of XMLTV tools to manage TV Listings"
-info InternalName=xmltv.exe
-info OriginalFilename=xmltv.exe
-info ProductName=xmltv
-info LegalCopyright="GNU General Public License http://www.gnu.org/licenses/gpl.txt"
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
