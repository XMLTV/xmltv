use ExtUtils::MakeMaker;
use Config;
use File::Basename ();

$VERSION = '0.5';

my $PREFIX = "/usr/local/";

# An explicit check for required modules should not be necessary,
# we mention them with PREREQ_PM below.
#
# Could maybe warn about Unicode::String but not worth bothering.
#
# Also no need to go through the files in $pmdir copying the .in
# versions to the final filenames.  Substituting @PREFIX@ and
# @VERSION@ in binary files is a nice idea, but should not be done
# in the Makefile.PL.  (Only when you run 'make', and even then
# only on a copy of the file, keeping the original.)
#
# Consequently, no special BEGIN section needed.
#

WriteMakefile
  (
   'NAME'          => 'XMLTV',
   # No VERSION_FROM, it's set in this file
   'EXE_FILES'     => [ 'grab/na/tv_grab_na',
			'grab/uk/tv_grab_uk',
			'filter/tv_extractinfo_en',
			'filter/tv_grep',
			'filter/tv_sort',
			'filter/tv_to_latex',
			'filter/tv_cat',
		      ],
   'PM'            => { 'XMLTV.pm'                   => '$(INST_LIBDIR)/XMLTV.pm',
			'grab/na/ZapListings.pm'     => '$(INST_LIBDIR)/XMLTV/ZapListings.pm',
			'grab/uk/Ananova_Channel.pm' => '$(INST_LIBDIR)/XMLTV/Ananova_Channel.pm',
			'grab/uk/UK_TZ.pm'           => '$(INST_LIBDIR)/XMLTV/UK_TZ.pm',
		      },
   'PREREQ_PM'     => { 'LWP' => 0,
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
		      },
    # No special parameters for 'make clean' or 'make dist'
);


# Try to hack in support for 'ordinary' documentation going in
# /usr/share/doc/.
#
sub MY::constants {
    package MY;
    my $inherited = shift->SUPER::constants(@_);
    $inherited .= "INST_PLAINDOC = blib/doc\n";
    $inherited .= "INSTALLPLAINDOC = \$(PREFIX)/share/doc/xmltv-$::VERSION\n";
    return $inherited;
}
sub MY::install {
    package MY;
    my $inherited = shift->SUPER::install(@_);

    # Add an extra dependency to 'doc_install'.
    $inherited =~ s/^(\s*doc_install\s+::\s.+)/$1 plaindoc_install/m or die;

    # Create the target 'plaindoc_install'.
    my $extra = <<'END'
plaindoc_install ::
        @echo Installing contents of $(INST_PLAINDOC) into $(INSTALLPLAINDOC)
        @$(MOD_INSTALL) \
                $(INST_PLAINDOC) $(INSTALLPLAINDOC)
END
  ;
    $extra =~ s/ {8}/\t/g;
    $inherited .= $extra;

    # Create stuff for managing blib/doc/, analogous to blib/bin/.  It
    # really isn't clear how to define these things, hope this works.
    #
    $extra = <<'END'
$(INST_PLAINDOC)/.exists :: $(PERL_INC)/perl.h
	@$(MKPATH) $(INST_PLAINDOC)
	@$(EQUALIZE_TIMESTAMP) $(PERL_INC)/perl.h $(INST_PLAINDOC)/.exists
	-@$(CHMOD) $(PERM_RWX) $(INST_PLAINDOC)
END
  ;
    $extra =~ s/ {8}/\t/g;
    $inherited .= $extra;

    return $inherited;
}
# Well documentation doesn't really belong under 'installbin', but
# I've stopped caring by this point.
#
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
     foreach (@docs) {
 	my $basename = File::Basename::basename($_);
	$extra = <<END
\$(INST_PLAINDOC)/$basename: $_ Makefile \$(INST_PLAINDOC)/.exists
	\@rm -f \$(INST_PLAINDOC)/$basename
	cp $_ \$(INST_PLAINDOC)/$basename
	\$(FIXIN) \$(INST_PLAINDOC)/$basename
	-\@\$(CHMOD) \$(PERM_RW) \$(INST_PLAINDOC)/$basename
END
	  ;
	$extra =~ s/ {8}/\t/g;
	$inherited .= $extra;
     }

    # These targets need to be added to pure_all.
    $inherited =~ s/^(\s*pure_all\s+::\s.+)/$1 pure_plaindoc/m
      or die "no pure_all in: $inherited";
    $inherited .= 'pure_plaindoc :: ';
    foreach (@docs) {
	my $basename = File::Basename::basename($_);
	$inherited .= "\$(INST_PLAINDOC)/$basename ";
    }
    $inherited .= "\n\t\@\$(NOOP)\n";

    # And realclean should remove them.
    $inherited =~ s/^(\s*realclean\s+::\s.+)/$1 realclean_plaindoc/m or die;
    $inherited .= "realclean_plaindoc ::\n\trm -f ";
    foreach (@docs) {
	my $basename = File::Basename::basename($_);
	$inherited .= "\$(INST_PLAINDOC)/$basename ";
    }
    $inherited .= "\n";

    return $inherited;
}
