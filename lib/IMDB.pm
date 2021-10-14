# The IMDB file contains two packages:
# 1. XMLTV::IMDB::Cruncher package which parses and manages IMDB "lists" files
#		from ftp.imdb.com
# 2. XMLTV::IMDB package that uses data files from the Cruncher package to
#		update/add details to XMLTV programme nodes.
#
# FUTURE - multiple hits on the same 'title only' could try and look for
#			character names matching from description to imdb.com character
#			names.
#
# FUTURE - multiple hits on 'title only' should probably pick latest
#			tv series over any older ones. May make for better guesses.
#
# BUG - we identify 'presenters' by the word "Host" appearing in the character
#		description. For some movies, character names include the word Host.
#		ex. Animal, The (2001) has a character named "Badger Milk Host".
#
# BUG - if there is a matching title with > 1 entry (say made for tv-movie and
#		at tv-mini series) made in the same year (or even "close" years) it is
#		possible for us to pick the wrong one we should pick the one with the
#		closest year, not just the first closest match based on the result ordering
#		for instance Ghost Busters was made in 1984, and into a tv series in
#		1986. if we have a list of GhostBusters 1983, we should pick the 1984 movie
#		and not 1986 tv series...maybe :) but currently we'll pick the first
#		returned close enough match instead of trying the closest date match of
#		the approx hits.
#

use strict;

package XMLTV::IMDB;

use Search::Dict;

use open ':encoding(iso-8859-1)';   # try to enforce file encoding (does this work in Perl <5.8.1? )

#
# HISTORY
# .6 = what was here for the longest time
# .7 = fixed file size est calculations
#	 = moviedb.info now includes _file_size_uncompressed values for each downloaded file
# .8 = updated file size est calculations
#	 = moviedb.dat directors and actors list no longer include repeated names (which mostly
#	  occured in episodic tv programs (reported by Alexy Khrabrov)
# .9 = added keywords data
# .10 = added plot data
# .11 = revised method for database creation to reduce memory use
#		bug: remove duplicated genres
#		bug: if TV-version and movie in same year then one (random) was lost
#		bug: multiple films with same title in same year then one was lost
#		bug: movies with (aka...) in title not handled properly
#		bug: incorrect data generated for a tv series (only the last episode found is stored)
#		bug: genres and cast are rolled-up from all episodes to the series record (misleading)
#		bug: multiple matches can sometimes extract the first one it comes across as a 'hit' 
#			  (potentially wrong - it should not augment incoming prog when multiple matches)
#		dbbuild: --filesort to sort interim data on disc rather than in memory
#		dbbuild: --nosystemsort to use File::Sort rather than operating system shell's 'sort' command
#		dbbuild: --movies-only to exclude tv-series (etc.) from database build
#
#
our $VERSION = '0.11';	  # version number of database

sub new
{
	my ($type) = shift;
	my $self={ @_ };			# remaining args become attributes

	for ('imdbDir', 'verbose') {
	die "invalid usage - no $_" if ( !defined($self->{$_}));
	}
	#$self->{verbose}=2;
	$self->{replaceDates}=0			if ( !defined($self->{replaceDates}));
	$self->{replaceTitles}=0		if ( !defined($self->{replaceTitles}));
	$self->{replaceCategories}=0	if ( !defined($self->{replaceCategories}));
	$self->{replaceKeywords}=0		if ( !defined($self->{replaceKeywords}));
	$self->{replaceURLs}=0		 	if ( !defined($self->{replaceURLs}));
	$self->{replaceDirectors}=1		if ( !defined($self->{replaceDirectors}));
	$self->{replaceActors}=0		if ( !defined($self->{replaceActors}));
	$self->{replacePresentors}=1	if ( !defined($self->{replacePresentors}));
	$self->{replaceCommentators}=1	if ( !defined($self->{replaceCommentators}));
	$self->{replaceStarRatings}=0	if ( !defined($self->{replaceStarRatings}));
	$self->{replacePlot}=0			if ( !defined($self->{replacePlot}));

	$self->{updateDates}=1			if ( !defined($self->{updateDates}));
	$self->{updateTitles}=1			if ( !defined($self->{updateTitles}));
	$self->{updateCategories}=1		if ( !defined($self->{updateCategories}));
	$self->{updateCategoriesWithGenres}=1 if ( !defined($self->{updateCategoriesWithGenres}));
	$self->{updateKeywords}=0		if ( !defined($self->{updateKeywords}));		# default is to NOT add keywords
	$self->{updateURLs}=1			if ( !defined($self->{updateURLs}));
	$self->{updateDirectors}=1		if ( !defined($self->{updateDirectors}));
	$self->{updateActors}=1			if ( !defined($self->{updateActors}));
	$self->{updatePresentors}=1		if ( !defined($self->{updatePresentors}));
	$self->{updateCommentators}=1	if ( !defined($self->{updateCommentators}));
	$self->{updateStarRatings}=1	if ( !defined($self->{updateStarRatings}));
	$self->{updatePlot}=0			if ( !defined($self->{updatePlot}));			# default is to NOT add plot

	$self->{numActors}=3			if ( !defined($self->{numActors}));		 		# default is to add top 3 actors

	$self->{moviedbIndex}="$self->{imdbDir}/moviedb.idx";
	$self->{moviedbData}="$self->{imdbDir}/moviedb.dat";
	$self->{moviedbInfo}="$self->{imdbDir}/moviedb.info";
	$self->{moviedbOffline}="$self->{imdbDir}/moviedb.offline";

	# default is not to cache lookups
	$self->{cacheLookups}=0 if ( !defined($self->{cacheLookups}) );
	$self->{cacheLookupSize}=0 if ( !defined($self->{cacheLookupSize}) );

	$self->{cachedLookups}->{tv_series}->{_cacheSize_}=0;

	bless($self, $type);

	$self->{categories}={'movie'		  =>'Movie',
			 'tv_movie'	   =>'TV Movie', # made for tv
			 'video_movie'	=>'Video Movie', # went straight to video or was made for it
			 'tv_series'	  =>'TV Series',
			 'tv_mini_series' =>'TV Mini Series'};

	$self->{stats}->{programCount}=0;

	for my $cat (keys %{$self->{categories}}) {
		$self->{stats}->{perfect}->{$cat}=0;
		$self->{stats}->{close}->{$cat}=0;
	}
	$self->{stats}->{perfectMatches}=0;
	$self->{stats}->{closeMatches}=0;

	$self->{stats}->{startTime}=time();

	return($self);
}

sub loadDBInfo($)
{
	my $file=shift;
	my $info;

	open(INFO, "< $file") || return("imdbDir index file \"$file\":$!\n");
	while(<INFO>) {
		chomp();
		if ( s/^([^:]+)://o ) {
			$info->{$1}=$_;
		}
	}
	close(INFO);
	return($info);
}

sub checkIndexesOkay($)
{
	my $self=shift;
	if ( ! -d "$self->{imdbDir}" ) {
		return("imdbDir \"$self->{imdbDir}\" does not exist\n");
	}

	if ( -f "$self->{moviedbOffline}" ) {
		return("imdbDir index offline: check $self->{moviedbOffline} for details");
	}

	for my $file ($self->{moviedbIndex}, $self->{moviedbData}, $self->{moviedbInfo}) {
		if ( ! -f "$file" ) {
			return("imdbDir index file \"$file\" does not exist\n");
		}
	}

	$VERSION=~m/^(\d+)\.(\d+)$/o || die "package corrupt, VERSION string invalid ($VERSION)";
	my ($major, $minor)=($1, $2);

	my $info=loadDBInfo($self->{moviedbInfo});
	return($info) if ( ref $info eq 'SCALAR' );

	if ( !defined($info->{db_version}) ) {
		return("imdbDir index db missing version information, rerun --prepStage all\n");
	}
	if ( $info->{db_version}=~m/^(\d+)\.(\d+)$/o ) {
		if ( $1 != $major || $2 < $minor ) {
			return("imdbDir index db requires updating, rerun --prepStage all\n");
		}
		if ( $1 == 0 && $2 == 1 ) {
			return("imdbDir index db requires update, rerun --prepStage 5 (bug:actresses never appear)\n");
		}
		if ( $1 == 0 && $2 == 2 ) {
			# 0.2 -> 0.3 upgrade requires prepStage 5 to be re-run
			return("imdbDir index db requires minor reindexing, rerun --prepStage 3 and 5\n");
		}
		if ( $1 == 0 && $2 == 3 ) {
			# 0.2 -> 0.3 upgrade requires prepStage 5 to be re-run
			return("imdbDir index db requires major reindexing, rerun --prepStage 2 and new prepStages 5,6,7,8 and 9\n");
		}
		if ( $1 == 0 && $2 == 4 ) {
			# 0.2 -> 0.3 upgrade requires prepStage 5 to be re-run
			return("imdbDir index db corrupt (got version 0.4), rerun --prepStage all\n");
		}
		# okay
		return(undef);
	}
	else {
		return("imdbDir index version of '$info->{db_version}' is invalid, rerun --prepStage all\n".
				"if problem persists, submit bug report to xmltv-devel\@lists.sf.net\n");
	}
}

sub basicVerificationOfIndexes($)
{
	my $self=shift;

	# check that the imdbdir is valid and up and running
	my $title="Army of Darkness";
	my $year=1992;

	$self->openMovieIndex() || return("basic verification of indexes failed\n".
					  "database index isn't readable");

	my $verbose = $self->{verbose}; $self->{verbose} = 0;
	my $res=$self->getMovieMatches($title, $year);
	$self->{verbose} = $verbose; undef $verbose;
	if ( !defined($res) ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "no match for basic verification of movie \"$title, $year\"\n");
	}
	if ( !defined($res->{exactMatch}) ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "no exact match for movie \"$title, $year\"\n");
	}
	if ( scalar(@{$res->{exactMatch}})!= 1) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "got more than one exact match for movie \"$title, $year\"\n");
	}
	my @exact=@{$res->{exactMatch}};
	if ( $exact[0]->{title} ne $title ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "title associated with key \"$title, $year\" is bad\n");
	}

	if ( $exact[0]->{year} ne "$year" ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "year associated with key \"$title, $year\" is bad\n");
	}

	my $id=$exact[0]->{id};
	$res=$self->getMovieIdDetails($id);
	if ( !defined($res) ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "no movie details for movie \"$title, $year\" (id=$id)\n");
	}

	if ( !defined($res->{directors}) ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "movie details didn't provide any director for movie \"$title, $year\" (id=$id)\n");
	}
	if ( !$res->{directors}[0]=~m/Raimi/o ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "movie details didn't show Raimi as the main director for movie \"$title, $year\" (id=$id)\n");
	}
	if ( !defined($res->{actors}) ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "movie details didn't provide any cast movie \"$title, $year\" (id=$id)\n");
	}
	if ( !$res->{actors}[0]=~m/Campbell/o ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "movie details didn't show Bruce Campbell as the main actor in movie \"$title, $year\" (id=$id)\n");
	}
	my $matches=0;
	for (@{$res->{genres}}) {
		if ( $_ eq "Action" ||
			 $_ eq "Comedy" ||
			 $_ eq "Fantasy" ||
			 $_ eq "Horror" ||
			 $_ eq "Romance" ) {
			$matches++;
		}
	}
	if ( $matches == 0 ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "movie details didn't show genres correctly for movie \"$title, $year\" (id=$id)\n");
	}
	if ( !defined($res->{ratingDist}) ||
	 !defined($res->{ratingVotes}) ||
	 !defined($res->{ratingRank}) ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "movie details didn't show imdbratings for movie \"$title, $year\" (id=$id)\n");
	}

	$self->closeMovieIndex();
	# all okay
	return(undef);

}

sub sanityCheckDatabase($)
{
	my $self=shift;
	my $errline;

	$errline=$self->checkIndexesOkay();
	return($errline) if ( defined($errline) );
	$errline=$self->basicVerificationOfIndexes();
	return($errline) if ( defined($errline) );

	# all okay
	return(undef);
}

sub error($$)
{
	print STDERR "tv_imdb: $_[1]\n";
}

sub status($$)
{
	if ( $_[0]->{verbose} ) {
		print STDERR "tv_imdb: $_[1]\n";
	}
}

sub debug($$)
{
	my $self=shift;
	my $mess=shift;
	if ( $self->{verbose} > 1 ) {
		print STDERR "tv_imdb: $mess\n";
	}
}

sub openMovieIndex($)
{
	my $self=shift;

	if ( !open($self->{INDEX_FD}, "< $self->{moviedbIndex}") ) {
		return(undef);
	}
	if ( !open($self->{DBASE_FD}, "< $self->{moviedbData}") ) {
		close($self->{INDEX_FD});
		return(undef);
	}
	return(1);
}

sub closeMovieIndex($)
{
	my $self=shift;

	close($self->{INDEX_FD});
	delete($self->{INDEX_FD});

	close($self->{DBASE_FD});
	delete($self->{DBASE_FD});

	return(1);
}

# moviedbIndex is a TSV file with the format:
#   searchtitle title year progtype lineno
#
sub getMovieMatches($$$)
{
	my $self=shift;
	my $title=shift;
	my $year=shift;

	# Articles are put at the end of a title ( in all languages )
	#$match=~s/^(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)\s+(.*)$/$2, $1/og;

	# append year to title
	my $match="$title";
	if ( defined($year) && $title!~m/\s+\((19|20)\d\d\)/o ) {
		$match.=" ($year)";
	}

	# to encode s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg
	# to decode s/%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/defined($1)? chr hex($1) : utf8_chr(hex($2))/oge;

	# url encode
	$match=lc($match);
	$match=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;

	$self->debug("looking for \"$match\" in $self->{moviedbIndex}");
	if ( !$self->{INDEX_FD} ) {
		die "internal error: index not open";
	}

	my $FD=$self->{INDEX_FD};
	Search::Dict::look(*{$FD}, $match, 0, 0);
	my $results;
	while (<$FD>) {
		last if ( !m/^$match/ );

		chomp();
		my @arr=split('\t', $_);
		if ( scalar(@arr) != 5 ) {
			warn "$self->{moviedbIndex} corrupt (correct key:$_)";
			next;
		}

		if ( $arr[0] eq $match ) {
			# return title and id
			#$arr[1]=~s/(.*),\s*(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/og;

			#$arr[0]=~s/%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/defined($1)? chr hex($1) : utf8_chr(hex($2))/oge;
			#$self->debug("exact:$arr[1] ($arr[2]) qualifier=$arr[3] id=$arr[4]");
			my $title=$arr[1];
			if ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\)$//o ) {
			}
			elsif ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\/[IVXL]+\)$//o ) {
			}
			else {
				die "unable to decode year from title key \"$title\", report to xmltv-devel\@lists.sf.net";
			}
			$title=~s/(.*),\s*(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/og;
			$self->debug("exact:$title ($arr[2]) qualifier=$arr[3] id=$arr[4]");
			push(@{$results->{exactMatch}}, {'key'=> $arr[1],
							 'title'=>$title,
							 'year'=>$arr[2],
							 'qualifier'=>$arr[3],
							 'id'=>$arr[4]});
		}
		else {
			# decode
			#s/%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/defined($1)? chr hex($1) : utf8_chr(hex($2))/oge;
			# return title
			#$arr[1]=~s/(.*),\s*(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/og;
			#$arr[0]=~s/%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/defined($1)? chr hex($1) : utf8_chr(hex($2))/oge;
			#$self->debug("close:$arr[1] ($arr[2]) qualifier=$arr[3] id=$arr[4]");
			my $title=$arr[1];

			if ( $title=~m/^\"/o && $title=~m/\"\s*\(/o ) { #"
				$title=~s/^\"//o; #"
				$title=~s/\"(\s*\()/$1/o; #"
			}

			if ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\)$//o ) {
			}
			elsif ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\/[IVXL]+\)$//o ) {
			}
			else {
				die "unable to decode year from title key \"$title\", report to xmltv-devel\@lists.sf.net";
			}
			$title=~s/(.*),\s*(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/og;
			$self->debug("close:$title ($arr[2]) qualifier=$arr[3] id=$arr[4]");
			push(@{$results->{closeMatch}}, {'key'=> $arr[1],
							 'title'=>$title,
							 'year'=>$arr[2],
							 'qualifier'=>$arr[3],
							 'id'=>$arr[4]});
		}
	}
	#print "MovieMatches on ($match) = ".Dumper($results)."\n";
	return($results);
}

