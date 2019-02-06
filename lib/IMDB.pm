# The IMDB file contains two packages:
# 1. XMLTV::IMDB::Cruncher package which parses and manages IMDB "lists" files
#    from ftp.imdb.com
# 2. XMLTV::IMDB package that uses data files from the Cruncher package to
#    update/add details to XMLTV programme nodes.
#
# FUTURE - multiple hits on the same 'title only' could try and look for
#          character names matching from description to imdb.com character
#          names.
#
# FUTURE - multiple hits on 'title only' should probably pick latest
#          tv series over any older ones. May make for better guesses.
#
# BUG - we identify 'presenters' by the word "Host" appearing in the character
#       description. For some movies, character names include the word Host.
#       ex. Animal, The (2001) has a character named "Badger Milk Host".
#
# BUG - if there is a matching title with > 1 entry (say made for tv-movie and
#       at tv-mini series) made in the same year (or even "close" years) it is
#       possible for us to pick the wrong one we should pick the one with the
#       closest year, not just the first closest match based on the result ordering
#       for instance Ghost Busters was made in 1984, and into a tv series in
#       1986. if we have a list of GhostBusters 1983, we should pick the 1984 movie
#       and not 1986 tv series...maybe :) but currently we'll pick the first
#       returned close enough match instead of trying the closest date match of
#       the approx hits.
#

use strict;

package XMLTV::IMDB;

use open ':encoding(iso-8859-1)';   # try to enforce file encoding (does this work in Perl <5.8.1? )

