#!/usr/bin/perl -w

use ExtUtils::MakeMaker;
use Config;
use File::Basename ();
use File::Find;
use Getopt::Long qw(:config pass_through);
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
such as 5.6.1 or 5.8.0.
END
  ;
}

# A couple of undocumented options to help with building the Windows
# distribution even on hosts that don't have all the necessary
# modules.
#
my $opt_nodeps = 0;
my $opt_yes = 0;
GetOptions('nodeps' => \$opt_nodeps, 'yes' => \$opt_yes);

our $VERSION;
$VERSION = '0.5.16';

our %extra_constants;
%extra_constants
  = (INST_PLAINDOC   => 'blib/doc',
     INSTALLPLAINDOC => "\$(PREFIX)/share/doc/xmltv-$::VERSION",
     INST_SHARE      => 'blib/share',
     INSTALLSHARE    => '$(PREFIX)/share/xmltv',

     # Manual page constants, shouldn't really be needed, but work
     # around bugs and make sure this stuff is the same across
     # MakeMaker versions.
     INSTALLMAN1DIR  => '$(PREFIX)/share/man/man1',
     INSTALLMAN3DIR  => '$(PREFIX)/share/man/man3',
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
  = qw(filter/tv_extractinfo_en
       filter/tv_grep
       filter/tv_sort
       filter/tv_to_latex
       filter/tv_to_text
       filter/tv_cat
       filter/tv_split
       filter/tv_imdb
      );

# Libraries to be installed.
my %pm
  = ('lib/XMLTV.pm'               => '$(INST_LIBDIR)/XMLTV.pm',
     'lib/TZ.pm'                  => '$(INST_LIBDIR)/XMLTV/TZ.pm',
     'lib/Clumps.pm'              => '$(INST_LIBDIR)/XMLTV/Clumps.pm',
     'lib/Usage.pm'               => '$(INST_LIBDIR)/XMLTV/Usage.pm',
     'lib/Version.pm'             => '$(INST_LIBDIR)/XMLTV/Version.pm',
     'lib/Ask.pm'                 => '$(INST_LIBDIR)/XMLTV/Ask.pm',
     'lib/Summarize.pm'           => '$(INST_LIBDIR)/XMLTV/Summarize.pm',
     'lib/IMDB.pm'                => '$(INST_LIBDIR)/XMLTV/IMDB.pm',
     'lib/Gunzip.pm'              => '$(INST_LIBDIR)/XMLTV/Gunzip.pm',
     'filter/Grep.pm'             => '$(INST_LIBDIR)/XMLTV/Grep.pm',
     'grab/Memoize.pm'            => '$(INST_LIBDIR)/XMLTV/Memoize.pm',
     'grab/Grab_XML.pm'           => '$(INST_LIBDIR)/XMLTV/Grab_XML.pm',
     'grab/Europe_TZ.pm'          => '$(INST_LIBDIR)/XMLTV/Europe_TZ.pm',
     'grab/Config_file.pm'        => '$(INST_LIBDIR)/XMLTV/Config_file.pm',
     'grab/Get_nice.pm'           => '$(INST_LIBDIR)/XMLTV/Get_nice.pm',
     'grab/Mode.pm'               => '$(INST_LIBDIR)/XMLTV/Mode.pm',
    );

# Modules required to install.
my %prereqs
  = (
     'LWP'         => 5.65,
     'XML::Twig'   => 3.09,
     'Date::Manip' => 5.42,
     'XML::Writer' => 0,
     'Memoize'     => 0,
     'Storable'    => 2.04,
    );

# Files which are run to generate source code.
my %pl_files = ('filter/tv_grep.PL'     => 'filter/tv_grep',
		'lib/XMLTV.pm.PL'       => 'lib/XMLTV.pm',
	       );

# Files to be installed in the system-wide share/ directory.
my %share_files;

# Files which 'make clean' should remove, but doesn't by default, so
# we have to patch it.
#
my @to_clean = ('filter/tv_grep',
		'lib/XMLTV.pm');

# Extra dependencies to add to the Makefile.
my @deps = ('filter/tv_grep' => [ qw(filter/tv_grep.in pm_to_blib) ],
	    'lib/XMLTV.pm' => [ 'lib/XMLTV.pm.in' ]);

# Some grabbers which are generated from .PL files need the share/
# directory passed as an extra argument.
#
my @grab_need_share;

# Flag to trigger special installation for tv_grab_uk (currently no
# other grabber needs the same variable-number-of-files installation).
#
my $do_uk_channel_pkgs = 0;

# 'Recommended but not required'.  It isn't currently handled to have
# the same module in both sets.
#
my %recommended
  = (
     'Lingua::EN::Numbers::Ordinate' => 0,
     'Lingua::Preferred' => 0,
     'Term::ProgressBar' => 2.03,
     'Compress::Zlib' => 0,
     'Unicode::String' => 0,
    );

# And Log::TraceMessages is 'suggested' but we don't warn about that.

if ($opt_yes) {
    *ask = sub { print "$_[0] yes\n"; 1 };
}
else {
    do 'lib/Ask.pm' or die 'could not load lib/Ask.pm, aborting';
    *ask = \&XMLTV::Ask::askBooleanQuestion;
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
    if (! ask("Do you wish to continue anyway?", 0)) {
	exit(1);
    }
}

# Now prompt about how much to install.  This is really only to
# reduce dependencies.  In the long run things like tv_check can be
# spun off into separate projects.
#
my @opt_components
  = ({ name => 'tv_grab_de',
       blurb => 'Grabber for Germany and Austria',
       exes => [ 'grab/de/tv_grab_de' ],
     },

     { name => 'tv_grab_uk',
       blurb => 'Grabber for Britain',
       exes => [ 'grab/uk/tv_grab_uk' ],
       pl_files => { 'grab/uk/tv_grab_uk.PL' => 'grab/uk/tv_grab_uk' },
       share_files => { 'grab/uk/channel_ids' => 'tv_grab_uk/channel_ids' },
       to_clean => [ 'grab/uk/tv_grab_uk' ],
       deps => [ 'grab/uk/tv_grab_uk' => [ 'grab/uk/tv_grab_uk.in' ] ],
       grab_need_share => [ 'uk' ],
       do_uk_channel_pkgs => 1,
     },

     { name => 'tv_grab_uk_rt',
       blurb => 'Alternative grabber for Britain',
       exes => [ 'grab/uk_rt/tv_grab_uk_rt' ],
       pl_files => { 'grab/uk_rt/tv_grab_uk_rt.PL' => 'grab/uk_rt/tv_grab_uk_rt' },
       share_files => { 'grab/uk_rt/channel_ids' => 'tv_grab_uk_rt/channel_ids' },
       to_clean => [ 'grab/uk_rt/tv_grab_uk_rt' ],
       deps => [ 'grab/uk_rt/tv_grab_uk_rt' => [ 'grab/uk_rt/tv_grab_uk_rt.in' ] ],
       grab_need_share => [ 'uk_rt' ],
     },

     { name => 'tv_grab_it',
       blurb => 'Grabber for Italy',
       exes => [ 'grab/it/tv_grab_it' ],
       pl_files => { 'grab/it/tv_grab_it.PL' => 'grab/it/tv_grab_it' },
       share_files => { 'grab/it/dud_channels' => 'tv_grab_it/dud_channels' },
       to_clean => [ 'grab/it/tv_grab_it' ],
       deps => [ 'grab/it/tv_grab_it' => [ 'grab/it/tv_grab_it.in' ] ],
       grab_need_share => [ 'it' ],
     },

     { name => 'tv_grab_na',
       blurb => 'Grabber for North America',
       exes => [ 'grab/na/tv_grab_na' ],
       pm => { 'grab/na/ZapListings.pm' =>
	       '$(INST_LIBDIR)/XMLTV/ZapListings.pm' },
       prereqs => { 'HTML::Parser' => 0 } },

     { name => 'tv_grab_sn',
       blurb => 'Grabber for Sweden and Norway',
       exes => [ 'grab/sn/tv_grab_sn' ],
       prereqs => { 'HTML::TableExtract' => '1.08' } },

#      { name => 'tv_grab_nz',
#        blurb => 'Grabber for New Zealand',
#        exes => [ 'grab/nz/tv_grab_nz' ],
#        pl_files => { 'grab/nz/tv_grab_nz.PL' => 'grab/nz/tv_grab_nz' },
#        share_files => { 'grab/nz/episode_names' => 'tv_grab_nz/episode_names' },
#        to_clean => [ 'grab/nz/tv_grab_nz' ],
#        deps => [ 'grab/nz/tv_grab_nz' => [ 'grab/nz/tv_grab_nz.in' ] ],
#        grab_need_share => [ 'nz' ],
#        prereqs => {},
#        special_prereqs =>
#        [ [ sub {
# 	       my $p = `python -c 'import sys; print sys.hexversion'`;
# 	       chomp $p;
# 	       return $p;
# 	   },
# 	   'Python', '17105648', '1.5.2' ] ] },

     { name => 'tv_grab_fi',
       blurb => 'Grabber for Finland',
       exes => [ 'grab/fi/tv_grab_fi' ],
       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_grab_es',
       blurb => 'Grabber for Spain',
       exes => [ 'grab/es/tv_grab_es' ],
       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_grab_nl',
       blurb => 'Grabber for the Netherlands',
       exes => [ 'grab/nl/tv_grab_nl' ],
       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_grab_nl_wolf',
       blurb => 'Alternative grabber for the Netherlands',
       exes => [ 'grab/nl_wolf/tv_grab_nl_wolf' ],
       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_grab_hu',
       blurb => 'Grabber for Hungary',
       exes => [ 'grab/hu/tv_grab_hu' ],
       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_grab_dk',
       blurb => 'Grabber for Denmark',
       exes => [ 'grab/dk/tv_grab_dk' ],
       prereqs => { 'HTML::TreeBuilder' => 0 } },

     { name => 'tv_check',
       blurb => 'Program to report exceptions and changes in a schedule',
       exes => [ 'choose/tv_check/tv_check' ],
       docs => [ qw(choose/tv_check/README.tv_check
		    choose/tv_check/tv_check_doc.html
		    choose/tv_check/tv_check_doc.jpg
		   ) ],
       prereqs => { 'Tk' => 0,
		    'Tk::TableMatrix' => 0,
		    'XML::Simple' => 0,
		  } },

     { name => 'tv_pick_cgi',
       blurb => 'CGI program to filter listings (to install manually)',
       prereqs => { 'CGI' => 0 },
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

# Generate a default configuration that installs as much as possible.
print STDERR <<END

Choose which optional components of xmltv you want to install.  The
XMLTV.pm library and the filter programs such as tv_grep and tv_sort
are installed by default; here you choose grabbers for different
countries and front-ends for managing listings.

END
  ;

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
    $info->{install} = $opt_yes || not $info->{missing};

    print STDERR ($s, ' ' x (1 + $width - length $s),
		  $info->{install} ? '[yes]' : '[no]',
		  "\n");
}
print STDERR "\n";
if (not ask('Do you want to proceed with this configuration?', 1)) {
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
	}
	elsif ($type eq 'run') {
	    $msg = "Do you plan to run $name?";
	}
	else { die }
	
	$info->{install} =
	  ask($msg, not $missing);
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
    for ($info->{do_uk_channel_pkgs}) {
	if (defined) {
	    die 'turn on, but not off' if not $_;
	    $do_uk_channel_pkgs = 1;
	}
    }
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
if ($err and not $opt_nodeps) {
    die "Required modules missing, not writing Makefile\n";
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

    # Add a target for a Windows distribution.
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
	@if test -e $(PREFIX); then \
	        echo To build a Windows distribution, please rerun Makefile.PL with >&2; \
	        echo "PREFIX set to a new (nonexistent) directory then 'make windows_dist'." >&2; \
	        echo '(Remember that only absolute paths work properly with MakeMaker.)' >&2; \
	        exit 1; \
	fi
	$(MAKE) install
	perl -MExtUtils::Command -e mv $(INSTALLPLAINDOC) $(PREFIX)/doc/
	perl -MExtUtils::Command -e rm_r $(PREFIX)/share/doc
	perl -MExtUtils::Command -e mkpath $(PREFIX)/doc/man
	# Convert the manual pages to plain text.  A bit roundabout,
	# this, we could just use pod2text to start with.  But since
	# 'make' generates troff documentation anyway this code is
	# easier.
	#
	set -e; for i in $(INST_MAN1DIR)/*; do \
	        b=`basename $$i .1`; \
	        if test "$$b" = '*'; then \
	                echo cannot find manpages in $(INST_MAN1DIR) >&2; \
	                exit 1; \
	        fi; \
	        echo Converting $$i to plain text; \
	        troff -mandoc -Tascii $$i | grotty -buo \
	            | perl -pe 's/Date::Manip[(]3[)]/date_formats.txt/g' \
	            >$(PREFIX)/doc/man/`basename $$i .1`.txt; \
	done
	# Remove 'real' manual pages, not needed on Windows.
	rm -rfv $(PREFIX)/man $(PREFIX)/share/man
	# My MakeMaker creates this dud directory.
	rm -rfv $(PREFIX)/5.8.0
	rmdir $(PREFIX)/share/doc
	set -e; \
	out=$(PREFIX)/doc/man/date_formats.txt; \
	echo Extracting part of Date::Manip manual page into $$out; \
	echo "This is an extract from the documentation of Perl's" \
	     "Date::Manip module, describing the different format" \
	     "strings that may be used for dates.  Bear in mind that" \
	     "depending on your Windows version you will need to quote" \
	     "the % characters on the command line somehow (see" \
	     "README.win32)." | fmt >$$out; \
	echo >>$$out; \
	(perldoc -u Date::Manip | perl -ne 'BEGIN { print "\n=pod\n\n" } print if (/^The format options are:/ .. /^=/) and not /^=/' | pod2text) >>$$out
	perl -MExtUtils::Command -e rm_rf $(INSTALLBIN) $(PREFIX)/lib/ $(INSTMANDIR) $(INSTALLMAN3DIR)
	perl -MExtUtils::Command -e cp xmltv.dtd $(PREFIX)
	# The following command will not be necessary when the source
	# tree was checked out on a DOSish system.  It may not even
	# work properly when run on a DOSish system - should check.
	#
	find $(PREFIX) -type f ! -name \*.jpg | xargs perl -i -pe 'BEGIN { binmode STDIN } s/\r*\n*$$/\r\n/'
	perl -MExtUtils::Command -e mv $(PREFIX)/doc/README* $(PREFIX)
	perl -MExtUtils::Command -e mv $(PREFIX)/README.win32 $(PREFIX)/README
	@echo
	@echo Part of a Windows distribution tree has been made in $(PREFIX)/.
	@echo Now copy in the executables!

};

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

    # Special case for tv_grab_uk.
    if ($do_uk_channel_pkgs) {
	my $ch_pkgs_dir= 'grab/uk/channel_pkgs';
	my $wanted = sub {
	    return if -d;
	    return if $File::Find::name =~ m!/CVS/!; # handy in working copy
	    die if defined $share_files{$File::Find::name};
	    (my $inst = $File::Find::name) =~ s!^grab/uk/!tv_grab_uk/! or die;
	    $share_files{$File::Find::name} = $inst;
	};
	File::Find::find($wanted, $ch_pkgs_dir);
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
	$inherited =~ s/^(\s*realclean\s+::\s.+)/$1 realclean_$filetype/m or die;
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
    # as an extra argument.
    #
    foreach (@grab_need_share) {
	$inherited =~
	  s<(grab/$_/tv_grab_$_.PL grab/$_/tv_grab_$_)\s*$>
	    <$1 $::extra_constants{INSTALLSHARE}>m
	    or die "no call to $_.PL in: $inherited";
    }
    return $inherited;
}

sub MY::makefile {
    package MY;
    my $inherited = shift->SUPER::makefile(@_);
    if ($do_uk_channel_pkgs) {
	# Add an extra dependency: the contents of tv_grab_uk's
	# packages directory.
	#
	$inherited =~ s{^((?:Makefile|\$\(FIRST_MAKEFILE\))\s+:)}
	  {$1 grab/uk/channel_pkgs}m
	    or die "no Makefile dependencies line in: $inherited";
    }
    return $inherited;
}

# Fix filename of some generated manpages.
sub MY::manifypods {
    package MY;
    for (my $inherited = shift->SUPER::manifypods(@_)) {
	foreach my $s (qw(Grab_XML Europe_TZ Config_file Get_nice Mode Summarize Gunzip)) {
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
	elsif (/^\t/ and defined $curr_target) {
	    # Commands for the target.
	    push @$curr_target, $_;
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
