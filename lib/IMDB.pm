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
# FUTURE - "Victoria and Albert" appears for imdb's "Victoria & Albert" (and -> &)
#
# FUTURE - close hit could be just missing or extra
#          punctuation:
#       "Run Silent, Run Deep" for imdb's "Run Silent Run Deep"
#       "Cherry, Harry and Raquel" for imdb's "Cherry, Harry and Raquel!"
#       "Cat Women of the Moon" for imdb's "Cat-Women of the Moon"
#       "Baywatch Hawaiian Wedding" for imdb's "Baywatch: Hawaiian Wedding" :)
#
# FUTURE - unless we go with case insensitive matches...
#       "Cherry, Harry And Raquel!" won't match imdb's "Cherry, Harry and Raquel!"
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
#

use strict;

package XMLTV::IMDB;

use vars qw($VERSION);
$VERSION = '0.1';

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

    $self->{look_cmd}="look";

    bless($self, $type);

    $self->{stats}->{failed}=0;
    $self->{stats}->{success}=0,
    $self->{stats}->{perfect}->{movie}=0;
    $self->{stats}->{perfect}->{tv_series}=0,
    $self->{stats}->{perfect}->{tv_mini_series}=0,
    $self->{stats}->{perfect}->{tv_movie}=0,
    $self->{stats}->{perfect}->{video_movie}=0,
    $self->{stats}->{perfect}->{video_game}=0,

    $self->{stats}->{close}->{movie}=0;
    $self->{stats}->{close}->{tv_series}=0,
    $self->{stats}->{close}->{tv_mini_series}=0,
    $self->{stats}->{close}->{tv_movie}=0,
    $self->{stats}->{close}->{video_movie}=0,
    $self->{stats}->{close}->{video_game}=0,

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
	return("imdbDir index db missing version information, rerun --prepStages all\n");
    }
    if ( $info->{db_version}=~m/^(\d+)\.(\d+)$/o ) {
	if ( $1 != $major || $minor < $2 ) {
	    return("imdbDir index db requires updating, rerun --prepStages all\n");
	}
    }
    # okay
    return(undef);
}

