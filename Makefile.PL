#!/usr/bin/perl -w
# $Id$

use ExtUtils::MakeMaker;
use Config;
use File::Basename ();
use File::Find;

# Don't use ':config pass_through' because that requires Getopt::Long
# 2.24 or later, and we don't have a clean way to require that.
#
use Getopt::Long; Getopt::Long::Configure('pass_through');

# Suppress 'isn't numeric' warnings from MakeMaker - see
# <http://sourceforge.net/tracker/?func=detail&atid=424135&aid=870170&group_id=39046>.
#
$SIG{__WARN__} = sub {
    for (my $msg = shift) {
        $_ = "warning: something's wrong" if not defined;
        warn $_
          unless /Argument .+ isn.t numeric in numeric lt .+MakeMaker.pm/;
    }
};

# ExtUtils::MakeMaker before 6.21 or so has a bug when PREFIX is not
# given explicitly -
# <http://article.gmane.org/gmane.comp.tv.xmltv.devel/3634>.
#
unless ($ExtUtils::MakeMaker::VERSION ge 6.21) {
    if (not grep /^PREFIX=/, @ARGV) {
        warn "You may want to explicitly give PREFIX to work around MakeMaker bugs.\n";
    }
}

use strict;

sub test_module( $$ );
sub check_date_manip();
sub test_special( $$ );
sub targets( $ );

if ($] == 5.006) {
    warn <<END
Some installations of perl 5.6.0 are buggy and crash while running
this script.  If you get 'segmentation fault' below, please report it
to the xmltv-users mailing list so we can try to work around the bug.
At present the only known fix is to upgrade to a newer perl version
such as 5.6.1 or 5.8.3.
END
;
}

# A couple of undocumented options to help with building the Windows
# distribution even on hosts that don't have all the necessary
# modules.  By default, we only warn if dependencies are missing.
# If --strict-deps is passed in, then the whole process fails.
#
my $opt_strictdeps = 0;
my $opt_yes = 0;
my $opt_default = 0;
my $opt_components;
my $opt_exclude;
GetOptions('strict-deps'  => \$opt_strictdeps,  # be strict about dependencies
           yes            => \$opt_yes,         # answer yes to all questions
           default        => \$opt_default,     # answer default to all questions
           'components=s' => \$opt_components,
           'exclude=s'    => \$opt_exclude,
          );

our $VERSION;
$VERSION = '0.5.66';

# Fragment of Makefile text to give the directory where files should
# be installed.  The extra '.' in the middle of the path is to avoid
# beginning with '//', which means a network share on Cygwin.
#
my $location = '$(DESTDIR)/./$(PREFIX)';

our %extra_constants;
%extra_constants
  = (INST_PLAINDOC   => 'blib/doc',
     INSTALLPLAINDOC => "$location/share/doc/xmltv-$::VERSION",
     INST_SHARE      => 'blib/share',
     INSTALLSHARE    => "$location/share/xmltv",

     # Manual page constants, shouldn't really be needed, but work
     # around bugs and make sure this stuff is the same across
     # MakeMaker versions.
     INSTALLMAN1DIR  => "$location/share/man/man1",
     INSTALLMAN3DIR  => "$location/share/man/man3",
     MAN3EXT         => '3',

     # Directory to install into when making Windows binary dist.
     WINDOWS_DIST    => "xmltv-$VERSION-win32",
     VERSION         => "$VERSION",
    );

# The following lists of dependencies and files to be installed may
# get modified later depending on what the user chooses.
#

# Documentation files to be installed.  This is a global variable
# because it is accessed by some code we add to MakeMaker.
#
our @docs;
@docs = qw(doc/COPYING doc/QuickStart doc/README.win32 README);

# Executables to be installed.
my @exes
  = qw(filter/tv_augment_tz
       filter/tv_extractinfo_en
       filter/tv_extractinfo_ar
       filter/tv_grep
       filter/tv_sort
       filter/tv_to_latex
       filter/tv_to_text
       filter/tv_to_potatoe
       filter/tv_cat
       filter/tv_split
       filter/tv_imdb
       filter/tv_remove_some_overlapping
       filter/tv_count
       filter/tv_merge
       filter/tv_augment
       tools/tv_validate_grabber
       tools/tv_validate_file
       tools/tv_find_grabbers
      );

# Libraries to be installed.
my %pm
  = ('lib/XMLTV.pm'               => '$(INST_LIBDIR)/XMLTV.pm',
     'lib/TZ.pm'                  => '$(INST_LIBDIR)/XMLTV/TZ.pm',
     'lib/Clumps.pm'              => '$(INST_LIBDIR)/XMLTV/Clumps.pm',
     'lib/Usage.pm'               => '$(INST_LIBDIR)/XMLTV/Usage.pm',
     'lib/Date.pm'                => '$(INST_LIBDIR)/XMLTV/Date.pm',
     'lib/Version.pm'             => '$(INST_LIBDIR)/XMLTV/Version.pm',
     'lib/Ask.pm'                 => '$(INST_LIBDIR)/XMLTV/Ask.pm',
     'lib/Ask/Tk.pm'              => '$(INST_LIBDIR)/XMLTV/Ask/Tk.pm',
     'lib/Ask/Term.pm'            => '$(INST_LIBDIR)/XMLTV/Ask/Term.pm',
     'lib/GUI.pm'                 => '$(INST_LIBDIR)/XMLTV/GUI.pm',
     'lib/ProgressBar.pm'         => '$(INST_LIBDIR)/XMLTV/ProgressBar.pm',
     'lib/ProgressBar/None.pm'    => '$(INST_LIBDIR)/XMLTV/ProgressBar/None.pm',
     'lib/ProgressBar/Term.pm'    => '$(INST_LIBDIR)/XMLTV/ProgressBar/Term.pm',
     'lib/ProgressBar/Tk.pm'      => '$(INST_LIBDIR)/XMLTV/ProgressBar/Tk.pm',
     'lib/Summarize.pm'           => '$(INST_LIBDIR)/XMLTV/Summarize.pm',
     'lib/Supplement.pm'          => '$(INST_LIBDIR)/XMLTV/Supplement.pm',
     'lib/IMDB.pm'                => '$(INST_LIBDIR)/XMLTV/IMDB.pm',
     'lib/Gunzip.pm'              => '$(INST_LIBDIR)/XMLTV/Gunzip.pm',
     'lib/Capabilities.pm'        => '$(INST_LIBDIR)/XMLTV/Capabilities.pm',
     'lib/Description.pm'         => '$(INST_LIBDIR)/XMLTV/Description.pm',
     'lib/Configure.pm'           => '$(INST_LIBDIR)/XMLTV/Configure.pm',
     'lib/Configure/Writer.pm'    => '$(INST_LIBDIR)/XMLTV/Configure/Writer.pm',
     'lib/Options.pm'             => '$(INST_LIBDIR)/XMLTV/Options.pm',
     'lib/ValidateFile.pm'        => '$(INST_LIBDIR)/XMLTV/ValidateFile.pm',
     'lib/ValidateGrabber.pm'     => '$(INST_LIBDIR)/XMLTV/ValidateGrabber.pm',
     'lib/PreferredMethod.pm'     => '$(INST_LIBDIR)/XMLTV/PreferredMethod.pm',
     'lib/Data/Recursive/Encode.pm' => '$(INST_LIBDIR)/XMLTV/Data/Recursive/Encode.pm',
     'lib/Augment.pm'             => '$(INST_LIBDIR)/XMLTV/Augment.pm',
     'filter/Grep.pm'             => '$(INST_LIBDIR)/XMLTV/Grep.pm',
     'grab/Memoize.pm'            => '$(INST_LIBDIR)/XMLTV/Memoize.pm',
     'grab/Grab_XML.pm'           => '$(INST_LIBDIR)/XMLTV/Grab_XML.pm',
     'grab/DST.pm'                => '$(INST_LIBDIR)/XMLTV/DST.pm',
     'grab/Config_file.pm'        => '$(INST_LIBDIR)/XMLTV/Config_file.pm',
     'grab/Get_nice.pm'           => '$(INST_LIBDIR)/XMLTV/Get_nice.pm',
     'grab/Mode.pm'               => '$(INST_LIBDIR)/XMLTV/Mode.pm',
    );