sub getMovieExactMatch($$$)
{
	my $self=shift;
	my $title=shift;
	my $year=shift;
	my $res=$self->getMovieMatches($title, $year);

	return(undef, 0) if ( !defined($res) );
	if ( !defined($res->{exactMatch}) ) {
		return(undef, 0);
	}
	if ( scalar(@{$res->{exactMatch}}) != 1 ) {
		return(undef, scalar(@{$res->{exactMatch}}));
	}
	return($res->{exactMatch}[0], 1);
}

sub getMovieCloseMatches($$)
{
	my $self=shift;
	my $title=shift;

	my $res=$self->getMovieMatches($title, undef) || return(undef);

	if ( defined($res->{exactMatch})) {
		die "corrupt imdb database - hit on \"$title\"";
	}
	return(undef) if ( !defined($res->{closeMatch}) );
	my @arr=@{$res->{closeMatch}};
	#print "CLOSE DUMP=".Dumper(@arr)."\n";
	return(@arr);
}

# moviedbData file is a TSV file with the format:
#   lineno:directors actors genres ratingDist ratingVotes ratingRank keywords plot
#
sub getMovieIdDetails($$)
{
	my $self=shift;
	my $id=shift;

	if ( !$self->{DBASE_FD} ) {
		die "internal error: index not open";
	}
	my $results;
	my $FD=$self->{DBASE_FD};
	Search::Dict::look(*{$FD}, "$id:", 0, 0);
	while (<$FD>) {
		last if ( !m/^$id:/ );
		chomp();
		if ( s/^$id:// ) {
			my ($directors, $actors, $genres, $ratingDist, $ratingVotes, $ratingRank, $keywords, $plot)=split('\t', $_);
			if ( $directors ne "<>" ) {
				for my $name (split('\|', $directors)) {
					# remove (I) etc from imdb.com names (kept in place for reference)
					$name=~s/\s\([IVXL]+\)$//o;
					# switch name around to be surname last
					$name=~s/^([^,]+),\s*(.*)$/$2 $1/o;
					push(@{$results->{directors}}, $name);
				}
			}
			if ( $actors ne "<>" ) {
				for my $name (split('\|', $actors)) {
					# remove (I) etc from imdb.com names (kept in place for reference)
					my $HostNarrator;
					if ( $name=~s/\s?\[([^\]]+)\]$//o ) {
						$HostNarrator=$1;
					}
					$name=~s/\s\([IVXL]+\)$//o;

					# switch name around to be surname last
					$name=~s/^([^,]+),\s*(.*)$/$2 $1/o;
					if ( $HostNarrator ) {
						if ( $HostNarrator=~s/,*Host//o ) {
							push(@{$results->{presenter}}, $name);
						}
						if ( $HostNarrator=~s/,*Narrator//o ) {
							push(@{$results->{commentator}}, $name);
						}
					}
					else {
						push(@{$results->{actors}}, $name);
					}
				}
			}
			if ( $genres ne "<>" ) {
				push(@{$results->{genres}}, split('\|', $genres));
			}
			if ( $keywords ne "<>" ) {
				push(@{$results->{keywords}}, split(',', $keywords));
			}
			$results->{ratingDist}=$ratingDist 		if ( $ratingDist ne "<>" );
			$results->{ratingVotes}=$ratingVotes 	if ( $ratingVotes ne "<>" );
			$results->{ratingRank}=$ratingRank 		if ( $ratingRank ne "<>" );
			$results->{plot}=$plot 					if ( $plot ne "<>" );
		}
		else {
			warn "lookup of movie (id=$id) resulted in garbage ($_)";
		}
	}
	if ( !defined($results) ) {
		# some movies we don't have any details for
		$results->{noDetails}=1;
	}
	#print "MovieDetails($id) = ".Dumper($results)."\n";
	return($results);
}

