use ExtUtils::MakeMaker;
use Config;
use File::Basename ();
use strict;

use vars '$VERSION'; $VERSION = '0.5';

my $PREFIX = "/usr/local/";

use vars '%extra_constants';
%extra_constants
  = (INST_PLAINDOC   => 'blib/doc',
     INSTALLPLAINDOC => "\$(PREFIX)/share/doc/xmltv-$::VERSION",
     INST_SHARE      => 'blib/share',
     INSTALLSHARE    => '$(PREFIX)/share/xmltv',
    );

my %prereqs
  = (
     'LWP' => 0,
     'XML::DOM' => 0,
     'Date::Manip' => 5.4,
     'XML::Writer' => 0,
     'XML::Simple' => 0,
     'Log::TraceMessages' => 0,
     'Lingua::Preferred' => 0,
     'Lingua::EN::Numbers::Ordinate' => 0,
     'Memoize' => 0,
     'Term::ProgressBar' => 0,
     'Tie::IxHash' => 0,
     'Unicode::String' => 0,
     'Compress::Zlib' => 0,
    );

# MakeMaker's warning message can be intimidating, check ourselves
# first.  This code can later be replaced with a less demanding
# dependency checker that asks what you intend to run and picks those
# dependencies.
#
my $err = 0;
foreach my $p (sort keys %prereqs) {
    eval "require $p";
    if ($@) {
	if ($@ =~ /^Can\'t locate \S+\.pm in \@INC/) {
	    warn "Required module $p seems not to be installed.\n";
	}
	else {
	    warn "Required module $p failed to load: $@";
	}
	++ $err;
    }
    elsif ($p->VERSION < $prereqs{$p}) {
	warn "Version $prereqs{$p} or later of module $p required\n";
	++ $err;
    }
}
exit(1) if $err;

WriteMakefile
  (
   'NAME'          => 'XMLTV',
   # No VERSION_FROM, it's set in this file
   'EXE_FILES'     => [ 'grab/de/tv_grab_de',
		        'grab/na/tv_grab_na',
			'grab/uk/tv_grab_uk',
			'filter/tv_extractinfo_en',
			'filter/tv_grep',
			'filter/tv_sort',
			'filter/tv_to_latex',
			'filter/tv_cat',
			'choose/tv_check/tv_check',
		      ],
   'PL_FILES' => { 'filter/tv_grep.PL'     => 'filter/tv_grep',
		   'grab/uk/tv_grab_uk.PL' => 'grab/uk/tv_grab_uk',
		   'lib/XMLTV.pm.PL'       => 'lib/XMLTV.pm',
		 },
   'PM'            => { 'lib/XMLTV.pm'               => '$(INST_LIBDIR)/XMLTV.pm',
			'lib/TZ.pm'                  => '$(INST_LIBDIR)/XMLTV/TZ.pm',
			'lib/Clumps.pm'              => '$(INST_LIBDIR)/XMLTV/Clumps.pm',
			'lib/Usage.pm'               => '$(INST_LIBDIR)/XMLTV/Usage.pm',
			'grab/Ask.pm'                => '$(INST_LIBDIR)/XMLTV/Ask.pm',
			'grab/Memoize.pm'            => '$(INST_LIBDIR)/XMLTV/Memoize.pm',
			'grab/na/ZapListings.pm'     => '$(INST_LIBDIR)/XMLTV/ZapListings.pm',
			'grab/uk/Ananova_Channel.pm' => '$(INST_LIBDIR)/XMLTV/Ananova_Channel.pm',
			'grab/uk/UK_TZ.pm'           => '$(INST_LIBDIR)/XMLTV/UK_TZ.pm',
		      },
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
	shift @t if $t[0] =~ /^\s*\@echo\b/;
	$t[0] =~ s/\@\$\(MOD_INSTALL\)/\$(PERL) -I. -MUninstall -e "uninstall(\@ARGV)"/
	  or die "first command of target $_ isn't \@\$\(MOD_INSTALL\)";
	(my $new_target = $_) =~ s/install$/uninstall/ or die;
	foreach ("\n\n$new_target ::\n", @t) {
	    $inherited .= $_;
	}
    }
    $inherited .= 'pure_uninstall :: pure_$(INSTALLDIRS)_uninstall' . "\n";
    $inherited .= 'uninstall :: all pure_uninstall plaindoc_uninstall share_uninstall';

    return $inherited;
}

# Extend installbin() to put doc and share under blib/.
sub MY::installbin {
    package MY;
    my $inherited = shift->SUPER::installbin(@_);

    # Add a target for each documentation file.  NB this means the
    # list of docs is stored here.
    #
    my @docs = qw(doc/COPYING doc/QuickStart doc/README
		  choose/tv_check/README.tv_check
		  choose/tv_check/tv_check_doc.html
		  choose/tv_check/tv_check_doc.jpg);
    my %doc_files;
    foreach (@docs) {
	$doc_files{$_} = File::Basename::basename($_);
    }
    my %share_files = ('grab/uk/channel_ids' => 'tv_grab_uk/channel_ids');
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
    $inherited .= "\n\t-rm -f lib/XMLTV.pm\n";
    return $inherited;
}

sub MY::processPL {
    package MY;
    my $inherited = shift->SUPER::processPL(@_);

    # Creating tv_grep depends on tv_grep.in and XMLTV.pm (as well as
    # tv_grep.PL).  Creating tv_grab_uk depends on tv_grab_uk.in.
    # Creating XMLTV.pm depends on XMLTV.pm.in.
    #
    $inherited =~ s!^(\s*filter/tv_grep\s+::\s.+)!$1 filter/tv_grep.in pm_to_blib!m
      or die "no filter/tv_grep in: $inherited";
    $inherited =~ s!^(\s*grab/uk/tv_grab_uk\s+::\s.+)!$1 grab/uk/tv_grab_uk.in!m
      or die "no grab/uk/tv_grab_uk in: $inherited";
    $inherited =~ s!^(\s*lib/XMLTV\.pm\s+::\s.+)!$1 lib/XMLTV.pm.in!m
      or die "no lib/XMLTV.pm in: $inherited";

    # And tv_grab_uk.in needs the share/ directory passed as an extra argument.
    $inherited =~ s{(grab/uk/tv_grab_uk.PL grab/uk/tv_grab_uk)\s*$}
      {$1 $::extra_constants{INSTALLSHARE}}m
	or die "no call to tv_grab_uk.PL in: $inherited";

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
	    die "bad makefile line: $_";
	}
    }
    return \%r;
}