# Modules required to install.
my %prereqs
  = (
     'LWP'         => 5.65,
     # XML::Parser is required by XML::Twig, but older versions have a
     # bug when $SIG{__DIE__} is set (well, could be a perl bug, but
     # anyway it doesn't appear with 2.34).
     #
     'XML::Parser' => 2.34,
     'XML::Twig'   => 3.10,
     'Date::Manip' => 5.42,
     'XML::Writer' => 0.600,
     'Memoize'     => 0,
     'Storable'    => 2.04,
     'File::Slurp' => 0,
     'XML::TreePP' => 0,
    );

# Files which are run to generate source code.
my %pl_files = ('filter/tv_grep.PL' => 'filter/tv_grep',
                'tools/tv_validate_file.PL' => 'tools/tv_validate_file',
                'tools/tv_validate_grabber.PL' => 'tools/tv_validate_grabber',
                'lib/XMLTV.pm.PL' => 'lib/XMLTV.pm',
                'lib/Supplement.pm.PL' => 'lib/Supplement.pm',
               );

# Some tools which are generated from .PL files need the share/
# directory passed as an extra argument.
#
my @need_share = ('tools/tv_validate_file',
                  'tools/tv_validate_grabber',
                  'lib/Supplement.pm',
                 );

# Files to be installed in the system-wide share/ directory.
my %share_files = ('xmltv.dtd' => 'xmltv.dtd',
                   'xmltv-lineups.xsd' => 'xmltv-lineups.xsd',
                   'filter/augment/augment.conf' => 'tv_augment/augment.conf',
                   'filter/augment/augment.rules' => 'tv_augment/augment.rules',
                  );

# Files which 'make clean' should remove, but doesn't by default, so
# we have to patch it.
#
my @to_clean = ('filter/tv_grep',
                'tools/tv_validate_file',
                'tools/tv_validate_grabber',
                'lib/XMLTV.pm',
                'lib/Supplement.pm',
               );

# Extra dependencies to add to the Makefile.
my @deps = ('filter/tv_grep' => [ qw(filter/tv_grep.in pm_to_blib) ],
            'tools/tv_validate_file' => [ qw(tools/tv_validate_file.in) ],
            'tools/tv_validate_grabber' => [ qw(tools/tv_validate_grabber.in) ],
            'lib/XMLTV.pm' => [ 'lib/XMLTV.pm.in' ],
            'lib/Supplement.pm' => [ 'lib/Supplement.pm.in' ],
           );

# Some grabbers which are generated from .PL files need the share/
# directory passed as an extra argument.
#
my @grab_need_share;

# 'Recommended but not required'.  It isn't currently handled to have
# the same module in both sets.
#
my %recommended
  = (
     'Lingua::EN::Numbers::Ordinate' => 0,
     'Lingua::Preferred' => '0.2.4',
     'Term::ProgressBar' => 2.03,
     'Compress::Zlib' => 0,
     'Unicode::String' => 0,
    );

# And Log::TraceMessages is 'suggested' but we don't warn about that.

if ($opt_yes) {
    *ask = sub { print "$_[0] yes\n"; 1 };
}
elsif ($opt_default) {
    *ask = sub { print "$_[0] $_[2]\n"; $_[2] };
}
else {
    require 'lib/Ask/Term.pm';
    *ask = \&XMLTV::Ask::Term::ask_boolean;
}

# Weird shit happens when you change things like PREFIX without
# rebuilding everything explicitly.
#
if (-e 'Makefile') {
    warn <<END
There is already a Makefile.  To avoid weird problems it is
recommended you run 'make distclean' to clear out old built files
before generating a new Makefile.

END
;
    if (! ask(0, "Do you wish to continue anyway?", 0)) {
        exit(1);
    }
}

# Now prompt about how much to install.  This is really only to
# reduce dependencies.  In the long run things like tv_check can be
# spun off into separate projects.
#
my @opt_components
  = (

     { name => 'tv_grab_ar',
       blurb => 'Grabber for Argentina',
       exes => [ 'grab/ar/tv_grab_ar' ],
       prereqs => { 'HTML::TreeBuilder' => 0,
                    'HTML::Entities'    => 0,
                    'HTTP::Cookies'     => 0,
                    'LWP::UserAgent'    => 0,
                    'JSON::PP'          => 0,
                    'Date::Language'    => 0, },
     },

# Disabled 2006-04-12 since it doesn't provide data anymore.
#     { name     => 'tv_grab_au',
#       blurb    => 'Grabber for Australia',
#       exes     => [ 'grab/au/tv_grab_au' ],
#       deps     => [ 'grab/au/tv_grab_au' => [ 'grab/au/tv_grab_au.in' ] ],
#       pl_files => { 'grab/au/tv_grab_au.PL' => 'grab/au/tv_grab_au' },
#       to_clean => [ 'grab/au/tv_grab_au' ],
#       share_files => { 'grab/au/channel_ids' => 'tv_grab_au/channel_ids' },
#       grab_need_share => [ 'au' ],
#     },

# 2008-11-09 disabled after ident string was blocked
#     { name => 'tv_grab_be',
#       blurb => 'Grabber for Belgium and Luxemburg',
#       exes => [ 'grab/be/tv_grab_be' ],
#       pl_files => { 'grab/be/tv_grab_be.PL' => 'grab/be/tv_grab_be' },
#       share_files => { 'grab/be/channel_ids_fr' => 'tv_grab_be/channel_ids_fr',
#                        'grab/be/channel_ids_nl' => 'tv_grab_be/channel_ids_nl' },
#       to_clean => [ 'grab/be/tv_grab_be' ],
#       deps => [ 'grab/be/tv_grab_be' => [ 'grab/be/tv_grab_be.in' ] ],
#       grab_need_share => [ 'be' ],
#       prereqs => { 'HTML::Entities' => 1.27 } ,
#     },

#     { name => 'tv_grab_br',
#       blurb => 'Grabber for Brazil',
#       exes => [ 'grab/br/tv_grab_br' ],
#       prereqs => { 'HTML::TreeBuilder' => 0 ,
#                    'HTML::Entities' => 1.27 , }
#     },

# disabled because it broke due to site changes 2009-03-08
#     { name => 'tv_grab_br_net',
#       blurb => 'Grabber for Brazil NET Cable',
#       exes => [ 'grab/br_net/tv_grab_br_net' ],
#       prereqs => { 'WWW::Mechanize' => 1.16 ,
#                   'HTTP::Cookies' => 1.39 , }
#     },

# disabled since blocked by www.fernsehen.ch guys
#     { name     => 'tv_grab_ch',
#       blurb    => 'Grabber for Switzerland',
#       exes     => [ 'grab/ch/tv_grab_ch' ],
#       deps     => [ 'grab/ch/tv_grab_ch' => [ 'grab/ch/tv_grab_ch.in' ] ],
#       pl_files => { 'grab/ch/tv_grab_ch.PL' => 'grab/ch/tv_grab_ch' },
#       to_clean => [ 'grab/ch/tv_grab_ch' ],
#       share_files => { 'grab/ch/channel_ids' => 'tv_grab_ch/channel_ids' },
#       grab_need_share => [ 'ch' ],
#     },

# disabled after ident string was blocked
#     { name     => 'tv_grab_ch_bluewin',
#       blurb    => 'Grabber for Switzerland',
#       exes     => [ 'grab/ch_bluewin/tv_grab_ch_bluewin' ],
#       deps     => [ 'grab/ch_bluewin/tv_grab_ch_bluewin'
#                               => [ 'grab/ch_bluewin/tv_grab_ch_bluewin.in' ] ],
#       pl_files => { 'grab/ch_bluewin/tv_grab_ch_bluewin.PL'
#                               => 'grab/ch_bluewin/tv_grab_ch_bluewin' },
#       to_clean => [ 'grab/ch_bluewin/tv_grab_ch_bluewin' ],
#       share_files => { 'grab/ch_bluewin/channel_ids'
#                               => 'tv_grab_ch_bluewin/channel_ids' },
#       grab_need_share => [ 'ch_bluewin' ],
#       prereqs => { 'HTML::Entities' => 1.27,
#                   'HTML::TreeBuilder' => 0 },
#     },

     { name     => 'tv_grab_ch_search',
           blurb    => 'Grabber for Switzerland',
           exes     => [ 'grab/ch_search/tv_grab_ch_search' ],
           deps     => [ 'grab/ch_search/tv_grab_ch_search'
                        => [ 'grab/ch_search/tv_grab_ch_search.in' ] ],
           pl_files => { 'grab/ch_search/tv_grab_ch_search.PL'
                            => 'grab/ch_search/tv_grab_ch_search' },
           to_clean => [ 'grab/ch_search/tv_grab_ch_search' ],
#          share_files => { 'grab/ch_search/channel_ids'
#                   => 'tv_grab_ch_search/channel_ids' },
           grab_need_share => [ 'ch_search' ],
           prereqs  => { 'HTML::Entities'    => 1.27,
                         'HTML::TreeBuilder' => 0, },
     },

# 2008-07-22 - removed by rmeden, website changes, won't be fixed
#     { name => 'tv_grab_dk',
#       blurb => 'Grabber for Denmark',
#       exes => [ 'grab/dk/tv_grab_dk' ],
#       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_grab_dk_dr',
       blurb => 'Grabber for Denmark (dr.dk)',
       exes => [ 'grab/dk_dr/tv_grab_dk_dr' ],
       prereqs => { 'Data::Dumper'   => 0,
                    'LWP::UserAgent' => 0,
                    'IO::Scalar'     => 0,
                    'DateTime'       => 0,
                    'JSON'           => 0, },
     },

     { name => 'tv_grab_dtv_la',
       blurb => 'Grabber for Latin America & Caribbean',
       exes => [ 'grab/dtv_la/tv_grab_dtv_la' ],
       prereqs => { 'LWP::UserAgent'    => 0,
                    'HTTP::Cookies'     => 0,
                    'HTML::TreeBuilder' => 0,
                    'JSON::PP'          => 0,
                    'Date::Manip'       => 0,
                    'Date::Parse'       => 0,
                    'Date::Language'    => 0, },
     },