#
# FUTURE - close hit could be just missing or extra
#		  punctuation:
#	   "Run Silent, Run Deep" for imdb's "Run Silent Run Deep"
#	   "Cherry, Harry and Raquel" for imdb's "Cherry, Harry and Raquel!"
#	   "Cat Women of the Moon" for imdb's "Cat-Women of the Moon"
#	   "Baywatch Hawaiian Wedding" for imdb's "Baywatch: Hawaiian Wedding" :)
#
# FIXED - "Victoria and Albert" appears for imdb's "Victoria & Albert" (and -> &)
# FIXED - "Columbo Cries Wolf" appears instead of "Columbo:Columbo Cries Wolf"
# FIXED - Place the article last, for multiple languages. For instance
#		 Los amantes del círculo polar -> amantes del círculo polar, Los
# FIXED - common international vowel changes. For instance
#		  "Anna Karénin" (é->e)
#
sub alternativeTitles($)
{
	my $title=shift;
	my @titles;

	push(@titles, $title);

	# try the & -> and conversion
	if ( $title=~m/\&/o ) {
		my $t=$title;
		while ( $t=~s/(\s)\&(\s)/$1and$2/o ) {
			push(@titles, $t);
		}
	}

	# try the and -> & conversion
	if ( $title=~m/\sand\s/io ) {
		my $t=$title;
		while ( $t=~s/(\s)and(\s)/$1\&$2/io ) {
			push(@titles, $t);
		}
	}

	# try the "Columbo: Columbo cries Wolf" -> "Columbo cries Wolf" conversion
	my $max=scalar(@titles);
	for (my $i=0; $i<$max ; $i++) {
		my $t=$titles[$i];
		if ( $t=~m/^[^:]+:.+$/io ) {
			while ( $t=~s/^[^:]+:\s*(.+)\s*$/$1/io ) {
				push(@titles, $t);
			}
		}
	}

	# Place the articles last
	$max=scalar(@titles);
	for (my $i=0; $i<$max ; $i++) {
		my $t=$titles[$i];
		if ( $t=~m/^(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)\s+(.*)$/io ) {
			$t=~s/^(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)\s+(.*)$/$2, $1/iog;
			push(@titles, $t);
		}
		if ( $t=~m/^(.+),\s*(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)$/io ) {
			$t=~s/^(.+),\s*(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/iog;
			push(@titles, $t);
		}
	}

	# convert all the special language characters
	$max=scalar(@titles);
	for (my $i=0; $i<$max ; $i++) {
		my $t=$titles[$i];
		if ( $t=~m/[ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÆæÇçÑñßÝýÿ]/io ) {
			$t=~s/[ÀÁÂÃÄÅàáâãäå]/a/gio;
			$t=~s/[ÈÉÊËèéêë]/e/gio;
			$t=~s/[ÌÍÎÏìíîï]/i/gio;
			$t=~s/[ÒÓÔÕÖØòóôõöø]/o/gio;
			$t=~s/[ÙÚÛÜùúûü]/u/gio;
			$t=~s/[Ææ]/ae/gio;
			$t=~s/[Çç]/c/gio;
			$t=~s/[Ññ]/n/gio;
			$t=~s/[ß]/ss/gio;
			$t=~s/[Ýýÿ]/y/gio;
			$t=~s/[¿]//gio;
			push(@titles, $t);
		}
	}

	# optional later possible titles include removing the '.' from titles
	# ie "Project V.I.P.E.R." matching imdb "Project VIPER"
	$max=scalar(@titles);
	for (my $i=0; $i<$max ; $i++) {
		my $t=$titles[$i];
		if ( $t=~s/\.//go ) {
			push(@titles,$t);
		}
	}
	return(\@titles);
}

sub findMovieInfo($$$$)
{
	my ($self, $title, $year, $exact)=@_;

	my @titles=@{alternativeTitles($title)};

	if ( $exact == 1 ) {
		# try an exact match first :)
		for my $mytitle ( @titles ) {
			my ($info,$matchcount) = $self->getMovieExactMatch($mytitle, $year);
			if ($matchcount > 1) {
				# if multiple records exactly match title+year then we don't know which one is correct
				$self->status("multiple hits on movie \"$mytitle".($mytitle=~m/\s+\((19|20)\d\d\)/?'':" ($year)")."\"");
				return(undef, $matchcount);
			}
			if ( defined($info) ) {
				if ( $info->{qualifier} eq "movie" ) {
					$self->status("perfect hit on movie \"$info->{key}\"");
					$info->{matchLevel}="perfect";
					return($info);
				}
				elsif ( $info->{qualifier} eq "tv_movie" ) {
					$self->status("perfect hit on made-for-tv-movie \"$info->{key}\"");
					$info->{matchLevel}="perfect";
					return($info);
				}
				elsif ( $info->{qualifier} eq "video_movie" ) {
					$self->status("perfect hit on made-for-video-movie \"$info->{key}\"");
					$info->{matchLevel}="perfect";
					return($info);
				}
				elsif ( $info->{qualifier} eq "video_game" ) {
					next;
				}
				elsif ( $info->{qualifier} eq "tv_series" ) {
				}
				elsif ( $info->{qualifier} eq "tv_mini_series" ) {
				}
				else {
					$self->error("$self->{moviedbIndex} responded with wierd entry for \"$info->{key}\"");
					$self->error("weird trailing qualifier \"$info->{qualifier}\"");
					$self->error("submit bug report to xmltv-devel\@lists.sf.net");
				}
			}
			$self->debug("no exact title/year hit on \"$mytitle".($mytitle=~m/\s+\((19|20)\d\d\)/?'':" ($year)")."\"");
		}
		return(undef);
	}
	elsif ( $exact == 2 ) {
		# looking for first exact match on the title, don't have a year to compare

		for my $mytitle ( @titles ) {
			# try close hit if only one :)
			my $cnt=0;
			my @closeMatches=$self->getMovieCloseMatches("$mytitle");

			# we traverse the hits twice, first looking for success,
			# then again to produce warnings about missed close matches
			for my $info (@closeMatches) {
				next if ( !defined($info) );
				$cnt++;

				# within one year with exact match good enough
				if ( lc($mytitle) eq lc($info->{title}) ) {

					if ( $info->{qualifier} eq "movie" ) {
						$self->status("close enough hit on movie \"$info->{key}\" (since no 'date' field present)");
						$info->{matchLevel}="close";
						return($info);
					}
					elsif ( $info->{qualifier} eq "tv_movie" ) {
						$self->status("close enough hit on made-for-tv-movie \"$info->{key}\" (since no 'date' field present)");
						$info->{matchLevel}="close";
						return($info);
					}
					elsif ( $info->{qualifier} eq "video_movie" ) {
						$self->status("close enough hit on made-for-video-movie \"$info->{key}\" (since no 'date' field present)");
						$info->{matchLevel}="close";
						return($info);
					}
					elsif ( $info->{qualifier} eq "video_game" ) {
						next;
					}
					elsif ( $info->{qualifier} eq "tv_series" ) {
					}
					elsif ( $info->{qualifier} eq "tv_mini_series" ) {
					}
					else {
						$self->error("$self->{moviedbIndex} responded with wierd entry for \"$info->{key}\"");
						$self->error("weird trailing qualifier \"$info->{qualifier}\"");
						$self->error("submit bug report to xmltv-devel\@lists.sf.net");
					}
				}
			}
		}
		# nothing worked
		return(undef);
	}

	# otherwise we're looking for a title match with a close year
	for my $mytitle ( @titles ) {
		# try close hit if only one :)
		my $cnt=0;
		my @closeMatches=$self->getMovieCloseMatches("$mytitle");

		# we traverse the hits twice, first looking for success,
		# then again to produce warnings about missed close matches
		for my $info (@closeMatches) {
			next if ( !defined($info) );
			$cnt++;

			# within one year with exact match good enough
			if ( lc($mytitle) eq lc($info->{title}) ) {
				my $yearsOff=abs(int($info->{year})-$year);

				$info->{matchLevel}="close";

				if ( $yearsOff <= 2 ) {
					my $showYear=int($info->{year});

					if ( $info->{qualifier} eq "movie" ) {
						$self->status("close enough hit on movie \"$info->{key}\" (off by $yearsOff years)");
						return($info);
					}
					elsif ( $info->{qualifier} eq "tv_movie" ) {
						$self->status("close enough hit on made-for-tv-movie \"$info->{key}\" (off by $yearsOff years)");
						return($info);
					}
					elsif ( $info->{qualifier} eq "video_movie" ) {
						$self->status("close enough hit on made-for-video-movie \"$info->{key}\" (off by $yearsOff years)");
						return($info);
					}
					elsif ( $info->{qualifier} eq "video_game" ) {
						$self->status("ignoring close hit on video-game \"$info->{key}\"");
						next;
					}
					elsif ( $info->{qualifier} eq "tv_series" ) {
						$self->status("ignoring close hit on tv series \"$info->{key}\"");
						#$self->status("close enough hit on tv series \"$info->{key}\" (off by $yearsOff years)");
					}
					elsif ( $info->{qualifier} eq "tv_mini_series" ) {
						$self->status("ignoring close hit on tv mini-series \"$info->{key}\"");
						#$self->status("close enough hit on tv mini-series \"$info->{key}\" (off by $yearsOff years)");
					}
					else {
						$self->error("$self->{moviedbIndex} responded with wierd entry for \"$info->{key}\"");
						$self->error("weird trailing qualifier \"$info->{qualifier}\"");
						$self->error("submit bug report to xmltv-devel\@lists.sf.net");
					}
				}
			}
		}

		# if we found at least something, but nothing matched
		# produce warnings about missed, but close matches
		for my $info (@closeMatches) {
			next if ( !defined($info) );

			# within one year with exact match good enough
			if ( lc($mytitle) eq lc($info->{title}) ) {
				my $yearsOff=abs(int($info->{year})-$year);
				if ( $yearsOff <= 2 ) {
					#die "internal error: key \"$info->{key}\" failed to be processed properly";
				}
				elsif ( $yearsOff <= 5 ) {
					# report these as status
					$self->status("ignoring close, but not good enough hit on \"$info->{key}\" (off by $yearsOff years)");
				}
				else {
					# report these as debug messages
					$self->debug("ignoring close hit on \"$info->{key}\" (off by $yearsOff years)");
				}
			}
			else {
				$self->debug("ignoring close hit on \"$info->{key}\" (title did not match)");
			}
		}
	}
	#$self->status("failed to lookup \"$title ($year)\"");
	return(undef);
}

sub findTVSeriesInfo($$)
{
	my ($self, $title)=@_;

	if ( $self->{cacheLookups} ) {
		my $id=$self->{cachedLookups}->{tv_series}->{$title};

		if ( defined($id) ) {
			#print STDERR "REF= (".ref($id).")\n";
			if ( $id ne '' ) {
				return($id);
			}
			return(undef);
		}
	}

	my @titles=@{alternativeTitles($title)};

	# try an exact match first :)
	my $idInfo;

	for my $mytitle ( @titles ) {
		# try close hit if only one :)
		my $cnt=0;
		my @closeMatches=$self->getMovieCloseMatches("$mytitle");

		for my $info (@closeMatches) {
			next if ( !defined($info) );
			$cnt++;

			if ( lc($mytitle) eq lc($info->{title}) ) {

				$info->{matchLevel}="perfect";

				if ( $info->{qualifier} eq "movie" ) {
					#$self->status("ignoring close hit on movie \"$info->{key}\"");
				}
				elsif ( $info->{qualifier} eq "tv_movie" ) {
					#$self->status("ignoring close hit on tv movie \"$info->{key}\"");
				}
				elsif ( $info->{qualifier} eq "video_movie" ) {
					#$self->status("ignoring close hit on made-for-video-movie \"$info->{key}\"");
				}
				elsif ( $info->{qualifier} eq "video_game" ) {
					#$self->status("ignoring close hit on made-for-video-movie \"$info->{key}\"");
					next;
				}
				elsif ( $info->{qualifier} eq "tv_series" ) {
					$idInfo=$info;
					$self->status("perfect hit on tv series \"$info->{key}\"");
					last;
				}
				elsif ( $info->{qualifier} eq "tv_mini_series" ) {
					$idInfo=$info;
					$self->status("perfect hit on tv mini-series \"$info->{key}\"");
					last;
				}
				else {
					$self->error("$self->{moviedbIndex} responded with wierd entry for \"$info->{key}\"");
					$self->error("weird trailing qualifier \"$info->{qualifier}\"");
					$self->error("submit bug report to xmltv-devel\@lists.sf.net");
				}
			}
		}
		last if ( defined($idInfo) );
	}

	if ( $self->{cacheLookups} ) {
		# flush cache after this lookup if its gotten too big
		if ( $self->{cachedLookups}->{tv_series}->{_cacheSize_} >
			 $self->{cacheLookupSize} ) {
			delete($self->{cachedLookups}->{tv_series});
			$self->{cachedLookups}->{tv_series}->{_cacheSize_}=0;
		}
		if ( defined($idInfo) ) {
			$self->{cachedLookups}->{tv_series}->{$title}=$idInfo;
		}
		else {
			$self->{cachedLookups}->{tv_series}->{$title}="";
		}
		$self->{cachedLookups}->{tv_series}->{_cacheSize_}++;
	}
	if ( defined($idInfo) ) {
		return($idInfo);
	}
	else {
		#$self->status("failed to lookup tv series \"$title\"");
		return(undef);
	}
}

#
# todo - add country of origin
# todo - video (colour/aspect etc) details
# todo - audio (stereo) details
# todo - ratings ? - use certificates.list
# todo - add description - plot summaries ? - which one do we choose ?
# todo - writer
# todo - producer
# todo - running time (duration)
# todo - identify 'Host' and 'Narrator's and put them in as
#		credits:presenter and credits:commentator resp.
# todo - check program length - probably a warning if longer ?
#		can we update length (separate from runnning time in the output ?)
# todo - icon - url from www.imdb.com of programme image ?
#		this could be done by scraping for the hyper linked poster
#		<a name="poster"><img src="http://ia.imdb.com/media/imdb/01/I/60/69/80m.jpg" height="139" width="99" border="0"></a>
#		and grabbin' out the img entry. (BTW ..../npa.jpg seems to line up with no poster available)
#
#
sub applyFound($$$)
{
	my ($self, $prog, $idInfo)=@_;

	my $title=$prog->{title}->[0]->[0];

	if ( $self->{updateDates} ) {
		my $date;

		# don't add dates only fix them for tv_series
		if ( $idInfo->{qualifier} eq "movie" ||
			 $idInfo->{qualifier} eq "video_movie" ||
			 $idInfo->{qualifier} eq "tv_movie" ) {
			#$self->debug("adding 'date' field (\"$idInfo->{year}\") on \"$title\"");
			$date=int($idInfo->{year});
		}
		else {
			#$self->debug("not adding 'date' field to $idInfo->{qualifier} \"$title\"");
			$date=undef;
		}

		if ( $self->{replaceDates} ) {
			if ( defined($prog->{date}) && defined($date) ) {
				$self->debug("replacing 'date' field");
				delete($prog->{date});
				$prog->{date}=$date;
			}
		}
		else {
			# only set date if not already defined
			if ( !defined($prog->{date}) && defined($date) ) {
				$prog->{date}=$date;
			}
		}
	}

	if ( $self->{updateTitles} ) {
		if ( $idInfo->{title} ne $title ) {
			if ( $self->{replaceTitles} ) {
				$self->debug("replacing (all) 'title' from \"$title\" to \"$idInfo->{title}\"");
				delete($prog->{title});
			}

			my @list;

			push(@list, [$idInfo->{title}, undef]);

			if ( defined($prog->{title}) ) {
				my $name=$idInfo->{title};
				my $found=0;
				for my $v (@{$prog->{title}}) {
					if ( lc($v->[0]) eq lc($name) ) {
						$found=1;
					}
					else {
						push(@list, $v);
					}
				}
			}
			$prog->{title}=\@list;
		}
	}

	if ( $self->{updateURLs} ) {
		if ( $self->{replaceURLs} ) {
			if ( defined($prog->{url}) ) {
				$self->debug("replacing (all) 'url'");
				delete($prog->{url});
			}
		}

		# add url to programme on www.imdb.com
		my $url=$idInfo->{key};
		
		#	{key} will include " marks if a tv series - remove these from search url [#148]
		$url = $1.$2  if ( $url=~m/^"(.*?)"(.*)$/ );
		
		# encode the title
		$url=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;
		$url="https://www.imdb.com/find?q=".$url."&s=tt&exact=true";

		if ( defined($prog->{url}) ) {
			my @rep;
			push(@rep, $url);
			for (@{$prog->{url}}) {
				# skip urls for imdb.com that we're probably safe to replace
				if ( !m;^http://us.imdb.com/M/title-exact;o && !m;^https://www.imdb.com/find;o ) {
					push(@rep, $_);
				}
			}
			$prog->{url}=\@rep;
		}
		else {
			push(@{$prog->{url}}, $url);
		}
	}

	# squirrel away movie qualifier so its first on the list of replacements
	my @categories;
	push(@categories, [$self->{categories}->{$idInfo->{qualifier}}, 'en']);
	if ( !defined($self->{categories}->{$idInfo->{qualifier}}) ) {
		die "how did we get here with an invalid qualifier '$idInfo->{qualifier}'";
	}

	my $details=$self->getMovieIdDetails($idInfo->{id});
	if ( $details->{noDetails} ) {
		# we don't have any details on this movie
	}
	else {
		# add directors list
		if ( $self->{updateDirectors} && defined($details->{directors}) ) {
			# only update directors if we have exactly one or if
			# its a movie of some kind, add more than one.
			if ( scalar(@{$details->{directors}}) == 1 ||
				$idInfo->{qualifier} eq "movie" ||
				$idInfo->{qualifier} eq "video_movie" ||
				$idInfo->{qualifier} eq "tv_movie" ) {

				if ( $self->{replaceDirectors} ) {
					if ( defined($prog->{credits}->{director}) ) {
					$self->debug("replacing director(s)");
					delete($prog->{credits}->{director});
					}
				}

				my @list;
				# add top 3 billing directors list form www.imdb.com
				for my $name (splice(@{$details->{directors}},0,3)) {
					push(@list, $name);
				}

				# preserve all existing directors listed if we did't already have them.
				if ( defined($prog->{credits}->{director}) ) {
					for my $name (@{$prog->{credits}->{director}}) {
						my $found=0;
						for(@list) {
							if ( lc eq lc($name) ) {
								$found=1;
							}
						}
						if ( !$found ) {
							push(@list, $name);
						}
					}
				}
				$prog->{credits}->{director}=\@list;
			}
			else {
				$self->debug("not adding 'director' field to $idInfo->{qualifier} \"$title\"");
			}
		}

		if ( $self->{updateActors} && defined($details->{actors}) ) {
			if ( $self->{replaceActors} ) {
				if ( defined($prog->{credits}->{actor}) ) {
					$self->debug("replacing actor(s) on $idInfo->{qualifier} \"$idInfo->{key}\"");
					delete($prog->{credits}->{actor});
				}
			}

			my @list;
			# add top billing actors (default = 3) from www.imdb.com
			for my $name (splice(@{$details->{actors}},0,$self->{numActors})) {
				push(@list, $name);
			}
			# preserve all existing actors listed if we did't already have them.
			if ( defined($prog->{credits}->{actor}) ) {
				for my $name (@{$prog->{credits}->{actor}}) {
					my $found=0;
					for(@list) {
						if ( lc eq lc($name) ) {
							$found=1;
						}
					}
					if ( !$found ) {
						push(@list, $name);
					}
				}
			}
			$prog->{credits}->{actor}=\@list;
		}

		if ( $self->{updatePresentors} && defined($details->{presenter}) ) {
			if ( $self->{replacePresentors} ) {
				if ( defined($prog->{credits}->{presenter}) ) {
					$self->debug("replacing presentor");
					delete($prog->{credits}->{presenter});
				}
			}
			$prog->{credits}->{presenter}=$details->{presenter};
		}
		if ( $self->{updateCommentators} && defined($details->{commentator}) ) {
			if ( $self->{replaceCommentators} ) {
				if ( defined($prog->{credits}->{commentator}) ) {
					$self->debug("replacing commentator");
					delete($prog->{credits}->{commentator});
				}
			}
			$prog->{credits}->{commentator}=$details->{commentator};
		}

		# push genres as categories
		if ( $self->{updateCategoriesWithGenres} ) {
			if ( defined($details->{genres}) ) {
				for (@{$details->{genres}}) {
					push(@categories, [$_, 'en']);
				}
			}
		}

		if ( $self->{updateStarRatings} && defined($details->{ratingRank}) ) {
			if ( $self->{replaceStarRatings} ) {
				if ( defined($prog->{'star-rating'}) ) {
					$self->debug("replacing 'star-rating'");
					delete($prog->{'star-rating'});
				}
				unshift( @{$prog->{'star-rating'}}, [ $details->{ratingRank} . "/10", 'IMDB User Rating' ] );
			}
			else {
				# add IMDB User Rating in front of all other star-ratings
				unshift( @{$prog->{'star-rating'}}, [ $details->{ratingRank} . "/10", 'IMDB User Rating' ] );
			}
		}

		if ( $self->{updateKeywords} ) {
			my @keywords;
			if ( defined($details->{keywords}) ) {
				for (@{$details->{keywords}}) {
					push(@keywords, [$_, 'en']);
				}
			}

			if ( $self->{replaceKeywords} ) {
				if ( defined($prog->{keywords}) ) {
					$self->debug("replacing (all) 'keywords'");
					delete($prog->{keywords});
				}
			}
			if ( defined($prog->{keyword}) ) {
				for my $value (@{$prog->{keyword}}) {
					my $found=0;
					for my $k (@keywords) {
						if ( lc($k->[0]) eq lc($value->[0]) ) {
							$found=1;
						}
					}
					if ( !$found ) {
						push(@keywords, $value);
					}
				}
			}
		$prog->{keyword}=\@keywords;
		}

		if ( $self->{updatePlot} ) {
			# plot is held as a <desc> entity
			# if 'replacePlot' then delete all existing <desc> entities and add new
			# else add this plot as an additional <desc> entity
			#
			if ( $self->{replacePlot} ) {
				if ( defined($prog->{desc}) ) {
					$self->debug("replacing (all) 'desc'");
					delete($prog->{desc});
				}
			}
			if ( defined($details->{plot}) ) {
				# check it's not already there
				my $found = 0;
				for my $_desc ( @{$prog->{desc}} ) {
					$found = 1  if ( @{$_desc}[0] eq $details->{plot} );
				}
				push @{$prog->{desc}}, [ $details->{plot}, 'en' ]  if !$found;
			}
		}

	}

	if ( $self->{updateCategories} ) {
		if ( $self->{replaceCategories} ) {
			if ( defined($prog->{category}) ) {
				$self->debug("replacing (all) 'category'");
				delete($prog->{category});
			}
		}
		if ( defined($prog->{category}) ) {
			for my $value (@{$prog->{category}}) {
				my $found=0;
				#print "checking category $value->[0] with $mycategory\n";
				for my $c (@categories) {
					if ( lc($c->[0]) eq lc($value->[0]) ) {
						$found=1;
					}
				}
				if ( !$found ) {
					push(@categories, $value);
				}
			}
		}
		$prog->{category}=\@categories;
	}

	return($prog);
}

sub augmentProgram($$$)
{
	my ($self, $prog, $movies_only)=@_;

	$self->{stats}->{programCount}++;

	# assume first title in first language is the one we want.
	my $title=$prog->{title}->[0]->[0];

	if ( defined($prog->{date}) && $prog->{date}=~m/^\d\d\d\d$/o ) {

		# for programs with dates we try:
		# - exact matches on movies
		# - exact matches on tv series
		# - close matches on movies
		my ($id, $matchcount) = $self->findMovieInfo($title, $prog->{date}, 1); # exact match
		if (defined $matchcount && $matchcount > 1) {
			$self->status("failed to find a sole match for movie \"$title".($title=~m/\s+\((19|20)\d\d\)/?'':" ($prog->{date})")."\"");
			return(undef);
		}
		if ( !defined($id) ) {
			$id=$self->findTVSeriesInfo($title);
			if ( !defined($id) ) {
				($id, $matchcount) = $self->findMovieInfo($title, $prog->{date}, 0); # close match
			}
		}
		if ( defined($id) ) {
			$self->{stats}->{$id->{matchLevel}."Matches"}++;
			$self->{stats}->{$id->{matchLevel}}->{$id->{qualifier}}++;
			return($self->applyFound($prog, $id));
		}
		$self->status("failed to find a match for movie \"$title".($title=~m/\s+\((19|20)\d\d\)/?'':" ($prog->{date})")."\"");
		return(undef);
		# fall through and try again as a tv series
	}

	if ( !$movies_only ) {
		my $id=$self->findTVSeriesInfo($title);
		if ( defined($id) ) {
			$self->{stats}->{$id->{matchLevel}."Matches"}++;
			$self->{stats}->{$id->{matchLevel}}->{$id->{qualifier}}++;
			return($self->applyFound($prog, $id));
		}

		if ( 0 ) {
			# this has hard to support 'close' results, unless we know
			# for certain we're looking for a movie (ie duration etc)
			# this is a bad idea.
			my ($id, $matchcount) = $self->findMovieInfo($title, undef, 2); # any title match
			if ( defined($id) ) {
				$self->{stats}->{$id->{matchLevel}."Matches"}++;
				$self->{stats}->{$id->{matchLevel}}->{$id->{qualifier}}++;
				return($self->applyFound($prog, $id));
			}
		}
		$self->status("failed to find a match for show \"$title\"");
	}
	return(undef);
}

#
# todo - add in stats on other things added (urls ?, actors, directors,categories)
#		separate out from what was added or updated
#
sub getStatsLines($)
{
	my $self=shift;
	my $totalChannelsParsed=shift;

	my $endTime=time();
	my %stats=%{$self->{stats}};

	my $ret=sprintf("Checked %d programs, on %d channels\n", $stats{programCount}, $totalChannelsParsed);

	for my $cat (sort keys %{$self->{categories}}) {
		$ret.=sprintf("  found %d %s titles", $stats{perfect}->{$cat}+$stats{close}->{$cat},
												$self->{categories}->{$cat});
		if ( $stats{close}->{$cat} != 0 ) {
			if ( $stats{close}->{$cat} == 1 ) {
				$ret.=sprintf(" (%d was not perfect)", $stats{close}->{$cat});
			}
			else {
				$ret.=sprintf(" (%d were not perfect)", $stats{close}->{$cat});
			}
		}
		$ret.="\n";
	}

	$ret.=sprintf("  augmented %.2f%% of the programs, parsing %.2f programs/sec\n",
		  ($stats{programCount}!=0)?(($stats{perfectMatches}+$stats{closeMatches})*100)/$stats{programCount}:0,
		  ($endTime!=$stats{startTime} && $stats{programCount} != 0)?
		  $stats{programCount}/($endTime-$stats{startTime}):0);

	return($ret);
}

1;

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

package XMLTV::IMDB::Crunch;

use LWP;
use XMLTV::Gunzip;
use IO::File;

# is system sort available?
use constant HAS_SYSTEMSORT => ($^O=~'linux|cygwin|MSWin32');

# is File::Sort available?
use constant HAS_FILESORT => defined eval { require File::Sort };

use open ':encoding(iso-8859-1)';   # try to enforce file encoding (does this work in Perl <5.8.1? )

# Use Term::ProgressBar if installed.
use constant Have_bar => eval {
	require Term::ProgressBar;
	$Term::ProgressBar::VERSION >= 2;
};

my $VERSION = '0.11';	  # version number of database

my %titlehash = ();

#
# This package parses and manages to index imdb plain text files from
# ftp.imdb.com/interfaces. (see http://www.imdb.com/interfaces for
# details)
#
# I might, given time build a download manager that:
#	- downloads the latest plain text files
#	- understands how to download each week's diffs and apply them
# Currently, the 'downloadMissingFiles' flag in the hash of attributes
# passed triggers a simple-minded downloader.
#
# I may also roll this project into a xmltv-free imdb-specific
# perl interface that just supports callbacks and understands more of
# the imdb file formats.
#

# [honir] 2020-12-27 An undocumented option --sample n  will fetch only n records from each IMDb data file
# Note the output will not be valid (since the n records will not cross-reference from the different files)
# it's simply a way to avoid having to process all 4.5 million titles when you are debugging!


sub new
{
	my ($type) = shift;
	my $self={ @_ };			# remaining args become attributes
	for ($self->{downloadMissingFiles}) {
		$_=0 if not defined; # default
	}

	for ('imdbDir', 'verbose') {
		die "invalid usage - no $_" if ( !defined($self->{$_}));
	}

	$self->{stageLast} = 9;	 # set the final stage in the build - i.e. the one which builds the final database
	$self->{stages} = { 1=>'movies', 2=>'directors', 3=>'actors', 4=>'actresses', 5=>'genres', 6=>'ratings', 7=>'keywords', 8=>'plot' };
	$self->{optionalStages} = { 'keywords' => 7, 'plot' => 8 };	 # list of optional stages - no need to download files for these

	$self->{moviedbIndex}="$self->{imdbDir}/moviedb.idx";
	$self->{moviedbData}="$self->{imdbDir}/moviedb.dat";
	$self->{moviedbInfo}="$self->{imdbDir}/moviedb.info";
	$self->{moviedbOffline}="$self->{imdbDir}/moviedb.offline";

	# only leave progress bar on if its available
	if ( !Have_bar ) {
		$self->{showProgressBar}=0;
	}

	bless($self, $type);
	
	if ( $self->{filesort} && !( HAS_FILESORT || HAS_SYSTEMSORT ) ) {
		$self->error("filesort requested but not available");
		return(undef);		
	}
	$self->{usefilesort}  = ( (HAS_FILESORT || HAS_SYSTEMSORT) && $self->{filesort} );		# --filesort => 1  --nofilesort => 0
	$self->{usesystemsort} = ( HAS_SYSTEMSORT && $self->{filesort} && $self->{systemsort});	# use linux sort in preference to File::Sort as it is sooo much faster on big files

	if ( $self->{stageToRun} ne $self->{stageLast} ) {
		# unless this is the last stage, check we have the necessary files
		return(undef)  if ( $self->checkFiles() != 0 );
	}

	return($self);
}


sub checkFiles () {

	my ($self)=@_;

	if ( ! -d "$self->{imdbDir}" ) {
		if ( $self->{downloadMissingFiles} ) {
			warn "creating directory $self->{imdbDir}\n";
			mkdir $self->{imdbDir}, 0777
			  or die "cannot mkdir $self->{imdbDir}: $!";
		}
		else {
			die "$self->{imdbDir}:does not exist";
		}
	}
	my $listsDir = "$self->{imdbDir}/lists";
	if ( ! -d $listsDir ) {
		mkdir $listsDir, 0777 or die "cannot mkdir $listsDir: $!";
	}

  CHECK_FILES:
	my %missingListFiles; # maps 'movies' to filename ...movies.gz

	FILES_CHECK:
	while ( my( $key, $value ) = each %{ $self->{stages} } ) {
		# don't check *all* files - only the ones we are crunching
		next FILES_CHECK  if ( lc($self->{stageToRun}) ne 'all' && $key != int($self->{stageToRun}) );
		my $file=$value;
		my $filename="$listsDir/$file.list";
		my $filenameGz="$filename.gz";
		my $filenameExists = -f $filename;
		my $filenameSize = -s $filename;
		my $filenameGzExists = -f $filenameGz;
		my $filenameGzSize = -s $filenameGz;

		if ( $filenameExists and not $filenameSize ) {
			warn "removing zero-length $filename\n";
			unlink $filename or die "cannot unlink $filename: $!";
			$filenameExists = 0;
		}
		if ( $filenameGzExists and not $filenameGzSize ) {
			warn "removing zero-length $filenameGz\n";
			unlink $filenameGz or die "cannot unlink $filenameGz: $!";
			$filenameGzExists = 0;
		}

		if ( not $filenameExists and not $filenameGzExists ) {
			# Just report one of the filenames, keep the message simple.
			warn "$filenameGz does not exist\n";
			if ( $self->{optionalStages}{$file} && lc($self->{stageToRun}) eq 'all' ) {
				warn "$file will not be added to database\n";
			} else {
				$missingListFiles{$file}=$filenameGz;
			}
		}
		elsif ( not $filenameExists and $filenameGzExists ) {
			$self->{imdbListFiles}->{$file}=$filenameGz;
		}
		elsif ( $filenameExists and not $filenameGzExists ) {
			$self->{imdbListFiles}->{$file}=$filename;
		}
		elsif ( $filenameExists and $filenameGzExists ) {
			die "both $filename and $filenameGz exist, remove one of them\n";
		}
		else { die }
	}
	
	if ( $self->{downloadMissingFiles} ) {
		my $baseUrl = 'ftp://ftp.fu-berlin.de/pub/misc/movies/database/frozendata';
		foreach ( sort keys %missingListFiles ) {
			my $url = "$baseUrl/$_.list.gz";
			my $filename = delete $missingListFiles{$_};
			my $partial = "$filename.partial";
			if (-e $partial) {
				if (not -s $partial) {
					print STDERR "removing empty $partial\n";
					unlink $partial or die "cannot unlink $partial: $!";
				}
				else {
					die <<END
$partial already exists, remove it or try renaming to $filename and
resuming the download of <$url> by hand.

END
  ;
				}
			}

			print STDERR <<END
Trying to download <$url>.
With a slow network link this could fail; it might be better to
download the file by hand and save it as
$filename.

END
  ;
			# For downloading we use LWP
			#
			my $ua = LWP::UserAgent->new();
			$ua->env_proxy();
			$ua->show_progress(1);

			my $req = HTTP::Request->new(GET => $url);
			$req->authorization_basic('anonymous', 'tv_imdb');

			my $resp = $ua->request($req, $filename);
			my $got_size = -s $filename;
			if (defined $resp and $resp->is_success ) {
				die if not $got_size;
				print STDERR "<$url>\n\t-> $filename, success\n\n";
			}
			else {
				my $msg = "failed to download $url to $filename";
				$msg .= ", http response code: ".$resp->status_line if defined $resp;
				warn $msg;
				if ($got_size) {
					warn "renaming $filename -> $partial\n";
					rename $filename, $partial
					  or die "cannot rename $filename to $partial: $!";
					warn "You might try continuing the download of <$url> manually.\n";
				}
				exit(1);
			}
		}
		
		$self->{downloadMissingFiles} = 0;
		goto CHECK_FILES;
	}

	if ( %missingListFiles ) {
		print STDERR "tv_imdb: requires you to download the above files from ftp.fu-berlin.de \n";
		#print STDERR "		 see http://www.imdb.com/interfaces for details\n";
		print STDERR "		 or try the --download option\n";
		#return(undef);
		return 1;
	}

	return 0;
}

sub sortfile ($$$) {
	my ($self, $stage, $file)=@_;
	
	# file already written : sort it using (1) system sort command, or (2) File::Sort package
	
	my $f=$file;
	my $st = time;
	my $res;
	
	if ($self->{usesystemsort}) {			# use shell sort if we can (much faster on big files)
		$self->status("using system sort on stage $stage");
		
		# which OS are we on?
		if ($^O=~'linux|cygwin') {		# TODO: untested on cygwin
			if ($stage == 1) {
				$res = system( "sort", "-t", "\t", qw(-k 1 -o), "$f.sorted", "$f" );
			} else {
				$res = system( "sort", qw(-t : -k 1n -o), "$f.sorted", "$f" );
			}
			if ($? == -1) { $self->error("failed to execute: $! \n"); } 
			 elsif ( $? & 127 || $? & 128 ) { $self->error("system call died with signal %d \n"); }
			 else  { $res = $? >> 8; }
			$res = 1 if $res == 0;		# successful call returns 0 in $?
		
		} elsif ($^O=~'MSWin32') {		# TODO: untested on Windows
			$res = system( "sort", "/O ", "$f.sorted", "$f");
			$res = 1 if $res == 0;	# successful call returns 0 in $?
		}
		
	} else {
		$self->status("using filesort on stage $stage (this might take up to 1 hour)");
		if ($stage == 1) {
			$res = File::Sort::sort_file({ t =>"\t", k=>'1', y=>200000, I=>"$f", o=>"$f.sorted" });
		} else {
			$res = File::Sort::sort_file({ t =>':', k=>'1n', y=>200000, I=>"$f", o=>"$f.sorted" });
		}
	}
	
	$self->status("sorting took ".(int(((time - $st)/60)*10)/10)." minutes") if (time - $st > 60);
	
	if (!$res) {
		die "Filesort failed on $f";
	} else {
		unlink($f);
		rename "$f.sorted", $f  or die "Cannot rename file: $!";
	}
	
	return($res);
}

sub redirect($$)
{
	my ($self, $file)=@_;

	if ( defined($file) ) {
		if ( !open($self->{logfd}, "> $file") ) {
			print STDERR "$file:$!\n";
			return(0);
		}
		$self->{errorCountInLog}=0;
	}
	else {
		close($self->{logfd});
		$self->{logfd}=undef;
	}
	return(1);
}

sub error($$)
{
	my $self=shift;
	if ( defined($self->{logfd}) ) {
		print {$self->{logfd}} $_[0]."\n";
		$self->{errorCountInLog}++;
	}
	else {
		print STDERR $_[0]."\n";
	}
}

sub status($$)
{
	my $self=shift;

	if ( $self->{verbose} ) {
		print STDERR $_[0]."\n";
	}
}

sub withThousands ($)
{
	my ($val) = @_;
	$val =~ s/(\d{1,3}?)(?=(\d{3})+$)/$1,/g;
	return $val;
}

sub openMaybeGunzip($)
{
	for ( shift ) {
		return gunzip_open($_) if m/\.gz$/;
		return new IO::File("< $_");
	}
}

sub closeMaybeGunzip($$)
{
	if ( $_[0]=~m/\.gz$/o ) {
		# Would close($fh) but that causes segfaults on my system.
		# Investigating, but in the meantime just leave it open.
		#
		#return gunzip_close($_[1]);
	}

	# Apparently this can also segfault (wtf?).
	#return close($_[1]);
}

sub beginProgressBar($$$)
{
	my ($self, $what, $countEstimate)=@_;
		print STDERR $what.'   '.$countEstimate;
	if ($self->{showProgressBar}) {
		$self->{progress} = Term::ProgressBar->new({name  => "$what",
								count => $countEstimate*1.01,
								ETA   => 'linear'});
		$self->{progress}->minor(0) if ($self->{showProgressBar});
		$self->{progress}->max_update_rate(1) if ($self->{showProgressBar});
		$self->{count_estimate} = $countEstimate;
		$self->{next_update} = 0;
	}
}

sub updateProgressBar($$$)
{
	my ($self, $what, $count)=@_;
	
	if ( $self->{showProgressBar} ) {
		# re-adjust target so progress bar doesn't seem too wonky
		if ( $count > $self->{count_estimate} ) {
			$self->{count_estimate} = $self->{progress}->target($count*1.05);
			$self->{next_update} = $self->{progress}->update($count);
		}
		elsif ( $count > $self->{next_update} ) {
			$self->{next_update} = $self->{progress}->update($count);
		}
	}
}

sub endProgressBar($$$)
{
	my ($self, $what, $count)=@_;
	
	if ( $self->{showProgressBar} ) {
		$self->{progress}->update($self->{count_estimate});
	}
}

sub makeTitleKey($$)
{
	# make a unique key for each prog title. Also determine the prog type.
	
	# some edge cases we need to handle:
	# 1] multiple titles with same year, e.g. 
	#			'83 (2017/I)
	#			'83 (2017/II)
	#
	# 2] multiple films with same year but different type, e.g.
	#			Journey to the Center of the Earth (2008)			# cinema release
	#			Journey to the Center of the Earth (2008) (TV)		# TV movie
	#			Journey to the Center of the Earth (2008) (V)		# straight to video
	#
	# 3] tv series and film with same year, e.g.
	#			"Ashes to Ashes" (2008)				# tv series
	#			Ashes to Ashes (2008)				# movie
	#
	# 4] titles without a year, e.g.
	#			California Cornflakes (????)
	#			Zed (????/II)
	#
	# 5] titles including alternatiove title, e.g.
	#			Family Prayers (aka Karim & Suha) (2010)
	#
	
	my ($self, $progtitle)=@_;

	# tidy the film title, and extract the prog type
	#
	my $dbkey = $progtitle;
	my $progtype;

	# drop episode information - ex: "Supernatural" (2005) {A Very Supernatural Christmas (#3.8)}
	my $isepisode = $dbkey=~s/\s*\{[^\}]+\}//go;
		
	# remove 'aka' details from prog-title
	$dbkey =~ s/\s*\((?:aka|as) ([^\)]+)\)//o;

	# todo - this would make things easier
	# change double-quotes around title to be (made-for-tv) suffix instead
	if ( $dbkey=~m/^\"/o && #"
		 $dbkey=~m/\"\s*\(/o ) { #"
		$dbkey.=" (tv_series)";
		$progtype=4;
	}
	# how rude, some entries have (TV) appearing more than once.
	$dbkey=~s/\(TV\)\s*\(TV\)$/(TV)/o;

	my $qualifier;
	if ( $dbkey=~m/\s+\(TV\)$/ ) {		# don't strip from title - it's considered part of the title: so we need it for matching against other source files
		$qualifier="tv_movie";
		$progtype=2;
	}
	elsif ( $dbkey=~m/\s+\(V\)$/ ) {	# ditto
		$qualifier="video_movie";
		$progtype=3;
	}
	elsif ( $dbkey=~m/\s+\(VG\)$/ ) {	# ditto
		$qualifier="video_game";
		$progtype=5;
	}
	elsif ( $dbkey=~s/\s+\(mini\) \(tv_series\)$// ) {	# but strip the rest
		$qualifier="tv_mini_series";
		$progtype=4;
	}
	elsif ( $dbkey=~s/\s+\(tv_series\)$// ) {
		$qualifier="tv_series";
		$progtype=4;
	}
	elsif ( $dbkey=~s/\s+\(mini\)$//o ) {
		$qualifier="tv_mini_series";
		$progtype=4;
	}
	else {
		$qualifier="movie";
		$progtype=1;
	}


	# make a key from the title
	#
	my $year; my $yearcount;
	my $title = $dbkey;

	if ( $title=~m/^\"/o && $title=~m/\"\s*\(/o ) { # remove " marks around title
		$title=~s/^\"//o; #"
		$title=~s/\"(\s*\()/$1/o; #"
	}
	
	# strip the above progtypes from the hashkey
	$title=~s/\s*\((TV|V|VG)\)$//;

	# extract the year from the title
	if ( $title=~s/\s+\((\d\d\d\d)\)$//o ||
		 $title=~s/\s+\((\d\d\d\d)\/([IVXL]+)\)$//o ) {
		$year=$1;
	}
	elsif ( $title=~s/\s+\((\?\?\?\?)\)$//o ||
		$title=~s/\s+\((\?\?\?\?)\/([IVXL]+)\)$//o ) {
		$year="0000";
	}
	else {
		$self->error("movie list format failed to decode year from title '$title'");
		$year="0000";
	}
	$title=~s/(.*),\s*(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/og;	# move definite article to front of title
	
	$title=~s/\t/ /g;  # remove tab chars (there shouldn't be any but it will corrupt our data output if we find one)

	my $hashkey=lc("$title ($year)");		# use calculated year to avoid things like "72 Hours (????/I)"
	
	$hashkey=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;
		
	#print STDERR "input:$dbkey\n\tdbkey:$hashkey\n\ttitle=$title\n\tyear=$year\n\tcounter=$yearcount\n\tqualifier=$qualifier\n";
	
	return ( $hashkey, $dbkey, $year, $yearcount, $qualifier, $progtype, $isepisode );
}
				