sub basicVerificationOfIndexes($)
{
    my $self=shift;

    # check that the imdbdir is invalid and up and running
    my $title="Army of Darkness";
    my $year=1993;
    my $res=$self->getMovieMatches($title, $year);
    if ( !defined($res) ) {
	return("basic verification of indexes failed\n".
	       "no match for basic verification of movie \"$title, $year\"\n");
    }
    if ( !defined($res->{exactMatch}) ) {
	return("basic verification of indexes failed\n".
	       "no exact match for movie \"$title, $year\"\n");
    }
    if ( scalar(@{$res->{exactMatch}})!= 1) {
	return("basic verification of indexes failed\n".
	       "got more than one exact match for movie \"$title, $year\"\n");
    }
    my @exact=@{$res->{exactMatch}};
    if ( $exact[0]->{title} ne $title ) {
	return("basic verification of indexes failed\n".
	       "title associated with key \"$title, $year\" is bad\n");
    }

    if ( $exact[0]->{year} ne "$year" ) {
	return("basic verification of indexes failed\n".
	       "year associated with key \"$title, $year\" is bad\n");
    }

    my $id=$exact[0]->{id};
    $res=$self->getMovieIdDetails($id);
    if ( !defined($res) ) {
	return("basic verification of indexes failed\n".
	       "no movie details for movie \"$title, $year\" (id=$id)\n");
    }
    
    if ( !defined($res->{directors}) ) {
	return("basic verification of indexes failed\n".
	       "movie details didn't provide any director for movie \"$title, $year\" (id=$id)\n");
    }
    if ( !$res->{directors}[0]=~m/Raimi/o ) {
	return("basic verification of indexes failed\n".
	       "movie details didn't show Raimi as the main director for movie \"$title, $year\" (id=$id)\n");
    }
    if ( !defined($res->{actors}) ) {
	return("basic verification of indexes failed\n".
	       "movie details didn't provide any cast movie \"$title, $year\" (id=$id)\n");
    }
    if ( !$res->{actors}[0]=~m/Campbell/o ) {
	return("basic verification of indexes failed\n".
	       "movie details didn't show Bruce Campbell as the main actor in movie \"$title, $year\" (id=$id)\n");
    }
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

#
# todo - add in stats on other things added (urls ?, actors, directors,categories)
#        separate out from what was added or updated
#
sub getStatsLines($$$$)
{
    my $self=shift;
    my $totalFilesParsed=shift;
    my $totalChannelsParsed=shift;
    my $totalProgramsParsed=shift;

    my $endTime=time();
    my $totalProgramsLookedUp=$self->{stats}->{failed}+$self->{stats}->{success};

    my $calcProgramsPerSecondParsed=($endTime!=$self->{stats}->{startTime} && $totalProgramsParsed != 0)?
	$totalProgramsParsed/($endTime-$self->{stats}->{startTime}): 0;

    my $calcProgramsPerSecondChecked=($endTime!=$self->{stats}->{startTime} && $totalProgramsLookedUp != 0)?
	$totalProgramsLookedUp/($endTime-$self->{stats}->{startTime}): 0;
    
    my $num_perfect=($self->{stats}->{perfect}->{movie}+
		     $self->{stats}->{perfect}->{tv_series}+
		     $self->{stats}->{perfect}->{tv_mini_series}+
		     $self->{stats}->{perfect}->{tv_movie}+
		     $self->{stats}->{perfect}->{video_movie}+
		     $self->{stats}->{perfect}->{video_game});

    my $num_close=($self->{stats}->{close}->{movie}+
		   $self->{stats}->{close}->{tv_series}+
		   $self->{stats}->{close}->{tv_mini_series}+
		   $self->{stats}->{close}->{tv_movie}+
		   $self->{stats}->{close}->{video_movie}+
		   $self->{stats}->{close}->{video_game});

    
    my $calcHitPercentage=($totalProgramsLookedUp!=0)?(($num_perfect+$num_close)*100)/$totalProgramsLookedUp:0;

    return(sprintf("Checked %d of the %d programs on %d channels in %d input files\n",
		   $totalProgramsLookedUp, $totalProgramsParsed, $totalChannelsParsed, $totalFilesParsed).
	   sprintf("  looked up %d programs, %d failed, got %d perfect hits and %d close hits\n",
		   $totalProgramsLookedUp, $self->{stats}->{failed}, $num_perfect, $num_close).
	   sprintf("  resulting in a %.2f%% hit percentage\n", $calcHitPercentage).
	   sprintf("  parsed %.2f programs/sec and checked %.2f programs/sec\n",
		   $calcProgramsPerSecondParsed, $calcProgramsPerSecondChecked));
}

# moviedbIndex file has the format:
# title:lineno
# where title is url encoded so that different implementations of 'look' work
# (some early bsd versions failed if any entries contained space or tabs)
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
    
    # escape for shell :)
    $match=~s/([\$\"])/\\$1/og;

    $self->debug("cmd: \"$self->{look_cmd} \"$match\" $self->{moviedbIndex} |\"");
    if ( !open(FD, "$self->{look_cmd} \"$match\" $self->{moviedbIndex} |") ) {
	return(undef);
    }
    my $results;
    while (<FD>) {
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
    close(FD);
    #print "MovieMatches on ($match) = ".Dumper($results)."\n";
    return($results);
}

sub getMovieExactMatch($$)
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

    $id=~s/([\$\"])/\\$1/og; #"

    #print "look $id: $self->{moviedbData}\n";
    if ( !open(FD, "$self->{look_cmd} '$id:' $self->{moviedbData} |") ) {
	return(undef);
    }
    my $results;
    while (<FD>) {
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
    close(FD);
    if ( !defined($results) ) {
	# some movies we don't have any details for
	$results->{noDetails}=1;
    }
    #print "MovieDetails($id) = ".Dumper($results)."\n";
    return($results);
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
sub addMovieInfo($$$$)
{
    my ($self, $prog, $title, $year)=@_;
    #my $prog=$$hash_ref;

    # try an exact match first :)
    my $idInfo;

    my $res=$self->getMovieMatches($title, $year);
    if ( defined($res) ) {
	if ( defined($res->{exactMatch})) {
	    $idInfo=$res->{exactMatch}[0];
	    $self->status("perfect hit on \"$title ($year)\"");
	    $self->{stats}->{perfect}->{$idInfo->{qualifier}}++;
	}
	elsif ( defined($res->{closeMatch}) ) {
	    for my $info (@{$res->{closeMatch}}) {
		next if ( !defined($info) );
		print "test close \"$title\" eq \"$info->{title}\"\n";
		if ( lc($title) eq lc($info->{title}) ) {
		    if ( $info->{qualifier} eq "movie" ) {
			$idInfo=$info;
			$self->status("perfect hit on made-for-tv-movie \"$info->{key}\"");
		    }
		    elsif ( $info->{qualifier} eq "tv_movie" ) {
			$idInfo=$info;
			$self->status("perfect hit on made-for-tv-movie \"$info->{key}\"");
		    }
		    elsif ( $info->{qualifier} eq "video_movie" ) {
			$idInfo=$info;
			$self->status("perfect hit on made-for-video-movie \"$info->{key}\"");
		    }
		    elsif ( $info->{qualifier} eq "video_game" ) {
			$self->status("ignoring perfect hit on video-game \"$info->{key}\"");
			next;
		    }
		    elsif ( $info->{qualifier} eq "tv_series" ) {
			$idInfo=$info;
			$self->status("perfect hit on tv series \"$info->{key}\"");
		    }
		    elsif ( $info->{qualifier} eq "tv_mini_series" ) {
			$idInfo=$info;
			$self->status("perfect hit on tv mini-series \"$info->{key}\"");
		    }
		    else {
			$self->error("$self->{moviedbIndex} responded with wierd entry for \"$info->{key}\"");
			$self->error("weird trailing qualifier \"$info->{qualifier}\"");
			$self->error("submit bug report to xmltv-devel\@lists.sf.net");
		    }
		    $self->{stats}->{perfect}->{$info->{qualifier}}++;
		}
	    }
	}
    }

    if ( !defined($idInfo) ) {
	$self->debug("no title/year hit on \"$title ($year)\"");
    }

    # try close hit if only one :)
    if ( !defined($idInfo) ) {

	my $cnt=0;
	my @closeMatches=$self->getMovieCloseMatches("$title");
	
	# we traverse the hits twice, first looking for success,
	# then again to produce warnings about missed close matches
	for my $info (@closeMatches) {
	    next if ( !defined($info) );
	    $cnt++;

	    # within one year with exact match good enough

	    if ( lc($title) eq lc($info->{title}) ) {
		my $yearsOff=abs(int($info->{year})-$year);
		
		if ( $yearsOff <= 2 ) {
		    my $showYear=int($info->{year});

		    if ( $info->{qualifier} eq "movie" ) {
			$idInfo=$info; 
			$self->status("close enough hit on movie \"$info->{key}\" (off by $yearsOff years)");
		    }
		    elsif ( $info->{qualifier} eq "tv_movie" ) {
			$idInfo=$info; 
			$self->status("close enough hit on made-for-tv-movie \"$info->{key}\" (off by $yearsOff years)");
		    }
		    elsif ( $info->{qualifier} eq "video_movie" ) {
			$idInfo=$info;
			$self->status("close enough hit on made-for-video-movie \"$info->{key}\" (off by $yearsOff years)");
		    }
		    elsif ( $info->{qualifier} eq "video_game" ) {
			$self->status("ignoring perfect hit on video-game \"$info->{key}\"");
			next;
		    }
		    elsif ( $info->{qualifier} eq "tv_series" ) {
			$idInfo=$info;
			$self->status("close enough hit on tv series \"$info->{key}\" (off by $yearsOff years)");
		    }
		    elsif ( $info->{qualifier} eq "tv_mini_series" ) {
			$idInfo=$info;
			$self->status("close enough hit on tv mini-series \"$info->{key}\" (off by $yearsOff years)");
		    }
		    else {
			$self->error("$self->{moviedbIndex} responded with wierd entry for \"$info->{key}\"");
			$self->error("weird trailing qualifier \"$info->{qualifier}\"");
			$self->error("submit bug report to xmltv-devel\@lists.sf.net");
		    }
		    $self->{stats}->{close}->{$info->{qualifier}}++;
		    last;
		}
	    }
	}

	# if we found at least something, but nothing matched
	# produce warnings about missed, but close matches
	if ( !defined($idInfo) && $cnt != 0 ) {
	    for my $info (@closeMatches) {
		next if ( !defined($info) );
		$cnt++;

		# within one year with exact match good enough
		if ( lc($title) eq lc($info->{title}) ) {
		    my $yearsOff=abs(int($info->{year})-$year);
		    if ( $yearsOff <= 2 ) {
			die "internal error: key \"$info->{key}\" failed to be processed properly";
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

	if ( $cnt == 0 ) {
	    $self->debug("no close hits on \"$title\"");
	}
    }
    
    if ( defined($idInfo) ) {

	if ( defined($prog->{date}) ) {
	    if ( $prog->{date} ne $idInfo->{year} ) {
		$self->status("updated 'date' field from \"$prog->{date}\" to be \"$idInfo->{year}\" on \"$title\"");
		$prog->{date}=int($idInfo->{year});
	    }
	}
	else {
	    $self->status("added 'date' field (\"$idInfo->{year}\") on \"$title\"");
	    $prog->{date}=int($idInfo->{year});
	}

	my $title=$prog->{title}->[0]->[0];
	if ( $idInfo->{title} ne $title ) {
	    $self->status("updated 'title' from \"$title\" to \"$idInfo->{title}\"");
	    $prog->{title}->[0]->[0]=$idInfo->{title};
	}

	my $categories={'movie'          =>'Movie',
			'tv_movie'       =>'TV Movie', # made for tv
			'video_movie'    =>'Video Movie', # went straight to video or was made for it
			'tv_series'      =>'TV Series',
			'tv_mini_series' =>'TV Mini Series'};
	
	my $mycategory=$categories->{$idInfo->{qualifier}};
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
	    $self->{stats}->{success}++;
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
			    $self->status("updated www.imdb.com url on movie \"$idInfo->{key}\"");
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
		delete($prog->{credits}->{director});
		for my $name (@{$details->{directors}}) {
		    push(@{$prog->{credits}->{director}}, $name);
		}
	    }
	    # add top 3 billing actors list form www.imdb.com
	    if ( defined($details->{actors}) ) {
		delete($prog->{credits}->{actor});
		for my $name (splice(@{$details->{actors}},0,3)) {
		    push(@{$prog->{credits}->{actor}}, $name);
		}
	    }
	    $self->{stats}->{success}++;
	}
	return($prog);
    }
    $self->{stats}->{failed}++;
    $self->status("failed to lookup \"$title ($year)\"");
    
    return($prog);
}

1;

package XMLTV::IMDB::Crunch;

#
# This package parses and manages to index imdb plain text files from
# ftp.imdb.com/interfaces. (see http://www.imdb.com/interfaces for
# details)
#
# I might, given time build a download manager that:
#    - downloads the latest plain text files
#    - understands how to download each week's diffs and apply them
#
# I may also roll this project into a xmltv-free imdb-specific
# perl interface that just supports callbacks and understands more of
# the imdb file formats.
#  - jerry@matilda.com
#

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes

    for ('imdbDir', 'verbose') {
	die "invalid usage - no $_" if ( !defined($self->{$_}));
    }
    if ( ! -d $self->{imdbDir} ) {
	die "$self->{imdbDir}:does not exist" ;
    }
    my $missingListFiles=0;
    for ('movies', 'actors', 'actresses', 'directors') {
	$self->{imdbListFiles}->{$_}="$self->{imdbDir}/lists/$_.list";
	if ( ! -f $self->{imdbListFiles}->{$_} ) {
	    if ( -f "$self->{imdbListFiles}->{$_}.gz" ) {
		$self->{imdbListFiles}->{$_}.=".gz";
	    }
	    else {
		print STDERR "$self->{imdbListFiles}->{$_}.gz: does not exist\n";
		$missingListFiles++;
	    }
	}
    }
    if ( $missingListFiles ) {
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

sub error($$)
{
    print STDERR $_[1]."\n";
}

sub status($$)
{
    if ( $_[0]->{verbose} ) {
	print STDERR $_[1]."\n";
    }
}

sub readMovies($$$)
{
    my ($self, $countEstimate, $file)=@_;
    my $startTime=time();

    if ( $file=~m/\.gz$/o ) {
	open(FD, "gzip -c -d $file |") || return(-2);
    }
    else {
	open(FD, "< $file") || return(-2);
    }
    while(<FD>) {
	if ( m/^MOVIES LIST/o ) {
	    if ( !($_=<FD>) || !m/^===========/o ) {
		$self->error("missing ======= after MOVIES LIST at line $.");
		return(-1);
	    }
	    if ( !($_=<FD>) || !m/^\s*$/o ) {
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

    my $count=0;
    my $percentDone=0;
    while(<FD>) {
	my $line=$_;
	#print "read line $.:$line";

	# end is line consisting of only '-'
	last if ( $line=~m/^\-\-\-\-\-\-\-+/o );

	$line=~s/\n$//o;
	
	my $tab=index($line, "\t");
	if ( $tab != -1 ) {
	    $line=substr($line, 0, $tab);
	    #print "$line\n";
	    #if ( defined($self->{movies}{$line}) ) {
	    #warn "movie ($line) appeared more than once: 2rd appearance at line $.";
	    #}
	    push(@{$self->{movies}}, $line);
	    $count++;

	    my $p=int(($count*100)/$countEstimate);
	    if ( $p ne $percentDone ) {
		$percentDone=$p;
		if ( $percentDone%5 == 0 ) {
		    my $sec=((((time()-$startTime)*100)/$percentDone)*(100-$percentDone))/100;
		    $sec=1 if ($sec < 1);
		    $self->status(sprintf("%d%% done, finished in approx %d seconds ($count movies so far)..",
					  $p, $sec));
		}
	    }
	}
	else {
	    $self->error("no tab in line $.: $line");
	}
    }
    close(FD);
    $self->status(sprintf("Parsed $count movies in %d seconds",time()-$startTime));
    return($count);
}

sub readCastOrDirectors($$$)
{
    my ($self, $whichCastOrDirector, $castCountEstimate, $file)=@_;
    my $startTime=time();

    my $header;
    my $whatAreWeParsing;

    if ( $whichCastOrDirector eq "actors" ) {
	$header="THE ACTORS LIST";
	$whatAreWeParsing=1;
    }
    elsif ( $whichCastOrDirector eq "actresses" ) {
	$header="THE ACTRESSES LIST";
	$whatAreWeParsing=2;
    }
    elsif ( $whichCastOrDirector eq "directors" ) {
	$header="THE DIRECTORS LIST";
	$whatAreWeParsing=3;
    }
    else {
	die "why are we here ?";
    }

    open(FD, "< $file") || return(-2);
    while(<FD>) {
	if ( m/^$header/ ) {
	    if ( !($_=<FD>) || !m/^===========/o ) {
		$self->error("missing ======= after $header at line $.");
		return(-1);
	    }
	    if ( !($_=<FD>) || !m/^\s*$/o ) {
		$self->error("missing empty line after ======= at line $.");
		return(-1);
	    }
	    if ( !($_=<FD>) || !m/^Name\s+Titles\s*$/o ) {
		$self->error("missing name/titles line after ======= at line $.");
		return(-1);
	    }
	    if ( !($_=<FD>) || !m/^[\s\-]+$/o ) {
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
    my $entryCount=0;
    my $castNames=0;
    my $percentDone=0;
    while(<FD>) {
	my $line=$_;
	$line=~s/\n$//o;
	#$self->status("read line $.:$line");
	
	# end is line consisting of only '-'
	last if ( $line=~m/^\-\-\-\-\-\-\-+/o );
	
	next if ( length($line) == 0 );

	if ( $line=~s/^([^\t]+)\t+//o ) {
	    $cur_name=$1;
	    $castNames++;

	    my $p=int(($castNames*100)/$castCountEstimate);
	    if ( $p ne $percentDone ) {
		$percentDone=$p;
		if ( $percentDone%5 == 0 ) {
		    my $sec=((((time()-$startTime)*100)/$percentDone)*(100-$percentDone))/100;
		    $sec=1 if ($sec < 1);
		    $self->status(sprintf("%d%% done, finished in approx %d seconds ($castNames $whichCastOrDirector in $entryCount movies)..",
					  $p, $sec));
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
	$entryCount++;
    }
    close(FD);
    $self->status(sprintf("Parsed $castNames $whichCastOrDirector in $entryCount movies in %d seconds",time()-$startTime));
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


sub crunchStage($)
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

    my $startTime=time();
    if ( $stage == 1 ) {
	$self->status("starting prep stage $stage (parsing movies.list)..");
	my $countEstimate=341000;
	my $num=$self->readMovies($countEstimate, "$self->{imdbListFiles}->{movies}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{movies} from ftp.imdb.com");
	    }
	    $self->status("prep stage $stage failed");
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for movies needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_movie_count", "$num");

	open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	for my $movie (@{$self->{movies}}) {
	    print OUT "$movie\n";
	}
	close(OUT);
    }
    elsif ( $stage == 2 ) {
	$self->status("starting prep stage $stage (parsing directors.list)..");

	$self->status("merging in directors data..");
	my $countEstimate=69000;
	my $num=$self->readCastOrDirectors("directors", $countEstimate, "$self->{imdbListFiles}->{directors}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{directors} from ftp.imdb.com");
	    }
	    $self->status("prep stage $stage failed");
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for directors needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_director_count", "$num");

	open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	for my $key (keys %{$self->{movies}}) {
	    print OUT "$key\t$self->{movies}{$key}\n";
	}
	close(OUT);
	#unlink("$self->{imdbDir}/stage2.data");
    }
    elsif ( $stage == 3 ) {
	$self->status("starting prep stage $stage (parsing actors.list)..");

	#print "re-reading movies into memory for reverse lookup..\n";
	my $countEstimate=430000;
	my $num=$self->readCastOrDirectors("actors", $countEstimate, "$self->{imdbListFiles}->{actors}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{actors} from ftp.imdb.com (see http://www.imdb.com/interfaces)");
	    }
	    $self->status("prep stage $stage failed");
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for actors needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_actor_count", "$num");

	open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	for my $key (keys %{$self->{movies}}) {
	    print OUT "$key\t$self->{movies}{$key}\n";
	}
	close(OUT);
    }
    elsif ( $stage == 4 ) {
	$self->status("starting prep stage $stage (parsing actresses.list)..");

	$self->status("restoring stage 3 data (actors data)..");
	open(IN, "< $self->{imdbDir}/stage3.data") || die "$self->{imdbDir}/stage3.data:$!";
	while(<IN>) {
	    chop();
	    s/^([^\t]+)\t//o;
	    $self->{movies}{$1}=$_;
	}
	close(IN);

	$self->status("merging in actresses data..");
	my $countEstimate=260000;
	my $num=$self->readCastOrDirectors("actresses", $countEstimate, "$self->{imdbListFiles}->{actresses}");
	if ( $num < 0 ) {
	    if ( $num == -2 ) {
		$self->error("you need to download $self->{imdbListFiles}->{actresses} from ftp.imdb.com");
	    }
	    $self->status("prep stage $stage failed");
	    return(1);
	}
	elsif ( abs($num - $countEstimate) > $countEstimate*.05 ) {
	    $self->status("ARG estimate of $countEstimate for actresses needs updating, I read $num");
	}
	$self->dbinfoAdd("db_stat_actress_count", "$num");

	open(OUT, "> $self->{imdbDir}/stage$stage.data") || die "$self->{imdbDir}/stage$stage.data:$!";
	for my $key (keys %{$self->{movies}}) {
	    print OUT "$key\t$self->{movies}{$key}\n";
	}
	close(OUT);
	#unlink("$self->{imdbDir}/stage3.data");
    }
    elsif ( $stage == 5 ) {
	my $tab=sprintf("\t");

	$self->status("starting prep stage $stage (creating indexes..)..");

	$self->status("parsing stage 1 data (movie list)..");
	my %movies;
	open(IN, "< $self->{imdbDir}/stage1.data") || die "$self->{imdbDir}/stage1.data:$!";
	while(<IN>) {
	    chop();
	    $movies{$_}="";
	}
	close(IN);

	$self->status("merging in stage 2 data (directors)..");
	open(IN, "< $self->{imdbDir}/stage2.data") || die "$self->{imdbDir}/stage2.data:$!";
	while(<IN>) {
	    chop();
	    s/^([^\t]+)\t//o;
	    if ( !defined($movies{$1}) ) {
	        $self->error("directors list references unidentified movie '$1'");
	        next;
	    }
	    $movies{$1}=$_;
	}
	close(IN);
	
	# fill in default for movies we didn't have a director for
	for my $key (keys %movies) {
	    if ( !length($movies{$key})) {
		$movies{$key}="nodir";
	    }
	}

	$self->status("merging in stage 4 data (actors and actresses)..");
	open(IN, "< $self->{imdbDir}/stage3.data") || die "$self->{imdbDir}/stage3.data:$!";
	while(<IN>) {
	    chop();
	    s/^([^\t]+)\t//o;
	    if ( !defined($movies{$1}) ) {
	        $self->error("actors or actresses list references unidentified movie '$1'");
	        next;
	    }
	    $movies{$1}.=$tab.$_;
	}
	close(IN);

	#unlink("$self->{imdbDir}/stage1.data");
	#unlink("$self->{imdbDir}/stage2.data");
	#unlink("$self->{imdbDir}/stage3.data");

	#
	# note: not all movies end up with a cast, but we include them anyway.
	#
	
	$self->status("computing indexes..");
	my %nmovies;
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
	    elsif ( $title=~s/\s+\((\d\d\d\d|\?\?\?\?)\)$//o ) {
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

	    #die ("no 1") if ( !defined($title));
	    #die ("no 2") if ( !defined($year));
	    #die ("no 3") if ( !defined($qualifier));
	    #die ("no 4") if ( !defined($directors));
	    #die ("no 5") if ( !defined($actors));
	    
	    $nmovies{$nkey}=$title.$tab.$year.$tab.$qualifier.$tab.$directors.$tab.$actors;
	    #$nmovies{$nkey}=[$title,$year,$qualifier,$directors,$actors];
	}
	if ( scalar(keys %movies) != 0 ) {
	    die "what happened, we have keys left ?";
	}
	undef(%movies);

	$self->status("writing out indexes..");
	open(OUT, "> $self->{moviedbIndex}") || die "$self->{moviedbIndex}:$!";
	open(ACT, "> $self->{moviedbData}") || die "$self->{moviedbData}:$!";
	my $num=1;
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
		# sort actors by billing
		for my $c (sort {$a cmp $b} split('\|', $actors)) {
		    my ($billing, $name)=split(':', $c);
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
	    my $lineno=sprintf("%07d", $num);
	    print OUT "$key\t$title\t$year\t$qualifier\t$lineno\n";
	    print ACT "$lineno:$details\n";
	    $num++;
	}
	close(ACT);
	close(OUT);

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
	$self->error("tv_imdb: invalid stage $stage: only 1-4 are valid");
	$self->status("prep stage $stage failed");
	return(1);
    }

    $self->dbinfoAdd("seconds_to_complete_prep_stage_$stage", (time()-$startTime));
    if ( $self->dbinfoSave() ) {
	$self->error("$self->{moviedbInfo}:$!");
	return(1);
    }
    $self->status("prep stage $stage success");
    return(0);
}

1;