# rmeden 2012-06-11 broken since 2011-11-25
#     { name => 'tv_grab_ee',
#       blurb => 'Grabber for Estonia',
#       exes => [ 'grab/ee/tv_grab_ee' ],
#       prereqs => { 'LWP::Simple' => 0 } },

# 2009-03-08 removed due to breakage after source site changes
#     { name => 'tv_grab_es',
#       blurb => 'Grabber for Spain - Analogic Terrestrial/Cable',
#       exes => [ 'grab/es/tv_grab_es' ],
#       prereqs => { 'HTML::TreeBuilder' => 0 } },

# tv_grab_es_digital no longer functioning due to site changes
#     { name => 'tv_grab_es_digital',
#       blurb => 'Grabber for Spain - Digital Satellite (D+)',
#       exes => [ 'grab/es_digital/tv_grab_es_digital' ],
#       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_grab_es_laguiatv',
       blurb => 'Alternative grabber for Spain',
       exes => [ 'grab/es_laguiatv/tv_grab_es_laguiatv' ],
       prereqs => { 'HTML::TreeBuilder' => 0, },
     },

# rmeden 2012-06-11 broken since 2012-03-29
#     { name => 'tv_grab_es_miguiatv',
#       blurb => 'Alternative grabber for Spain using miguiatv.com',
#       exes => [ 'grab/es_miguiatv/tv_grab_es_miguiatv' ],
#       prereqs => { 'HTML::TreeBuilder' => 0 } },#

     { name => 'tv_grab_eu_dotmedia',
       blurb => 'Grabber for Europe (xmltv.se / dotmedia)',
       exes => [ 'grab/eu_dotmedia/tv_grab_eu_dotmedia' ],
       prereqs => { 'XML::LibXML'    => 0,
                    'Compress::Zlib' => 0,
                    'IO::Stringy'    => 0,
                    'HTTP::Cache::Transparent' => 0, },
     },

     { name => 'tv_grab_eu_egon',
       blurb => 'Grabber for german speaking area (Egon zappt)',
       exes => [ 'grab/eu_egon/tv_grab_eu_egon' ],
       pl_files => { 'grab/eu_egon/tv_grab_eu_egon.PL'
                     => 'grab/eu_egon/tv_grab_eu_egon' },
       to_clean => [ 'grab/eu_egon/tv_grab_eu_egon' ],
       deps => [ 'grab/eu_egon/tv_grab_eu_egon'
                 => [ 'grab/se_swedb/tv_grab_se_swedb.in' ] ],
       prereqs => { 'XML::LibXML'    => 0,
                    'Compress::Zlib' => 0,
                    'IO::Stringy'    => 0,
                    'HTTP::Cache::Transparent' => 0, },
     },

     { name => 'tv_grab_eu_epgdata',
       blurb => '$$ Grabber for some European countries (epgdata.com)',
       exes => [ 'grab/eu_epgdata/tv_grab_eu_epgdata' ],
       share_files => { 'grab/eu_epgdata/channel_ids' => 'tv_grab_eu_epgdata/channel_ids' },
       prereqs => { 'XML::Twig'      => 0,
                    'Archive::Zip'   => 0,
                    'HTML::Entities' => 0,
                    'LWP::Simple'    => 0,
                    'File::Temp'     => 0,
                    'DateTime::Format::Strptime' => 0, },
     },

     { name     => 'tv_grab_fi',
       blurb    => 'Grabber for Finland',
       exes     => [ 'grab/fi/tv_grab_fi' ],
       deps     => [
                     'grab/fi/tv_grab_fi' => [
                         'grab/fi/tv_grab_fi.pl',
                         'grab/fi/fi/common.pm',
                         'grab/fi/fi/day.pm',
                         'grab/fi/fi/programme.pm',
                         'grab/fi/fi/programmeStartOnly.pm',
                         'grab/fi/fi/source/foxtv.pm',
                         'grab/fi/fi/source/iltapulu.pm',
                         'grab/fi/fi/source/telkku.pm',
                         'grab/fi/fi/source/telvis.pm',
                         'grab/fi/fi/source/yle.pm',
                     ],
                   ],
       pl_files => { 'grab/fi/merge.PL' => 'grab/fi/tv_grab_fi' },
       to_clean => [ 'grab/fi/tv_grab_fi' ],
       prereqs  => {
                    'HTML::TreeBuilder' => 0,
                    'Time::Local'       => 0, },
     },

     { name     => 'tv_grab_fi_sv',
       blurb    => 'Grabber for Finland (Swedish)',
       exes     => [ 'grab/fi_sv/tv_grab_fi_sv' ],
       prereqs  => { 'DateTime'   => 0,
                     'IO::Scalar' => 0,
                     'HTML::TreeBuilder' => 0, },
     },

     { name => 'tv_grab_fr',
       blurb => 'Grabber for France',
       exes => [ 'grab/fr/tv_grab_fr' ],
       prereqs => { 'HTML::Entities'    => 1.27,
                    'HTML::TreeBuilder' => 0, },
     },

     { name => 'tv_grab_fr_kazer',
       blurb => 'Grabber for France (Kazer)',
       exes => [ 'grab/fr_kazer/tv_grab_fr_kazer' ],
       prereqs => { 'IO::Uncompress::Unzip' => 0, },
     },

     { name => 'tv_grab_hr',
       blurb => 'Grabber for Croatia',
       exes => [ 'grab/hr/tv_grab_hr' ],
       pl_files => { 'grab/hr/tv_grab_hr.PL'
                     => 'grab/hr/tv_grab_hr' },
       to_clean => [ 'grab/hr/tv_grab_hr' ],
       deps => [ 'grab/hr/tv_grab_hr'
                 => [ 'grab/se_swedb/tv_grab_se_swedb.in' ] ],
       prereqs => { 'XML::LibXML'    => 0,
                    'Compress::Zlib' => 0,
                    'IO::Stringy'    => 0,
                    'HTTP::Cache::Transparent' => 0, },
     },

     { name => 'tv_grab_huro',
       blurb => 'Grabber for Hungary, Romania, Slovakia, Czech Republic',
       exes => [ 'grab/huro/tv_grab_huro' ],
       pl_files => { 'grab/huro/tv_grab_huro.PL'
                     => 'grab/huro/tv_grab_huro' },
       share_files => { 'grab/huro/jobmap' => 'tv_grab_huro/jobmap',
                        'grab/huro/catmap.hu' => 'tv_grab_huro/catmap.hu',
                        'grab/huro/catmap.ro' => 'tv_grab_huro/catmap.ro',
                        'grab/huro/catmap.sk' => 'tv_grab_huro/catmap.sk',
                        'grab/huro/catmap.cz' => 'tv_grab_huro/catmap.cz',
                     },
       to_clean => [ 'grab/huro/tv_grab_huro' ],
       deps => [ 'grab/huro/tv_grab_huro'
                 => [ 'grab/huro/tv_grab_huro.in' ] ],
       grab_need_share => [ 'huro' ],
       prereqs => { 'HTML::TreeBuilder' => 0 },
     },

     { name => 'tv_grab_il',
       blurb => 'Grabber for Israel',
       exes => [ 'grab/il/tv_grab_il' ],
     },