#
# HISTORY
# .6 = what was here for the longest time
# .7 = fixed file size est calculations
#    = moviedb.info now includes _file_size_uncompressed values for each downloaded file
# .8 = updated file size est calculations
#    = moviedb.dat directors and actors list no longer include repeated names (which mostly
#      occured in episodic tv programs (reported by Alexy Khrabrov)
# .9 = added keywords data
# .10 = added plot data
#
our $VERSION = '0.10';      # version number of database

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes

    for ('imdbDir', 'verbose') {
	die "invalid usage - no $_" if ( !defined($self->{$_}));
    }
    #$self->{verbose}=2;
    $self->{replaceDates}=0        if ( !defined($self->{replaceDates}));
    $self->{replaceTitles}=0       if ( !defined($self->{replaceTitles}));
    $self->{replaceCategories}=0   if ( !defined($self->{replaceCategories}));
    $self->{replaceKeywords}=0     if ( !defined($self->{replaceKeywords}));
    $self->{replaceURLs}=0         if ( !defined($self->{replaceURLs}));
    $self->{replaceDirectors}=1    if ( !defined($self->{replaceDirectors}));
    $self->{replaceActors}=0       if ( !defined($self->{replaceActors}));
    $self->{replacePresentors}=1   if ( !defined($self->{replacePresentors}));
    $self->{replaceCommentators}=1 if ( !defined($self->{replaceCommentators}));
    $self->{replaceStarRatings}=0  if ( !defined($self->{replaceStarRatings}));
    $self->{replacePlot}=0         if ( !defined($self->{replacePlot}));

    $self->{updateDates}=1        if ( !defined($self->{updateDates}));
    $self->{updateTitles}=1       if ( !defined($self->{updateTitles}));
    $self->{updateCategories}=1   if ( !defined($self->{updateCategories}));
    $self->{updateCategoriesWithGenres}=1 if ( !defined($self->{updateCategoriesWithGenres}));
    $self->{updateKeywords}=0     if ( !defined($self->{updateKeywords}));          # default is to NOT add keywords
    $self->{updateURLs}=1         if ( !defined($self->{updateURLs}));
    $self->{updateDirectors}=1    if ( !defined($self->{updateDirectors}));
    $self->{updateActors}=1       if ( !defined($self->{updateActors}));
    $self->{updatePresentors}=1   if ( !defined($self->{updatePresentors}));
    $self->{updateCommentators}=1 if ( !defined($self->{updateCommentators}));
    $self->{updateStarRatings}=1  if ( !defined($self->{updateStarRatings}));
    $self->{updatePlot}=0         if ( !defined($self->{updatePlot}));          # default is to NOT add plot

    $self->{numActors}=3          if ( !defined($self->{numActors}));           # default is to add top 3 actors

    $self->{moviedbIndex}="$self->{imdbDir}/moviedb.idx";
    $self->{moviedbData}="$self->{imdbDir}/moviedb.dat";
    $self->{moviedbInfo}="$self->{imdbDir}/moviedb.info";
    $self->{moviedbOffline}="$self->{imdbDir}/moviedb.offline";

    # default is not to cache lookups
    $self->{cacheLookups}=0 if ( !defined($self->{cacheLookups}) );
    $self->{cacheLookupSize}=0 if ( !defined($self->{cacheLookupSize}) );

    $self->{cachedLookups}->{tv_series}->{_cacheSize_}=0;

    bless($self, $type);

    $self->{categories}={'movie'          =>'Movie',
			 'tv_movie'       =>'TV Movie', # made for tv
			 'video_movie'    =>'Video Movie', # went straight to video or was made for it
			 'tv_series'      =>'TV Series',
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
	chop();
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

    # check that the imdbdir is invalid and up and running
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

use Search::Dict;

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

# moviedbIndex file has the format:
# title:lineno
# where key is a url encoded title followed by the year of production and a colon
sub getMovieMatches($$$)
{
    my $self=shift;
    my $title=shift;
    my $year=shift;

    # Articles are put at the end of a title ( in all languages )
    #$match=~s/^(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)\s+(.*)$/$2, $1/og;

    my $match="$title";
    if ( defined($year) ) {
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

	chop();
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
	    elsif ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\/[IVX]+\)$//o ) {
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
	    elsif ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\/[IVX]+\)$//o ) {
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

    return(undef) if ( !defined($res) );
    if ( !defined($res->{exactMatch}) ) {
	return(undef);
    }
    if ( scalar(@{$res->{exactMatch}}) != 1 ) {
	return(undef);
    }
    return($res->{exactMatch}[0]);
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
	chop();
	if ( s/^$id:// ) {
	    my ($directors, $actors, $genres, $ratingDist, $ratingVotes, $ratingRank, $keywords, $plot)=split('\t', $_);
	    if ( $directors ne "<>" ) {
		for my $name (split('\|', $directors)) {
		    # remove (I) etc from imdb.com names (kept in place for reference)
		    $name=~s/\s\([IVX]+\)$//o;
		    # switch name around to be surname last
		    $name=~s/^([^,]+),\s*(.*)$/$2 $1/o;
		    push(@{$results->{directors}}, $name);
		}
	    }
	    if ( $actors ne "<>" ) {
		for my $name (split('\|', $actors)) {
		    # remove (I) etc from imdb.com names (kept in place for reference)
		    my $HostNarrator;
		    if ( $name=~s/\[([^\]]+)\]$//o ) {
			$HostNarrator=$1;
		    }
		    $name=~s/\s\([IVX]+\)$//o;

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
	    $results->{ratingDist}=$ratingDist if ( $ratingDist ne "<>" );
	    $results->{ratingVotes}=$ratingVotes if ( $ratingVotes ne "<>" );
	    $results->{ratingRank}=$ratingRank if ( $ratingRank ne "<>" );
	    $results->{plot}=$plot if ( $plot ne "<>" );
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
#          punctuation:
#       "Run Silent, Run Deep" for imdb's "Run Silent Run Deep"
#       "Cherry, Harry and Raquel" for imdb's "Cherry, Harry and Raquel!"
#       "Cat Women of the Moon" for imdb's "Cat-Women of the Moon"
#       "Baywatch Hawaiian Wedding" for imdb's "Baywatch: Hawaiian Wedding" :)
#
# FIXED - "Victoria and Albert" appears for imdb's "Victoria & Albert" (and -> &)
# FIXED - "Columbo Cries Wolf" appears instead of "Columbo:Columbo Cries Wolf"
# FIXED - Place the article last, for multiple languages. For instance
#         Los amantes del círculo polar -> amantes del círculo polar, Los
# FIXED - common international vowel changes. For instance
#          "Anna Karénin" (é->e)
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
	    my $info=$self->getMovieExactMatch($mytitle, $year);
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
	    $self->debug("no exact title/year hit on \"$mytitle ($year)\"");
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
#        credits:presenter and credits:commentator resp.
# todo - check program length - probably a warning if longer ?
#        can we update length (separate from runnning time in the output ?)
# todo - icon - url from www.imdb.com of programme image ?
#        this could be done by scraping for the hyper linked poster
#        <a name="poster"><img src="http://ia.imdb.com/media/imdb/01/I/60/69/80m.jpg" height="139" width="99" border="0"></a>
#        and grabbin' out the img entry. (BTW ..../npa.jpg seems to line up with no poster available)
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

	$url=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;
	$url="http://us.imdb.com/M/title-exact?".$url;

	if ( defined($prog->{url}) ) {
	    my @rep;
	    push(@rep, $url);
	    for (@{$prog->{url}}) {
		# skip urls for imdb.com that we're probably safe to replace
		if ( !m;^http://us.imdb.com/M/title-exact;o ) {
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
	my $id=$self->findMovieInfo($title, $prog->{date}, 1); # exact match
	if ( !defined($id) ) {
	    $id=$self->findTVSeriesInfo($title);
	    if ( !defined($id) ) {
		$id=$self->findMovieInfo($title, $prog->{date}, 0); # close match
	    }
	}
	if ( defined($id) ) {
	    $self->{stats}->{$id->{matchLevel}."Matches"}++;
	    $self->{stats}->{$id->{matchLevel}}->{$id->{qualifier}}++;
	    return($self->applyFound($prog, $id));
	}
	$self->status("failed to find a match for movie \"$title ($prog->{date})\"");
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
	    my $id=$self->findMovieInfo($title, undef, 2); # any title match
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
#        separate out from what was added or updated
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

use open ':encoding(iso-8859-1)';   # try to enforce file encoding (does this work in Perl <5.8.1? )

# Use Term::ProgressBar if installed.
use constant Have_bar => eval {
    require Term::ProgressBar;
    $Term::ProgressBar::VERSION >= 2;
};

#
# This package parses and manages to index imdb plain text files from
# ftp.imdb.com/interfaces. (see http://www.imdb.com/interfaces for
# details)
#
# I might, given time build a download manager that:
#    - downloads the latest plain text files
#    - understands how to download each week's diffs and apply them
# Currently, the 'downloadMissingFiles' flag in the hash of attributes
# passed triggers a simple-minded downloader.
#
# I may also roll this project into a xmltv-free imdb-specific
# perl interface that just supports callbacks and understands more of
# the imdb file formats.
#

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes
    for ($self->{downloadMissingFiles}) {
	$_=0 if not defined; # default
    }

    for ('imdbDir', 'verbose') {
	die "invalid usage - no $_" if ( !defined($self->{$_}));
    }

    $self->{stageLast} = 9;     # set the final stage in the build - i.e. the one which builds the final database
    $self->{stages} = { 1=>'movies', 2=>'directors', 3=>'actors', 4=>'actresses', 5=>'genres', 6=>'ratings', 7=>'keywords', 8=>'plot' };
    $self->{optionalStages} = { 'keywords' => 7, 'plot' => 8 };     # list of optional stages - no need to download files for these

    $self->{moviedbIndex}="$self->{imdbDir}/moviedb.idx";
    $self->{moviedbData}="$self->{imdbDir}/moviedb.dat";
    $self->{moviedbInfo}="$self->{imdbDir}/moviedb.info";
    $self->{moviedbOffline}="$self->{imdbDir}/moviedb.offline";

    # only leave progress bar on if its available
    if ( !Have_bar ) {
	$self->{showProgressBar}=0;
    }

    bless($self, $type);

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
            if ( $self->{optionalStages}{$file} ) {
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
	print STDERR "tv_imdb: requires you to download the above files from ftp.imdb.com\n";
	print STDERR "         see http://www.imdb.com/interfaces for details\n";
        print STDERR "         or try the --download option\n";
	#return(undef);
        return 1;
    }

    return 0;
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

use XMLTV::Gunzip;
use IO::File;

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

sub readMoviesOrGenres($$$$)
{
    my ($self, $whichMoviesOrGenres, $countEstimate, $file)=@_;
    my $startTime=time();
    my $header;
    my $whatAreWeParsing;
    my $lineCount=0;

    if ( $whichMoviesOrGenres eq "Movies" ) {
	$header="MOVIES LIST";
	$whatAreWeParsing=1;
    }
    elsif ( $whichMoviesOrGenres eq "Genres" ) {
	$header="8: THE GENRES LIST";
	$whatAreWeParsing=2;
    }
    my $fh = openMaybeGunzip($file) || return(-2);
    while(<$fh>) {
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

    my $progress=Term::ProgressBar->new({name  => "parsing $whichMoviesOrGenres",
					 count => $countEstimate,
					 ETA   => 'linear'})
	if ( $self->{showProgressBar} );

    $progress->minor(0) if ($self->{showProgressBar});
    $progress->max_update_rate(1) if ($self->{showProgressBar});
    my $next_update=0;

    my $count=0;
    while(<$fh>) {
	$lineCount++;
	my $line=$_;
	#print "read line $lineCount:$line\n";

	# end is line consisting of only '-'
	last if ( $line=~m/^\-\-\-\-\-\-\-+/o );

	$line=~s/\n$//o;

	my $tab=index($line, "\t");
	if ( $tab != -1 ) {
	    my $mkey=substr($line, 0, $tab);

	    next if ($mkey=~m/\s*\{\{SUSPENDED\}\}/o);

	    if ( $whatAreWeParsing == 2 ) {
		# don't see what these are...?
		# ignore {{SUSPENDED}}
		$mkey=~s/\s*\{\{SUSPENDED\}\}//o;

		# ignore {Twelve Angry Men (1954)}
		$mkey=~s/\s*\{[^\}]+\}//go;

		# skip enties that have {} in them since they're tv episodes
		#next if ( $mkey=~s/\s*\{[^\}]+\}$//o );

		my $genre=substr($line, $tab);

		# genres sometimes has more than one tab
		$genre=~s/^\t+//og;
		if ( defined($self->{movies}{$mkey}) ) {
		    $self->{movies}{$mkey}.="|".$genre;
		}
		else {
		    $self->{movies}{$mkey}=$genre;
		    # returned count is number of unique titles found
		    $count++;
		}
	    }
	    else {
		push(@{$self->{movies}}, $mkey);
		# returned count is number of titles found
		$count++;
	    }

	    if ( $self->{showProgressBar} ) {
		# re-adjust target so progress bar doesn't seem too wonky
		if ( $count > $countEstimate ) {
		    $countEstimate = $progress->target($count+1000);
		    $next_update=$progress->update($count);
		}
		elsif ( $count > $next_update ) {
		    $next_update=$progress->update($count);
		}
	    }
	}
	else {
	    $self->error("$file:$lineCount: unrecognized format (missing tab)");
	    $next_update=$progress->update($count) if ($self->{showProgressBar});
	}
    }
    $progress->update($countEstimate) if ($self->{showProgressBar});

    $self->status(sprintf("parsing $whichMoviesOrGenres found ".withThousands($count)." titles in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

    closeMaybeGunzip($file, $fh);
    return($count);
}

sub readCastOrDirectors($$$)
{
    my ($self, $whichCastOrDirector, $castCountEstimate, $file)=@_;
    my $startTime=time();

    my $header;
    my $whatAreWeParsing;
    my $lineCount=0;

    if ( $whichCastOrDirector eq "Actors" ) {
	$header="THE ACTORS LIST";
	$whatAreWeParsing=1;
    }
    elsif ( $whichCastOrDirector eq "Actresses" ) {
	$header="THE ACTRESSES LIST";
	$whatAreWeParsing=2;
    }
    elsif ( $whichCastOrDirector eq "Directors" ) {
	$header="THE DIRECTORS LIST";
	$whatAreWeParsing=3;
    }
    else {
	die "why are we here ?";
    }

    my $fh = openMaybeGunzip($file) || return(-2);
    my $progress=Term::ProgressBar->new({name  => "parsing $whichCastOrDirector",
					 count => $castCountEstimate,
					 ETA   => 'linear'})
      if ($self->{showProgressBar});
    $progress->minor(0) if ($self->{showProgressBar});
    $progress->max_update_rate(1) if ($self->{showProgressBar});
    my $next_update=0;
    while(<$fh>) {
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

    my $cur_name;
    my $count=0;
    my $castNames=0;
    while(<$fh>) {
	$lineCount++;
	my $line=$_;
	$line=~s/\n$//o;
	#$self->status("read line $lineCount:$line");

	# end is line consisting of only '-'
	last if ( $line=~m/^\-\-\-\-\-\-\-+/o );

	next if ( length($line) == 0 );

	if ( $line=~s/^([^\t]+)\t+//o ) {
	    $cur_name=$1;
	    $castNames++;

	    if ( $self->{showProgressBar} ) {
		# re-adjust target so progress bar doesn't seem too wonky
		if ( $castNames > $castCountEstimate ) {
		    $castCountEstimate = $progress->target($castNames+100);
		    $next_update=$progress->update($castNames);
		}
		elsif ( $castNames > $next_update ) {
		    $next_update=$progress->update($castNames);
		}
	    }
	}

	my $billing;
	my $HostNarrator="";
	if ( $whatAreWeParsing < 3 ) {
	    # actors or actresses
	    $billing="9999";
	    if ( $line=~s/\s*<(\d+)>//o ) {
		$billing=sprintf("%04d", int($1));
	    }

	    if ( (my $start=index($line, " [")) != -1 ) {
		#my $end=rindex($line, "]");
		my $ex=substr($line, $start+1);

		if ( $ex=~s/Host//o ) {
		    if ( length($HostNarrator) ) {
			$HostNarrator.=",";
		    }
		    $HostNarrator.="Host";
		}
		if ( $ex=~s/Narrator//o ) {
		    if ( length($HostNarrator) ) {
			$HostNarrator.=",";
		    }
		    $HostNarrator.="Narrator";
		}
		$line=substr($line, 0, $start);
		# ignore character name
	    }
	}
	# try ignoring these
	next if ($line=~m/\s*\{\{SUSPENDED\}\}/o);

	# don't see what these are...?
	# ignore {{SUSPENDED}}
	$line=~s/\s*\{\{SUSPENDED\}\}//o;

  # [honir] this is wrong - this puts cast from all the episodes as though they are in the entire series!
	# ##ignore {Twelve Angry Men (1954)}
	$line=~s/\s*\{[^\}]+\}//o;

	if ( $whatAreWeParsing < 3 ) {
	    if ( $line=~s/\s*\(aka ([^\)]+)\).*$//o ) {
		# $attr=$1;
	    }
	}
	if ( $line=~s/  (\(.*)$//o ) {
	    # $attrs=$1;
	}
	$line=~s/^\s+//og;
	$line=~s/\s+$//og;

	if ( $whatAreWeParsing < 3 ) {
	    if ( $line=~s/\s+Narrator$//o ) {
		# ignore
	    }
	}

	my $val=$self->{movies}{$line};
	my $name=$cur_name;
	if ( length($HostNarrator) ) {
	    $name.="[$HostNarrator]";
	}
	if ( defined($billing) ) {
	    if ( defined($val) ) {
		$self->{movies}{$line}=$val."|$billing:$name";
	    }
	    else {
		$self->{movies}{$line}="$billing:$name";
	    }
	}
	else {
	    if ( defined($val) ) {
		$self->{movies}{$line}=$val."|$name";
	    }
	    else {
		$self->{movies}{$line}=$name;
	    }
	}
	$count++;
    }
    $progress->update($castCountEstimate) if ($self->{showProgressBar});

    $self->status(sprintf("parsing $whichCastOrDirector found ".withThousands($castNames)." names, ".
			  withThousands($count)." titles in ".withThousands($lineCount)." lines in %d seconds",time()-$startTime));

    closeMaybeGunzip($file, $fh);

    return($castNames);
}

sub readRatings($$$$)
{
    my ($self, $countEstimate, $file)=@_;
    my $startTime=time();
    my $lineCount=0;

    my $fh = openMaybeGunzip($file) || return(-2);
    while(<$fh>) {
	$lineCount++;
	if ( m/^MOVIE RATINGS REPORT/o ) {
	    if ( !($_=<$fh>) || !m/^\s*$/o) {
		$self->error("missing empty line after \"MOVIE RATINGS REPORT\" at line $lineCount");
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
	    $self->error("$file: stopping at line $lineCount, didn't see \"MOVIE RATINGS REPORT\" line");
	    closeMaybeGunzip($file, $fh);
	    return(-1);
	}
    }

    my $progress=Term::ProgressBar->new({name  => "parsing Ratings",
					 count => $countEstimate,
					 ETA   => 'linear'})
      if ($self->{showProgressBar});

    $progress->minor(0) if ($self->{showProgressBar});
    $progress->max_update_rate(1) if ($self->{showProgressBar});
    my $next_update=0;

    my $count=0;
    while(<$fh>) {
	$lineCount++;
	my $line=$_;
	#print "read line $lineCount:$line";

	$line=~s/\n$//o;

	# skip empty lines (only really appear right before last line ending with ----
	next if ( $line=~m/^\s*$/o );
	# end is line consisting of only '-'
	last if ( $line=~m/^\-\-\-\-\-\-\-+/o );

        # e.g. New  Distribution  Votes  Rank  Title
        #            0000000133  225568   8.9  12 Angry Men (1957)
	if ( $line=~s/^\s+([\.|\*|\d]+)\s+(\d+)\s+(\d+)\.(\d+)\s+//o ) {
	    $self->{movies}{$line}=[$1,$2,"$3.$4"];
	    $count++;
	    if ( $self->{showProgressBar} ) {
		# re-adjust target so progress bar doesn't seem too wonky
		if ( $count > $countEstimate ) {
		    $countEstimate = $progress->target($count+1000);
		    $next_update=$progress->update($count);
		}
		elsif ( $count > $next_update ) {
		    $next_update=$progress->update($count);
		}
	    }
	}
	else {
	    $self->error("$file:$lineCount: unrecognized format");
	    $next_update=$progress->update($count) if ($self->{showProgressBar});
	}
    }
    $progress->update($countEstimate) if ($self->{showProgressBar});

    $self->status(sprintf("parsing Ratings found ".withThousands($count)." titles in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

    closeMaybeGunzip($file, $fh);
    return($count);
}

sub readKeywords($$$$)
{
    my ($self, $countEstimate, $file)=@_;
    my $startTime=time();
    my $lineCount=0;

    my $fh = openMaybeGunzip($file) || return(-2);
    while(<$fh>) {
	$lineCount++;

	if ( m/THE KEYWORDS LIST/ ) {
	    if ( !($_=<$fh>) || !m/^===========/o ) {
		$self->error("missing ======= after \"THE KEYWORDS LIST\" at line $lineCount");
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
	elsif ( $lineCount > 100000 ) {
	    $self->error("$file: stopping at line $lineCount, didn't see \"THE KEYWORDS LIST\" line");
	    closeMaybeGunzip($file, $fh);
	    return(-1);
	}
    }

    my $progress=Term::ProgressBar->new({name  => "parsing keywords",
					 count => $countEstimate,
					 ETA   => 'linear'})
      if ($self->{showProgressBar});

    $progress->minor(0) if ($self->{showProgressBar});
    $progress->max_update_rate(1) if ($self->{showProgressBar});
    my $next_update=0;

    my $count=0;
    while(<$fh>) {
	$lineCount++;
	my $line=$_;
	chomp($line);
	next if ($line =~ m/^\s*$/);
	my ($title, $keyword) = ($line =~ m/^(.*)\s+(\S+)\s*$/);
	if ( defined($title) and defined($keyword) ) {

            my ($episode) = $title =~ m/^.*\s+(\{.*\})$/;

            # ignore anything which is an episode (e.g. "{Doctor Who (#10.22)}" )
            if ( !defined $episode || $episode eq '' )
            {
                if ( defined($self->{movies}{$title}) ) {
                    $self->{movies}{$title}.=",".$keyword;
                } else {
                    $self->{movies}{$title}=$keyword;
                    # returned count is number of unique titles found
                    $count++;
                }
            }

            if ( $self->{showProgressBar} ) {
                # re-adjust target so progress bar doesn't seem too wonky
    	        if ( $count > $countEstimate ) {
    	    	    $countEstimate = $progress->target($count+1000);
                    $next_update=$progress->update($count);
    	        }
    	        elsif ( $count > $next_update ) {
    	    	    $next_update=$progress->update($count);
    	        }
    	    }
        } else {
	    $self->error("$file:$lineCount: unrecognized format \"$line\"");
	    $next_update=$progress->update($count) if ($self->{showProgressBar});
	}
    }
    $progress->update($countEstimate) if ($self->{showProgressBar});

    $self->status(sprintf("parsing Keywords found ".withThousands($count)." titles in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

    closeMaybeGunzip($file, $fh);
    return($count);
}

sub readPlots($$$$)
{
    my ($self, $countEstimate, $file)=@_;
    my $startTime=time();
    my $lineCount=0;

    my $fh = openMaybeGunzip($file) || return(-2);
    while(<$fh>) {
	$lineCount++;

	if ( m/PLOT SUMMARIES LIST/ ) {
	    if ( !($_=<$fh>) || !m/^===========/o ) {
		$self->error("missing ======= after \"PLOT SUMMARIES LIST\" at line $lineCount");
		closeMaybeGunzip($file, $fh);
		return(-1);
	    }
	    if ( !($_=<$fh>) || !m/^-----------/o ) {
		$self->error("missing ------- line after ======= at line $lineCount");
		closeMaybeGunzip($file, $fh);
		return(-1);
	    }
	    last;
	}
	elsif ( $lineCount > 500 ) {
	    $self->error("$file: stopping at line $lineCount, didn't see \"PLOT SUMMARIES LIST\" line");
	    closeMaybeGunzip($file, $fh);
	    return(-1);
	}
    }

    my $progress=Term::ProgressBar->new({name  => "parsing plots",
					 count => $countEstimate,
					 ETA   => 'linear'})
      if ($self->{showProgressBar});

    $progress->minor(0) if ($self->{showProgressBar});
    $progress->max_update_rate(1) if ($self->{showProgressBar});
    my $next_update=0;

    my $count=0;
    while(<$fh>) {
	$lineCount++;
	my $line=$_;
	chomp($line);
	next if ($line =~ m/^\s*$/);
	my ($title, $episode) = ($line =~ m/^MV:\s(.*?)\s?(\{.*\})?$/);
	if ( defined($title) ) {

            # ignore anything which is an episode (e.g. "{Doctor Who (#10.22)}" )
            if ( !defined $episode || $episode eq '' )
            {
                my $plot = '';
                LOOP:
                while (1) {
                    if ( $line = <$fh> ) {
                        $lineCount++;
                        chomp($line);
                        next if ($line =~ m/^\s*$/);
                        if ( $line =~ m/PL:\s(.*)$/ ) {     # plot summary is a number of lines starting "PL:"
                            $plot .= ($plot ne ''?' ':'') . $1;
                        }
                        last LOOP if ( $line =~ m/BY:\s(.*)$/ );     # the author line "BY:" signals the end of the plot summary
                    } else {
                        last LOOP;
                    }
                }

                if ( !defined($self->{movies}{$title}) ) {
                    # ensure there's no tab chars in the plot or else the db stage will barf
                    $plot =~ s/\t//og;
                    $self->{movies}{$title}=$plot;
                    # returned count is number of unique titles found
                    $count++;
                }
            }

            if ( $self->{showProgressBar} ) {
                # re-adjust target so progress bar doesn't seem too wonky
    	        if ( $count > $countEstimate ) {
    	    	    $countEstimate = $progress->target($count+1000);
                    $next_update=$progress->update($count);
    	        }
    	        elsif ( $count > $next_update ) {
    	    	    $next_update=$progress->update($count);
    	        }
    	    }
        } else {
            # skip lines up to the next "MV:"
            if ($line !~ m/^(---|PL:|BY:)/ ) {
                $self->error("$file:$lineCount: unrecognized format \"$line\"");
            }
	    $next_update=$progress->update($count) if ($self->{showProgressBar});
	}
    }
    $progress->update($countEstimate) if ($self->{showProgressBar});

    $self->status(sprintf("parsing Plots found $count ".withThousands($count)." in ".
			  withThousands($lineCount)." lines in %d seconds",time()-$startTime));

    closeMaybeGunzip($file, $fh);
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

sub invokeStage($$)
{
    my ($self, $stage)=@_;

    my $startTime=time();
    if ( $stage == 1 ) {
	$self->status("parsing Movies list for stage $stage..");
	my $countEstimate=$self->dbinfoCalcEstimate("movies", 47);

	my $num=$self->readMoviesOrGenres("Movies", $countEstimate, "$self->{imdbListFiles}->{movies}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{movies} from ftp.imdb.com");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.10 ) {
	    my $better=$self->dbinfoCalcBytesPerEntry("movies", $num);
	    $self->status("ARG estimate of $countEstimate for movies needs updating, found $num ($better bytes/entry)");
	}
	$self->dbinfoAdd("db_stat_movie_count", "$num");

	$self->status("writing stage1 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing titles",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    my $count=0;
	    for my $movie (@{$self->{movies}}) {
		print OUT "$movie\n";

		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
    }
    elsif ( $stage == 2 ) {
	$self->status("parsing Directors list for stage $stage..");

	my $countEstimate=$self->dbinfoCalcEstimate("directors", 258);

	my $num=$self->readCastOrDirectors("Directors", $countEstimate, "$self->{imdbListFiles}->{directors}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{directors} from ftp.imdb.com (see http://www.imdb.com/interfaces)");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.10 ) {
	    my $better=$self->dbinfoCalcBytesPerEntry("directors", $num);
	    $self->status("ARG estimate of $countEstimate for directors needs updating, found $num ($better bytes/entry)");
	}
	$self->dbinfoAdd("db_stat_director_count", "$num");

	$self->status("writing stage2 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing directors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    my $count=0;
	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    for my $key (keys %{$self->{movies}}) {
		my %dir;
		for (split('\|', $self->{movies}{$key})) {
		    $dir{$_}++;
		}
		my @list;
		for (keys %dir) {
		    push(@list, sprintf("%03d:%s", $dir{$_}, $_));
		}
		my $value="";
		for my $c (reverse sort {$a cmp $b} @list) {
		    my ($num, $name)=split(':', $c);
		    $value.=$name."|";
		}
		$value=~s/\|$//o;
		print OUT "$key\t$value\n";

		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
	#unlink("$self->{imdbDir}/stage1.data");
    }
    elsif ( $stage == 3 ) {
	$self->status("parsing Actors list for stage $stage..");

	#print "re-reading movies into memory for reverse lookup..\n";
	my $countEstimate=$self->dbinfoCalcEstimate("actors", 449);

	my $num=$self->readCastOrDirectors("Actors", $countEstimate, "$self->{imdbListFiles}->{actors}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{actors} from ftp.imdb.com (see http://www.imdb.com/interfaces)");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.10 ) {
	    my $better=$self->dbinfoCalcBytesPerEntry("actors", $num);
	    $self->status("ARG estimate of $countEstimate for actors needs updating, found $num ($better bytes/entry)");
	}
	$self->dbinfoAdd("db_stat_actor_count", "$num");

	$self->status("writing stage3 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing actors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    my $count=0;
	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    for my $key (keys %{$self->{movies}}) {
		print OUT "$key\t$self->{movies}{$key}\n";

		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
    }
    elsif ( $stage == 4 ) {
	$self->status("parsing Actresses list for stage $stage..");

	my $countEstimate=$self->dbinfoCalcEstimate("actresses", 483);
	my $num=$self->readCastOrDirectors("Actresses", $countEstimate, "$self->{imdbListFiles}->{actresses}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{actresses} from ftp.imdb.com (see http://www.imdb.com/interfaces)");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.10 ) {
	    my $better=$self->dbinfoCalcBytesPerEntry("actresses", $num);
	    $self->status("ARG estimate of $countEstimate for actresses needs updating, found $num ($better bytes/entry)");
	}
	$self->dbinfoAdd("db_stat_actress_count", "$num");

	$self->status("writing stage4 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing actresses",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    my $count=0;
	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    for my $key (keys %{$self->{movies}}) {
		print OUT "$key\t$self->{movies}{$key}\n";
		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
	#unlink("$self->{imdbDir}/stage3.data");
    }
    elsif ( $stage == 5 ) {
	$self->status("parsing Genres list for stage $stage..");
	my $countEstimate=$self->dbinfoCalcEstimate("genres", 68);

	my $num=$self->readMoviesOrGenres("Genres", $countEstimate, "$self->{imdbListFiles}->{genres}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{genres} from ftp.imdb.com");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.10 ) {
	    my $better=$self->dbinfoCalcBytesPerEntry("genres", $num);
	    $self->status("ARG estimate of $countEstimate for genres needs updating, found $num ($better bytes/entry)");
	}
	$self->dbinfoAdd("db_stat_genres_count", "$num");

	$self->status("writing stage5 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_genres_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing genres",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    my $count=0;
	    for my $movie (keys %{$self->{movies}}) {
		print OUT "$movie\t$self->{movies}->{$movie}\n";

		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
    }
    elsif ( $stage == 6 ) {
	$self->status("parsing Ratings list for stage $stage..");
	my $countEstimate=$self->dbinfoCalcEstimate("ratings", 68);

	my $num=$self->readRatings($countEstimate, "$self->{imdbListFiles}->{ratings}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{ratings} from ftp.imdb.com");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.10 ) {
	    my $better=$self->dbinfoCalcBytesPerEntry("ratings", $num);
	    $self->status("ARG estimate of $countEstimate for ratings needs updating, found $num ($better bytes/entry)");
	}
	$self->dbinfoAdd("db_stat_ratings_count", "$num");

	$self->status("writing stage6 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_ratings_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing ratings",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    my $count=0;
	    for my $movie (keys %{$self->{movies}}) {
		my @value=@{$self->{movies}->{$movie}};
		print OUT "$movie\t$value[0]\t$value[1]\t$value[2]\n";

		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
    }
    elsif ( $stage == 7 ) {
	$self->status("parsing Keywords list for stage $stage..");

	if ( !defined($self->{imdbListFiles}->{keywords}) ) {
	    $self->status("no keywords file downloaded, see --with-keywords details in documentation");
	    return(0);
	}

	my $countEstimate=5630000;
	my $num=$self->readKeywords($countEstimate, "$self->{imdbListFiles}->{keywords}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{keywords} from ftp.imdb.com");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for keywords needs updating, found $num");
	}
	$self->dbinfoAdd("keywords_list_file",         "$self->{imdbListFiles}->{keywords}");
	$self->dbinfoAdd("keywords_list_file_size", -s "$self->{imdbListFiles}->{keywords}");
	$self->dbinfoAdd("db_stat_keywords_count", "$num");

	$self->status("writing stage$stage data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_keywords_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing keywords",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";

	    my $count=0;
	    for my $movie (keys %{$self->{movies}}) {
		print OUT "$movie\t$self->{movies}->{$movie}\n";

		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
    }
    elsif ( $stage == 8 ) {
	$self->status("parsing Plot list for stage $stage..");

	if ( !defined($self->{imdbListFiles}->{plot}) ) {
	    $self->status("no plot file downloaded, see --with-plot details in documentation");
	    return(0);
	}

	my $countEstimate=222222;
	my $num=$self->readPlots($countEstimate, "$self->{imdbListFiles}->{plot}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{plot} from ftp.imdb.com");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for plots needs updating, found $num");
	}
	$self->dbinfoAdd("plots_list_file",         "$self->{imdbListFiles}->{plot}");
	$self->dbinfoAdd("plots_list_file_size", -s "$self->{imdbListFiles}->{plot}");
	$self->dbinfoAdd("db_stat_plots_count", "$num");

	$self->status("writing stage$stage data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_plots_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing plots",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";

	    my $count=0;
	    for my $movie (keys %{$self->{movies}}) {
		print OUT "$movie\t$self->{movies}->{$movie}\n";

		$count++;
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(OUT);
	    delete($self->{movies});
	}
    }
    elsif ( $stage == $self->{stageLast} ) {
	my $tab=sprintf("\t");

	$self->status("indexing all previous stage's data for stage ".$self->{stageLast}."..");

	$self->status("parsing stage 1 data (movie list)..");
	my %movies;
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "reading titles",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage1.data") || die "$self->{imdbDir}/stage1.data:$!";
	    while(<IN>) {
		chop();
		$movies{$_}="";

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    close(IN);
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	}

	$self->status("merging in stage 2 data (directors)..");
	if ( 1 ) {
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "merging directors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage2.data") || die "$self->{imdbDir}/stage2.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t//o;
		if ( !defined($movies{$1}) ) {
		    $self->error("directors list references unidentified title '$1'");
		    next;
		}
		$movies{$1}=$_;

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(IN);
	}

	if ( 1 ) {
	    # fill in default for movies we didn't have a director for
	    for my $key (keys %movies) {
		if ( !length($movies{$key})) {
		    $movies{$key}="<>";
		}
	    }
	}

	$self->status("merging in stage 3 data (actors)..");
	if ( 1 ) {
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "merging actors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage3.data") || die "$self->{imdbDir}/stage3.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t//o;
		my $dbkey=$1;
		my $val=$movies{$dbkey};
		if ( !defined($val) ) {
		    $self->error("actors list references unidentified title '$dbkey'");
		    next;
		}
		if ( $val=~m/$tab/o ) {
		    $movies{$dbkey}=$val."|".$_;
		}
		else {
		    $movies{$dbkey}=$val.$tab.$_;
		}
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(IN);
	}

	$self->status("merging in stage 4 data (actresses)..");
	if ( 1 ) {
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "merging actresses",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage4.data") || die "$self->{imdbDir}/stage4.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t//o;
		my $dbkey=$1;
		my $val=$movies{$dbkey};
		if ( !defined($val) ) {
		    $self->error("actresses list references unidentified title '$dbkey'");
		    next;
		}
		if ( $val=~m/$tab/o ) {
		    $movies{$dbkey}=$val."|".$_;
		}
		else {
		    $movies{$dbkey}=$val.$tab.$_;
		}
		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(IN);
	}
	if ( 1 ) {
	    # fill in placeholder if no actors were found
	    for my $key (keys %movies) {
		if ( !($movies{$key}=~m/$tab/o) ) {
		    $movies{$key}.=$tab."<>";
		}
	    }
	}

	$self->status("merging in stage 5 data (genres)..");
	if ( 1 ) {
	    my $countEstimate=$self->dbinfoGet("db_stat_genres_count", 1);  # '1' prevents the spurious "(nothing to do)" msg
	    my $progress=Term::ProgressBar->new({name  => "merging genres",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage5.data") || die "$self->{imdbDir}/stage5.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t//o;
		my $dbkey=$1;
		my $genres=$_;
		my $val=$movies{$dbkey};
		if ( !defined($val) ) {
		    $self->error("genres list references unidentified title '$1'");
		    next;
		}
		$movies{$dbkey}.=$tab.$genres;

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(IN);
	}

	if ( 1 ) {
	    # fill in placeholder if no genres were found
	    for my $key (keys %movies) {
		my $val=$movies{$key};
		my $t=index($val, $tab);
		if ( $t == -1 ) {
		    die "corrupt entry '$key' '$val'";
		}
		if ( index($val, $tab, $t+1) == -1 ) {
		    $movies{$key}.=$tab."<>";
		}
	    }
	}

	$self->status("merging in stage 6 data (ratings)..");
	if ( 1 ) {
	    my $countEstimate=$self->dbinfoGet("db_stat_ratings_count", 1);  # '1' prevents the spurious "(nothing to do)" msg
	    my $progress=Term::ProgressBar->new({name  => "merging ratings",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage6.data") || die "$self->{imdbDir}/stage6.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$//o;
		my $dbkey=$1;
		my ($ratingDist, $ratingVotes, $ratingRank)=($2,$3,$4);

		my $val=$movies{$dbkey};
		if ( !defined($val) ) {
		    $self->error("ratings list references unidentified title '$1'");
		    next;
		}
		$movies{$dbkey}.=$tab.$ratingDist.$tab.$ratingVotes.$tab.$ratingRank;

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(IN);
	}

	if ( 1 ) {
	    # fill in placeholder if no genres were found
	    for my $key (keys %movies) {
		my $val=$movies{$key};

		my $t=index($val, $tab);
		if ( $t == -1  ) {
		    die "corrupt entry '$key' '$val'";
		}
		my $j=index($val, $tab, $t+1);
		if ( $j == -1  ) {
		    die "corrupt entry '$key' '$val'";
		}
		if ( index($val, $tab, $j+1) == -1 ) {
		    $movies{$key}.=$tab."<>".$tab."<>".$tab."<>";
		}
	    }
	}

	$self->status("merging in stage 7 data (keywords)..");
	#if ( 1 ) {         # this stage is optional
        if ( -f "$self->{imdbDir}/stage7.data" ) {
	    my $countEstimate=$self->dbinfoGet("db_stat_keywords_count", 1);  # '1' prevents the spurious "(nothing to do)" msg
	    my $progress=Term::ProgressBar->new({name  => "merging keywords",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage7.data") || die "$self->{imdbDir}/stage7.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t+//o;
		my $dbkey=$1;
		my $keywords=$_;
		if ( !defined($movies{$dbkey}) ) {
		    $self->error("keywords list references unidentified title '$1'");
		    next;
		}
		$movies{$dbkey}.=$tab.$keywords;

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(IN);
	}

	if ( 1 ) {
	    # fill in default for movies we didn't have any keywords for
	    for my $key (keys %movies) {
		my $val=$movies{$key};
		#keyword is 6th entry
		my $t = 0;
		for my $i (0..4) {
		    $t=index($val, $tab, $t);
		    if ( $t == -1 ) {
		    	die "Corrupt entry '$key' '$val'";
		    }
		    $t+=1;
		}
		if ( index($val, $tab, $t) == -1 ) {
		    $movies{$key}.=$tab."<>";
		}
	    }
	}

	$self->status("merging in stage 8 data (plots)..");
	#if ( 1 ) {         # this stage is optional
        if ( -f "$self->{imdbDir}/stage8.data" ) {
	    my $countEstimate=$self->dbinfoGet("db_stat_plots_count", 1);  # '1' prevents the spurious "(nothing to do)" msg
	    my $progress=Term::ProgressBar->new({name  => "merging plots",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage8.data") || die "$self->{imdbDir}/stage8.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t+//o;
		my $dbkey=$1;
		my $plot=$_;
		if ( !defined($movies{$dbkey}) ) {
		    $self->error("plot list references unidentified title '$1'");
		    next;
		}
		$movies{$dbkey}.=$tab.$plot;

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $. > $countEstimate ) {
			$countEstimate = $progress->target($.+100);
			$next_update=$progress->update($.);
		    }
		    elsif ( $. > $next_update ) {
			$next_update=$progress->update($.);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(IN);
	}
	if ( 1 ) {
	    # fill in default for movies we didn't have any plot for
	    for my $key (keys %movies) {
		my $val=$movies{$key};
		#plot is 7th entry
		my $t = 0;
		for my $i (0..5) {
		    $t=index($val, $tab, $t);
		    if ( $t == -1 ) {
		    	die "Corrupt entry '$key' '$val'";
		    }
		    $t+=1;
		}
		if ( index($val, $tab, $t) == -1 ) {
		    $movies{$key}.=$tab."<>";
		}
	    }
	}

	#unlink("$self->{imdbDir}/stage1.data");
	#unlink("$self->{imdbDir}/stage2.data");
	#unlink("$self->{imdbDir}/stage3.data");

        # ---------------------------------------------------------------------------------------


	#
	# note: not all movies end up with a cast, but we include them anyway.
	#

	my %nmovies;
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "computing index",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    my $count=0;
	    for my $key (keys %movies) {
		my $dbkey=$key;

		# drop episode information - ex: {Twelve Angry Men (1954)}
		$dbkey=~s/\s*\{[^\}]+\}//go;

		# todo - this would make things easier
		# change double-quotes around title to be (made-for-tv) suffix instead
		if ( $dbkey=~m/^\"/o && #"
		     $dbkey=~m/\"\s*\(/o ) { #"
		    $dbkey.=" (tv_series)";
		}
		# how rude, some entries have (TV) appearing more than once.
		$dbkey=~s/\(TV\)\s*\(TV\)$/(TV)/o;

		my $qualifier;
		if ( $dbkey=~s/\s+\(TV\)$//o ) {
		    $qualifier="tv_movie";
		}
		elsif ( $dbkey=~s/\s+\(mini\) \(tv_series\)$// ) {
		    $qualifier="tv_mini_series";
		}
		elsif ( $dbkey=~s/\s+\(tv_series\)$// ) {
		    $qualifier="tv_series";
		}
		elsif ( $dbkey=~s/\s+\(mini\)$//o ) {
		    $qualifier="tv_mini_series";
		}
		elsif ( $dbkey=~s/\s+\(V\)$//o ) {
		    $qualifier="video_movie";
		}
		elsif ( $dbkey=~s/\s+\(VG\)$//o ) {
		    #$qualifier="video_game";
		    delete($movies{$key});
		    next;
		}
		else {
		    $qualifier="movie";
		}
		#if ( $dbkey=~s/\s+\((tv_series|tv_mini_series|tv_movie|video_movie|video_game)\)$//o ) {
		 #   $qualifier=$1;
		#}
		my $year;
		my $title=$dbkey;

		if ( $title=~m/^\"/o && $title=~m/\"\s*\(/o ) { #"
		    $title=~s/^\"//o; #"
		    $title=~s/\"(\s*\()/$1/o; #"
		}

		if ( $title=~s/\s+\((\d\d\d\d)\)$//o ||
		     $title=~s/\s+\((\d\d\d\d)\/[IVX]+\)$//o ) {
		    $year=$1;
		}
		elsif ( $title=~s/\s+\((\?\?\?\?)\)$//o ||
			$title=~s/\s+\((\?\?\?\?)\/[IVX]+\)$//o ) {
		    $year="0000";
		}
		else {
		    $self->error("movie list format failed to decode year from title '$title'");
		    $year="0000";
		}
		$title=~s/(.*),\s*(The|A|Une|Las|Les|Los|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/og;

		my $hashkey=lc("$title ($year)");
		$hashkey=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;

		if ( defined($movies{$hashkey}) ) {
		    die "unable to place moviedb key for $key, report to xmltv-devel\@lists.sf.net";
		}
		die "title \"$title\" contains a tab" if ( $title=~m/\t/o );
		#print "key:$dbkey\n\ttitle=$title\n\tyear=$year\n\tqualifier=$qualifier\n";
		#print "key $key: value=\"$movies{$key}\"\n";

		$nmovies{$hashkey}=$dbkey.$tab.$year.$tab.$qualifier.$tab.delete($movies{$key});
		$count++;

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});

	    if ( scalar(keys %movies) != 0 ) {
		die "what happened, we have keys left ?";
	    }
	    undef(%movies);
	}

	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count", 0);
	    my $progress=Term::ProgressBar->new({name  => "writing database",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if ($self->{showProgressBar});
	    $progress->minor(0) if ($self->{showProgressBar});
	    $progress->max_update_rate(1) if ($self->{showProgressBar});
	    my $next_update=0;

	    open(IDX, "> $self->{moviedbIndex}") || die "$self->{moviedbIndex}:$!";
	    open(DAT, "> $self->{moviedbData}") || die "$self->{moviedbData}:$!";
	    my $count=0;
	    for my $key (sort {$a cmp $b} keys %nmovies) {
		my $val=delete($nmovies{$key});
		#print "movie $key: $val\n";
		#$val=~s/^([^\t]+)\t([^\t]+)\t([^\t]+)\t//o || die "internal failure ($key:$val)";
		my ($dbkey, $year, $qualifier,$directors,$actors,@rest)=split('\t', $val);
		#die ("no 1") if ( !defined($dbkey));
		#die ("no 2") if ( !defined($year));
		#die ("no 3") if ( !defined($qualifier));
		#die ("no 4") if ( !defined($directors));
		#die ("no 5") if ( !defined($actors));
		#print "key:$key\n\ttitle=$dbkey\n\tyear=$year\n\tqualifier=$qualifier\n";

		#my ($directors, $actors)=split('\t', $val);

		my $details="";

		if ( $directors eq "<>" ) {
		    $details.="<>";
		}
		else {
		    # sort directors by last name, removing duplicates
		    my $last='';
		    for my $name (sort {$a cmp $b} split('\|', $directors)) {
			if ( $name ne $last ) {
			    $details.="$name|";
			    $last=$name;
			}
		    }
		    $details=~s/\|$//o;
		}

		#print "      $dbkey: $val\n";
		if ( $actors eq "<>" ) {
		    $details.=$tab."<>";
		}
		else {
		    $details.=$tab;

		    # sort actors by billing, removing repeated entries
		    # be warned, two actors may have the same billing level
		    my $last='';
		    for my $c (sort {$a cmp $b} split('\|', $actors)) {
			my ($billing, $name)=split(':', $c);
			# remove Host/Narrators from end
			# BUG - should remove (I)'s from actors/actresses names when details are generated
			$name=~s/\s\([IVX]+\)\[/\[/o;
			$name=~s/\s\([IVX]+\)$//o;

			if ( $name ne $last ) {
			    $details.="$name|";
			    $last=$name;
			}
			#print "      $c: split gives'$billing' and '$name'\n";
		    }
		    $details=~s/\|$//o;
		}
		$count++;
		my $lineno=sprintf("%07d", $count);
		print IDX $key."\t".$dbkey."\t".$year."\t".$qualifier."\t".$lineno."\n";
		print DAT $lineno.":".$details."\t".join($tab, @rest)."\n";

		if ($self->{showProgressBar}) {
		    # re-adjust target so progress bar doesn't seem too wonky
		    if ( $count > $countEstimate ) {
			$countEstimate = $progress->target($count+100);
			$next_update=$progress->update($count);
		    }
		    elsif ( $count > $next_update ) {
			$next_update=$progress->update($count);
		    }
		}
	    }
	    $progress->update($countEstimate) if ($self->{showProgressBar});
	    close(DAT);
	    close(IDX);
	}

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
                    $self->error("data for this stage will NOT be added");
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
