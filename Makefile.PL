#!/usr/bin/perl -w
use ExtUtils::MakeMaker;
use Config;
use File::Basename ();
use strict;

use vars '$VERSION';
$VERSION = '0.5.4';

use vars '%extra_constants';
%extra_constants
  = (INST_PLAINDOC   => 'blib/doc',
     INSTALLPLAINDOC => "\$(PREFIX)/share/doc/xmltv-$::VERSION",
     INST_SHARE      => 'blib/share',
     INSTALLSHARE    => '$(PREFIX)/share/xmltv',
     # This next line shouldn't be needed, it works around a bug.
     INSTALLMAN1DIR  => '$(PREFIX)/man/man1',
     # Directory to install into when making Windows binary dist.
     WINDOWS_DIST    => "xmltv-$VERSION-win32",
    );

# The following lists of dependencies and files to be installed may
# get modified later depending on what the user chooses.
#

# Documentation files to be installed.  This is a global variable
# because it is accessed by some code we add to MakeMaker.
#
use vars '@docs';
@docs = qw(doc/COPYING doc/QuickStart doc/README.win32 README);

# Executables to be installed.
my @exes
  = qw(grab/de/tv_grab_de
       grab/uk/tv_grab_uk
       grab/uk_rt/tv_grab_uk_rt
       filter/tv_extractinfo_en
       filter/tv_grep
       filter/tv_sort
       filter/tv_to_latex
       filter/tv_cat
      );

# Libraries to be installed.
my %pm
  = ('lib/XMLTV.pm'               => '$(INST_LIBDIR)/XMLTV.pm',
     'lib/TZ.pm'                  => '$(INST_LIBDIR)/XMLTV/TZ.pm',
     'lib/Clumps.pm'              => '$(INST_LIBDIR)/XMLTV/Clumps.pm',
     'lib/Usage.pm'               => '$(INST_LIBDIR)/XMLTV/Usage.pm',
     'lib/Ask.pm'                 => '$(INST_LIBDIR)/XMLTV/Ask.pm',
     'lib/UK_TZ.pm'           => '$(INST_LIBDIR)/XMLTV/UK_TZ.pm',
     'grab/Memoize.pm'            => '$(INST_LIBDIR)/XMLTV/Memoize.pm',
     'grab/uk/Ananova_Channel.pm' => '$(INST_LIBDIR)/XMLTV/Ananova_Channel.pm',
    );

# Modules required to install.
my %prereqs
  = (
     'LWP' => 5.65,
     'XML::Twig' => 3.09,
     'Date::Manip' => 5.4,
     'XML::Writer' => 0,
    );

# There is something particularly broken about Date::Manip on Red Hat
# 8.0, we check for that specially.
#
if ($^O =~ /linux/i) {
    open(FH, 'perl -MDate::Manip -e 0 2>&1 |') or die "cannot open pipe from perl: $!";
    while (<FH>) {
	if (/^Malformed UTF-8 character/) {
	    for ($ENV{LC_ALL}) {
		if (defined and s/\.UTF-?8//) {
		    die
"Your installed Date::Manip module is producing errors like: $_

This is a known bug with UTF-8 locales, most commonly seen on Red Hat
Linux 8.0. See
<http://bugzilla.redhat.com/bugzilla/show_bug.cgi?id=74884>.

Until Date::Manip is fixed to work with UTF-8, you need to change your
LC_ALL environment variable to turn off the UTF-8 locale.

Try setting LC_ALL to $_ and running the Makefile.PL again.  If that
doesn't work, please contact the XMLTV maintainer.
";
		}
		else {
		    die
"Date::Manip producing errors like '$_', but locale is not UTF-8.  Try
setting LC_ALL=en_US and running the Makefile.PL again; also report
this message to the XMLTV maintainer.
";
		}
	    }
	}
    }
    close FH;			# ignore exit status
}

# 'Recommended but not required'.  It isn't currently handled to have
# the same module in both sets.
#
my %recommended
  = (
     'Lingua::EN::Numbers::Ordinate' => 0,
     'Lingua::Preferred' => 0,
     'Memoize' => 0,
     'Term::ProgressBar' => 0,
     'Compress::Zlib' => 0,
     'Unicode::String' => 0,
    );

# And Log::TraceMessages is 'suggested' but we don't warn about that.

do 'lib/Ask.pm' or die 'could not load lib/Ask.pm, aborting';

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
    if (! XMLTV::Ask::askBooleanQuestion("Do you wish to continue anyway?", 0)) {
	exit(1);
    }
}