# 2013-05-13 xmltv feed disabled by What's On due to TOS violations. It may come back
#     { name     => 'tv_grab_in',
#       blurb => 'Grabber for India (zipazap.com)',
#       exes     => [ 'grab/in/tv_grab_in' ],
#       prereqs => { 'XML::LibXML' => 0,
#                    'IO::Scalar' => 0,
#                  },
#     },

     { name => 'tv_grab_is',
       blurb => 'Grabber for Iceland',
       exes => [ 'grab/is/tv_grab_is' ],
       share_files => { 'grab/is/category_map' => 'tv_grab_is/category_map' },
       prereqs => { 'XML::LibXSLT' => 0,
                    'XML::DOM'     => 0, },
     },

     { name => 'tv_grab_it',
       blurb => 'Grabber for Italy',
       exes => [ 'grab/it/tv_grab_it' ],
       pl_files => { 'grab/it/tv_grab_it.PL' => 'grab/it/tv_grab_it' },
       share_files => { 'grab/it/channel_ids' => 'tv_grab_it/channel_ids' },
       to_clean => [ 'grab/it/tv_grab_it', 'grab/it/tv_grab_it.in2' ],
       deps => [ 'grab/it/tv_grab_it' => [ 'grab/it/tv_grab_it.in' ] ],
       grab_need_share => [ 'it' ],
     },

     { name => 'tv_grab_it_dvb',
       blurb => 'Grabber for Italy from DVB-S stream',
       exes => [ 'grab/it_dvb/tv_grab_it_dvb' ],
       pl_files => { 'grab/it_dvb/tv_grab_it_dvb.PL' => 'grab/it_dvb/tv_grab_it_dvb' },
       share_files => { 'grab/it_dvb/channel_ids' => 'tv_grab_it_dvb/channel_ids',
                        'grab/it_dvb/sky_it.dict' => 'tv_grab_it_dvb/sky_it.dict',
                        'grab/it_dvb/sky_it.themes' => 'tv_grab_it_dvb/sky_it.themes',
                   },
       to_clean => [ 'grab/it_dvb/tv_grab_it_dvb' ],
       deps => [ 'grab/it_dvb/tv_grab_it_dvb' => [ 'grab/it_dvb/tv_grab_it_dvb.in' ] ],
       grab_need_share => [ 'it_dvb' ],
       prereqs => { 'Data::Dump'  => 0,
                    'IO::Select'  => 0,
                    'Linux::DVB'  => 0,
                    'Time::HiRes' => 0, } ,
     },

# 2009-03-05 rmeden - source site seems to be blocking our agent string
#     { name => 'tv_grab_jp',
#       blurb => 'Grabber for Japan',
#       exes => [ 'grab/jp/tv_grab_jp' ],
#       prereqs => { 'HTML::TreeBuilder' => 0,
#                    'Text::Kakasi' => 0 },
#     },

     { name     => 'tv_grab_na_dd',
       blurb => '$$ Grabber for North America-schedulesdirect.org',
       exes     => [ 'grab/na_dd/tv_grab_na_dd' ],
       pl_files => { 'grab/na_dd/tv_grab_na_dd.PL' => 'grab/na_dd/tv_grab_na_dd' },
       deps     => [ 'grab/na_dd/tv_grab_na_dd' => [ 'grab/na_dd/tv_grab_na_dd.in' ] ],
       to_clean => [ 'grab/na_dd/tv_grab_na_dd' ],
       prereqs => { 'SOAP::Lite'    => 0.67,
                    'Term::ReadKey' => 0,
                    'XML::Twig'     => 3.28, },
       grab_need_share => [ 'na_dd' ],
     },

     { name => 'tv_grab_na_dtv',
       blurb => 'Grabber for North America (DirecTV)',
       exes => [ 'grab/na_dtv/tv_grab_na_dtv' ],
       prereqs => {
         'DateTime'         => 0,
         'HTTP::Cookies'    => 0,
         'LWP::UserAgent'   => 0,
         'JSON::PP'         => 0,
         'HTML::TokeParser' => 0, },
     },

# 2013-02-02 disabled after site changes broke grabber (no <IMG> tags!)
#     { name     => 'tv_grab_na_icons',
#       blurb    => 'Grabber for North American Channel Icons',
#       exes     => [ 'grab/na_icons/tv_grab_na_icons' ],
#       deps     => [ 'grab/na_icons/tv_grab_na_icons' => [ 'grab/na_icons/tv_grab_na_icons.in' ] ],
#       pl_files => { 'grab/na_icons/tv_grab_na_icons.PL' => 'grab/na_icons/tv_grab_na_icons' },
#       to_clean => [ 'grab/na_icons/tv_grab_na_icons' ],
#       prereqs  => { 'HTML::TreeBuilder' => 0,
#                     'XML::Twig'         => 3.28,
#                     'WWW::Mechanize' => 1.02 },
#       grab_need_share => [ 'na_icons' ],
#     },

     { name => 'tv_grab_na_tvmedia',
       blurb => 'Grabber for North America (TVMedia)',
       exes => [ 'grab/na_tvmedia/tv_grab_na_tvmedia' ],
       prereqs => { 'XML::LibXML' => 0,
                    'LWP::Simple' => 0, },
     },

# rmeden 2008-02-13 disabled after site changes broke grabber
#    { name => 'tv_grab_nc',
#      blurb => 'Grabber for Nouvelle Caledonie Island (France)',
#      exes => [ 'grab/nc/tv_grab_nc' ],
#      prereqs => { 'HTML::TreeBuilder' => 0 ,
#                   'HTML::Entities'    => 0 } },

     { name => 'tv_grab_nl',
       blurb => 'Grabber for the Netherlands',
       exes => [ 'grab/nl/tv_grab_nl' ],
       prereqs => { 'HTTP::Cache::Transparent' => 0,
                    'HTML::TreeBuilder' => 0,
                    'HTML::Entities'    => 0,
                    'IO::File'     => 0,
                    'Date::Parse'  => 0,
                    'Date::Format' => 0,
                    'DateTime'     => 0,
                    'Encode'       => 0,
                    'JSON::PP'     => 0, },
     },

# 2008-07-12 - removed by rmeden, not getting programs for a while.
#     { name => 'tv_grab_nl_wolf',
#       blurb => 'Alternative grabber for the Netherlands',
#       exes => [ 'grab/nl_wolf/tv_grab_nl_wolf' ],
#       prereqs => { 'HTML::TreeBuilder' => 0 } },

# depreciate tv_grab_no as it is no longer supported (per author, cwattengard@gmail.com)
# has been replaced by tv_grab_no_gfeed
#
#     { name => 'tv_grab_no',
#       blurb => 'Grabber for Norway',
#       exes => [ 'grab/no/tv_grab_no' ],
#       prereqs => { 'HTML::Entities' => 1.27 },
#     },

     { name => 'tv_grab_no_gfeed',
       blurb => 'Grabber for Norway (gfeed.info)',
       exes => [ 'grab/no_gfeed/tv_grab_no_gfeed' ],
       pl_files => { 'grab/no_gfeed/tv_grab_no_gfeed.PL'
                     => 'grab/no_gfeed/tv_grab_no_gfeed' },
       to_clean => [ 'grab/no_gfeed/tv_grab_no_gfeed' ],
       deps => [ 'grab/no_gfeed/tv_grab_no_gfeed'
                 => [ 'grab/se_swedb/tv_grab_se_swedb.in' ] ],
       prereqs => { 'XML::LibXML'    => 0,
                    'Compress::Zlib' => 0,
                    'IO::Stringy'    => 0,
                    'HTTP::Cache::Transparent' => 0, },
     },

     { name => 'tv_grab_pt',
       blurb => 'Grabber for Portugal',
       exes => [ 'grab/pt/tv_grab_pt' ],
       prereqs => { 'Getopt::Long'      => 0,
                    'HTML::TreeBuilder' => 0,
                    'HTML::Entities'    => 1.27,
                    'HTTP::Cache::Transparent' => 0,
                    'DateTime'          => 0,
                    'Encode'            => 0, 
                    'JSON::PP'          => 0, },
     },

     { name => 'tv_grab_pt_meo',
       blurb => 'Grabber for Portugal (MEO)',
       exes => [ 'grab/pt_meo/tv_grab_pt_meo' ],
       prereqs => { 'DateTime'    => 0,
                    'XML::LibXML' => 0,
                    'LWP'         => 0, },
     },