sub readMovies($$$$$)
{
	# build %movieshash from movies.list source file
	
	my ($self, $which, $countEstimate, $file, $stage)=@_;
	my $startTime=time();
	my $header;
	my $whatAreWeParsing;
	my $lineCount=0;

	if ( $which eq "Movies" ) {
		$header="MOVIES LIST";
		$whatAreWeParsing=1;
	}
	
	$self->beginProgressBar('parsing '.$which, $countEstimate);
	
	
	#-----------------------------------------------------------
	# find the start of the actual data
	
	my $fh = openMaybeGunzip($file) || return(-2);
	while(<$fh>) {
		chomp();
		$lineCount++;
		if ( m/^$header/ ) {
			if ( !($_=<$fh>) || !m/^===========/o ) {
				$self->error("missing ======= after $header at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			if ( !($_=<$fh>) || !m/^\s*$/o ) {
				$self->error("missing empty line after ======= at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			last;
		}
		elsif ( $lineCount > 1000 ) {		# didn't find the header within the first 1000 lines in the file! (wrong file? file corrupt? data changed?)
			$self->error("$file: stopping at line $lineCount, didn't see \"$header\" line");
			closeMaybeGunzip($file, $fh);
			return(-1);
		}
	}



	#-----------------------------------------------------------
	# read the movies data, and create the db IDX file (as a temporary file called stage1.data)
	#    input data are "film-name  year" separated by one or more tabs
	#		Army of Darkness (1992)					1992
		
	my $count=0; my $countout=0;
	while(<$fh>) {
		chomp();
		$lineCount++;
		my $line=$_;
		next if ( length($line) == 0 );
		last if ( $self->{sample} != 0 && $self->{sample} < $count );	# undocumented option (used in debugging)
		#$self->status("read line $lineCount:$line");

		# end of data is line consisting of only '-'
		last if ( $line =~ m/^\-\-\-\-\-\-\-+/o );

		my $tabstop = index($line, "\t");	# there is always at least one tabstop in the incoming data
		if ( $tabstop != -1 ) {
			my ($mtitle, $myear) = $line =~ m/^(.*?)\t+(.*)$/;

			next if ($mtitle =~ m/\s*\{\{SUSPENDED\}\}/o);
			
			# returned count is number of titles found
			$count++;

			# compute the data we need for the IDX file
			#	key  title  year  title  id
			#
			my ($hashkey, $title, $year, $yearcount, $qualifier, $progtype, $isepisode) = $self->makeTitleKey($mtitle);
			
			# we don't want "video games"
			if ($qualifier eq "video_game") { next; }
			
			# we don't keep episode information   TODO: enhancement: change tv_imdb to do episodes?
			if ($isepisode == 1) { next; }
			
			next if ($self->{moviesonly} && ($progtype != 1 && $progtype != 2) );	# user requested movies_only
			
			
			# store the movies data
			if ($self->{usefilesort}) {
				# if sorting on disc then write the extracted movies data to an interim file
				print {$self->{fhdata}} $hashkey."\t".$title."\t".$year."\t".$qualifier."\n";
				
			} else {
				# store the title in a hash of $key=>{$title}
				if ( defined($self->{movieshash}{$hashkey}) ) {	# check for duplicates
					#
					# there's a lot (c. 9,000!) instances of duplicate titles in the movies.list file
					#   so only report where titles are different
					if ( defined $self->{movieshash}{$hashkey}{$title} && $self->{movieshash}{$hashkey}{$title} ne $year."\t".$qualifier ) {	# {."\t".$progtype}			
						$self->error("duplicate moviedb key computed $hashkey - this programme will be ignored $mtitle");
						#$self->error("        ".$self->{movieshash}{$hashkey}{$title});
						next;
					}
				}
				
				# the output IDX and DAT files must be sorted by dbkey (because of the way the searching is done)
				# so we need to store all the incoming 4 million records and then sort them
				#
				$self->{movieshash}{$hashkey}{$title} = $year."\t".$qualifier;			# we don't currently use the progtype flag so don't print it  {."\t".$progtype}
				
			}
			
			# return number of titles kept
			$countout++;
			
			$self->updateProgressBar('', $lineCount);
		}
		else {
			$self->error("$file:$lineCount: unrecognized format (missing tab)");
			$self->updateProgressBar('', $lineCount);
		}
	}
	
	$self->endProgressBar();

	$self->status(sprintf("parsing $which found ".withThousands($countout)." titles in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

	closeMaybeGunzip($file, $fh);

	#-----------------------------------------------------------
	return($count, $countout);
}

sub readCastOrDirectors($$$$$)
{
	my ($self, $which, $countEstimate, $file, $stage)=@_;
	my $startTime=time();
	my $header;
	my $whatAreWeParsing;
	my $lineCount=0;

	if ( $which eq "Actors" ) {
		$header="THE ACTORS LIST";
		$whatAreWeParsing=1;
	}
	elsif ( $which eq "Actresses" ) {
		$header="THE ACTRESSES LIST";
		$whatAreWeParsing=2;
	}
	elsif ( $which eq "Directors" ) {
		$header="THE DIRECTORS LIST";
		$whatAreWeParsing=3;
	}
	else {
		die "why are we here ?";
	}
	
	$self->beginProgressBar('parsing '.$which, $countEstimate);

	#
	# note: not all movies end up with a cast, but we include these movies anyway.
	#

	#-----------------------------------------------------------
	# find the start of the actual data
	
	my $fh = openMaybeGunzip($file) || return(-2);
	while(<$fh>) {
		chomp();
		$lineCount++;
		if ( m/^$header/ ) {
			if ( !($_=<$fh>) || !m/^===========/o ) {
				$self->error("missing ======= after $header at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			if ( !($_=<$fh>) || !m/^\s*$/o ) {
				$self->error("missing empty line after ======= at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			if ( !($_=<$fh>) || !m/^Name\s+Titles\s*$/o ) {
				$self->error("missing name/titles line after ======= at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			if ( !($_=<$fh>) || !m/^[\s\-]+$/o ) {
				$self->error("missing name/titles suffix line after ======= at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			last;
		}
		elsif ( $lineCount > 1000 ) {
			$self->error("$file: stopping at line $lineCount, didn't see \"$header\" line");
			closeMaybeGunzip($file, $fh);
			return(-1);
		}
	}


	#-----------------------------------------------------------
	# read the cast or directors data, and create the stagex.data file
	#    input data are "person-name  film-title" separated by one or more tabs
	#		Raimi,Sam		Army of Darkness (1992)
	#	 person name appears only once for multiple film entries
	
	my $count=0;
	my $countnames=0;
	my $cur_name;
	while(<$fh>) {
		chomp();
		$lineCount++;
		my $line=$_;
		next if ( length($line) == 0 );
		last if ( $self->{sample} != 0 && $self->{sample} < $count );	# undocumented option (used in debugging)
		#$self->status("read line $lineCount:$line");

		# end is line consisting of only '-'
		last if ( $line =~ m/^\-\-\-\-\-\-\-+/o );
		
		my $tabstop = index($line, "\t");	# there is always at least one tabstop in the incoming data
		if ( $tabstop != -1 ) {
			my ($mname, $mtitle) = $line =~ m/^(.*?)\t+(.*)$/;	# get person-name (everything up to the first tab)

			next if ($mtitle=~m/\s*\{\{SUSPENDED\}\}/o);
			
			# skip enties that have {} in them since they're tv episodes
			next if ($mtitle=~m/\s*\{[^\}]+\}$/ );
			
			# skip "video games"
			next if ($mtitle=~m/\s+\(VG\)(\s|$)/ );
			#  note may not be end of line e.g.  "Ahad, Alex (I)		Skullgirls (2012) (VG)  (creative director)"


			# returned count is number of directors found
			$count++;
			
			$mname =~ s/^\s+|\s+$//g;	# trim
			
			# person name appears only on the first record in a group for this person
			if ($mname ne '') {
				$countnames++;
				$cur_name = $mname;
			}  
			
			
			# Directors' processing
			#	A. Guggenheim, Sonia	After Maiko (2015)  (as Sonia Guggenheim)
			#							Journey (2015/III)  (as Sonia Guggenheim)
			#	A. Solla, Ricardo		"7 vidas" (1999) {(#2.37)}
			#							"7 vidas" (1999) {Atahualpa Yupanqui (#6.20)}
			#
			
			# Actors' processing
			#	-Gradowska, Kasia Lewandowska	Who are the WWP Women? (2015) (V)  [Herself]  <1>
			#	'Rovel' Torres, Crystal	"The Tonight Show Starring Jimmy Fallon" (2014) {Ice T/Andrew Rannells/Lupe Fiasco (#2.105)}  [Herself - Musical Support]
			#	's Gravemade, Nienke	A Short Tour & Farewell (2015)
			#							Tweeduizendseks (2010) (TV)  [Yolanda van der Graaf]
			#	Bennett, Mollie		"Before the Snap" (2011)  (voice)  [Narrator]
			#	'Twinkie' Bird, Tracy	"Casting Qs" (2010) {An Interview with Tracy 'Twinkie' Byrd (#2.14)}  (as Twinkie Byrd)  [Herself]
			#	Abbott, Tasha (I)	"Electives" (2018)  [Julie]  <41>
			#
			
			my $billing;
			my $hostnarrator;
			if ( $whatAreWeParsing < 3 ) {	# actors or actresses
				
				# extract/strip the billing
				$billing="9999";
				if ( $mtitle =~ s/\s*<(\d+)>//o ) {		# e.g. <41>
					$billing = sprintf("%04d", int($1));
				}
				
				# extract/strip the role/character
				if ( $mtitle =~ s/\s*\[(.*?)\]//o ) {		# e.g. [Julie] or [Narrator]
					if ( $1 =~ m/(Host|Narrator)/ ) {		# also picks up "Hostess", "Co-Host"
						$hostnarrator = $1;
					}
				}
			}
			

			#-------------------------------------------------------
			# tidy the title

			# remove the episode if a series
			if ( $mtitle =~ s/\s*\{[^\}]+\}//o ) {	#redundant
				# $attr=$1;
				next; 	# skip tv episodes (we only output main titles so don't store episode data against the main title)
			}
		
			# remove 'aka' details from prog-title
			if ( $mtitle =~ s/\s*\((?:aka|as) ([^\)]+)\)//o ) {
				# $attr=$1;
			}
		
			# remove prog type (e.g. "(V)" or "(TV)" )
			# no: don't strip from title - it's considered part of the title: so we need it for matching against movies.list
			##if ( $mtitle =~ s/\s(\((TV|V|VG)\))//o ) {
				# $attrs=$1;
			##}
		
			# junk everything after "  ("  (e.g. "  (collaborating director)" )
			if ( $mtitle =~ s/  (\(.*)$//o ) {
				# $attrs=$1;
			}
			
			$mtitle =~ s/^\s+|\s+$//g;	# trim
				
				
			#-------------------------------------------------------
			# $mtitle should now contain the programme's title
			my $title = $mtitle;
			
			# find the IDX id from the hash of titles ($title=>$lineno) created in stage 1
			my $idxid = $self->{titleshash}{$title};
			
			if (!$idxid ) {
				## no, don't print errors where we can't match the incoming title - there are 100s of these in the incoming data
				##  often where the year on the actor record is 1 year out
				##  people will get worried if we report over 1000 errors and there's nothing we can sensibly do about them
				##$self->error("$file:$lineCount: cannot find $title in titles list");
				###   if we reinstate this test then we'd need to allow for 'moviesonly' option (i.e. a lot of titles will have been deliberately excluded)
				next;
			}


			#-------------------------------------------------------
			# the output ".data" files must be sorted by id so they can be merged in stage final
			# so we need to store all the incoming records and then sort them 
			#
			my $mperson = '';
			$mperson = "$billing:" if ( defined($billing) );
			$mperson .= $cur_name;
			$mperson .= " [$hostnarrator]" if ( defined($hostnarrator) );	# this is wrong: incoming data are "lastname, firstname" so this creates "Huwyler, Fabio [Host]"
			
			if ($self->{usefilesort}) {
				# write the extracted imdb data to a temporary file, preceeded by the IDX id for each record
				my $k = sprintf("%07d", $idxid);
				print {$self->{fhdata}} $k.':'.$mperson."\n";
				
			} else {
				my $h = "stage${stage}hash";
				if (defined( $self->{$h}{$idxid} )) {
					$self->{$h}{$idxid} .= "|".$mperson;
				} else {
					$self->{$h}{$idxid}  = $mperson;
				}
			}

			
			$self->updateProgressBar('', $lineCount);
		}
		else {
			$self->error("$file:$lineCount: unrecognized format (missing tab)");
			$self->updateProgressBar('', $lineCount);
		}
	}
	
	$self->endProgressBar();
	
	$self->status(sprintf("parsing $which found ".withThousands($countnames)." names, ".
			  withThousands($count)." titles in ".withThousands($lineCount)." lines in %d seconds",time()-$startTime));

	closeMaybeGunzip($file, $fh);

	#-----------------------------------------------------------
	return($count);
}

sub readGenres($$$$$)
{
	my ($self, $which, $countEstimate, $file, $stage)=@_;
	my $startTime=time();
	my $header;
	my $whatAreWeParsing;
	my $lineCount=0;

	if ( $which eq "Genres" ) {
		$header="8: THE GENRES LIST";
		$whatAreWeParsing=1;
	}
	
	$self->beginProgressBar('parsing '.$which, $countEstimate);


	#-----------------------------------------------------------
	# find the start of the actual data
	
	my $fh = openMaybeGunzip($file) || return(-2);
	while(<$fh>) {
		chomp();
		$lineCount++;
		if ( m/^$header/ ) {
			if ( !($_=<$fh>) || !m/^===========/o ) {
				$self->error("missing ======= after $header at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			if ( !($_=<$fh>) || !m/^\s*$/o ) {
				$self->error("missing empty line after ======= at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			last;
		}
		elsif ( $lineCount > 1000 ) {
			$self->error("$file: stopping at line $lineCount, didn't see \"$header\" line");
			closeMaybeGunzip($file, $fh);
			return(-1);
		}
	}

	
	#-----------------------------------------------------------
	# read the genres data, and create the stagex.data file
	#    input data are "film-title  genre" separated by one or more tabs
	#	 multiple genres are searated by |
	#		Army of Darkness (1992)					Horror
	#		King Jeff (2009)	Comedy|Short
	
	my $count=0;
	while(<$fh>) {
		chomp();
		$lineCount++;
		my $line=$_;
		next if ( length($line) == 0 );
		last if ( $self->{sample} != 0 && $self->{sample} < $lineCount );	# undocumented option (used in debugging)
		#$self->status("read line $lineCount:$line");

		# end is line consisting of only '-'
		last if ( $line=~m/^\-\-\-\-\-\-\-+/o );
		
		my $tabstop = index($line, "\t");	# there is always at least one tabstop in the incoming data
		if ( $tabstop != -1 ) {
			my ($mtitle, $mgenres) = $line =~ m/^(.*?)\t+(.*)$/;	# get film-title (everything up to the first tab)

			next if ($mtitle=~m/\s*\{\{SUSPENDED\}\}/o);
			
			# skip enties that have {} in them since they're tv episodes
			next if ($mtitle=~m/\s*\{[^\}]+\}/ );
			
			# skip "video games"
			next if ($mtitle=~m/\s+\(VG\)$/ );

			# returned count is number of titles found
			$count++;
			
			if ( $whatAreWeParsing == 1 ) {	# genres

				# genres sometimes contains tabs
				$mgenres=~s/^\t+//og;
				
			}
			

			#-------------------------------------------------------
			# tidy the title

			# remove the episode if a series
			if ( $mtitle =~ s/\s*\{[^\}]+\}//o ) {	#redundant
				# $attr=$1;
			}
		
			# remove 'aka' details from prog-title
			if ( $mtitle =~ s/\s*\((?:aka|as) ([^\)]+)\)//o ) {
				# $attr=$1;
			}
			
			$mtitle =~ s/^\s+|\s+$//g;	# trim
				
			
			#-------------------------------------------------------
			# $mtitle should now contain the programme's title
			my $title = $mtitle;
			
			# find the IDX id from the hash of titles ($title=>$lineno) created in stage 1
			my $idxid = $self->{titleshash}{$title};
			
			if (!$idxid ) {
				## no, don't print errors where we can't match the incoming title - there are 100s of these in the incoming data
				##  often where the year on the actor record is 1 year out
				##$self->error("$file:$lineCount: cannot find $title in titles list");
				next;
			}


			#-------------------------------------------------------
			# the output ".data" files must be sorted by id so they can be merged in stage final
			# so we need to store all the incoming records and then sort them
			#
			if ($self->{usefilesort}) {
				# write the extracted imdb data to a temporary file, preceeded by the IDX id for each record
				my $k = sprintf("%07d", $idxid);
				print {$self->{fhdata}} $k.':'.$mgenres."\n";
				
			} else {
				my $h = "stage${stage}hash";
				if (defined( $self->{$h}{$idxid} )) {
					$self->{$h}{$idxid} .= "|".$mgenres;
				} else {
					$self->{$h}{$idxid}  = $mgenres;
				}
			}

			
			$self->updateProgressBar('', $lineCount);
		}
		else {
			$self->error("$file:$lineCount: unrecognized format (missing tab)");
			$self->updateProgressBar('', $lineCount);
		}
	}
	
	$self->endProgressBar();
	
	$self->status(sprintf("parsing $which found ".withThousands($count)." titles in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

	closeMaybeGunzip($file, $fh);

	#-----------------------------------------------------------
	return($count);
}

sub readRatings($$$$$)
{
	my ($self, $which, $countEstimate, $file, $stage)=@_;
	my $startTime=time();
	my $header;
	my $whatAreWeParsing;
	my $lineCount=0;

	if ( $which eq "Ratings" ) {
		$header="MOVIE RATINGS REPORT";
		$whatAreWeParsing=1;
	}
	
	$self->beginProgressBar('parsing '.$which, $countEstimate);


	#-----------------------------------------------------------
	# find the start of the actual data
	
	my $fh = openMaybeGunzip($file) || return(-2);
	while(<$fh>) {
		chomp();
		$lineCount++;
		if ( m/^$header/ ) {
			# there is no ====== in ratings data!
			if ( !($_=<$fh>) || !m/^\s*$/o ) {
				$self->error("missing empty line after $header at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			if ( !($_=<$fh>) || !m/^New  Distribution  Votes  Rank  Title/o ) {
				$self->error("missing \"New  Distribution  Votes  Rank  Title\" at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			last;
		}
		elsif ( $lineCount > 1000 ) {
			$self->error("$file: stopping at line $lineCount, didn't see \"$header\" line");
			closeMaybeGunzip($file, $fh);
			return(-1);
		}
	}

	
	#-----------------------------------------------------------
	# read the ratings data, and create the stagex.data file
	#    input data are "flag-new disribution  votes  rank  film-title" separated by one or more spaces
	#			0000002211  000001   9.9  Army of Darkness (1992)
	#			0000000133  225568   8.9  12 Angry Men (1957)
	
	my $count=0;
	while(<$fh>) {
		chomp();
		$lineCount++;
		my $line=$_;
		next if ( length($line) == 0 );
		last if ( $self->{sample} != 0 && $self->{sample} < $lineCount );	# undocumented option (used in debugging)
		#$self->status("read line $lineCount:$line");

		# skip empty lines (only really appear right before last line ending with ----
		next if ( $line=~m/^\s*$/o );
		# end is line consisting of only '-'
		last if ( $line=~m/^\-\-\-\-\-\-\-+/o );
		
		my $tabstop = index($line, " ");	# there is always at least one space in the incoming data
		if ( $tabstop != -1 ) {
			my ($mdistrib, $mvotes, $mrank, $mtitle) = $line =~ m/^\s+([\.|\*|\d]+)\s+(\d+)\s+(\d+\.\d+)\s+(.*)$/;
			
			next if ($mtitle=~m/\s*\{\{SUSPENDED\}\}/o);

			next if ($mtitle=~m/\s*\{[^\}]+\}/ ); # skip tv episodes
			
			next if ($mtitle=~m/\s+\(VG\)$/ );  # we don't want "video games"

			# returned count is number of titles found
			$count++;
			
			if ( $whatAreWeParsing == 1 ) {	# ratings
				# null
			}
			

			#-------------------------------------------------------
			# tidy the title

			# remove the episode if a series
			if ( $mtitle =~ s/\s*\{[^\}]+\}//o ) {	#redundant
				# $attr=$1;
			}
		
			# remove 'aka' details from prog-title
			if ( $mtitle =~ s/\s*\((?:aka|as) ([^\)]+)\)//o ) {
				# $attr=$1;
			}
			
			$mtitle =~ s/^\s+|\s+$//g;	# trim
				
			
			#-------------------------------------------------------
			# $mtitle should now contain the programme's title
			my $title = $mtitle;
			
			# find the IDX id from the hash of titles ($title=>$lineno) created in stage 1
			my $idxid = $self->{titleshash}{$title};
			
			if (!$idxid ) {
				## no, don't print errors where we can't match the incoming title - there are 100s of these in the incoming data
				##  often where the year on the actor record is 1 year out
				##$self->error("$file:$lineCount: cannot find $title in titles list");
				next;
			}


			#-------------------------------------------------------
			# the output ".data" files must be sorted by id so they can be merged in stage final
			# so we need to store all the incoming records and then sort them
			#
			if ($self->{usefilesort}) {
				# write the extracted imdb data to a temporary file, preceeded by the IDX id for each record
				my $k = sprintf("%07d", $idxid);
				print {$self->{fhdata}} $k.':'."$mdistrib;$mvotes;$mrank"."\n";
				
			} else {
				my $h = "stage${stage}hash";
				if (defined( $self->{$h}{$idxid} )) {
					# we shouldn't get duplicates
					$self->error("$file: duplicate film found at line $lineCount - this rating will be ignored $mtitle");
				} else {
					$self->{$h}{$idxid}  = "$mdistrib;$mvotes;$mrank";
				}
			}

			
			$self->updateProgressBar('', $lineCount);
		}
		else {
			$self->error("$file:$lineCount: unrecognized format (missing tab)");
			$self->updateProgressBar('', $lineCount);
		}
	}
	
	$self->endProgressBar();
	
	$self->status(sprintf("parsing $which found ".withThousands($count)." titles in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

	closeMaybeGunzip($file, $fh);

	#-----------------------------------------------------------
	return($count);
}

sub readKeywords($$$$$)
{
	my ($self, $which, $countEstimate, $file, $stage)=@_;
	my $startTime=time();
	my $header;
	my $whatAreWeParsing;
	my $lineCount=0;

	if ( $which eq "Keywords" ) {
		$header="8: THE KEYWORDS LIST";
		$whatAreWeParsing=1;
	}
	
	$self->beginProgressBar('parsing '.$which, $countEstimate);


	#-----------------------------------------------------------
	# find the start of the actual data
	
	my $fh = openMaybeGunzip($file) || return(-2);
	while(<$fh>) {
		chomp();
		$lineCount++;
		if ( m/^$header/ ) {
			if ( !($_=<$fh>) || !m/^===========/o ) {
				$self->error("missing ======= after $header at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			if ( !($_=<$fh>) || !m/^\s*$/o ) {
				$self->error("missing empty line after ======= at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			last;
		}
		elsif ( $lineCount > 150000 ) {		# line 101935 as at 2020-12-23
			$self->error("$file: stopping at line $lineCount, didn't see \"$header\" line");
			closeMaybeGunzip($file, $fh);
			return(-1);
		}
	}

	
	#-----------------------------------------------------------
	# read the keywords data, and create the stagex.data file
	#    input data are "film-title  keyword" separated by one or more tabs
	#	 multiple keywords are searated by |
	#		Army of Darkness (1992)					Horror
	#		King Jeff (2009)	Comedy|Short
	
	my $count=0;
	while(<$fh>) {
		chomp();
		$lineCount++;
		my $line=$_;
		next if ( length($line) == 0 );
		last if ( $self->{sample} != 0 && $self->{sample} < $lineCount );	# undocumented option (used in debugging)
		#$self->status("read line $lineCount:$line");

		# end is line consisting of only '-'
		last if ( $line=~m/^\-\-\-\-\-\-\-+/o );
		
		my $tabstop = index($line, "\t");	# there is always at least one tabstop in the incoming data
		if ( $tabstop != -1 ) {
			my ($mtitle, $mkeywords) = $line =~ m/^(.*?)\t+(.*)$/;	# get film-title (everything up to the first tab)

			next if ($mtitle=~m/\s*\{\{SUSPENDED\}\}/o);

			next if ($mtitle=~m/\s*\{[^\}]+\}/ ); # skip tv episodes
			
			next if ($mtitle=~m/\s+\(VG\)$/ );  # we don't want "video games"

			# returned count is number of titles found
			$count++;
			
			if ( $whatAreWeParsing == 1 ) {	# genres

				# ignore anything which is an episode (e.g. "{Doctor Who (#10.22)}" )
				next if $mtitle =~ m/^.*\s+(\{.*\})$/;
				
			}
			

			#-------------------------------------------------------
			# tidy the title

			# remove the episode if a series
			# [honir] this is wrong - this puts all the keywords as though they are in the entire series!
			if ( $mtitle =~ s/\s*\{[^\}]+\}//o ) {	#redundant
				# $attr=$1;
			}
		
			# remove 'aka' details from prog-title
			if ( $mtitle =~ s/\s*\((?:aka|as) ([^\)]+)\)//o ) {
				# $attr=$1;
			}
			
			$mtitle =~ s/^\s+|\s+$//g;	# trim
				
			
			#-------------------------------------------------------
			# $mtitle should now contain the programme's title
			my $title = $mtitle;
			
			# find the IDX id from the hash of titles ($title=>$lineno) created in stage 1
			my $idxid = $self->{titleshash}{$title};
			
			if (!$idxid ) {
				## no, don't print errors where we can't match the incoming title - there are 100s of these in the incoming data
				##  often where the year on the actor record is 1 year out
				##$self->error("$file:$lineCount: cannot find $title in titles list");
				next;
			}


			#-------------------------------------------------------
			# the output ".data" files must be sorted by id so they can be merged in stage final
			# so we need to store all the incoming records and then sort them
			#
			if ($self->{usefilesort}) {
				# write the extracted imdb data to a temporary file, preceeded by the IDX id for each record
				my $k = sprintf("%07d", $idxid);
				print {$self->{fhdata}} $k.':'.$mkeywords."\n";
				
			} else {
				my $h = "stage${stage}hash";
				if (defined( $self->{$h}{$idxid} )) {
					$self->{$h}{$idxid} .= "|".$mkeywords;
				} else {
					$self->{$h}{$idxid}  = $mkeywords;
				}
			}

			
			$self->updateProgressBar('', $lineCount);
		}
		else {
			$self->error("$file:$lineCount: unrecognized format (missing tab)");
			$self->updateProgressBar('', $lineCount);
		}
	}
	
	$self->endProgressBar();
	
	$self->status(sprintf("parsing $which found ".withThousands($count)." titles in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

	closeMaybeGunzip($file, $fh);

	#-----------------------------------------------------------
	return($count);
}

sub readPlots($$$$$)
{
	my ($self, $which, $countEstimate, $file, $stage)=@_;
	my $startTime=time();
	my $header;
	my $whatAreWeParsing;
	my $lineCount=0;

	if ( $which eq "Plot" ) {
		$header="PLOT SUMMARIES LIST";
		$whatAreWeParsing=1;
	}

	$self->beginProgressBar('parsing '.$which, $countEstimate);


	#-----------------------------------------------------------
	# find the start of the actual data
	
	my $fh = openMaybeGunzip($file) || return(-2);
	while(<$fh>) {
		chomp();
		$lineCount++;
		if ( m/^$header/ ) {
			if ( !($_=<$fh>) || !m/^===========/o ) {
				$self->error("missing ======= after $header at line $lineCount");
				closeMaybeGunzip($file, $fh);
				return(-1);
			}
			# no blank line in plot data!
			##if ( !($_=<$fh>) || !m/^\s*$/o ) {
			##	$self->error("missing empty line after ======= at line $lineCount");
			##	closeMaybeGunzip($file, $fh);
			##	return(-1);
			##}
			last;
		}
		elsif ( $lineCount > 1000 ) {
			$self->error("$file: stopping at line $lineCount, didn't see \"$header\" line");
			closeMaybeGunzip($file, $fh);
			return(-1);
		}
	}

	
	#-----------------------------------------------------------
	# read the plot data, and create the stagex.data file
	#    input data are "flag-new disribution  votes  rank  film-title" separated by one or more spaces
	#		there can be multiple entries for each film
	#			-------------------------------------------------------------------------------
	#			MV: Army of Darkness (1992)
	#			
	#			PL: Ash is transported with his car to 1,300 A.D., where he is captured by Lord
	#			PL: Arthur and turned slave with Duke Henry the Red and a couple of his men.
	#			[...]
	#			PL: battle between Ash's 20th Century tactics and the minions of darkness.
	#			
	#			BY: David Thiel <d-thiel@uiuc.edu>
	#			
	#			PL: Ash finds himself stranded in the year 1300 AD with his car, his shotgun,
	#			PL: and his chainsaw. Soon he is discovered and thought to be a spy for a rival
	#			[...]
	#			PL: forces at play in the land. Ash accidentally releases the Army of Darkness
	#			PL: when retrieving the book, and a fight to the finish ensues.
	#			
	#			BY: Ed Sutton <esutton@mindspring.com>

	my $count=0;
	while(<$fh>) {
		chomp();
		$lineCount++;
		my $line=$_;
		next if ( length($line) == 0 );
		last if ( $self->{sample} != 0 && $self->{sample} < $lineCount );	# undocumented option (used in debugging)
		#$self->status("read line $lineCount:$line");
	
		# skip empty lines
		next if ( $line=~m/^\s*$/o );
		
		next if ( $line=~m/\s*\{[^\}]+\}/ ); # skip tv episodes
			
		next if ( $line=~m/\s+\(VG\)$/ );  # skip "video games"

		# process a data block - starts with "MV:"
		#
		my ($mtitle, $mepisode) = ($line =~ m/^MV:\s(.*?)\s?(\{.*\})?$/);
		if ( defined($mtitle) ) {
			my $mplot = '';

			# ignore anything which is an episode (e.g. "{Doctor Who (#10.22)}" )
			if ( !defined $mepisode || $mepisode eq '' )
			{
				LOOP:
				while (1) {
					if ( $line = <$fh> ) {
						$lineCount++;
						chomp($line);
						next if ($line =~ m/^\s*$/);
						if ( $line =~ m/PL:\s(.*)$/ ) {	 	# plot summary is a number of lines starting "PL:"
							$mplot .= ($mplot ne ''?' ':'') . $1;
						}
						last LOOP if ( $line =~ m/BY:\s(.*)$/ );	 # the author line "BY:" signals the end of the plot summary
					} else {
						last LOOP;
					}
				}

				# ensure there's no tab chars in the plot or else the db stage will barf
				$mplot =~ s/\t//og;
				
				# returned count is number of unique titles found
				$count++;
			}
			
			
			#-------------------------------------------------------
			# tidy the title

			# remove the episode if a series
			if ( $mtitle =~ s/\s*\{[^\}]+\}//o ) {	#redundant
				# $attr=$1;
			}
		
			# remove 'aka' details from prog-title
			if ( $mtitle =~ s/\s*\((?:aka|as) ([^\)]+)\)//o ) {
				# $attr=$1;
			}
			
			$mtitle =~ s/^\s+|\s+$//g;	# trim
				
			
			#-------------------------------------------------------
			# $mtitle should now contain the programme's title
			my $title = $mtitle;
			
			# find the IDX id from the hash of titles ($title=>$lineno) created in stage 1
			my $idxid = $self->{titleshash}{$title};
			
			if (!$idxid ) {
				## no, don't print errors where we can't match the incoming title - there are 100s of these in the incoming data
				##  often where the year on the actor record is 1 year out
				##$self->error("$file:$lineCount: cannot find $title in titles list");
				next;
			}


			#-------------------------------------------------------
			# the output ".data" files must be sorted by id so they can be merged in stage final
			# so we need to store all the incoming records and then sort them
			#
			if ($self->{usefilesort}) {
				# write the extracted imdb data to a temporary file, preceeded by the IDX id for each record
				my $k = sprintf("%07d", $idxid);
				print {$self->{fhdata}} $k.':'.$mplot."\n";
				
			} else {
				my $h = "stage${stage}hash";
				if (defined( $self->{$h}{$idxid} )) {
					# we shouldn't get duplicates
					$self->error("$file: duplicate film found at line $lineCount - this plot will be ignored $mtitle");
				} else {
					$self->{$h}{$idxid}  = $mplot;
				}
			}

			
			$self->updateProgressBar('', $lineCount);
		}
		else {
			# skip lines up to the next "MV:"  (this means we only get the first plot summary for each film)
			if ($line !~ m/^(---|PL:|BY:)/ ) {
				$self->error("$file:$lineCount: unrecognized format \"$line\"");
			}
			$self->updateProgressBar('', $lineCount);
		}
	}
	
	$self->endProgressBar();
	
	$self->status(sprintf("parsing $which found ".withThousands($count)." in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

	closeMaybeGunzip($file, $fh);

	#-----------------------------------------------------------
	return($count);
}

sub stageComplete($)
{
	my ($self, $stage)=@_;

	if ( -f "$self->{imdbDir}/stage$stage.data" ) {
		return(1);
	}
	return(0);
}

sub dbinfoLoad($)
{
	my $self=shift;

	my $ret=XMLTV::IMDB::loadDBInfo($self->{moviedbInfo});
	if ( ref $ret eq 'SCALAR' ) {
		return($ret);
	}
	$self->{dbinfo}=$ret;
	return(undef);
}

sub dbinfoAdd($$$)
{
	my ($self, $key, $value)=@_;
	$self->{dbinfo}->{$key}=$value;
}

sub dbinfoGet($$$)
{
	my ($self, $key, $defaultValue)=@_;
	if ( defined($self->{dbinfo}->{$key}) ) {
		return($self->{dbinfo}->{$key});
	}
	return($defaultValue);
}

sub dbinfoSave($)
{
	my $self=shift;
	open(INFO, "> $self->{moviedbInfo}") || return(1);
	for (sort keys %{$self->{dbinfo}}) {
		print INFO "".$_.":".$self->{dbinfo}->{$_}."\n";
	}
	close(INFO);
	return(0);
}

sub dbinfoGetFileSize($$)
{
	my ($self, $key)=@_;

	if ( !defined($self->{imdbListFiles}->{$key}) ) {
		die ("invalid call");
	}
	my $fileSize=int(-s "$self->{imdbListFiles}->{$key}");

	# if compressed, then attempt to run gzip -l
	if ( $self->{imdbListFiles}->{$key}=~m/.gz$/) {
		if ( open(my $fd, "gzip -l ".$self->{imdbListFiles}->{$key}."|") ) {
			# if parse fails, then defalt to wild ass guess of compression of 65%
			$fileSize=int(($fileSize*100)/(100-65));

			while(<$fd>) {
				if ( m/^\s*\d+\s+(\d+)/ ) {
					$fileSize=$1;
				}
			}
			close($fd);
		}
		else {
			# wild ass guess of compression of 65%
			$fileSize=int(($fileSize*100)/(100-65));
		}
	}
	return($fileSize);
}

sub dbinfoCalcEstimate($$$)
{
	my ($self, $key, $estimateSizePerEntry)=@_;

	my $fileSize=$self->dbinfoGetFileSize($key);

	my $countEstimate=int($fileSize/$estimateSizePerEntry);

	$self->dbinfoAdd($key."_list_file", $self->{imdbListFiles}->{$key});
	$self->dbinfoAdd($key."_list_file_size", int(-s "$self->{imdbListFiles}->{$key}"));
	$self->dbinfoAdd($key."_list_file_size_uncompressed", $fileSize);
	$self->dbinfoAdd($key."_list_count_estimate", $countEstimate);
	return($countEstimate);
}

sub dbinfoCalcBytesPerEntry($$$)
{
	my ($self, $key, $calcActualForThisNumber)=@_;

	my $fileSize=$self->dbinfoGetFileSize($key);

	return(int($fileSize/$calcActualForThisNumber));
}

sub gettitleshash($$) 
{
	# load the titles list (stage1.data) into memory 
	
	my ($self, $countEstimate)=@_;
	my $startTime=time();
	my $lineCount=0;

	undef $self->{titleshash};
	
	$self->beginProgressBar('loading titles list', $countEstimate);

	open(IN, "< $self->{imdbDir}/stage1.data") || die "$self->{imdbDir}/stage1.data:$!";
	my $count=0;
	my $maxidxid=0;
	while(<IN>) {
		chomp();
		my $line=$_;
		next if ( length($line) == 0 );
		#$self->status("read line $lineCount:$line");
		$lineCount++;
		
		# check the database version number
		if ($lineCount == 1) {
			if ( m/^0000000:version ([\d\.]*)$/ ) {
				if ($1 ne $VERSION) {
					$self->error("incorrect database version");
					return(1);
				} else {
					next;
				}
			} else {
				$self->error("missing database version at line $lineCount");
				return(1);
			}
		}
		

		if (index($line, ":") != -1 ) {
			$count++;
			
			# extract the title-idx-id and the film-title
			#  0000002:army%20of%20darkness%20%281992%29	Army of Darkness (1992)	1992	movie	0000002
			#
			my ($midxid, $mhashkey, $mtitle) = $line =~ m/^(\d*):(.*?)\t+(.*?)\t/;

			if ($midxid && $mtitle) {
				$self->{titleshash}{$mtitle} = int($midxid);	# build the hash
				
				$maxidxid = $midxid if ( $midxid > $maxidxid );
			}
			
			$self->updateProgressBar('', $lineCount);
		}
		else {
			$self->error("$lineCount: unrecognized format (missing tab)");
			$self->updateProgressBar('', $lineCount);
		}
	}
	
	$self->endProgressBar();
	
	$self->status(sprintf("found ".withThousands($count)." titles in ".
			  withThousands($lineCount-1)." lines in %d seconds",time()-$startTime));		# drop 1 for the "version" line

	close(IN);

	#-----------------------------------------------------------
	return($count, $maxidxid);
}	

sub dedupe($$$)
{
	# basic deduping of data entries
	
	my ($self, $data, $sep)=@_;

	my @outarr;
	my @arr = split( ($sep eq '|' ? '\|' : $sep) , $$data);
	my %out;
	
	foreach my $v (@arr) {
		my ($a, $b) = $v =~ m/^(\d*):?(.*)\s*$/;
		if (!defined $out{$b}) {
			push @outarr, $v;
			$out{$b} = $v;
		}
	}
	
	$$data = join($sep, @outarr);
	return;
}

sub stripbilling($$$)
{
	# strip the billing from the names
	# also strip the "(I)" etc suffix from names
	
	my ($self, $data, $sep)=@_;

	my @outarr;
	my @arr = split( ($sep eq '|' ? '\|' : $sep) , $$data);
	
	foreach my $v (@arr) {
		my ($a, $b) = $v =~ m/^(\d*):?(.*)\s*$/;
		$b=~s/\s\([IVXL]+\)\[/\[/o;
		$b=~s/\s\([IVXL]+\)$//o;
		push @outarr, $b;
	}
	
	$$data = join($sep, @outarr);
	return;
}

sub sortnames($$$)
{
	# basic sorting of names
	
	my ($self, $data, $sep)=@_;
	
	my @arr = split( ($sep eq '|' ? '\|' : $sep) , $$data);

	$$data = join($sep, sort(@arr) );
	return;
}

sub stripprogtype($$)
{
	# strip the (TV) or (V) or (VG) suffix from title
	
	my ($self, $data)=@_;
	
	my ($midx, $mtitle, $mrest) = $$data =~ m/^(.*?)\t(.*?)\t(.*)$/;
	
	$mtitle =~ s/\s(\((TV|V|VG)\))//;
	
	$$data = $midx ."\t". $mtitle ."\t". $mrest;
	return;
}

sub readfilesbyidxid($$$$)
{
	# read lines from the data files 2..8 looking for matches on a passed idxid
	#  (don't use this for stage1 data - use a call to readdatafile to simply get the next record
	
	my ($self, $fhs, $fdat, $idxid)=@_;

	while (my ($stage, $fh) = each ( %$fhs )) {

		$fdat->{$stage} =  { k=>0, v=>'' } if !defined $fdat->{$stage}{k};
		
		if ($fdat->{$stage}{k} < $idxid) {
			#print STDERR "fetching from $stage   ".$fdat->{$stage}{k}."    < $idxid   \n";
			
			my ($fstage, $fidxid, $fdata) = $self->readdatafile( $fhs->{$stage}, $stage, $idxid, -1);
			
			if ($self->{usefilesort}) {
				# if we are using filesort then there will be multiple records with the same idxid
				#  we need to fetch all of these and combine them
				my $_fidxid = $fidxid;
				while ( $_fidxid == $fidxid && $_fidxid != 9999999 ) {
					# read next record 
					(my $_fstage, $_fidxid, my $_fdata) = $self->readdatafile( $fhs->{$stage}, $stage, $idxid, $_fidxid );
					if ($_fidxid == $fidxid) {
						$fdata .= '|' . $_fdata;
					}
				}

				# need to dedupe our merged data
				($fstage, $fidxid, $fdata) = $self->tidydatafile( $fstage, $fidxid, $fdata );
			
			}
			
			# store the file record
			$fdat->{$stage} = { k=>$fidxid, v=>$fdata };
		}
	}
	
	
	# here's a fudge: we need to merge the actors (stage 3) and actresses (stage 4) together
		my @pnames;
		push ( @pnames, $fdat->{3}{v} )  if ( $fdat->{3}{k} == $idxid );
		push ( @pnames, $fdat->{4}{v} )  if ( $fdat->{4}{k} == $idxid );
		
		if (scalar @pnames) {
			# join the two data values, sort, strip...
			my $pnames = join('|', @pnames);

			$self->sortnames(\$pnames, '|');		# sorts by "billing:name"
			$self->stripbilling(\$pnames, '|');		# strip "billing:" and "(I)" on name
			
			### ...and then store in one of the actors/actresses value while nulling the other
			if ( $fdat->{3}{k} == $idxid ) {
				$fdat->{3}{v} = $pnames;
				$fdat->{4}{v} = ':::'  if ( $fdat->{4}{k} == $idxid );
			}
			elsif ( $fdat->{4}{k} == $idxid ) {
				$fdat->{4}{v} = $pnames;
				$fdat->{3}{v} = ':::'  if ( $fdat->{3}{k} == $idxid );
			}
		}
	# end fudge

	return;
}
	
sub readdatafile($$$$$)
{
	my ($self, $fh, $stage, $idxid, $lidxid)=@_;

	# read a line from a file

	my $line;
		
	# if we have a parked record then use that one
	if ( defined $self->{datafile}{$stage} ) {
		$line = $self->{datafile}{$stage};
		undef $self->{datafile}{$stage};
			
	} else {
		if ( eof($fh) ) {
			return ($stage, 9999999, '');		
		}
		defined( $line = readline $fh ) or die "readline failed on file for stage $stage : $!";
	}
	
	# extract the idxid from the start of each line
	#  0000002:army%20of%20darkness%20%281992%29	Army of Darkness (1992)	1992	movie	0000002
	my ($midxid, $mdata) = $line =~ m/^(\d*):(.*)$/;
	 
	if ($midxid) {

		# there should not be any records in datafile n which are not in datafile 1
		if ( $midxid < $idxid ) {
			$self->error("unexpected record in stage $stage data file at $midxid (expected $idxid)");
		}
		else {
			# processing on the data for each interim file
			($stage, $midxid, $mdata) = $self->tidydatafile( $stage, $midxid, $mdata );
		}
		
		# if the incoming idxid has changed then park the record
		if ( $lidxid != -1 && $midxid != $lidxid ) {
			$self->{datafile}{$stage} = $line;
		}

	}
	
	return ($stage, $midxid, $mdata);
}

sub tidydatafile($$$$)
{
	my ($self, $stage, $midxid, $mdata)=@_;

	# tidy/reformat the data from a stagex.data file
	
	if ($midxid) {

		# processing on the data for each interim file

		# movies #1 : strip the (TV) (V) markers from the movie title
		# directors #2 : (i) dedupe (ii) sort into name order (not correct but there's no sequencing in the imdb data)
		# actors/actresses #3,#4 : (i) dedeupe (ii) sort into billing order (iii) strip billing id   Note: need to merge actors and actresses
		# genres #5 : (i) dedupe
		# ratings #6 : (i) split elements and separate by tabs
		# keywords #7 : (i) dedupe, (ii) replace separator with comma
		# plots #8 : 
		#
		if ($stage == 1) {
			$self->stripprogtype(\$mdata);
			
		} elsif ($stage == 2) {
			$self->dedupe(\$mdata, '|');
			$self->stripbilling(\$mdata, '|');
			$self->sortnames(\$mdata, '|');		# sorts by "lastname, firstname"
			
		} elsif ($stage == 3 || $stage == 4) {
			$self->dedupe(\$mdata, '|');
			# defer sorting and strip billing deferred until after we have joined actors + actresses
			## $self->sortnames(\$mdata, '|');		# sorts by "billing:name"
			## $self->stripbilling(\$mdata, '|'); 
			
		} elsif ($stage == 5) {
			$self->dedupe(\$mdata, '|');
			
		} elsif ($stage == 6) {
			$mdata =~ s/;/\t/g;		# replace ";" separator with tabs
			
		} elsif ($stage == 7) {
			$self->dedupe(\$mdata, '|');
			$mdata =~ s/\|/,/g;
			
		} elsif ($stage == 8) {
			# noop
		}
		
	}
	
	return ($stage, $midxid, $mdata);
}

sub invokeStage($$)
{
	my ($self, $stage)=@_;

	my $startTime=time();

	#----------------------------------------------------------------------------
	if ( $stage == 1 ) {

		$self->status("parsing Movies list for stage $stage ...");
		my $countEstimate=$self->dbinfoCalcEstimate("movies", 45);

		# if we are using --filesort then write output file direct (and not use a hash)
		if ($self->{usefilesort}) {
			open($self->{fhdata}, ">", "$self->{imdbDir}/stage$stage.data.tmp") || die "$self->{imdbDir}/stage$stage.data.tmp:$!";
		}
			
		my ($num, $numout) = $self->readMovies("Movies", $countEstimate, "$self->{imdbListFiles}->{movies}",  $stage);
		
		if ($self->{usefilesort}) {
			close($self->{fhdata});
		}

		if ( $num < 0 ) {
			if ( $num == -2 ) {
				$self->error("you need to download $self->{imdbListFiles}->{movies} from the ftp site, or use the --download option");
			}
			return(1);
		}
		elsif ( abs($num - $countEstimate) > $countEstimate*.10 ) {
			my $better=$self->dbinfoCalcBytesPerEntry("movies", $num);
			##not accurate: $self->status("ARG estimate of $countEstimate for movies needs updating, found $num ($better bytes/entry)");
		}
		$self->dbinfoAdd("db_stat_movie_count", "$numout");
		
		#use Data::Dumper;print STDERR Dumper($self->{movieshash});
		#use Data::Dumper;my $_h="stage${stage}hash";print STDERR Dumper( $self->{$_h} );
		
		
		#-----------------------------------------------------------
		# sort the title keys and write the stage1.data file
		#
		# if we are using --filesort then write output file direct (and not use a hash)
		if ($self->{usefilesort}) {

			$self->beginProgressBar("writing stage $stage data", $self->dbinfoGet("db_stat_movie_count", 0) );
			
			# movies are in an interim file (stage1.data.tmp). 
			#	We need to 	(1) sort the file, 
			#				(2) translate to stage1.data (adding the idxid)
			#				(3) store in %titleshash
			my $res;
			
			# (1) sort the file in situ
			$res = $self->sortfile($stage, "$self->{imdbDir}/stage$stage.data.tmp");
			# if (!$res) { do something? }
			
			# (2) & (3) read the sorted file and create out stage1.data while building titleshash hash
			undef $self->{titleshash};
			
			open(IN, "< $self->{imdbDir}/stage$stage.data.tmp") || die "$self->{imdbDir}/stage$stage.data.tmp:$!";
			open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
			print OUT '0000000:version '.$VERSION."\n";
			
			my $count=0; 
			while(<IN>) {
				my $line=$_;

				$count++;
				my $idxid=sprintf("%07d", $count);

				my ($k, $k2, $v2) = $line =~ m/^(.*?)\t(.*?)\t(.*?)$/;

				# the following equates to
				#	print OUT $idxid.":".$dbkey."\t".$title."\t".$year."\t".$qualifier."\t".$lineno."\n";
				print OUT $idxid.':'.$k."\t".$k2."\t".$v2."\t".$idxid."\n";
				
				#  and create a shared hash of $title=>$lineno (i.e. IDX 'id')
				$self->{titleshash}{$k2} = $count;	# store the idx id for this title
		
				
				$self->updateProgressBar('', $count);
			}
			$self->endProgressBar();	
			
			$self->{maxid} = $count;		# remember the largest values of title id (for loop stop)
			
			close(OUT);
			close(IN);
			
			unlink "$self->{imdbDir}/stage$stage.data.tmp";
			
			
		} else {
			
			# movies data are in a hash (%movieshash) to we need to write that to disc (stage1.data)
			
			$self->beginProgressBar("writing stage $stage data", $num);
			
			open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
			print OUT '0000000:version '.$VERSION."\n";
			
			my $count=0;
			foreach my $k (sort keys( %{$self->{movieshash}} )) {
				
				while ( my ($k2, $v2) = each %{$self->{movieshash}{$k}} ) {	# movieshash is a hash of hashes
					
					$count++;
					my $idxid=sprintf("%07d", $count);
						
					# the following equates to
					#	print OUT $idxid.":".$dbkey."\t".$title."\t".$year."\t".$qualifier."\t".$lineno."\n";
					print OUT $idxid.':'.$k."\t".$k2."\t".$v2."\t".$idxid."\n";
					
					#  and create a shared hash of $title=>$lineno (i.e. IDX 'id')
					$self->{titleshash}{$k2} = $count;	# store the int version of the id for this title
														#  (note multiple titles may have the same hashkey)
				}
				
				delete( $self->{movieshash}{$k} );
				
				$self->updateProgressBar('', $count);
			}
				
			$self->endProgressBar();	
			
			$self->{maxid} = $count;		# remember the largest values of title id (for loop stop)
					
			close(OUT);
		}
		
		#use Data::Dumper;print STDERR Dumper( $self->{titleshash} );die;
		
	}
	
	
	#----------------------------------------------------------------------------
	elsif ( $stage >= 2 && $stage < $self->{stageLast} ) {
		
		# these stages need the hash of film-title=>idxid
		#   if we have come from stage 1 (i.e. "prep-stage=all" then we will have that from stage=1
		#	otherwise we will need to build *.e.g "prep-stage=2"
		#
		if (!defined( $self->{titleshash} ) ) {
			my $countEstimate 	= $self->dbinfoGet("db_stat_movie_count", 0);
			my ($titlecount, $maxid) = $self->gettitleshash($countEstimate);
			if ($titlecount == -1) { 
				$self->error('could not make title list - quitting');
				return(1);
			}
			$self->{maxid} = $maxid;	# remember the largest values of title id (for loop stop)
			#use Data::Dumper;print STDERR Dumper( $self->{titleshash} );
		}
		
		# nb: {stages} = { 1=>'movies', 2=>'directors', 3=>'actors', 4=>'actresses', 5=>'genres', 6=>'ratings', 7=>'keywords', 8=>'plot' };
		my $stagename 		= $self->{stages}{$stage};
		my $stagenametext 	= ucfirst $self->{stages}{$stage};

		$self->status("parsing $stagenametext list for stage $stage ...");
		
		# skip optional stages
		if ( ( !defined $self->{imdbListFiles}->{$stagename} ) && ( defined $self->{optionalStages}->{$stagename} ) ) {
			return(0);
		}
		
		# approx average record length for each incoming data file (used to guesstimate number of records in file)
		my %countestimates = ( 1=>'45', 2=> '40', 3=> '55', 4=> '55', 5=> '35', 6=> '65', 7=> '20', 8=> '50' );
		my $countEstimate = $self->dbinfoCalcEstimate($stagename, $countestimates{$stage});

		my %stagefunctions = ( 	1=>\&readMovies,  			2=>\&readCastOrDirectors,
								3=>\&readCastOrDirectors,  	4=>\&readCastOrDirectors,
								5=>\&readGenres,			6=>\&readRatings,
								7=>\&readKeywords,			8=>\&readPlots
							 );

	
		# if we are using --filesort then write output file direct (and not use a hash)
		if ($self->{usefilesort}) {
			open($self->{fhdata}, ">", "$self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
			print {$self->{fhdata}} '0000000:version '.$VERSION."\n";
		}
	
		my $num=$stagefunctions{$stage}->($self, $stagenametext, $countEstimate, "$self->{imdbListFiles}->{$stagename}",  $stage);
	
		if ($self->{usefilesort}) {
			close($self->{fhdata});
		}

		if ( $num < 0 ) {
			if ( $num == -2 ) {
				$self->error("you need to download $self->{imdbListFiles}->{$stagename} from the ftp site, or use the --download option");
			}
			return(1);
		}
		elsif ( $num > 0 && abs($num - $countEstimate) > $countEstimate*.10 ) {
			my $better=$self->dbinfoCalcBytesPerEntry($stagename, $num);
			$self->status("ARG estimate of $countEstimate for $stagename needs updating, found $num ($better bytes/entry)");
		}
		$self->dbinfoAdd("db_stat_${stagename}_count", "$num");
		
	
	
		#-----------------------------------------------------------
		# print the title keys in IDX id order : write the stagex.data file
		#
		if ($self->{usefilesort}) {
			
			# file already written : just needs sorting (in situ)
			my $f="$self->{imdbDir}/stage$stage.data";
			my $res = $self->sortfile($stage, $f);
			# todo: check the reply?
			
		} else {
			#use Data::Dumper;my $_h="stage${stage}hash";print STDERR Dumper( $self->{$_h} );
			
			# write the stage.data file from the memory hash 
			
			$self->beginProgressBar("writing stage $stage data", $num);
			
			open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
			print OUT '0000000:version '.$VERSION."\n";
			
			# don't sort the hash keys - that will just cost memory. Just pull them out in numerical order.
			my $h = "stage${stage}hash";
			#	
			# read the stage data hash in idxid order
			for (my $i = 0; $i <= $self->{maxid}; $i++){
			
				# write the extracted imdb data to a temporary file, preceeded by the IDX id for each record
				my $k = sprintf("%07d", $i);

				if ( $self->{$h}{$i} ) {
					my $v = $self->{$h}{$i};
					delete ( $self->{$h}{$i} );
					#
					print OUT $k.':'.$v."\n";
				}
					
				$self->updateProgressBar('', $i);
			}
				
			$self->endProgressBar();	
					
			close(OUT);
			
			#use Data::Dumper;print STDERR "leftovers: $stage ".Dumper( $self->{$h} )."\n";
			
			delete ( $self->{$h} );
		}
		
		#use Data::Dumper;print STDERR Dumper( $self->{titleshash} );
	}
	
	
	#----------------------------------------------------------------------------
	elsif ( $stage == $self->{stageLast} ) {
		
		# delete existing IDX; trim stage1.data to IDX; merge stage 2-8.data into DAT
		
		# free up some memory
		undef $self->{titleshash};
		
		my $tab=sprintf("\t");

		$self->status("indexing all previous stage's data for stage ".$self->{stageLast}."...");
		
		
		#----------------------------------------------------------------------
		# read all the parsed data files created in stages 1-8 and merges them
		# read one record at a time from each file!
		
		my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
		
		$self->beginProgressBar('writing database', $countEstimate);

		open(IDX, "> $self->{moviedbIndex}") || die "$self->{moviedbIndex}:$!";
		open(DAT, "> $self->{moviedbData}") || die "$self->{moviedbData}:$!";
		
		my $i;
		my %fh;
		for $i (1..($self->{stageLast}-1)) {
			# skip optional files if they don't exist
			if ( ($i == 7 &&  !( -f "$self->{imdbDir}/stage7.data" ))
			 ||  ($i == 8 &&  !( -f "$self->{imdbDir}/stage8.data" )) ) {
				 next;
			 }
			# 
			open($fh{$i}, "< $self->{imdbDir}/stage$i.data") || die "$self->{imdbDir}/stage$i.data:$!";
		 }
			
		# check the file version numbers
		while (my ($k, $v) = each (%fh)) {
			$_ = readline $v;
			if ( m/^0000000:version ([\d\.]*)$/ ) {
				if ($1 ne $VERSION) {
					$self->error("incorrect database version in stage $k file");
					return(1);
				} else {
					next;
				}
			} else {
				$self->error("missing database version in stage $k file");
				return(1);
			}
		}
				
				
		#----------------------------------------------------------------------
		my %fdat;
		
		my $count=0;
		my $go=1;
		while ($go) {	

			last if ( eof($fh{1}) );	# I suppose we ought to check if there any recs remaining in the other files (todo)
	
			# read a movie record
			my ($fstage, $fidxid, $fdata) = $self->readdatafile($fh{1}, 1, -1, -1);

			$fdat{$fstage} = { k=>$fidxid, v=>$fdata };
			
			if ($fidxid) {
				$count++;

				# get matching records from other data files
				$self->readfilesbyidxid(\%fh, \%fdat, $fidxid);
 			
				# merge data from other records
				my $mdata = $fidxid.':';
	
				for $i (2..($self->{stageLast}-1)) {
					
					# we can join actors and actresses - only 1 of them will have data now
					next if ( $fdat{$i}{k} == $fidxid  &&  $fdat{$i}{v} eq ':::' );
					# only output either actors or actresses but not both (otherwise we'll get an extra marker in the output
					next if ($i == 3) &&  ( $fdat{3}{k} != $fidxid );
					next if ($i == 4) &&  ( $fdat{4}{k} != $fidxid ) && ( $fdat{3}{k} == $fidxid );		# don't output marker if we've just done it for actors
					# drop through if actresses (#4) and no actors (#3) for this film
					
					
					if ( $fdat{$i}{k} == $fidxid ) {
						$mdata .= $fdat{$i}{v};
					}
					else {
						# don't data for this stage ($i) so just print the 'empty' marker
						$mdata .= '<>';
						if ($i == 6) { $mdata .= "\t".'<>'."\t".'<>'; }  # fudge to add extra spacers in ratings data
					}
					
					$mdata .= "\t" unless $i == ($self->{stageLast}-1);
				}
				
				#print STDERR "mdata ".$mdata."\n";
			
				# write the DAT record
				print DAT $mdata ."\n";
				
				# write the IDX record				
				print IDX $fdata ."\n";
			}


			$self->updateProgressBar('', $count);
		}
		
		$self->endProgressBar();
		
		$self->status(sprintf("wrote ".withThousands($count)." titles in %d seconds",time()-$startTime));

		close(IDX);
		close(IN);
		while (my ($k, $v) = each (%fh)) {
			close($v);
		}
	


		# ---------------------------------------------------------------------------------------
		
		$self->dbinfoAdd("db_version", $XMLTV::IMDB::VERSION);

		if ( $self->dbinfoSave() ) {
			$self->error("$self->{moviedbInfo}:$!");
			return(1);
		}

		$self->status("running quick sanity check on database indexes...");
		my $imdb=new XMLTV::IMDB('imdbDir' => $self->{imdbDir},
					 'verbose' => $self->{verbose});

		if ( -e "$self->{moviedbOffline}" ) {
			unlink("$self->{moviedbOffline}");
		}

		if ( my $errline=$imdb->sanityCheckDatabase() ) {
			open(OFF, "> $self->{moviedbOffline}") || die "$self->{moviedbOffline}:$!";
			print OFF $errline."\n";
			print OFF "one of the prep stages' must have produced corrupt data\n";
			print OFF "report the following details to xmltv-devel\@lists.sf.net\n";

			my $info=XMLTV::IMDB::loadDBInfo($self->{moviedbInfo});
			if ( ref $info eq 'SCALAR' ) {
				print OFF "\tdbinfo file corrupt\n";
				print OFF "\t$info";
			}
			else {
				for my $key (sort keys %{$info}) {
					print OFF "\t$key:$info->{$key}\n";
				}
			}
			print OFF "database taken offline\n";
			close(OFF);
			open(OFF, "< $self->{moviedbOffline}") || die "$self->{moviedbOffline}:$!";
			while(<OFF>) {
				chop();
				$self->error($_);
			}
			close(OFF);
			return(1);
		}
		$self->status("sanity intact :)");
	}
	else {
		$self->error("tv_imdb: invalid stage $stage: only 1-".$self->{stageLast}." are valid");
		return(1);
	}

	$self->dbinfoAdd("seconds_to_complete_prep_stage_$stage", (time()-$startTime));
	if ( $self->dbinfoSave() ) {
		$self->error("$self->{moviedbInfo}:$!");
		return(1);
	}
	return(0);
}

sub crunchStage($$)
{
	my ($self, $stage)=@_;

	if ( $stage == $self->{stageLast} ) {
		 # check all the pre-requisite stages have been run
		for (my $st=1 ; $st < $self->{stageLast}; $st++ ) {
			if ( !$self->stageComplete($st) ) {
				#$self->error("prep stages must be run in sequence..");
				$self->error("prepStage $st either has never been run or failed");
				if ( grep { $_ == $st } values %{$self->{optionalStages}} ) {
					$self->error("data for this stage will NOT be added");			####### todo: unless flag present
				} else {
					$self->error("rerun tv_imdb with --prepStage=$st");
					return(1);
				}
			}
		}
	}

	if ( -f "$self->{moviedbInfo}" && $stage != 1 ) {
		my $ret=$self->dbinfoLoad();
		if ( $ret ) {
			$self->error($ret);
			return(1);
		}
	}

	# open stage logfile and run the requested stage
	$self->redirect("$self->{imdbDir}/stage$stage.log") || return(1);
	my $ret=$self->invokeStage($stage);
	$self->redirect(undef);

	if ( $ret == 0 ) {
		if ( $self->{errorCountInLog} == 0 ) {
			$self->status("prep stage $stage succeeded with no errors");
		}
		else {
			$self->status("prep stage $stage succeeded with $self->{errorCountInLog} errors in $self->{imdbDir}/stage$stage.log");			
			if ( $stage == $self->{stageLast} && $self->{errorCountInLog} > 30 && $self->{errorCountInLog} < 80 ) {
				$self->status("this stage commonly produces around 60 (or so) warnings because of imdb");
				$self->status("list file inconsistancies, they can usually be safely ignored");
			}
		}
	}
	else {
		if ( $self->{errorCountInLog} == 0 ) {
			$self->status("prep stage $stage failed (with no logged errors)");
		}
		else {
			$self->status("prep stage $stage failed with $self->{errorCountInLog} errors in $self->{imdbDir}/stage$stage.log");
		}
	}
	return($ret);
}

1;