# Now prompt about how much to install.  This is really only to
# reduce dependencies.  In the long run things like tv_check can be
# spun off into separate projects.
#
my @opt_components
  = ({ name => 'tv_check',
       blurb =>
       'Tv_check is a graphical front-end to listings data.  You pick the
shows you are interested in, and then tv_check alerts you to
unexpected extra episodes or schedule changes.',
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
       blurb =>
       "Tv_pick_cgi is a front-end to choose your TV viewing.  It presents all
programmes in the listings and asks you about each one.  But you can
killfile programmes by answering 'never', in which case you won't be
asked again about that show.

It is a CGI program which runs through a web server and web browser, or
with the lynxcgi mode of the lynx web browser.  You need to install it
by hand; this Makefile.PL will only check that the necessary libraries
are present.",
       prereqs => { 'CGI' => 0 },
       type => 'run',
       default => 0,
     },

     { name => 'tv_grab_na',
       blurb => 'Tv_grab_na is the listings grabber for North America.',
       exes => [ 'grab/na/tv_grab_na' ],
       pm => { 'grab/na/ZapListings.pm' =>
	       '$(INST_LIBDIR)/XMLTV/ZapListings.pm' },
       prereqs => { 'HTML::Parser' => 0 } },

     { name => 'tv_grab_sn',
       blurb => 'Tv_grab_sn is the listings grabber for Sweden and Norway.',
       exes => [ 'grab/sn/tv_grab_sn' ],
       prereqs => { 'HTML::TableExtract' => '1.08' } },
    );