# rmeden 2011-06-12 not working
#    { name => 'tv_grab_re',
#       blurb => 'Grabber for Reunion Island (France)',
#       exes => [ 'grab/re/tv_grab_re' ],
#       prereqs => { 'HTML::TreeBuilder' => 0 ,
#                    'HTML::Entities'    => 0 } },

     { name => 'tv_grab_se_swedb',
       blurb => 'Grabber for Sweden',
       exes => [ 'grab/se_swedb/tv_grab_se_swedb' ],
       pl_files => { 'grab/se_swedb/tv_grab_se_swedb.PL'
                     => 'grab/se_swedb/tv_grab_se_swedb' },
       to_clean => [ 'grab/se_swedb/tv_grab_se_swedb' ],
       deps => [ 'grab/se_swedb/tv_grab_se_swedb'
                 => [ 'grab/se_swedb/tv_grab_se_swedb.in' ] ],
       prereqs => { 'XML::LibXML'    => 0,
                    'Compress::Zlib' => 0,
                    'IO::Stringy'    => 0,
                    'HTTP::Cache::Transparent' => 0, },
     },

     { name => 'tv_grab_se_tvzon',
       blurb => 'Grabber for Sweden (tvzon.se)',
       exes => [ 'grab/se_tvzon/tv_grab_se_tvzon' ],
       pl_files => { 'grab/se_tvzon/tv_grab_se_tvzon.PL'
                     => 'grab/se_tvzon/tv_grab_se_tvzon' },
       to_clean => [ 'grab/se_tvzon/tv_grab_se_tvzon' ],
       deps => [ 'grab/se_tvzon/tv_grab_se_tvzon'
                 => [ 'grab/se_swedb/tv_grab_se_swedb.in' ] ],
       prereqs => { 'XML::LibXML'    => 0,
                    'Compress::Zlib' => 0,
                    'IO::Stringy'    => 0,
                    'HTTP::Cache::Transparent' => 0, },
     },

     { name => 'tv_grab_tr',
       blurb => 'Grabber for Turkey (Digiturk)',
       exes => [ 'grab/tr/tv_grab_tr' ],
       prereqs => { 'HTTP::Cache::Transparent' => 1.0,
                    'LWP::UserAgent' => 0,
                    'HTTP::Cookies'  => 0,
                    'DateTime'       => 0,
                    'Date::Parse'    => 0,
                    'Encode'         => 0,
                    'URI::Escape'    => 0,
                    'File::Path'     => 0, },
     },

     { name => 'tv_grab_uk_atlas',
       blurb => 'Fast grabber for UK and Ireland using Atlas database',
       exes => [ 'grab/uk_atlas/tv_grab_uk_atlas' ],
       share_files => {
            'grab/uk_atlas/tv_grab_uk_atlas.user.map.conf'
                => 'tv_grab_uk_atlas/tv_grab_uk_atlas.user.map.conf',
            'grab/uk_atlas/tv_grab_uk_atlas.pa.genres.conf'
                => 'tv_grab_uk_atlas/tv_grab_uk_atlas.pa.genres.conf',
            'grab/uk_atlas/tv_grab_uk_atlas.map.genres.conf'
                => 'tv_grab_uk_atlas/tv_grab_uk_atlas.map.genres.conf',
            'grab/uk_atlas/tv_grab_uk_atlas.map.channels.conf'
                => 'tv_grab_uk_atlas/tv_grab_uk_atlas.map.channels.conf',
            'grab/uk_atlas/cgi-bin/getatlas.pl'
                => 'tv_grab_uk_atlas/cgi-bin/getatlas.pl', },
       prereqs => { 'HTTP::Cache::Transparent' => 1.0,
                    'LWP::UserAgent'  => 0,
                    'HTTP::Cookies'   => 0,
                    'JSON::PP'        => 0,
                    'DateTime'        => 0,
                    'Date::Parse'     => 0,
                    'Encode'          => 0,
                    'URI::Escape'     => 0,
                    'File::Path'      => 0,
                    'Data::Dumper'    => 0,
                    'Pod::Usage'      => 0, },
     },

     { name => 'tv_grab_uk_bleb',
       blurb => 'Fast alternative grabber for the UK',
       exes => [ 'grab/uk_bleb/tv_grab_uk_bleb' ],
       pl_files => { 'grab/uk_bleb/tv_grab_uk_bleb.PL' => 'grab/uk_bleb/tv_grab_uk_bleb' },
       share_files => { 'grab/uk_bleb/icon_urls' => 'tv_grab_uk_bleb/icon_urls' },
       to_clean => [ 'grab/uk_bleb/tv_grab_uk_bleb' ],
       deps => [ 'grab/uk_bleb/tv_grab_uk_bleb' => [ 'grab/uk_bleb/tv_grab_uk_bleb.in' ] ],
       grab_need_share => [ 'uk_bleb' ],
       prereqs => { 'IO::Stringy' => 0, 'Archive::Zip' => 0, },
     },

# [bilbo_uk] The Guardian have removed their online tv listings service @ 1/Oct/14
#     { name => 'tv_grab_uk_guardian',
#       blurb => 'Grabber for UK and Ireland using The Guardian website',
#       exes => [ 'grab/uk_guardian/tv_grab_uk_guardian' ],
#       share_files => {
#            'grab/uk_guardian/tv_grab_uk_guardian.map.conf'
#                => 'tv_grab_uk_guardian/tv_grab_uk_guardian.map.conf',
#       },
#       prereqs => { 'HTTP::Cache::Transparent' => 1.0,
#                    'DateTime'        => 0,
#                    'File::Path'      => 0,
#                    'Encode'          => 0, },
#     },

     { name => 'tv_grab_uk_rt',
       blurb => 'Grabber for UK and Ireland (Radio Times)',
       exes => [ 'grab/uk_rt/tv_grab_uk_rt' ],
       share_files => {
            'grab/uk_rt/channel_ids'
                => 'tv_grab_uk_rt/channel_ids',
            'grab/uk_rt/prog_titles_to_process'
                => 'tv_grab_uk_rt/prog_titles_to_process',
            'grab/uk_rt/regional_channels_by_postcode'
                => 'tv_grab_uk_rt/regional_channels_by_postcode',
            'grab/uk_rt/channels_platforms'
                => 'tv_grab_uk_rt/channels_platforms',
            'grab/uk_rt/utf8_fixups'
                => 'tv_grab_uk_rt/utf8_fixups',
            'grab/uk_rt/channel_icons'
                => 'tv_grab_uk_rt/channel_icons',

            'grab/uk_rt/lineups/xmltv-lineups.xsl'
                => 'tv_grab_uk_rt/lineups/xmltv-lineups.xsl',

            'grab/uk_rt/lineups/lineups.xml'
                => 'tv_grab_uk_rt/lineups/lineups.xml',

            'grab/uk_rt/lineups/freesatfromsky.xml'
                => 'tv_grab_uk_rt/lineups/freesatfromsky.xml',
            'grab/uk_rt/lineups/freesathd.xml'
                => 'tv_grab_uk_rt/lineups/freesathd.xml',
            'grab/uk_rt/lineups/freesat.xml'
                => 'tv_grab_uk_rt/lineups/freesat.xml',
            'grab/uk_rt/lineups/freeviewhd.xml'
                => 'tv_grab_uk_rt/lineups/freeviewhd.xml',
            'grab/uk_rt/lineups/freeview.xml'
                => 'tv_grab_uk_rt/lineups/freeview.xml',
            'grab/uk_rt/lineups/saorview.xml'
                => 'tv_grab_uk_rt/lineups/saorview.xml',
            'grab/uk_rt/lineups/skyhd.xml'
                => 'tv_grab_uk_rt/lineups/skyhd.xml',
            'grab/uk_rt/lineups/sky.xml'
                => 'tv_grab_uk_rt/lineups/sky.xml',
            'grab/uk_rt/lineups/upcirelandhd.xml'
                => 'tv_grab_uk_rt/lineups/upcirelandhd.xml',
            'grab/uk_rt/lineups/upcireland.xml'
                => 'tv_grab_uk_rt/lineups/upcireland.xml',
            'grab/uk_rt/lineups/virginhd.xml'
                => 'tv_grab_uk_rt/lineups/virginhd.xml',
            'grab/uk_rt/lineups/virgin.xml'
                => 'tv_grab_uk_rt/lineups/virgin.xml',

            'grab/uk_rt/lineups/freeview.map'
                => 'tv_grab_uk_rt/lineups/freeview.map',
            'grab/uk_rt/lineups/freesat.map'
                => 'tv_grab_uk_rt/lineups/freesat.map',
            'grab/uk_rt/lineups/saorview.map'
                => 'tv_grab_uk_rt/lineups/saorview.map', },
       prereqs => { 'HTTP::Cache::Transparent' => 1.0,
                    'IO::Stringy'        => 0,
                    'LWP::UserAgent'     => 0,
                    'DateTime'           => 0,
                    'DateTime::Duration' => 0,
                    'DateTime::TimeZone' => 0,
                    'HTML::Entities'     => 1.27,
                    'XML::LibXML'        => 0, },
     },

     { name => 'tv_grab_uk_tvguide',
       blurb => 'Grabber for UK and Ireland using TV Guide website',
       exes => [ 'grab/uk_tvguide/tv_grab_uk_tvguide' ],
       share_files => {
            'grab/uk_tvguide/tv_grab_uk_tvguide.map.conf'
                => 'tv_grab_uk_tvguide/tv_grab_uk_tvguide.map.conf',
       },
       prereqs => { 'HTTP::Cache::Transparent' => 1.0,
                    'DateTime'        => 0,
                    'Date::Parse'     => 0,
                    'Encode'          => 0,
                    'URI::Escape'     => 0,
                    'File::Path'      => 0,
                    'Data::Dumper'    => 0, },
     },

