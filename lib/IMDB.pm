#
# $Id$
#
# The IMDB file contains two packages:
# 1. XMLTV::IMDB::Cruncher package which parses and manages IMDB "lists" files
#    from ftp.imdb.com
# 2. XMLTV::IMDB package that uses data files from the Cruncher package to
#    update/add details to XMLTV programme nodes.
#
# Be warned, this and the tv_imdb script are prototypes and may change
# without notice.
#
#
# FUTURE - common english->french vowel changes. For instance
#          "Anna Karénin" (é->e)
#
# FIXED - "Victoria and Albert" appears for imdb's "Victoria & Albert" (and -> &)
#
# FUTURE - close hit could be just missing or extra
#          punctuation:
#       "Run Silent, Run Deep" for imdb's "Run Silent Run Deep"
#       "Cherry, Harry and Raquel" for imdb's "Cherry, Harry and Raquel!"
#       "Cat Women of the Moon" for imdb's "Cat-Women of the Moon"
#       "Baywatch Hawaiian Wedding" for imdb's "Baywatch: Hawaiian Wedding" :)
#
# FUTURE "Columbo Cries Wolf" appears instead of "Columbo:Columbo Cries Wolf"
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

use vars qw($VERSION);
$VERSION = '0.2';

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes

    for ('imdbDir', 'verbose') {
	die "invalid usage - no $_" if ( !defined($self->{$_}));
    }
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
	if ( $1 != $major || $minor < $2 ) {
	    return("imdbDir index db requires updating, rerun --prepStage all\n");
	}
	if ( $1 == 0 && $2 == 1 ) {
	    return("imdbDir index db requires update, rerun --prepStage 5 (bug:actresses never appear)\n");
	}
	# okay
	return(undef);
    }
    else {
	return("imdbDir index version of '$info->{db_version}' is invalid, rerun --prepStage 5\n".
	       "if problem persists, submit bug report to xmltv-devel\@lists.sf.net\n");
    }
}