foreach my $info (@opt_components) {
    my $name = $info->{name};
    print STDERR "* $info->{blurb}\n\n";
    use vars '%p'; local *p = $info->{prereqs};
    my @prereqs_names = grep { test_prereq($_, $p{$_})->[0] ne 'OK' } keys %p;
    my $default;
    if (not @prereqs_names) {
	# Everything already installed.
	$default = $info->{default};
	$default = 1 if not defined $default;
    }
    elsif (@prereqs_names == 1) {
	my $mod = $prereqs_names[0];
	print STDERR "To install $name, you will need the $mod module.";
	my $min_ver = $prereqs{$mod};
	if ($min_ver) {
	    print STDERR " (version $min_ver or higher)";
	}
	print STDERR "\n\n";
	$default = 0;
    }
    else {
	print STDERR "To install $name, you will need the following modules:\n\n";
	foreach (sort @prereqs_names) {
	    print STDERR "$_";
	    my $min_ver = $prereqs{$_};
	    if ($min_ver) {
		print STDERR " (version $min_ver or higher)";
	    }
	    print STDERR "\n";
	}
	print STDERR "\n";
	$default = 0;
    }

    my $type = $info->{type};
    $type = 'install' if not defined $type;
    my $msg;
    if ($type eq 'install') {
	$msg = "Do you wish to install $name?";
    }
    elsif ($type eq 'run') {
	$msg = "Do you plan to run $name?";
    }
    else {
	warn "bad optional component 'type' $type";
	$msg = "Use $name?";
    }

    if (XMLTV::Ask::askBooleanQuestion($msg, $default)) {
	push @exes, @{$info->{exes}}               if $info->{exes};
	push @docs, @{$info->{docs}}               if $info->{docs};
	%pm = (%pm, %{$info->{pm}})                if $info->{pm};
	%prereqs = (%prereqs, %{$info->{prereqs}}) if $info->{prereqs};
    }
    print STDERR "\n";
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
sub test_prereq( $$ ) {
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
    if ($minver != 0) {
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
    my ($r, $more) = @{test_prereq($p, $minver)};
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
die "Required modules missing, not writing Makefile\n" if $err;

WriteMakefile
  (
   'NAME'          => 'XMLTV',
   # No VERSION_FROM, it's set in this file
   'EXE_FILES'     => \@exes,
   'PL_FILES'      => { 'filter/tv_grep.PL'     => 'filter/tv_grep',
			'grab/uk/tv_grab_uk.PL' => 'grab/uk/tv_grab_uk',
			'grab/uk_rt/tv_grab_uk_rt.PL' => 'grab/uk_rt/tv_grab_uk_rt',
			'lib/XMLTV.pm.PL'       => 'lib/XMLTV.pm',
		      },
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

xmltv.exe :: $(EXE_FILES) lib/exe_wrap.pl
	set PERLAPP_OPT=--nologo --force --trim="Convert::EBCDIC;DB_File;Encode;HASH;HTML::FromText;Text::Iconv;Unicode::Map8;v5"
	echo $(EXE_FILES) >exe_files.txt
	perlapp -exe=xmltv.exe -add "$(EXE_FILES)" -bind exe_files.txt lib/exe_wrap.pl
	$(RM_F) exe_files.txt

windows_dist ::
	@if test -e $(PREFIX); then \
	        echo To build a Windows distribution, please rerun Makefile.PL with >&2; \
	        echo "PREFIX set to a new (nonexistent) directory then 'make windows_dist'." >&2; \
	        echo '(Remember that only absolute paths work properly with MakeMaker.)' >&2; \
	        exit 1; \
	fi
	$(MAKE) install
	mv $(INSTALLPLAINDOC) $(PREFIX)/doc/
	rmdir $(PREFIX)/share/doc
	mkdir -p $(PREFIX)/doc/man
	set -e; for i in $(INSTALLMAN1DIR)/*; do \
	        b=`basename $$i .1`; \
	        if test "$$b" = '*'; then \
	                echo cannot find manpages in $(INSTALLMAN1DIR) >&2; \
	                exit 1; \
	        fi; \
	        echo Converting $$i to plain text; \
	        troff -mandoc -Tascii $$i | grotty -buo \
	            >$(PREFIX)/doc/man/`basename $$i .1`.txt; \
	done
	rm -rfv $(INSTALLBIN) $(PREFIX)/lib/ $(INSTALLMAN1DIR) $(INSTALLMAN3DIR)
	rmdir $(PREFIX)/man
	cp -avi xmltv.dtd $(PREFIX)
	# The following command will not be necessary when the source
	# tree was checked out on a DOSish system.
	#
	find $(PREFIX) -type f | xargs unix2dos
	mv -vi $(PREFIX)/doc/README* $(PREFIX)
	mv -vf $(PREFIX)/README.win32 $(PREFIX)/README
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
    my %share_files = ('grab/uk/channel_ids' => 'tv_grab_uk/channel_ids',
		       'grab/uk_rt/channel_ids' => 'tv_grab_uk_rt/channel_ids',
		      );
    foreach (<grab/uk/channel_pkgs/*>) {
	next if -d;
	die if defined $share_files{$_};
	(my $inst = $_) =~ s!^grab/uk/!tv_grab_uk/! or die;
	$share_files{$_} = $inst;
    }
    my %new_filetypes = (plaindoc => \%doc_files, share => \%share_files);
    my %seen_dir;
    foreach my $filetype (sort keys %new_filetypes) {
	my $uc = uc $filetype;
	use vars '%files'; local *files = $new_filetypes{$filetype};
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
	\@rm -f \$(INST_$uc)/$inst_pos
	cp $src \$(INST_$uc)/$inst_pos
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
	$inherited .= "realclean_$filetype ::\n\trm -f ";
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
    $inherited .= "\n\t-rm -f filter/tv_grep\n";
    $inherited .= "\n\t-rm -f grab/uk/tv_grab_uk\n";
    $inherited .= "\n\t-rm -f grab/uk_rt/tv_grab_uk_rt\n";
    $inherited .= "\n\t-rm -f lib/XMLTV.pm\n";
    return $inherited;
}

sub MY::processPL {
    package MY;
    my $inherited = shift->SUPER::processPL(@_);

    # Creating tv_grep depends on tv_grep.in and XMLTV.pm (as well as
    # tv_grep.PL).  Creating tv_grab_uk depends on tv_grab_uk.in.
    # Creating tv_grab_uk_rt depends on tv_grab_uk_rt.in.  Creating
    # XMLTV.pm depends on XMLTV.pm.in.
    #
    $inherited =~ s!^(\s*filter/tv_grep\s+::\s.+)!$1 filter/tv_grep.in pm_to_blib!m
      or die "no filter/tv_grep in: $inherited";
    $inherited =~ s!^(\s*grab/uk/tv_grab_uk\s+::\s.+)!$1 grab/uk/tv_grab_uk.in!m
      or die "no grab/uk/tv_grab_uk in: $inherited";
    $inherited =~ s!^(\s*grab/uk_rt/tv_grab_uk_rt\s+::\s.+)!$1 grab/uk_rt/tv_grab_uk_rt.in!m
      or die "no grab/uk_rt/tv_grab_uk_rt in: $inherited";
    $inherited =~ s!^(\s*lib/XMLTV\.pm\s+::\s.+)!$1 lib/XMLTV.pm.in!m
      or die "no lib/XMLTV.pm in: $inherited";

    # And two of the .in generators need the share/ directory passed
    # as an extra argument.
    #
    $inherited =~ s{(grab/uk/tv_grab_uk.PL grab/uk/tv_grab_uk)\s*$}
      {$1 $::extra_constants{INSTALLSHARE}}m
	or die "no call to tv_grab_uk.PL in: $inherited";
    $inherited =~ s{(grab/uk_rt/tv_grab_uk_rt.PL grab/uk_rt/tv_grab_uk_rt)\s*$}
      {$1 $::extra_constants{INSTALLSHARE}}m
	or die "no call to tv_grab_uk_rt.PL in: $inherited";

    return $inherited;
}

sub MY::makefile {
    package MY;
    my $inherited = shift->SUPER::makefile(@_);
    
    # Add an extra dependency: the contents of tv_grab_uk's packages
    # directory. 
    #
    $inherited =~ s{^(Makefile\s+:)}{$1 grab/uk/channel_pkgs}m
      or die "no Makefile dependencies line in: $inherited";
    return $inherited;
}

# Split a section of makefile into targets.
sub targets {
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