# honir 2015-03-05 hasn't worked since 2014-11-19 - source site permanently broken
#     { name => 'tv_grab_za',
#       blurb => 'Grabber for South Africa',
#       exes => [ 'grab/za/tv_grab_za' ],
#       prereqs => { 'HTML::TreeBuilder' => 0,
#                    'HTML::Entities' => 1.27 } },

     { name => 'tv_check',
       blurb => 'Program to report exceptions and changes in a schedule',
       exes => [ 'choose/tv_check/tv_check' ],
       docs => [ qw(choose/tv_check/README.tv_check
                    choose/tv_check/tv_check_doc.html
                    choose/tv_check/tv_check_doc.jpg
                   ) ],
       prereqs => { 'Tk' => 0,
                    'Tk::TableMatrix' => 0, }
     },

     { name => 'tv_grab_combiner',
       blurb => 'Grabber that combines data from other grabbers',
       exes => [ 'grab/combiner/tv_grab_combiner' ],
       prereqs => { 'XML::LibXML' => 0, },
     },

     { name => 'tv_pick_cgi',
       blurb => 'CGI program to filter listings (to install manually)',
       prereqs => { 'CGI' => 0, },
       type => 'run',
     },

    );

# Now we need to prompt about each optional component.  The style of
# prompting, though not the code, is based on SOAP::Lite.  I would
# like to add '--noprompt' and '--with tv_grab_nl' options to help
# automated package building, but I haven't implemented that yet.
#

# For each component work out whether its prereqs are installed and
# store the result in {missing} - either false, or a hashref.
#
foreach my $info (@opt_components) {
    my $name = $info->{name};
    my %modules_missing;
    our %module_prereqs;
    local *module_prereqs = $info->{prereqs} || {};
    foreach (sort keys %module_prereqs) {
        my $ver = $module_prereqs{$_};
        next if test_module($_, $ver)->[0] eq 'OK';
        warn "strange, module prereq $_ mentioned twice"
          if defined $modules_missing{$_};
        $modules_missing{$_} = $ver;
    }

    our @special_prereqs;
    my %special_missing;
    local *special_prereqs = $info->{special_prereqs} || {};
    foreach (@special_prereqs) {
        my ($sub, $name, $ver, $friendly_ver) = @$_;
        next if test_special($sub, $ver)->[0] eq 'OK';
        warn "strange, special prereq $name mentioned twice"
          if defined $special_missing{$name};
        $special_missing{$name} = $friendly_ver;
    }

    my %missing = (%modules_missing, %special_missing);
    if (not keys %missing) {
        $info->{missing} = 0;
    }
    else {
        $info->{missing} = \%missing;
    }
}

if (not defined $opt_components) {
    # Generate a default configuration that installs as much as possible.
    print STDERR <<END

Choose which optional components of xmltv you want to install.  The
XMLTV.pm library and the filter programs such as tv_grep and tv_sort
are installed by default; here you choose grabbers for different
countries and front-ends for managing listings.

END
;

    my %by_name;
    foreach (@opt_components) {
        $by_name{$_->{name}} = $_;
        $_->{exclude} = 0; # default if not mentioned
    }

    if (defined $opt_exclude) {
        foreach (split /,/, $opt_exclude) {
            my $i = $by_name{$_};
            die "unknown component $_\n" if not $i;
            $i->{exclude} = 1;
        }
    }

    my $width = 0;
    foreach my $info (@opt_components) {
        my $w = length("$info->{blurb} ($info->{name})");
        $width = $w if $w > $width;
    }
    foreach my $info (@opt_components) {
        my $missing = $info->{missing};
        my $s = "$info->{blurb} ($info->{name})";

        # Guess a default value for {install} based on whether
        # prerequisites were found.
        #
        $info->{install} = (not $info->{exclude}) && ($opt_yes || not $info->{missing});

        print STDERR ($s, ' ' x (1 + $width - length $s),
                      $info->{install} ? '[yes]' : '[no]',
                      "\n");
    }
    print STDERR "\n";
    if (not ask(0, 'Do you want to proceed with this configuration?', 1)) {
        # Need to set {install} for each component by prompting.
        foreach my $info (@opt_components) {
            my $missing = $info->{missing};
            my $name = $info->{name};
            print STDERR "\n* $info->{blurb} ($name)\n\n";
            if ($missing) {
                print STDERR "These dependencies are missing for $name:\n\n";
                foreach (sort keys %$missing) {
                    print STDERR "$_";
                    my $min_ver = $missing->{$_};
                    if ($min_ver) {
                        print STDERR " (version $min_ver or higher)";
                    }
                    print STDERR "\n";
                }
                print STDERR "\n";
            }

            my $msg;
            my $type = $info->{type};
            if (not defined $type or $type eq 'install') {
                $msg = "Do you wish to install $name?";
            } elsif ($type eq 'run') {
                $msg = "Do you plan to run $name?";
            } else {
                die;
            }

            $info->{install} =
              ask(0, $msg, not $missing);
        }
    }
}
else {
    my @to_install = split /\s+/, $opt_components;
    my %by_name;
    foreach (@opt_components) {
        $by_name{$_->{name}} = $_;
        $_->{install} = 0; # default if not mentioned
    }
    foreach (@to_install) {
        my $i = $by_name{$_};
        die "unknown component $_\n" if not $i;
        $i->{install} = 1;
    }
}

foreach my $info (@opt_components) {
    next if not $info->{install};
    push @exes, @{$info->{exes}}                  if $info->{exes};
    push @docs, @{$info->{docs}}                  if $info->{docs};
    %pm = (%pm, %{$info->{pm}})                   if $info->{pm};
    %prereqs = (%prereqs, %{$info->{prereqs}})    if $info->{prereqs};
    %pl_files = (%pl_files, %{$info->{pl_files}}) if $info->{pl_files};
    %share_files = (%share_files, %{$info->{share_files}})
      if $info->{share_files};
    push @to_clean, @{$info->{to_clean}}          if $info->{to_clean};
    push @deps, @{$info->{deps}}                  if $info->{deps};
    push @grab_need_share, @{$info->{grab_need_share}}
      if $info->{grab_need_share};
}

my $warned_uninstall_broken = 1;


# Test the installed version of a module.
#
# Parameters:
#   Name of module
#   Version required, or 0 for don't care
#
# Returns a tuple of two scalars: the first scalar is one of
#
# OK            - a recent enough version is installed.
# NOT_INSTALLED - the module is not installed.
# FAILED        - the second scalar contains an error message.
# TOO_OLD       - the second scalar contains the version found.
#
sub test_module( $$ ) {
    my ($mod, $minver) = @_;
    die if not defined $mod; die if not defined $minver;
    eval "require $mod";
    if ($@) {
        # This if-test is separate to suppress spurious 'Use of
        # uninitialized value in numeric lt (<)' warning.
        #
        if ($@ ne '') {
            if ($@ =~ /^Can\'t locate \S+\.pm in \@INC/) {
                return [ 'NOT_INSTALLED', undef ];
            }
            else {
                chomp (my $msg = $@);
                return [ 'FAILED', $msg ];
            }
        }
    }

    my $ver = $mod->VERSION;
    if ($minver ne '0') {
        return [ 'TOO_OLD', undef ] if not defined $ver;
        return [ 'TOO_OLD', $ver ] if $ver lt $minver;
    }

    return [ 'OK', undef ];
}