sub basicVerificationOfIndexes($)
{
    my $self=shift;

    # check that the imdbdir is invalid and up and running
    my $title="Army of Darkness";
    my $year=1993;

    $self->openMovieIndex() || return("basic verification of indexes failed\n".
				      "database index isn't readable");

    my $res=$self->getMovieMatches($title, $year);
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
    #$match=~s/^(The|A|Une|Les|L\'|Le|La|El|Das)\s+(.*)$/$2, $1/og;
    
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
	    #$arr[1]=~s/(.*),\s*(The|A|Une|Les|L\'|Le|La|El|Das)$/$2 $1/og;
		    
	    #$arr[0]=~s/%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/defined($1)? chr hex($1) : utf8_chr(hex($2))/oge;
	    $self->debug("exact:$arr[1] ($arr[2]) qualifier=$arr[3] id=$arr[4]");
	    push(@{$results->{exactMatch}}, {'key'=> "$arr[1] ($arr[2])",
					     'title'=>$arr[1],
					     'year'=>$arr[2],
					     'qualifier'=>$arr[3],
					     'id'=>$arr[4]});
	}
	else {
	    # decode
	    #s/%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/defined($1)? chr hex($1) : utf8_chr(hex($2))/oge;
	    # return title
	    #$arr[1]=~s/(.*),\s*(The|A|Une|Les|L\'|Le|La|El|Das)$/$2 $1/og;
	    #$arr[0]=~s/%(?:([0-9a-fA-F]{2})|u([0-9a-fA-F]{4}))/defined($1)? chr hex($1) : utf8_chr(hex($2))/oge;
	    $self->debug("close:$arr[1] ($arr[2]) qualifier=$arr[3] id=$arr[4]");
	    push(@{$results->{closeMatch}}, {'key'=> "$arr[1] ($arr[2])",
					     'title'=>$arr[1],
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
	    my ($directors, $actors)=split('\t', $_);
	    if ( $directors ne "<unknown>" ) {
		for my $name (split('\|', $directors)) {
		    # remove (I) etc from imdb.com names (kept in place for reference)
		    $name=~s/\s\([IVX]+\)$//o;
		    # switch name around to be surname last
		    $name=~s/^([^,]+),\s*(.*)$/$2 $1/o;
		    push(@{$results->{directors}}, $name);
		}
	    }
	    if ( $actors ne "<unknown>" ) {
		for my $name (split('\|', $actors)) {
		    # remove (I) etc from imdb.com names (kept in place for reference)
		    $name=~s/\s\([IVX]+\)$//o;
		    # switch name around to be surname last
		    $name=~s/^([^,]+),\s*(.*)$/$2 $1/o;
		    push(@{$results->{actors}}, $name);
		}
	    }
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

sub alternativeTitles($)
{
    my $title=shift;
    my @titles;

    push(@titles, $title);
    if ( $title=~m/\&/o ) {
	my $t=$title;
	while ( $t=~s/(\s)\&(\s)/$1and$2/o ) {
	    push(@titles, $t);
	}
    }
    if ( $title=~m/\sand\s/io ) {
	my $t=$title;
	while ( $t=~s/(\s)and(\s)/$1\&$2/io ) {
	    push(@titles, $t);
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
		    $self->debug("ignoing close hit on \"$info->{key}\" (off by $yearsOff years)");
		}
	    }
	    else {
		$self->debug("ignoing close hit on \"$info->{key}\" (title did not match)");
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
# todo - ratings ? star ratings ? - use certificates.list
# todo - add description (replace an option ?)
# todo - writer
# todo - producer
# todo - commentator ?
# todo - check program length - probably a warning if longer ?
#        can we update length (separate from runnning time in the output ?)
# todo - icon - url from www.imdb.com of programme image ?
#        this could be done by scraping for the hyper linked poster
#        <a name="poster"><img src="http://ia.imdb.com/media/imdb/01/I/60/69/80m.jpg" height="139" width="99" border="0"></a>
#        and grabbin' out the img entry. (BTW ..../npa.jpg seems to line up with no poster available)
#
sub applyFound($$$)
{
    my ($self, $prog, $idInfo)=@_;

    my $title=$prog->{title}->[0]->[0];

    if ( defined($prog->{date}) ) {
	if ( $prog->{date} ne $idInfo->{year} ) {
	    $self->debug("replacing 'date' field from \"$prog->{date}\" to be \"$idInfo->{year}\" on \"$title\"");
	    $prog->{date}=int($idInfo->{year});
	}
    }
    else {
	# don't add dates only fix them for tv_series
	if ( $idInfo->{qualifier} eq "movie" ||
	     $idInfo->{qualifier} eq "video_movie" ||
	     $idInfo->{qualifier} eq "tv_movie" ) {
	    $self->debug("adding 'date' field (\"$idInfo->{year}\") on \"$title\"");
	    $prog->{date}=int($idInfo->{year});
	}
	else {
	    $self->debug("not adding 'date' field to $idInfo->{qualifier} \"$title\"");
	}
    }
    
    if ( $idInfo->{title} ne $title ) {
	$self->debug("replacing 'title' from \"$title\" to \"$idInfo->{title}\"");
	$prog->{title}->[0]->[0]=$idInfo->{title};
    }

    my $mycategory=$self->{categories}->{$idInfo->{qualifier}};
    die "how did we get here with an invalid qualifier '$idInfo->{qualifier}'" if (!defined($mycategory));

    # update/add category based on the type we matched from imdb.com
    if ( defined($prog->{category}) ) {
	
	my $found=0;
	for my $value (@{$prog->{category}}) {
	    #print "checking category $value->[0] with $mycategory\n";
	    if ( $value->[0] eq $mycategory ) {
		$found=1;
	    }
	}
	if ( !$found ) {
	    push(@{$prog->{category}}, [$mycategory,undef]);
	}
    }
    else {
	push(@{$prog->{category}}, [$mycategory,undef]);
    }
    
    my $details=$self->getMovieIdDetails($idInfo->{id});
    if ( $details->{noDetails} ) {
	# we don't have any details on this movie
    }
    else {
	# add url to programme on www.imdb.com
	my $url=$title;
	$url=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;
	$url="http://www.imdb.com/Title?".$url;
	if ( defined($prog->{url}) ) {
	    my @rep;
	    my $updated=0;
	    for (@{$prog->{url}}) {
		#print "checking existing url $_\n";
		if ( m;^http://www.imdb.com/Title;o ) {
		    if ( $_ ne $url && !$updated ) {
			$self->debug("updating www.imdb.com url on movie \"$idInfo->{key}\"");
			$updated=1;
			push(@rep, $url);
		    }
		}
		else {
		    push(@rep, $_);
		}
	    }
	    push(@rep, $url) if ( $updated == 0 );
	    $prog->{url}=\@rep;
	}
	else {
	    push(@{$prog->{url}}, $url);
	}
	    
	# add directors list form www.imdb.com
	if ( defined($details->{directors}) ) {
	    # don't add directors for movie or (if tv show) we have EXACTLY ONE director
	    if ( scalar(@{$details->{directors}}) == 1 ||
		 $idInfo->{qualifier} eq "movie" ||
		 $idInfo->{qualifier} eq "video_movie" ||
		 $idInfo->{qualifier} eq "tv_movie" ) {
		if ( defined($prog->{credits}->{director}) ) {
		    $self->debug("replacing director(s) on $idInfo->{qualifier} \"$idInfo->{key}\"");
		    delete($prog->{credits}->{director});
		}
		for my $name (@{$details->{directors}}) {
		    push(@{$prog->{credits}->{director}}, $name);
		}
	    }
	    else {
		$self->debug("not adding 'director' field to $idInfo->{qualifier} \"$title\"");
	    }
	}
	# add top 3 billing actors list form www.imdb.com
	if ( defined($details->{actors}) ) {
	    if ( defined($prog->{credits}->{actor}) ) {
		$self->debug("replacing actor(s) on $idInfo->{qualifier} \"$idInfo->{key}\"");
		delete($prog->{credits}->{actor});
	    }
	    for my $name (splice(@{$details->{actors}},0,3)) {
		push(@{$prog->{credits}->{actor}}, $name);
	    }
	}
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

package XMLTV::IMDB::Crunch;
use LWP::Simple;

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
    if ( ! -d "$self->{imdbDir}" ) {
	die "$self->{imdbDir}:does not exist" ;
    }
    my $listsDir = "$self->{imdbDir}/lists";
    if ( ! -d $listsDir ) {
	mkdir $listsDir, 0777 or die "cannot mkdir $listsDir: $!";
    }
  CHECK_FILES:
    my %missingListFiles; # maps 'movies' to filename ...movies.gz
    for ('movies', 'actors', 'actresses', 'directors') {
	my $filename="$listsDir/$_.list";
	my $filenameGz="$filename.gz";
	my $filenameExists = -f $filename;
	my $filenameSize = -s _;
	my $filenameGzExists = -f $filenameGz;
	my $filenameGzSize = -s _;

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
	    $missingListFiles{$_}=$filenameGz;
	}
	elsif ( not $filenameExists and $filenameGzExists ) {
	    $self->{imdbListFiles}->{$_}=$filenameGz;
	}
	elsif ( $filenameExists and not $filenameGzExists ) {
	    $self->{imdbListFiles}->{$_}=$filename;
	}
	elsif ( $filenameExists and $filenameGzExists ) {
	    die "both $filename and $filenameGz exist, remove one of them\n";
	}
	else { die }
    }
    if ( $self->{downloadMissingFiles} ) {
	my $baseUrl = 'ftp://ftp.fu-berlin.de/pub/misc/movies/database/';
	foreach ( sort keys %missingListFiles ) {
	    my $url = "$baseUrl/$_.list.gz";
	    my $filename = $missingListFiles{$_};
	    my $partial = "$filename.partial";
	    if (-e $partial) {
		if (not -s _) {
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
	    # For downloading we use LWP::Simple::getprint() which
	    # writes to stdout.
	    #
#
# change from getprint to getstore. getprint converts line endings on MacOS
# and windows, and this scews up binary files.  In addition, getstore doesn't
# need all the games with STDOUT. - Robert Eden 7/5/03
#
#	    local *OLDOUT;
#	    open(OLDOUT, '>&STDOUT') or die "cannot dup stdout: $!";
#	    open(STDOUT, ">$filename") or die "cannot write to $filename: $!";
#	    my $success = getprint($url);
#	    close STDOUT or die "cannot close $filename: $!";
#	    open(STDOUT, '>&OLDOUT') or die "cannot dup stdout back again: $!";
        my $success = getstore($url,$filename);
	    if (not $success) {
		warn "failed to download $url to $filename, renaming to $partial\n";
		rename $filename, $partial
		  or die "cannot rename $filename to $partial: $!";
		warn "You might try continuing the download of <$url> manually.\n";
		exit(1);
	    }
	    print STDERR "<$url>\n\t-> $filename, success\n\n";
	}
	$self->{downloadMissingFiles} = 0;
	goto CHECK_FILES;
    }

    if ( %missingListFiles ) {
	print STDERR "tv_imdb: requires you to download the above files from ftp.imdb.com\n";
	print STDERR "         see http://www.imdb.com/interfaces for details\n";
	return(undef);
    }

    $self->{moviedbIndex}="$self->{imdbDir}/moviedb.idx";
    $self->{moviedbData}="$self->{imdbDir}/moviedb.dat";
    $self->{moviedbInfo}="$self->{imdbDir}/moviedb.info";
    $self->{moviedbOffline}="$self->{imdbDir}/moviedb.offline";

    bless($self, $type);
    return($self);
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

use XMLTV::Gunzip;
use IO::File;
sub openMaybeGunzip($)
{
    for ( shift ) {
	return gunzip_open($_) if m/\.gz$/;
	return new IO::File("< $_");
    }
}

sub readMovies($$$)
{
    my ($self, $countEstimate, $file)=@_;
    my $startTime=time();

    my $fh = openMaybeGunzip($file) || return(-2);
    while(<$fh>) {
	if ( m/^MOVIES LIST/o ) {
	    if ( !($_=<$fh>) || !m/^===========/o ) {
		$self->error("missing ======= after MOVIES LIST at line $.");
		return(-1);
	    }
	    if ( !($_=<$fh>) || !m/^\s*$/o ) {
		$self->error("missing empty line after ======= at line $.");
		return(-1);
	    }
	    last;
	}
	elsif ( $. > 1000 ) {
	    $self->error("$file: stopping at line $., didn't see \"MOVIES LIST\" line");
	    return(-1);
	}
    }

    my $progress=Term::ProgressBar->new({name  => 'parsing Movies',
					 count => $countEstimate,
					 ETA   => 'linear'})
      if Have_bar;

    $progress->minor(0) if Have_bar;
    $progress->max_update_rate(1) if Have_bar;
    my $next_update=0;

    my $count=0;
    while(<$fh>) {
	my $line=$_;
	#print "read line $.:$line";

	# end is line consisting of only '-'
	last if ( $line=~m/^\-\-\-\-\-\-\-+/o );

	$line=~s/\n$//o;
	
	my $tab=index($line, "\t");
	if ( $tab != -1 ) {
	    $line=substr($line, 0, $tab);

	    push(@{$self->{movies}}, $line);
	    $count++;
	
	    if (Have_bar) {
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
	    $self->error("$file:$.: unrecognized format (missing tab)");
	    $next_update=$progress->update($count) if Have_bar;
	}
    }
    $progress->update($countEstimate) if Have_bar;

    # Would close($fh) but that causes segfaults on my system.
    # Investigating, but in the meantime just leave it open.
    #

    $self->status(sprintf("Parsed $count titles in %d seconds",time()-$startTime));
    return($count);
}

sub readCastOrDirectors($$$)
{
    my ($self, $whichCastOrDirector, $castCountEstimate, $file)=@_;
    my $startTime=time();

    my $header;
    my $whatAreWeParsing;

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
      if Have_bar;
    $progress->minor(0) if Have_bar;
    $progress->max_update_rate(1) if Have_bar;
    my $next_update=0;
    while(<$fh>) {
	if ( m/^$header/ ) {
	    if ( !($_=<$fh>) || !m/^===========/o ) {
		$self->error("missing ======= after $header at line $.");
		return(-1);
	    }
	    if ( !($_=<$fh>) || !m/^\s*$/o ) {
		$self->error("missing empty line after ======= at line $.");
		return(-1);
	    }
	    if ( !($_=<$fh>) || !m/^Name\s+Titles\s*$/o ) {
		$self->error("missing name/titles line after ======= at line $.");
		return(-1);
	    }
	    if ( !($_=<$fh>) || !m/^[\s\-]+$/o ) {
		$self->error("missing name/titles suffix line after ======= at line $.");
		return(-1);
	    }
	    last;
	}
	elsif ( $. > 1000 ) {
	    $self->error("$file: stopping at line $., didn't see \"$header\" line");
	    return(-1);
	}
    }

    my $cur_name;
    my $count=0;
    my $castNames=0;
    while(<$fh>) {
	my $line=$_;
	$line=~s/\n$//o;
	#$self->status("read line $.:$line");
	
	# end is line consisting of only '-'
	last if ( $line=~m/^\-\-\-\-\-\-\-+/o );
	
	next if ( length($line) == 0 );

	if ( $line=~s/^([^\t]+)\t+//o ) {
	    $cur_name=$1;
	    $castNames++;

	    if (Have_bar) {
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
	if ( $whatAreWeParsing < 3 ) {
	    # actors or actresses
	    $billing="9999";
	    if ( $line=~s/\s*<(\d+)>//o ) {
		$billing=sprintf("%04d", int($1));
	    }
	    
	    if ( (my $start=index($line, " [")) != -1 ) {
		#my $end=rindex($line, "]");
		$line=substr($line, 0, $start);
		# ignore character name
	    }
	}
	if ( $line=~s/\s*\{[^\}]+\}//o ) {
	    # ignore {Twelve Angry Men (1954)}
	    # don't see what these are...?
	}

	if ( $line=~s/\s*\(aka ([^\)]+)\).*$//o ) {
	    # $attr=$1;
	}
	elsif ( $line=~s/  (\(.*)$//o ) {
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
	if ( defined($billing) ) {
	    if ( defined($val) ) {
		$self->{movies}{$line}=$val."|$billing:$cur_name";
	    }
	    else {
		$self->{movies}{$line}="$billing:$cur_name";
	    }
	}
	else {
	    if ( defined($val) ) {
		$self->{movies}{$line}=$val."|$cur_name";
	    }
	    else {
		$self->{movies}{$line}=$cur_name;
	    }
	}
	$count++;
    }
    $progress->update($castCountEstimate) if Have_bar;
    # close($fh); # see earlier comment
    $self->status(sprintf("Parsed $castNames $whichCastOrDirector in $count titles in %d seconds",time()-$startTime));
    return($castNames);
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
    my ($self, $key, $value)=@_;
    return($self->{dbinfo}->{$key});
}

sub dbinfoSave($)
{
    my $self=shift;
    open(INFO, "> $self->{moviedbInfo}") || return(1);
    for (keys %{$self->{dbinfo}}) {
	print INFO "".$_.":".$self->{dbinfo}->{$_}."\n";
    }
    close(INFO);
    return(0);
}


sub invokeStage($$)
{
    my ($self, $stage)=@_;

    my $startTime=time();
    if ( $stage == 1 ) {
	$self->status("starting prep stage $stage (parsing movies.list)..");
	my $countEstimate=341000;
	my $num=$self->readMovies($countEstimate, "$self->{imdbListFiles}->{movies}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{movies} from ftp.imdb.com");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for movies needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_movie_count", "$num");

	$self->status("writing stage1 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "writing titles",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;
	    
	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    my $count=0;
	    for my $movie (@{$self->{movies}}) {
		print OUT "$movie\n";
		
		$count++;
		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(OUT);
	}
    }
    elsif ( $stage == 2 ) {
	$self->status("starting prep stage $stage (parsing directors.list)..");

	my $countEstimate=69000;
	my $num=$self->readCastOrDirectors("Directors", $countEstimate, "$self->{imdbListFiles}->{directors}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{directors} from ftp.imdb.com (see http://www.imdb.com/interfaces)");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for directors needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_director_count", "$num");

	$self->status("writing stage2 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "writing directors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
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
		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(OUT);
	}
	#unlink("$self->{imdbDir}/stage1.data");
    }
    elsif ( $stage == 3 ) {
	$self->status("starting prep stage $stage (parsing actors.list)..");

	#print "re-reading movies into memory for reverse lookup..\n";
	my $countEstimate=430000;
	my $num=$self->readCastOrDirectors("Actors", $countEstimate, "$self->{imdbListFiles}->{actors}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{actors} from ftp.imdb.com (see http://www.imdb.com/interfaces)");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for actors needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_actor_count", "$num");

	$self->status("writing stage3 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "writing actors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;
	    
	    my $count=0;
	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    for my $key (keys %{$self->{movies}}) {
		print OUT "$key\t$self->{movies}{$key}\n";
		
		$count++;
		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(OUT);
	}
    }
    elsif ( $stage == 4 ) {
	$self->status("starting prep stage $stage (parsing actresses.list)..");

	my $countEstimate=260000;
	my $num=$self->readCastOrDirectors("Actresses", $countEstimate, "$self->{imdbListFiles}->{actresses}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{actresses} from ftp.imdb.com (see http://www.imdb.com/interfaces)");
	    }
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for actresses needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_actress_count", "$num");

	$self->status("writing stage4 data ..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "writing actresses",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;
	    
	    my $count=0;
	    open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	    for my $key (keys %{$self->{movies}}) {
		print OUT "$key\t$self->{movies}{$key}\n";
		$count++;
		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(OUT);
	}
	#unlink("$self->{imdbDir}/stage3.data");
    }
    elsif ( $stage == 5 ) {
	my $tab=sprintf("\t");

	$self->status("starting prep stage $stage (creating indexes..)..");

	$self->status("parsing stage 1 data (movie list)..");

	my %movies;

	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "reading titles",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;
	    
	    open(IN, "< $self->{imdbDir}/stage1.data") || die "$self->{imdbDir}/stage1.data:$!";
	    while(<IN>) {
		chop();
		$movies{$_}="";
		
		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	}

	$self->status("merging in stage 2 data (directors)..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "reading directors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
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

		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(IN);
	}
	    
	# fill in default for movies we didn't have a director for
	for my $key (keys %movies) {
	    if ( !length($movies{$key})) {
		$movies{$key}="nodir";
	    }
	}

	$self->status("merging in stage 3 data (actors)..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "reading actors",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage3.data") || die "$self->{imdbDir}/stage3.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t//o;
		my $title=$1;
		my $val=$movies{$title};
		if ( !defined($val) ) {
		    $self->error("actors list references unidentified title '$title'");
		    next;
		}
		if ( $val=~m/$tab/o ) {
		    $movies{$title}=$val."|".$_;
		}
		else {
		    $movies{$title}=$val.$tab.$_;
		}
		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(IN);
	}
	    
	$self->status("merging in stage 4 data (actresses)..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "reading actresses",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;

	    open(IN, "< $self->{imdbDir}/stage4.data") || die "$self->{imdbDir}/stage4.data:$!";
	    while(<IN>) {
		chop();
		s/^([^\t]+)\t//o;
		my $title=$1;
		my $val=$movies{$title};
		if ( !defined($val) ) {
		    $self->error("actresses list references unidentified title '$title'");
		    next;
		}
		if ( $val=~m/$tab/o ) {
		    $movies{$title}=$val."|".$_;
		}
		else {
		    $movies{$title}=$val.$tab.$_;
		}
		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(IN);
	}

	#unlink("$self->{imdbDir}/stage1.data");
	#unlink("$self->{imdbDir}/stage2.data");
	#unlink("$self->{imdbDir}/stage3.data");

	#
	# note: not all movies end up with a cast, but we include them anyway.
	#
	
	$self->status("computing indexes..");
	my %nmovies;
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "indexing by title",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;
	    
	    my $count=0;
	    for my $key (keys %movies) {
		my $nkey=$key;
		
		# todo - this would make things easier
		# change double-quotes around title to be (made-for-tv) suffix instead 
		if ( $nkey=~m/^\"/o && #"
		     $nkey=~m/\"\s*\(/o ) { #"
		    $nkey=~s/^\"//o; # "
		    $nkey=~s/\"(\s*\()/$1/o; #"
		    $nkey.=" (tv_series)";
		}
		# how rude, some entries have (TV) appearing more than once.
		$nkey=~s/\(TV\)\s*\(TV\)$/(TV)/o;
		
		$nkey=~s/\(mini\) \(tv_series\)$/(tv_mini_series)/o;
		$nkey=~s/\(mini\)$/(tv-mini-series)/o;
		$nkey=~s/\(TV\)$/(tv_movie)/o;
		$nkey=~s/\(V\)$/(video_movie)/o;
		$nkey=~s/\(VG\)$/(video_game)/o;
		
		my $title=$nkey;
		my $qualifier="movie";
		if ( $title=~s/\s+\((tv_series|tv_mini_series|tv_movie|video_movie|video_game)\)$//o ) {
		    $qualifier=$1;
		}
		my $year;
		if ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\)$//o ) {
		    $year=$1;
		}
		elsif ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\/[IVX]+\)$//o ) {
		    $year=$1;
		}
		else {
		    die "unable to decode year from title key \"$title\", report to xmltv-devel\@lists.sf.net";
		}
		$year="0000" if ( $year eq "????" );
		$title=~s/(.*),\s*(The|A|Une|Les|L\'|Le|La|El|Das)$/$2 $1/og;
		
		$nkey=lc("$title ($year)");
		$nkey=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;
		
		if ( defined($movies{$nkey}) ) {
		    die "unable to place moviedb key for $key, report to xmltv-devel\@lists.sf.net";
		}
		die "title \"$title\" contains a tab" if ( $title=~m/\t/o );
		#print "key:$nkey\n\ttitle=$title\n\tyear=$year\n\tqualifier=$qualifier\n";
		#print "key $key: value=\"$movies{$key}\"\n";
		my ($directors, $actors)=split('\t', delete($movies{$key}));
		
		$directors="<unknown>" if ( !defined($directors) || $directors eq "nodir");
		$actors="<unknown>" if ( !defined($actors) );

		$nmovies{$nkey}=$title.$tab.$year.$tab.$qualifier.$tab.$directors.$tab.$actors;

		$count++;

		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;

	    if ( scalar(keys %movies) != 0 ) {
		die "what happened, we have keys left ?";
	    }
	    undef(%movies);
	}

	$self->status("writing out indexes..");
	{
	    my $countEstimate=$self->dbinfoGet("db_stat_movie_count");
	    my $progress=Term::ProgressBar->new({name  => "writing index",
						 count => $countEstimate,
						 ETA   => 'linear'})
	      if Have_bar;
	    $progress->minor(0) if Have_bar;
	    $progress->max_update_rate(1) if Have_bar;
	    my $next_update=0;
	    
	    open(OUT, "> $self->{moviedbIndex}") || die "$self->{moviedbIndex}:$!";
	    open(ACT, "> $self->{moviedbData}") || die "$self->{moviedbData}:$!";
	    my $count=0;
	    for my $key (sort {$a cmp $b} keys %nmovies) {
		my $val=delete($nmovies{$key});
		#print "movie $key: $val\n";
		#$val=~s/^([^\t]+)\t([^\t]+)\t([^\t]+)\t//o || die "internal failure ($key:$val)";
		my ($title, $year, $qualifier,$directors,$actors)=split('\t', $val);
		#die ("no 1") if ( !defined($title));
		#die ("no 2") if ( !defined($year));
		#die ("no 3") if ( !defined($qualifier));
		#die ("no 4") if ( !defined($directors));
		#die ("no 5") if ( !defined($actors));
		#print "key:$key\n\ttitle=$title\n\tyear=$year\n\tqualifier=$qualifier\n";
		
		#my ($directors, $actors)=split('\t', $val);
		
		my $details="";
		
		if ( $directors eq "<unknown>" ) {
		    $details.="<unknown>";
		}
		else {
		    # sort directors by last name
		    for my $name (sort {$a cmp $b} split('\|', $directors)) {
			$details.="$name|";
		    }
		    $details=~s/\|$//o;
		}
		$details.=$tab;
		#print "      $title: $val\n";
		if ( $actors eq "<unknown>" ) {
		    $details.="<unknown>";
		}
		else {
		    my %order;
		    # sort actors by billing
		    for my $c (sort {$a cmp $b} split('\|', $actors)) {
			my ($billing, $name)=split(':', $c);
			if ( $billing != 9999 && defined($order{$billing}) ) {
			    # this occurs, most of the time so we don't check it  :<
			    #$self->error("title \"$title\" has two actors at billing level $billing ($order{$billing} and $name)");
			}
			$order{$billing}=$name;
			#if ( !defined($billing) || ! defined($name) ) {
			#warn "no billing or name in $c from movie $title";
			#warn "y=$year";
			#warn "q=$qualifier";
			#warn "d=$directors";
			#warn "a=$actors";
			#}
			#
			# BUG - should remove (I)'s from actors/actresses names when details are generated
			$name=~s/\s\([IVX]+\)$//o;
			
			$details.="$name|";
			#print "      $c: split gives'$billing' and '$name'\n";
		    }
		}
		$details=~s/\|$//o;
		$count++;
		my $lineno=sprintf("%07d", $count);
		print OUT "$key\t$title\t$year\t$qualifier\t$lineno\n";
		print ACT "$lineno:$details\n";

		if (Have_bar) {
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
	    $progress->update($countEstimate) if Have_bar;
	    close(ACT);
	    close(OUT);
	}

	$self->dbinfoAdd("db_version", $XMLTV::IMDB::VERSION);

	if ( $self->dbinfoSave() ) {
	    $self->error("$self->{moviedbInfo}:$!");
	    return(1);
	}

	$self->status("running quick sanity check on database indexes...");
	my $imdb=new XMLTV::IMDB('imdbDir' => $self->{imdbDir},
				 'verbose' => $self->{verbose});

	if ( my $errline=$imdb->sanityCheckDatabase() ) {
	    open(OFF, "> $self->{moviedbOffline}") || die "$self->{moviedbOffline}:$!";
	    print OFF $errline;
	    print OFF "one of the prep stages' must have produced corrupt data\n";
	    print OFF "report the following details to xmltv-devel\@lists.sf.net\n";
	    
	    my $info=XMLTV::IMDB::loadDBInfo($self->{moviedbInfo});
	    if ( ref $info eq 'SCALAR' ) {
		print OFF "\tdbinfo file corrupt\n";
		print OFF "\t$info";
	    }
	    else {
		for my $key (keys %{$info}) {
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
	$self->error("tv_imdb: invalid stage $stage: only 1-5 are valid");
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

    for (my $st=1 ; $st < $stage ; $st++ ) {
	if ( !$self->stageComplete($st) ) {
	    $self->error("prep stages must be run in sequence..");
	    $self->error("prepStage $st either has never been run or failed");
	    $self->error("rerun tv_imdb with --prepStage=$st");
	    return(1);
	}
    }

    if ( -f "$self->{moviedbInfo}" ) {
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