# Run a subroutine and check that its output has the correct version.
#
# Parameters:
#   code reference to run
#   minumum version
#
# The code ref should return undef meaning 'package not present' or
# else a version number.
#
# Returns as for test_module() (but 'FAILED' not an option).
#
sub test_special( $$ ) {
    my ($sub, $minver) = @_;
    my $ver = $sub->();
    return [ 'NOT_INSTALLED', undef ] if not defined $ver;
    if ($minver ne '0') {
        return [ 'TOO_OLD', undef ] if not defined $ver;
        return [ 'TOO_OLD', $ver ] if $ver lt $minver;
    }
    return [ 'OK', undef ];
}

# MakeMaker's warning message can be intimidating, check ourselves
# first.  We warn about missing 'recommended' modules but don't abort
# because of them.
#
my $err = 0;
foreach my $p ((sort keys %prereqs), (sort keys %recommended)) {
    my $required = (defined $prereqs{$p});
    my $verbed = $required ? 'required' : 'recommended';
    my $Verbed = uc(substr($verbed, 0, 1)) . substr($verbed, 1);
    my $minver = $required ? $prereqs{$p} : $recommended{$p};
    die "bad minver for $p" if not defined $minver;
    my ($r, $more) = @{test_module($p, $minver)};
    if ($r eq 'OK') {
        # Installed and recent enough.
    }
    elsif ($r eq 'NOT_INSTALLED') {
        print STDERR "Module $p seems not to be installed.\n";
        print(($minver ? "$p $minver" : $p), " is $verbed.\n");
        ++ $err if $required;
    }
    elsif ($r eq 'FAILED') {
        print STDERR "$Verbed module $p failed to load: $more\n";
        print(($minver ? "$p $minver" : $p), " is $verbed.\n");
        ++ $err if $required;
    }
    elsif ($r eq 'TOO_OLD') {
        if (defined $more) {
            print STDERR "$p-$minver is $verbed, but $more is installed\n";
        }
        else {
            print STDERR "$p-$minver is $verbed, but an unknown version is installed\n";
        }
        ++ $err if $required;
    }
    else { die }
}
if ($err) {
    if ($opt_strictdeps) {
        die "Required modules missing.  Makefile will not be created.\n";
    }
    else {
        warn "Required modules missing, 'make' is unlikely to work\n";
    }
}

WriteMakefile
  (
   'NAME'          => 'XMLTV',
   # No VERSION_FROM, it's set in this file
   'EXE_FILES'     => \@exes,
   'PL_FILES'      => \%pl_files,
   'PM'            => \%pm,
   'PREREQ_PM'     => \%prereqs,
    # No special parameters for 'make clean' or 'make dist'
  );


sub MY::constants {
    package MY;
    my $inherited = shift->SUPER::constants(@_);
    die if not keys %::extra_constants;
    foreach (sort keys %::extra_constants) {
        $inherited .= "$_ = $::extra_constants{$_}\n";
    }
    return $inherited;
}
sub MY::install {
    package MY;
    my $inherited = shift->SUPER::install(@_);

    # Decided that 'plaindoc_install' should be directly under
    # 'install', not under the misleadingly named 'doc_install'.
    #
    my %extra_deps = (install => [ 'plaindoc_install', 'share_install' ]);
    foreach my $t (keys %extra_deps) {
        foreach my $d (@{$extra_deps{$t}}) {
            $inherited =~ s/^(\s*$t\s+::\s.+)/$1 $d/m or die;
        }
    }

    foreach (qw(plaindoc share)) {
        my $target = $_ . '_install';
        my $uc = uc;

        my $inst_var = "INST_$uc";
        my $extra = <<END
# Add code to create the directory under blib/.
\$($inst_var)/.exists :: \$(PERL_INC)/perl.h
	\@\$(MKPATH) \$($inst_var)
	\@\$(EQUALIZE_TIMESTAMP) \$(PERL_INC)/perl.h \$($inst_var)/.exists
	-\@\$(CHMOD) \$(PERM_RWX) \$($inst_var)

# Create a target to install to the final location.
$target ::
        \@echo Installing contents of \$(INST_$uc) into \$(INSTALL$uc)
        \@\$(MOD_INSTALL) \\
                \$(INST_$uc) \$(INSTALL$uc)

END
;
        $extra =~ s/ {8}/\t/g;
        $inherited .= $extra;
    }

    # Remove existing non-working 'uninstall' target.
    $inherited =~ s!^uninstall\s:.*$!!m
      or die "no uninstall target in: $inherited";

    # For each *_install create a corresponding _uninstall.
    my $targets = ::targets($inherited);
    foreach (qw(pure_perl_install pure_site_install plaindoc_install share_install)) {
        die "no $_ in: $inherited" if not defined $targets->{$_};
        my @t = @{$targets->{$_}}; # make a copy
        my $done = 0;
        foreach (@t) {
            if (s/\@\$\(MOD_INSTALL\)/\$(PERL) -I. -MUninstall -e "uninstall(\@ARGV)"/) {
                $done = 1;
                last;
            }
            s/Installing contents of (\S+) into (\S+)/Removing contents of $1 from $2/;
        }
        if (not $done) {
            print STDERR "couldn't find \@\$(MOD_INSTALL) in target $_, uninstall may not work\n"
              unless $warned_uninstall_broken;
        }
        (my $new_target = $_) =~ s/install$/uninstall/ or die;
        foreach ("\n\n$new_target ::\n", @t) {
            $inherited .= $_;
        }
    }
    $inherited .= 'pure_uninstall :: pure_$(INSTALLDIRS)_uninstall' . "\n";
    $inherited .= 'uninstall :: all pure_uninstall plaindoc_uninstall share_uninstall' . "\n";

    # Add a target for a Windows distribution.  Note this is
    # singlequoted and then we substitute one variable by hand!
    #
    $inherited .= q{

xmltv.exe :: $(EXE_FILES) lib/exe_wrap.pl lib/exe_opt.pl
	echo $(EXE_FILES)                             >exe_files.txt
	perl lib/exe_opt.pl $(VERSION)                >exe_opt.txt
	echo -lib  $(INST_ARCHLIB) --lib $(INST_LIB) >>exe_opt.txt
	echo -add  "$(EXE_FILES)"                    >>exe_opt.txt
	echo -bind exe_files.txt                     >>exe_opt.txt
	echo -exe  xmltv.exe                         >>exe_opt.txt
	perlapp @exe_opt.txt lib/exe_wrap.pl
	$(RM_F) exe_files.txt
	$(RM_F) exe_opt.txt

windows_dist ::
	@perl -e "if (-e '$location') { print STDERR qq[To build a Windows distribution, please rerun Makefile.PL with\nPREFIX set to a new (nonexistent) directory then 'make windows_dist'.\n(Remember that only absolute paths work properly with MakeMaker.)\n]; exit 1 }"
	@perl -e 'print "Have you updated doc/README.win32 for this release? "; exit 1 unless <STDIN> =~ /^[yY]/'
	$(MAKE) install
	perl -MExtUtils::Command -e mv $(INSTALLPLAINDOC) $location/doc/
	perl -MExtUtils::Command -e rm_r $location/share/doc
	perl -MExtUtils::Command -e mkpath $location/doc/man
	# Generate plain text documentation from pod.
	perl -e "chdir 'blib/script' or die; foreach (<*>) { system qq'pod2text <\$$_ >$location/doc/man/\$$_.txt' }"
	# Remove 'real' manual pages, not needed on Windows.
	perl -MExtUtils::Command -e rm_rf $location/man $location/share/man
	# My MakeMaker creates this dud directory.
	perl -MExtUtils::Command -e rm_rf $location/5.8.0
	rmdir $location/share/doc
	# Generate Date::Manip docs by filtering perldoc output.  The
	# use of temp files instead of pipes is so set -e works properly.
	#
	echo Extracting part of Date::Manip manual page into $location/doc/man/date_formats.txt
	echo "This is an extract from the documentation of Perl's Date::Manip module," >>$location/doc/man/date_formats.txt
	echo "describing the different format strings that may be used for dates."     >>$location/doc/man/date_formats.txt
	echo "Bear in mind that depending on your Windows version you will need to"    >>$location/doc/man/date_formats.txt
	echo "quote the % characters on the command line somehow (see README.win32)."  >>$location/doc/man/date_formats.txt
	echo "" >>$location/doc/man/date_formats.txt
	perldoc -u Date::Manip >$location/doc/man/date_formats.txt.tmp
	perl -ne "BEGIN { print qq'\n=pod\n\n' } print if (/^The format options are:/ .. /^=/) and not /^=/" <$location/doc/man/date_formats.txt.tmp >$location/doc/man/date_formats.txt.tmp.1
	pod2text <$location/doc/man/date_formats.txt.tmp.1 >>$location/doc/man/date_formats.txt
	perl -MExtUtils::Command -e rm_f $location/doc/man/date_formats.txt.tmp*
	# Don't use $(INSTALLBIN), it seems to disregard PREFIX passed
	# to 'make'.
	#
	perl -MExtUtils::Command -e rm_rf $location/bin/ $location/lib/ $(INSTMANDIR) $(INSTALLMAN3DIR)
	perl -MExtUtils::Command -e cp xmltv.dtd $location
	perl -MExtUtils::Command -e cp xmltv-lineups.xsd $location
	perl -MExtUtils::Command -e cp ChangeLog $location/ChangeLog.txt
	# The following command will not be necessary when the source
	# tree was checked out on a DOSish system.  It may not even
	# work properly when run on a DOSish system - should check.
	#
	# (Simulation in perl of find | xargs; there's probably a
	# better way but I'm too lazy to find it.)
	#
	perl -MFile::Find -e "find(sub { print qq[\\$$File::Find::name\n] if -f and not /[.]jpg/ }, '$location')" | perl -e 'chomp(@ARGV = (@ARGV, <STDIN>)); exec @ARGV' perl -i -pe 'BEGIN { binmode STDIN } s/\r*\n*$$/\r\n/'
	perl -MExtUtils::Command -e mv $location/doc/README* $location
	perl -MExtUtils::Command -e mv $location/README.win32 $location/README.txt
	@echo
	@echo Part of a Windows distribution tree has been made in $location/.
	@echo Now copy in the executables!

};
    $inherited =~ s/\$location/$location/g or die;

    return $inherited;
}

# Extend installbin() to put doc and share under blib/.
sub MY::installbin {
    package MY;
    my $inherited = shift->SUPER::installbin(@_);

    # Add a target for each documentation file.
    my %doc_files;
    foreach (@::docs) {
        $doc_files{$_} = File::Basename::basename($_);
    }

    my %new_filetypes = (plaindoc => \%doc_files, share => \%share_files);
    my %seen_dir;
    foreach my $filetype (sort keys %new_filetypes) {
        my $uc = uc $filetype;
        our %files; local *files = $new_filetypes{$filetype};
        foreach my $src (sort keys %files) {
            my $inst_pos = $files{$src};
            my $extra = '';

            # The directory containing this file in blib/ needs to be created.
            my @dirs = split m!/!, $inst_pos; pop @dirs;
            foreach (0 .. $#dirs) {
                my $dir = join('/', @dirs[0 .. $_]);
                my $parent = join('/', @dirs[0 .. $_-1]);
                next if $seen_dir{$dir}++;
                die if (length $parent and not $seen_dir{$parent});
                my $parent_exists = "\$(INST_$uc)/$parent/.exists";
                $parent_exists =~ tr!/!/!s;
                $extra .= <<END
\$(INST_$uc)/$dir/.exists :: \$(PERL_INC)/perl.h $parent_exists
	\@\$(MKPATH) \$(INST_$uc)/$dir
	\@\$(EQUALIZE_TIMESTAMP) \$(PERL_INC)/perl.h \$(INST_$uc)/$dir/.exists
	-\@\$(CHMOD) \$(PERM_RWX) \$(INST_$uc)/$dir
END
;
            }
            my $dir_exists = "\$(INST_$uc)/" . join('/', @dirs) . '/.exists';
            $dir_exists =~ tr!/!/!s;

            $extra .= <<END
\$(INST_$uc)/$inst_pos: $src Makefile $dir_exists
	\@\$(RM_F) \$(INST_$uc)/$inst_pos
	perl -MExtUtils::Command -e cp $src \$(INST_$uc)/$inst_pos
	-\@\$(CHMOD) \$(PERM_RW) \$(INST_$uc)/$inst_pos
END
;
            $extra =~ s/ {8}/\t/g;
            $inherited .= $extra;
        }

        # These targets need to be added to pure_all, using a new target
        # pure_$filetype.
        #
        $inherited =~ s/^(\s*pure_all\s+::\s.+)/$1 pure_$filetype/m
          or die "no pure_all in: $inherited";
        $inherited .= "pure_$filetype :: ";
        foreach (sort keys %files) {
            my $inst_pos = $files{$_};
            $inherited .= "\$(INST_$uc)/$inst_pos ";
        }
        $inherited .= "\n\t\@\$(NOOP)\n";

        # And realclean should remove them, by calling realclean_$filetype.
        $inherited =~ s/^(\s*realclean\s+::\s[^\\]+)/$1 realclean_$filetype /m or die;
        $inherited .= "realclean_$filetype ::\n\t\$(RM_F) ";
        foreach (sort keys %files) {
            my $inst_pos = $files{$_};
            $inherited .= "\$(INST_$uc)/$inst_pos ";
        }
        $inherited .= "\n";
    }

    return $inherited;
}

# 'make clean' doesn't remove generated files from *.PL (see posting
# to makemaker@perl.org).  Fix it.
#
sub MY::clean {
    package MY;
    my $inherited = shift->SUPER::clean(@_);
    $inherited =~ s/\s+$//;
    $inherited .= "\n\t-\$(RM_F) $_\n" foreach @to_clean;
    return $inherited;
}

sub MY::processPL {
    package MY;
    my $inherited = shift->SUPER::processPL(@_);

    # Add some exra dependencies.
    my ($k, $v);
    while (@deps) {
        ($k, $v, @deps) = @deps;
        $inherited =~ s!^(\s*$k\s+::\s.+)!"$1 " . join(' ', @$v)!me
          or die "no $k in: $inherited";
    }

    # And some of the .in generators need the share/ directory passed
    # as an extra argument.  This is the location in the installed
    # system, not that where files are being copied, so $(PREFIX) but
    # no $(DESTDIR).
    #
    foreach (@grab_need_share) {
        $inherited =~
          s<(grab/$_/tv_grab_$_.PL grab/$_/tv_grab_$_)\s*$>
            <$1 \$(PREFIX)/share/xmltv>m
            or die "no call to $_.PL in: $inherited";
    }

    foreach (@need_share) {
        $inherited =~
          s<($_.PL $_)\s*$>
            <$1 \$(PREFIX)/share/xmltv>m
            or die "no call to $_.PL in: $inherited";
    }


    return $inherited;
}

sub MY::makefile {
    package MY;
    my $inherited = shift->SUPER::makefile(@_);
    return $inherited;
}

# Fix filename of some generated manpages.
sub MY::manifypods {
    package MY;
    for (my $inherited = shift->SUPER::manifypods(@_)) {
        foreach my $s (qw(Grab_XML Configure::Writer Configure Data::Recursive::Encode Date GUI Gunzip Options PreferredMethod Summarize Supplement ValidateFile ValidateGrabber Version)) {
            s!\$\(INST_MAN3DIR\)/(?:grab::|)$s[.]\$\(MAN3EXT\)!"\$(INST_MAN3DIR)/XMLTV::$s.\$(MAN3EXT)"!;
            s!\$\(INSTALLMAN3DIR\)/$s.\$\(MAN3EXT\)!"\$(INSTALLMAN3DIR)/XMLTV::$s.\$(MAN3EXT)"!;
        }
        return $_;
    }
}

# Split a section of makefile into targets.
sub targets( $ ) {
    my @lines = split /\n/, shift;
    $_ .= "\n" foreach @lines;
    my %r;
    my $curr_target;
    foreach (@lines) {
        if (/^(\S+)\s+:/) {
            # Beginning of a new target.
            my $name = $1;
            die "target $name seen twice" if defined $r{$name};
            $r{$name} = $curr_target = [];
        }
        elsif (/^\s+/ and defined $curr_target) {
            # Commands for the target.
            push @$curr_target, $_;
        }
        elsif (/^$/) {
            # Blank lines are legal in a target definition
        }
        elsif (/^\s*(?:\#.*)?$/) {
            undef $curr_target;
        }
        else {
            chomp;
            die "bad makefile line: '$_'";
        }
    }
    return \%r;
}
