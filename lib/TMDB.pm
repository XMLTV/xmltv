#
# Author: Geoff Westcott, 2021
# (based on IMDB.pm  Author: Jerry Veldhuis)
#

use strict;
use warnings;

package XMLTV::TMDB;

#
# CHANGE LOG
# 0.1 = development version (no public release)
# 0.2 = change API calls to use 'append_to_response' to reduce number of calls
# 0.3 = added content-ids to output xml
# 0.4 = added <image> and <url> elements to cast & crew
#       added <image> to programme (in place of <url>)
#       min version of XMLTV.pm is > 1.0.0
#
our $VERSION = '0.4';


use LWP::Protocol::https;
use HTTP::Response;

use Data::Dumper qw(Dumper);

#---------------------------------------------------------------
use XMLTV 1.0.1;        # min version of xmltv.pm required
use XMLTV::TMDB::API;
# version 0.04 of WWW::TMDB::API is broken for movie searching (TMDB changed the API with a breaking change)
# a custom version was created for use here
# - redeclare the search() method with correct path "movie" instead of "movies"
# - also add the year as a search param
# - also casts() is now called 'credits'
# - also images() : add the image_language (c.f. https://www.themoviedb.org/talk/583238a6c3a3685ba1032b0e )
# - add new method configuration() to fetch API config data
#---------------------------------------------------------------

sub error($$)
{
	print STDERR "tv_tmdb: $_[1]\n";
}

sub status($$)
{
	if ( $_[0]->{verbose} ) {
		print STDERR "tv_tmdb: $_[1]\n";
	}
}

sub debug($$)
{
	my $self=shift;
	my $mess=shift;
	if ( $self->{verbose} > 1 ) {
		print STDERR "tv_tmdb: $mess\n";
	}
}

sub debugmore($$$)
{
	my $self=shift;
	my $level=shift;
	my $mess=shift;
	my $dump=shift;
	if ( $self->{verbose} >= $level ) {
		print STDERR "tv_tmdb: " . (split(/::/,(caller(1))[3]))[-1] . ' : ' . $mess . " = \n" . Dumper($dump);
	}
}

sub unique (@)			# de-dupe two (or more) arrays   TODO: make this case insensitive
{
    # From CPAN List::MoreUtils, version 0.22
    my %h;
    map { $h{$_}++ == 0 ? $_ : () } @_;
}
sub uniquemulti (@)		# de-dupe two (or more) array of arrays on first value   TODO: make this case insensitive
{
    my %h;
    map { $h{$_->[0]}++ == 0 ? $_ : () } @_;
}

#---------------------------------------------------------------------

# constructor
#
sub new
{
	my ($type) = shift;
	my $self={ @_ };			# remaining args become attributes

	$self->{wwwUrl} = 'https://www.themoviedb.org/';

	for ('apikey', 'verbose') {
		die "invalid usage - no $_" if ( !defined($self->{$_}));
	}
	$self->{replaceDates}=0			if ( !defined($self->{replaceDates}));
	$self->{replaceTitles}=0		if ( !defined($self->{replaceTitles}));
	$self->{replaceCategories}=0	if ( !defined($self->{replaceCategories}));
	$self->{replaceKeywords}=0		if ( !defined($self->{replaceKeywords}));
	$self->{replaceURLs}=0		 	if ( !defined($self->{replaceURLs}));
	$self->{replaceDirectors}=1		if ( !defined($self->{replaceDirectors}));
	$self->{replaceActors}=0		if ( !defined($self->{replaceActors}));
	$self->{replacePresentors}=1	if ( !defined($self->{replacePresentors}));
	$self->{replaceCommentators}=1	if ( !defined($self->{replaceCommentators}));
	$self->{replaceGuests}=1		if ( !defined($self->{replaceGuests}));
	$self->{replaceStarRatings}=0	if ( !defined($self->{replaceStarRatings}));
	$self->{replaceRatings}=0		if ( !defined($self->{replaceRatings}));
	$self->{replacePlot}=0			if ( !defined($self->{replacePlot}));
	$self->{replaceReviews}=0		if ( !defined($self->{replaceReviews}));

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
	$self->{updateGuests}=1			if ( !defined($self->{updateGuests}));
	$self->{updateStarRatings}=1	if ( !defined($self->{updateStarRatings}));
	$self->{updateRatings}=1		if ( !defined($self->{updateRatings}));			# add programme's classification (MPAA/BBFC etc)
	$self->{updatePlot}=0			if ( !defined($self->{updatePlot}));			# default is to NOT add plot
	$self->{updateReviews}=1		if ( !defined($self->{updateReviews}));			# default is to add reviews
	$self->{updateRuntime}=1		if ( !defined($self->{updateRuntime}));			# add programme's runtime
	$self->{updateActorRole}=1		if ( !defined($self->{updateActorRole}));		# add roles to cast in output
	$self->{updateImage}=1			if ( !defined($self->{updateImage}));			# add programme's poster image
	$self->{updateCastImage}=1		if ( !defined($self->{updateCastImage}));		# add image url to actors and directors (needs updateActors/updateDirectors)
	$self->{updateCastUrl}=1		if ( !defined($self->{updateCastUrl}));			# add url to actors and directors webpage (needs updateActors/updateDirectors)
	$self->{updateContentId}=1		if ( !defined($self->{updateContentId}));		# add programme's id

	$self->{numActors}=3			if ( !defined($self->{numActors}));		 		# default is to add top 3 actors
	$self->{numReviews}=1			if ( !defined($self->{numReviews}));			# default is to add top 1 review
	$self->{removeYearFromTitles}=1	if ( !defined($self->{removeYearFromTitles}));	# strip trailing "(2021)" from title
	$self->{getYearFromTitles}=1	if ( !defined($self->{getYearFromTitles}));		# if no 'date' incoming then see if title ends with a "(year)"
	$self->{moviesonly}=0			if ( !defined($self->{moviesonly}));			# default to augment both movies and tv
	$self->{minVotes}=50			if ( !defined($self->{minVotes}));				# default to needing 50 votes before 'star-rating' value is accepted


	# default is not to cache lookups
	$self->{cacheLookups}=0 		if ( !defined($self->{cacheLookups}) );
	$self->{cacheLookupSize}=0 		if ( !defined($self->{cacheLookupSize}) );

	$self->{cachedLookups}->{tv_series}->{_cacheSize_}=0;

	bless($self, $type);


	# stats counters
	$self->{categories}={'movie'		  	=>'Movie',
					#	 'tv_movie'			=>'TV Movie', 		# made for tv
					#	 'video_movie'		=>'Video Movie',	# went straight to video or was made for it
						 'tv_series'	  	=>'TV Series',
					#	 'tv_mini_series' 	=>'TV Mini Series'
						};
						
		# note there is no 'qualifier' in TMDB data - we only have either 'movie' or 'tv'
				
	$self->{stats}->{programCount}=0;

	for my $cat (keys %{$self->{categories}}) {
		$self->{stats}->{perfect}->{$cat}=0;
		$self->{stats}->{close}->{$cat}=0;
	}
	$self->{stats}->{perfectMatches}=0;
	$self->{stats}->{closeMatches}=0;

	$self->{stats}->{startTime}=time();


	#print STDERR Dumper($self); die();

	return($self);
}



#-----------------------------------------------------------------------------------------#
#-----------------------------------------------------------------------------------------#
# The methods below follow their equivalents in IMDB.pm to simplify future maintenance.   #
#   So we keep the names the same even though they may not be strictly accurate.          #
#   Some methods aren't applicable to the TMDB lookup but we keep them anyway.            #
#-----------------------------------------------------------------------------------------#
#-----------------------------------------------------------------------------------------#

# not applicable in this package
#
sub checkIndexesOkay($)
{
	my $self=shift;
	
	# nothing to do here
	return(undef);
}

# check that the tmdb api is up and running by fetching a known-to-exist programme
#
sub basicVerificationOfIndexes($)
{
	my $self=shift;

	# check that the tmdb api is up and running by fetching a known-to-exist programme
	my $title="Army of Darkness";
	my $year=1992;
	
	$self->openMovieIndex() || return("basic verification of api failed\n".
					  "api is not accessible");

	# tempo hide the verbose setting while we fetch the test movie
	my $verbose = $self->{verbose}; $self->{verbose} = 0;
	my $res = $self->getMovieMatches($title, $year);
	$self->{verbose} = $verbose; undef $verbose;
	
	# there is less to do here than with IMDB.pm as we don't need to check on the database build
	# so a simple check that the API is accessible (i.e. api_key is valid) and returns the movie
	# we expect will be sufficient
	
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
	if ( scalar(@{$res->{exactMatch}})!= 1) {			# we expect only 1 matching hit for the test movie
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "got more than one exact match for movie \"$title, $year\"\n");
	}
	if ( @{$res->{exactMatch}}[0]->{year} ne "$year" ) {
		$self->closeMovieIndex();
		return("basic verification of indexes failed\n".
			   "year associated with key \"$title, $year\" is bad\n");
	}

	$self->closeMovieIndex();
	
	# all okay
	return(undef);
}

# check the api is accessible
#
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

# instantiate a TMDB::API object
#
sub openMovieIndex($)
{
	my $self=shift;
	
	my $tmdb_client = XMLTV::TMDB::API->new( 'api_key' => $self->{apikey}, 'ua' => LWP::UserAgent->new( 'agent' => "XMLTV-TMDB-API/$VERSION"), 'soft' => 1 );
	
	# force https
	$tmdb_client->{url} =~ s/^http:/https:/;
        
	$self->{tmdb_client} = $tmdb_client;
	
	return(1);
}

# destroy the TMDB::API object
#
sub closeMovieIndex($)
{
	my $self=shift;

	undef $self->{tmdb_client};

	return(1);
}


# strip some punctuation from the title
#  be conservative with this: we're really only looking at periods, 
#  so that "Dr. Who" and "Dr Who" are treated as equal
#
# TODO: we need to match incoming accented chars with unaccented input
#         e.g. tmdb "Amélie" does not match (line 441) if xml is "Amelie" (no accent)
#
sub tidy($$)
{
	my $self=shift;
	my $title=shift;
	
	# actions:
	#  1. strip periods, commas, apostrophes, quotes, colons, semicolons, hyphen
	#  2. strip articles: the, le, la, das
	#  3. strip year (e.g. " (2005)"
	#  4-5. tidy spaces
	#  6. lowercase
	
	$title =~ s/[\.,'":;\-]//g;
	$title =~ s/\b(the|le|la|das)\b//ig;		# TODO: add others?
	$title =~ s/\s+\((19|20)\d\d\)\s*$//;
	$title =~ s/(^\s+)|(\s+$)//;
	$title =~ s/\s+/ /g;
	return lc($title);
}


# check the fetch reply from the API
#
sub checkHttpError($$)
{
	my $self=shift;
	my $uaresult=shift;
	
	my $res = @{$uaresult}[0];
	my $uaresponse = @{$uaresult}[1];
	
	$self->debugmore(5, "ua response", $uaresponse);
	
	if ( $uaresponse->{code} == 401 ) {
		$self->error("TMDB said 'Unauthorised' : is your apikey correct? : cannot continue");
		exit(1);			# TODO: more graceful exit!
	} 
	elsif ( $uaresponse->{code} >= 500 ) {
		$self->error("TMDB said '$uaresponse->{msg}' : cannot continue");
		exit(1);			# TODO: more graceful exit!
	}
	elsif ( $uaresponse->{code} == 429 ) {	# HTTP_TOO_MANY_REQUESTS
		$self->error("TMDB said '$uaresponse->{msg}' : cannot continue");
		exit(1);			# TODO: more graceful exit!
	}
	elsif ( $uaresponse->{code} >= 400 ) {
		$self->status("TMDB said '$uaresponse->{msg}' : will try to continue");
	}
	
	return $res;
}


# get matches (either movie or tv) from TMDB using title + year (optional)
#
# TODO: handle paged results (but not seen any yet)
#
sub getSearchMatches($$$)
{
	my $self=shift;
	my $title=shift;
	my $year=shift;
	my $type=shift;
	
	# strip year from the title, if present
	($title,my $junk,my $titleyear) = $title =~ m/^(.*?)(\s+\(((19|20)\d\d)\))?$/; 
	#
	$year = '' if !defined $year;			# note: don't override tha param year or else 'close matches' won't work
	
	$self->debug("looking for $type \"$title\" ".($year ne ''?"+ $year ":'')."") 	if $type eq 'movie';
	$self->debug("looking for $type \"$title\"") 									if $type eq 'tv';
	
	# lookup TMDB
	my $matches;
	$matches = $self->checkHttpError( $self->{tmdb_client}->$type->search( query => $title, year => $year ) ) 	if $type eq 'movie';
	$matches = $self->checkHttpError( $self->{tmdb_client}->$type->search( query => $title ) )					if $type eq 'tv';
	
	
	# API.pm returns a Perl data structure from the JSON reply
	#
    #--------------------------------------------------------------------------------------------
	# MOVIE
	#	{
    #      'total_pages' => 1,
    #      'total_results' => 1,
    #      'page' => 1,
    #      'results' => [
    #                     {
    #                       'original_language' => 'en',
    #                       'video' => bless( do{\(my $o = 0)}, 'JSON::PP::Boolean' ),
    #                       'release_date' => '1992-10-31',
    #                       'vote_count' => 2247,
    #                       'genre_ids' => [
    #                                        14,
    #                                        27,
    #                                        35
    #                                      ],
    #                       'original_title' => 'Army of Darkness',
    #                       'vote_average' => '7.3',
    #                       'overview' => 'Ash is transported back to medieval days, where he is captured by the dreaded Lord Arthur. Aided by the deadly chainsaw that has become his only friend, Ash is sent on a perilous mission to recover the Book of the Dead, a powerful tome that gives its owner the power to summon an army of ghouls.',
    #                       'popularity' => '18.055',
    #                       'poster_path' => '/mOsWtjRGABrPrqqtm0U6WQp4GVw.jpg',
    #                       'title' => 'Army of Darkness',
    #                       'backdrop_path' => '/5Tfj9mbCq8KzJZ1cnPEWPhqecI7.jpg',
    #                       'id' => 766,
    #                       'adult' => $VAR1->{'results'}[0]{'video'}
    #                     }
    #                   ]
    #    };
    #--------------------------------------------------------------------------------------------
    # TV SERIES
	#	{
	#		"total_pages": 1,
	#		"total_results": 14
	#		"page": 1,
	#		"results": [
	#			{
	#				"backdrop_path": "/sRfl6vyzGWutgG0cmXmbChC4iN6.jpg",
	#				"first_air_date": "2005-03-26",
	#				"genre_ids": [
	#					10759,
	#					18,
	#					10765
	#				],
	#				"id": 57243,
	#				"name": "Doctor Who",
	#				"origin_country": [
	#					"GB"
	#				],
	#				"original_language": "en",
	#				"original_name": "Doctor Who",
	#				"overview": "The Doctor is a Time Lord: a 900 year old alien with 2 hearts, part of a gifted civilization who mastered time travel. The Doctor saves planets for a living—more of a hobby actually, and the Doctor's very, very good at it.",
	#				"popularity": 169.084,
	#				"poster_path": "/sz4zF5z9zyFh8Z6g5IQPNq91cI7.jpg",
	#				"vote_average": 7.3,
	#				"vote_count": 2225
	#			},
    #--------------------------------------------------------------------------------------------


	my $results;

	foreach my $match (@{ $matches->{results} }) {
		
		my $airdate;
		$airdate = $match->{release_date}	if $type eq 'movie';
		$airdate = $match->{first_air_date}	if $type eq 'tv';
		$airdate = '' if !defined $airdate;
		
		(my $yr) = $airdate =~ m/^((19|20)\d\d)/;
		$yr = '' if !defined $yr || $yr eq '1900';		# TMDB says: "If you see a '1900' referenced on a movie, that means that no release date has been added."

		my ($progtitle,$progtitle_alt);
		$progtitle 		= $match->{title}			if $type eq 'movie';
		$progtitle 		= $match->{name}			if $type eq 'tv';
		$progtitle_alt 	= $match->{original_title}	if $type eq 'movie';
		$progtitle_alt 	= $match->{original_name}	if $type eq 'tv';


		# year must match for an "exact" match
		#
		# TODO: title match will fail if incoming title is missing accented character
		#         e.g. if incoming title is "Amelie" - tmdb is "Amélie" and therefore won't match
		#       an ugly fudge would be to tempo convert TMDB accented chars to basic character for comparison purposes
		#         (c.f. the code block "convert all the special language characters" in alternativeTitles()
		#
		if ( ( $self->tidy($progtitle) eq $self->tidy($title) || $self->tidy($progtitle_alt) eq $self->tidy($title) )
		 && ( $yr eq $year && $year ne '' ) && $type eq 'movie' ) {		# return all tv matches as 'close' not 'exact'
			
			$self->debug("exact: \"$progtitle\" $yr  [$match->{id}]");
			
			push(@{$results->{exactMatch}}, {'key'		=> $title,
											 'title'	=> $progtitle,
											 'year'		=> $yr,
											 'qualifier'=> ($type eq 'tv' ? 'tv_series' : $type),
											 'type'		=> $type,
											 'id'		=> $match->{id},
											 'lang'		=> $match->{original_language}		# might this be different to the language of the current title?
											 });
		}
		else {
			
			$self->debug("close: \"$progtitle\" $yr  [$match->{id}]");
			
			push(@{$results->{closeMatch}}, {'key'		=> $title,
											 'title'	=> $progtitle,
											 'year'		=> $yr,
											 'qualifier'=> ($type eq 'tv' ? 'tv_series' : $type),
											 'type'		=> $type,
											 'id'		=> $match->{id},
											 'lang'		=> $match->{original_language}
											 });
		}
	}
	
	$self->debugmore(4,'search results',$results);
	
	return($results);
}


# get movie matches from TMDB using title + year (optional)
#
sub getMovieMatches($$$)
{
	my $self=shift;
	my $title=shift;
	my $year=shift;
	
	return $self->getSearchMatches($title, $year, 'movie');
}


# get tv matches from TMDB using title + year (optional)
#
sub getTvMatches($$$)
{
	my $self=shift;
	my $title=shift;
	my $year=shift;
	
	return $self->getSearchMatches($title, $year, 'tv');
}


# get movie matches from TMDB - look for a single hit - match on title + year
#
sub getMovieExactMatch($$$)
{
	my $self=shift;
	my $title=shift;
	my $year=shift;
	
	$self->debug("looking for exact match");
	my $res=$self->getMovieMatches($title, $year);
	
	$self->debugmore(3,'matches',$res);

	return(undef, 0) if ( !defined($res) );
	
	if ( !defined($res->{exactMatch}) ) {
		return( undef, 0 );
	}
	if ( scalar(@{$res->{exactMatch}}) < 1 ) {
		return( undef, scalar(@{$res->{exactMatch}}) );
	}

	$self->debugmore(2,'match',$res->{exactMatch});
		
	return( $res->{exactMatch}, scalar(@{$res->{exactMatch}}) );
}


# get movie matches from TMDB - match on title only (no year)
#
sub getMovieCloseMatches($$)
{
	my $self=shift;
	my $title=shift;

	$self->debug("looking for close match");
	my $res=$self->getMovieMatches($title, undef);
	
	$self->debugmore(4,'matches',$res);

	if ( defined($res->{exactMatch})) {
		$self->status("unexpected exact match on movie \"$title\"");
	}
	return( undef, 0 ) if ( !defined($res->{closeMatch}) );
	
	$self->debugmore(3,'match',$res->{closeMatch});

	return( $res->{closeMatch}, scalar(@{$res->{closeMatch}}) );
}


# get Tv matches from TMDB - match on title only (no year)
#
sub getTvCloseMatches($$)
{
	my $self=shift;
	my $title=shift;

	$self->debug("looking for close match");
	my $res=$self->getTvMatches($title, undef);
	
	$self->debugmore(4,'matches',$res);

	if ( defined($res->{exactMatch})) {
		$self->status("unexpected exact match on tv \"$title\"");
	}
	return( undef, 0 ) if ( !defined($res->{closeMatch}) );
	
	$self->debugmore(3,'match',$res->{closeMatch});
	
	return( $res->{closeMatch}, scalar(@{$res->{closeMatch}}) );
}


# BUG - we identify 'presenters' by the word "Host" appearing in the character
#		description. For some movies, character names include the word Host.
#		ex. Animal, The (2001) has a character named "Badger Milk Host".
#
sub getMovieOrTvIdDetails($$$)
{
	my $self=shift;
	my $id=shift;
	my $type=shift;
	
	# get the API configuration from TMDB if we don't already have it
	#
	$self->{tmdb_conf} = $self->checkHttpError( $self->{tmdb_client}->config->configuration() );
	#
	# set base url for actor/director images
	my $profile_base = $self->{tmdb_conf}->{images}->{base_url} . $self->{tmdb_conf}->{images}->{profile_sizes}[1];		# arbitrarily pick the second one (expecting w185 = 185x278 )	
	#
	# set base url for movie poster images
	my $poster_base     = $self->{tmdb_conf}->{images}->{base_url} . $self->{tmdb_conf}->{images}->{poster_sizes}[4];	# arbitrarily pick the fifth one (expecting w500 = 500x750 )
	my $backdrop_base   = $self->{tmdb_conf}->{images}->{base_url} . $self->{tmdb_conf}->{images}->{backdrop_sizes}[1];	# arbitrarily pick the second one (expecting w780 = 780x439 )
	# smaller versions:
	my $poster_base_s   = $self->{tmdb_conf}->{images}->{base_url} . $self->{tmdb_conf}->{images}->{poster_sizes}[0];	# arbitrarily pick the first one (expecting w92 = 92x138 )
	my $backdrop_base_s = $self->{tmdb_conf}->{images}->{base_url} . $self->{tmdb_conf}->{images}->{backdrop_sizes}[0];	# arbitrarily pick the first one (expecting w300 = 300x169 )
	
	
	# get the movie details from TMDB
	#
	my $tmdb_info;
	
	# v0.1 method-> $tmdb_info = $self->checkHttpError( $self->{tmdb_client}->$type->info( ID => $id ) );
	
	# note different path for release_dates vs content_ratings
	$tmdb_info = $self->checkHttpError( $self->{tmdb_client}->$type->info( ID => $id, append_to_response => 'keywords,credits,release_dates,reviews' ) ) if ( $type eq 'movie' );
	$tmdb_info = $self->checkHttpError( $self->{tmdb_client}->$type->info( ID => $id, append_to_response => 'keywords,credits,content_ratings,reviews' ) ) if ( $type eq 'tv' );
	
	
	
	my $results;		# response to be returned to caller
	
	# let's replicate what IMDB.pm retrieved :
	#    ($directors, $actors, $genres, $ratingDist, $ratingVotes, $ratingRank, $keywords, $plot); also $presenter, $commentator
	
	$results->{ratingVotes} 	= $tmdb_info->{vote_count} 		if defined $tmdb_info->{vote_count};
	$results->{ratingRank} 		= $tmdb_info->{vote_average} 	if defined $tmdb_info->{vote_average} && $tmdb_info->{vote_average} > 0;
	$results->{plot} 			= $tmdb_info->{overview} 		if defined $tmdb_info->{overview};
	
	
	foreach my $genre (@{ $tmdb_info->{genres} }) {
		push(@{$results->{genres}}, $genre->{name});
	}
	
	
	# get the keywords
	# v0.1 method->  my $tmdb_keywords = $self->checkHttpError( $self->{tmdb_client}->$type->keywords( ID => $id ) );   # $tmdb_keywords->{keywords}
	#
	my $tmdb_keywords = $tmdb_info->{keywords};
	#
	if ( defined $tmdb_keywords->{keywords} ) { 
		foreach my $keyword (@{ $tmdb_keywords->{keywords} }) {
			push(@{$results->{keywords}}, $keyword->{name});
		}
	}
	
	
	# get the credits  (cast and crew)
	# v0.1 method->  my $tmdb_credits = $self->checkHttpError( $self->{tmdb_client}->$type->credits( ID => $id ) );		# $tmdb_credits->{cast} & $tmdb_credits->{crew}
	#
	my $tmdb_credits = $tmdb_info->{credits};
	#
	# TMDB seems to return the list pre-sorted by 'order', which is nice
	#
	if ( defined $tmdb_credits->{cast} ) {
		foreach my $cast (@{ $tmdb_credits->{cast} }) {
			# 
			if ( defined $cast->{character} && $cast->{character}=~m/Host|Presenter/ ) {
				push(@{$results->{presenter}}, $cast->{name}); }
			elsif 
			   ( defined $cast->{character} && $cast->{character}=~m/Narrator|Commentator/ ) {
				push(@{$results->{commentator}}, $cast->{name}); }
			elsif 
			   ( defined $cast->{character} && $cast->{character}=~m/Guest/ ) {
				push(@{$results->{guest}}, $cast->{name}); }
			else {
				push(@{$results->{actors}}, $cast->{name});			# use this to keep consistency with TMDB
			}
			#
			#
			# note in TMDB an actor can appear twice with different 'character'. See Chris Shields in Christmas Joy (2018) : character1 = 'Chris Andrews', character2='Dr. Walsh'.  We should concatenate these if outputting 'character' attribute.
			#
			my $found=0;
			if ( defined $cast->{character} && $cast->{character} ne '' && defined $results->{actorsplus} ) {
				
				# find the matching array entry
				my @list = @{ $results->{actorsplus} };
				for (my $i=0; $i < scalar @list; $i++) {
					my $h = $list[$i];
					if ( $h->{id} eq $cast->{id} ) {
						# already in list, so concatenate 'character's
						@{$results->{actorsplus}}[$i]->{'character'} .= '/'. $cast->{character};
						$found=1;
						last;
					}
				}
	
			}		
			# this is a new entry - just add it to actors' list	
			if (!$found) 
			{	
				push(@{$results->{actorsplus}}, { 	'name'		=>$cast->{name}, 
													'id'		=>$cast->{id},
													'character'	=>$cast->{character},
													'order'		=>$cast->{order},
													'imageurl'	=>(defined $cast->{profile_path} ? $profile_base.$cast->{profile_path} : '')
												} );				# use this to add TMDB unique data
			}
			
		}
	}
					
	if ( defined $tmdb_credits->{crew} ) {
		foreach my $crew (@{ $tmdb_credits->{crew} }) {
			# 
			if ( $crew->{job}=~m/^Director$/ ) {					# this may be too strict but we must avoid "Director of Photography" etc
				push(@{$results->{directors}}, $crew->{name});		# use this to keep consistency with TMDB
				#
				push(@{$results->{directorsplus}}, {'name'		=>$crew->{name}, 
													'id'		=>$crew->{id},
													'job'		=>$crew->{job},
													'order'		=>$crew->{order},
													'imageurl'	=>(defined $crew->{profile_path} ? $profile_base.$crew->{profile_path} : '')
													} );			# use this to add TMDB unique data
			}
		}
	}
	
	
	# get the classification
	if ( $type eq 'movie' ) {
		
		# v0.1 method->  my $tmdb_classifications = $self->checkHttpError( $self->{tmdb_client}->$type->release_dates( ID => $id ) );	# $tmdb_classifications->{results}
		#
		my $tmdb_classifications = $tmdb_info->{release_dates};
		#
		if ( defined $tmdb_classifications->{results} ) { 
			foreach my $classification (@{ $tmdb_classifications->{results} }) {
				# just get US,CA,GB
				# TODO: select based on user's country code (somehow)
				my %lookup = map { $_ => undef } qw( US CA GB );
				if ( exists $lookup{ $classification->{iso_3166_1} } ) {
					
					my $rating;
					my $i=0;
					
					foreach my $release (@{ $classification->{release_dates} }) {
						$i++;
						#
						# TMDB has various 'types' of classification (premiere, theatrical, tv, etc)
						#   which one to use?
						# Let's go for type=1 "Premiere", or if missing then just grab the first in the list
						if ( $release->{type} == 1 || $i == 1 ) {
							$rating = $release->{certification}  if $release->{certification} ne '';
						}
					}
					if ( $rating ) {		# sometimes the field is empty!
						push(@{$results->{classifications}}, {'system'		=>$classification->{iso_3166_1},
															  'rating'		=>$rating
															 } );
					}
				}
			}
		}
		
	} else {
		
		# v0.1 method->  my $tmdb_classifications = $self->checkHttpError( $self->{tmdb_client}->$type->content_ratings( ID => $id ) );
		#
		my $tmdb_classifications = $tmdb_info->{content_ratings};
		#
		if ( defined $tmdb_classifications->{results} ) { 
			foreach my $classification (@{ $tmdb_classifications->{results} }) {
				# just get US,CA,GB
				# TODO: select based on user's country code (somehow)
				my %lookup = map { $_ => undef } qw( US CA GB );
				if ( exists $lookup{ $classification->{iso_3166_1} } ) {
					if ( $classification->{rating} ne '' ) {
						push(@{$results->{classifications}}, {'system'		=>$classification->{iso_3166_1},
															  'rating'		=>$classification->{rating}
														  } );
					}
				}
			}
		}
		
	}
	
	
	# get the reviews
	# v0.1 method->  my $tmdb_keywords = $self->checkHttpError( $self->{tmdb_client}->$type->reviews( ID => $id ) ); 
	#
	my $tmdb_reviews = $tmdb_info->{reviews};
	#
	if ( defined $tmdb_reviews->{results} ) { 
		foreach my $review (@{ $tmdb_reviews->{results} }) {
			push(@{$results->{reviews}},  {'author'		=>$review->{author},
										   'content'	=>$review->{content},
										   'date'		=>$review->{created_at},
										   'url'		=>$review->{url}
										  } );
		}
	}
	

	
	# new stuff not in IMDB.pm
	#
	$results->{runtime} 			= $tmdb_info->{runtime} 						if defined $tmdb_info->{runtime} && $tmdb_info->{runtime} > 0;
	$results->{tmdb_id} 			= $tmdb_info->{id} 								if defined $tmdb_info->{id};
	$results->{imdb_id} 			= $tmdb_info->{imdb_id} 						if defined $tmdb_info->{imdb_id};
	$results->{posterurl} 			= $poster_base.$tmdb_info->{poster_path} 		if defined $tmdb_info->{poster_path};
	$results->{backdropurl} 		= $backdrop_base.$tmdb_info->{backdrop_path} 	if defined $tmdb_info->{backdrop_path};
	$results->{posterurl_sm} 		= $poster_base_s.$tmdb_info->{poster_path} 		if defined $tmdb_info->{poster_path};
	$results->{backdropurl_sm} 		= $backdrop_base_s.$tmdb_info->{backdrop_path} 	if defined $tmdb_info->{backdrop_path};
	
		
	if ( !defined($results) ) {
		# some movies we don't have any details for
		$results->{noDetails}=1;
	}

	return($results);
}


# make some possible alternative titles (spelling, punctuation, etc)
#  (these probably aren't necessary for TMDB which seems to cater for these alternatives automagically)
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

	# deprecated - not required for TMDB
	# # Place the articles last
	# $max=scalar(@titles);
	# for (my $i=0; $i<$max ; $i++) {
	# 	my $t=$titles[$i];
	# 	if ( $t=~m/^(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)\s+(.*)$/io ) {
	# 		$t=~s/^(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)\s+(.*)$/$2, $1/iog;
	# 		push(@titles, $t);
	# 	}
	# 	if ( $t=~m/^(.+),\s*(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)$/io ) {
	# 		$t=~s/^(.+),\s*(The|A|Une|Les|Los|Las|L\'|Le|La|El|Das|De|Het|Een)$/$2 $1/iog;
	# 		push(@titles, $t);
	# 	}
	# }

	# deprecated - not required for TMDB
	# # convert all the special language characters
	# $max=scalar(@titles);
	# for (my $i=0; $i<$max ; $i++) {
	# 	my $t=$titles[$i];
	# 	if ( $t=~m/[ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÆæÇçÑñßÝýÿ]/io ) {
	# 		$t=~s/[ÀÁÂÃÄÅàáâãäå]/a/gio;
	# 		$t=~s/[ÈÉÊËèéêë]/e/gio;
	# 		$t=~s/[ÌÍÎÏìíîï]/i/gio;
	# 		$t=~s/[ÒÓÔÕÖØòóôõöø]/o/gio;
	# 		$t=~s/[ÙÚÛÜùúûü]/u/gio;
	# 		$t=~s/[Ææ]/ae/gio;
	# 		$t=~s/[Çç]/c/gio;
	# 		$t=~s/[Ññ]/n/gio;
	# 		$t=~s/[ß]/ss/gio;
	# 		$t=~s/[Ýýÿ]/y/gio;
	# 		$t=~s/[¿]//gio;
	# 		push(@titles, $t);
	# 	}
	# }
	
	# later possible titles include removing the '.' from titles
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


# find matching movie records on TMDB
# $exact = 1 : exact matches on movies - needs title & year
# $exact = 2 : exact matches on movies - title only
# else       : close matches on movies - needs title & year
#		
# TODO: partial matching, e.g. "Cuckoos Nest" should match with "One Flew over the Cuckoos Nest"
#
sub findMovieInfo($$$$$)
{
	my ($self, $title, $prog, $year, $exact)=@_;

	my @titles=@{alternativeTitles($title)};
	
	$self->debugmore(3,'altvetitles',\@titles);


	if ( $exact == 1 ) {
		# looking for an exact match on title + year

		for my $mytitle ( @titles ) {
			
			# look-up TMDB
			my ($info, $matchcount) = $self->getMovieExactMatch($mytitle, $year);
			
			if ($matchcount > 1) {
				# if multiple records exactly match title+year then we don't know which one is correct
				
				# see if we can match Director (c.f. "Chaos" (2005) or "20,000 Leagues Under the Sea" (1997) )
				if ( defined $prog->{credits}->{director} ) {
					
					my @infonew; my $found=0;
		
					DIRCHK: foreach my $infoeach (@$info) {

						my $tmdb_credits = $self->checkHttpError( $self->{tmdb_client}->movie->credits( ID => $infoeach->{id} ) );		# $tmdb_credits->{cast} & {crew}
						
						if ( defined $tmdb_credits->{crew} ) {
							
							foreach my $director ( @{ $prog->{credits}->{director} } ) {
								
								if ( scalar ( grep { lc($_->{job}) eq 'director' && $self->tidy($_->{name}) eq $self->tidy($director) } @{ $tmdb_credits->{crew} } ) >0 ) {
									# TODO: of course this will break if the same director directed BOTH films (but how likely is that?)
									$found = 1;
									push (@infonew, $infoeach);
									last DIRCHK;
								}
							
							}
							
						}
						
					}
					
					( $info, $matchcount ) = ( \@infonew, 1 )  if $found;	# reset the search result to just this one match
					
				}
				
				if ($matchcount > 1) {
					$self->status("multiple hits on movie \"$mytitle\" (".($year eq ''?'-':$year).")");
					return(undef, $matchcount);
				}
			}
			
			if ($matchcount == 1) {
				if ( defined($info) ) {
					$info = @$info[0];
					if ( $info->{qualifier} eq "movie" ) {
						$self->status("perfect hit on movie \"$info->{title}\" [$info->{id}]");
						$info->{matchLevel}="perfect";
						return($info);
					}
					# note there is no 'qualifier' in TMDB data - we only have either 'movie' or 'tv'
				}
			}
			$self->status("no exact title/year hit on \"$mytitle\" (".($year eq ''?'-':$year).")");
		}
		return(undef);
	}
	elsif ( $exact == 2 ) {
		# looking for first exact match on the title, don't have a year to compare

		for my $mytitle ( @titles ) {

			my ($closeMatches, $matchcount) = $self->getMovieCloseMatches($mytitle);

			if ( $matchcount == 1 ) {		# this seems unlikely!

				for my $info (@$closeMatches) {
					if ( $self->tidy($mytitle) eq $self->tidy($info->{title}) ) {

						if ( $info->{qualifier} eq "movie" ) {
							$self->status("close enough hit on movie \"$info->{title}\" [$info->{id}] (since no 'date' field present)");
							$info->{matchLevel}="close";
							return($info);
						}
						# note there is no 'qualifier' in TMDB data - we only have either 'movie' or 'tv'
					}
				}
			}
		}
		return(undef);
	}


	# otherwise we're looking for a title match with a close year (within 2 years)
	#
	for my $mytitle ( @titles ) {

		my ($closeMatches, $matchcount) = $self->getMovieCloseMatches($mytitle);
		
		if ( $matchcount> 0 ) {

			# we traverse the hits twice, first looking for success,
			# then again to produce warnings about missed close matches
			#
			for my $info (@$closeMatches) {

				# within one year with title match good enough
				if ( $self->tidy($mytitle) eq $self->tidy($info->{title}) && $info->{year} ne '' ) {
					
					my $yearsOff=abs(int($info->{year})-$year);

					$info->{matchLevel}="close";

					if ( $yearsOff <= 2 ) {
						my $showYear=int($info->{year});

						if ( $info->{qualifier} eq "movie" ) {
							$self->status("close enough hit on movie \"$info->{title}\" (off by $yearsOff years)");
							return($info);
						}
						elsif ( $info->{qualifier} eq "tv_series" ) {
							#$self->status("close enough hit on tv series \"$info->{title}\" (off by $yearsOff years)");
							#return($info);
						}
						else {
							$self->error("$self->{moviedbIndex} responded with wierd entry for \"$info->{title}\"");
							$self->error("weird trailing qualifier \"$info->{qualifier}\"");
							$self->error("submit bug report to xmltv-devel\@lists.sf.net");
						}
						# note there is no 'qualifier' in TMDB data - we only have either 'movie' or 'tv'
					}
				}
			}

			# if we found at least something, but nothing matched
			# produce warnings about missed, but close matches
			#
			for my $info (@$closeMatches) {

				# title match?
				if ( $self->tidy($mytitle) eq $self->tidy($info->{title}) && $info->{year} ne '' ) {
					
					my $yearsOff=abs(int($info->{year})-$year);
					
					if ( $yearsOff <= 2 ) {
						#die "internal error: key \"$info->{title}\" failed to be processed properly";
					}
					elsif ( $yearsOff <= 5 ) {
						# report these as status
						$self->status("ignoring close, but not good enough hit on \"$info->{title}\" (off by $yearsOff years)");
					}
					else {
						# report these as debug messages
						$self->debug("ignoring close hit on \"$info->{title}\" (off by $yearsOff years)");
					}
				}
				else {
					$self->debug("ignoring close hit on \"$info->{title}\" (title did not match)");
				}
			}
			
			$self->status("no close title/year hit on \"$mytitle\" (".($year eq ''?'-':$year).")");
		}
	}
	
	#$self->status("failed to lookup \"$title ($year)\"");
	return(undef);
}


# find matching tv records on TMDB
#
sub findTVSeriesInfo($$)
{
	my ($self, $title)=@_;

	# if using cache...
	if ( $self->{cacheLookups} ) {
		my $idInfo=$self->{cachedLookups}->{tv_series}->{$title};

		if ( defined($idInfo) ) {
			#print STDERR "REF= (".ref($idInfo).")\n";
			if ( $idInfo ne '' ) {
				return($idInfo);
			}
			return(undef);
		}
	}


	my @titles=@{alternativeTitles($title)};

	my $idInfo;

	for my $mytitle ( @titles ) {
		# looking for matches on title

		my ($closeMatches, $matchcount) = $self->getTvCloseMatches($mytitle);

		# if there are multiple matches with the same 'title' then we don't know which one is right
		#  e.g. Doctor Who (1963), Doctor Who (2005)
		#
		# TODO: fix this somehow?  we could pick up the airdate from the tv prog but that is unlikely to 
		#        match the 'series' record ("first_air_date") on TMDB, so that won't help
		#
		if (scalar ( grep { $self->tidy($_->{title}) eq $self->tidy($mytitle) } @$closeMatches ) > 1) {
			$self->status("multiple hits on tv series \"$mytitle\"");
			last;
		}
		
		# ok there's only 1 match
		# get the matching entry
		#
		for my $info (@$closeMatches) {
			if ( $self->tidy($mytitle) eq $self->tidy($info->{title}) ) {
				$info->{matchLevel}="perfect";

				if ( $info->{qualifier} eq "tv_series" ) {
					$idInfo=$info;
					$self->status("perfect hit on tv series \"$info->{key}\" [$info->{id}]");
					last;
				}
				# note there is no 'qualifier' in TMDB data - we only have either 'movie' or 'tv'
			}
		}
		last if ( defined($idInfo) );
	}


	# if using cache...
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


# apply the changes to the source record
#
# todo - ratings : not available in TMDB sadly
# we could add the following (but who cares?)
# todo - writer
# todo - producer
# todo - adapter  ( 'job' = 'Teleplay' )
#
sub applyFound($$$)
{
	my ($self, $prog, $idInfo)=@_;
	
	# get the movie/tv details from TMDB
	my $details = $self->getMovieOrTvIdDetails($idInfo->{id}, $idInfo->{type});
	
	$self->debugmore(5,'tdmb_match',$idInfo);
	$self->debugmore(5,'details',$details);


	my $title=$prog->{title}->[0]->[0];
	
	$self->debug("augmenting $idInfo->{qualifier} \"$title\"");

	if ( $self->{updateDates} ) {
		my $date;

		# don't add dates to tv_series (only replace them)
		if ( $idInfo->{qualifier} eq "movie" ||
			 $idInfo->{qualifier} eq "video_movie" ||
			 $idInfo->{qualifier} eq "tv_movie" ) {
			$self->debug("adding 'date' field (\"$idInfo->{year}\") on \"$title\"");
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
	
	
	if ( $self->{removeYearFromTitles} ) {
		
		if ( $title =~ m/\s+\((19|20)\d\d\)\s*$/ ) {
						
			$self->debug("removing year from all 'title'");
				
			my @list;

			if ( defined($prog->{title}) ) {
				for my $v (@{$prog->{title}}) {
					my $otitle = $v->[0];
					if ( $v->[0] =~ s/\s+\((19|20)\d\d\)\s*$// ) {
						$self->debug("removing year from 'title' \"$otitle\" to \"$v->[0]\"");
					}
					push(@list, $v);
				}
			}
			$prog->{title}=\@list;
		}
	}


	if ( $self->{updateTitles} ) {
		
		if ( $idInfo->{title} ne $title ) {
			if ( $self->{replaceTitles} ) {
				$self->debug("replacing (all) 'title' from \"$title\" to \"$idInfo->{title}\"");
				delete($prog->{title});
			}

			my @list;

			push(@list, [$idInfo->{title}, $idInfo->{lang}]);

			if ( defined($prog->{title}) ) {
				my $name=$idInfo->{title};
				my $found=0;
				for my $v (@{$prog->{title}}) {
					if ( $self->tidy($v->[0]) eq $self->tidy($name) ) {
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

		# add url pointing to programme on www.themoviedb.org
		my $url2;
		if ( defined($details->{tmdb_id}) )
		{
			$url2= $self->{wwwUrl} .  ( $idInfo->{qualifier} =~ /movie/ ? 'movie' : 'tv' ) . "/" . $details->{tmdb_id};
		}

		$self->debug("adding 'url' $url2") if $url2;

		# add url pointing to programme on www.imdb.com
		my $url;
		#
		# see if TMDB has an IMDb "tt" identifier
		#
		if ( defined($details->{imdb_id}) && ( $details->{imdb_id} =~ m/^tt\d*$/ ) ) 
		{
			$url="https://www.imdb.com/title/".$details->{imdb_id}."/";
		}
		else 	# no tt id found - revert to old 'search' url
		{
			$url=$idInfo->{key};
			
			# encode the title
			$url=~s/([^a-zA-Z0-9_.-])/uc sprintf("%%%02x",ord($1))/oeg;
			$url="https://www.imdb.com/find?q=".$url."&s=tt&exact=true";

			# possible altve url using 'search' instead of 'find', but there's no option for 'exact' hits only
			# https://www.imdb.com/search/title/?title=titanic&release_date=1995-01-01,1999-12-31&view=simple
			# c.f. https://www.imdb.com/search/title/
		}
		
		$self->debug("adding 'url' $url");

		if ( defined($prog->{url}) ) {
			my @rep;
			push(@rep, [ $url2, 'TMDB' ]) if $url2;
			push(@rep, [ $url,  'IMDb' ]) if $url;
			for (@{$prog->{url}}) {
				# skip urls for imdb.com that we're probably safe to replace
				if ( !m;^http://us.imdb.com/M/title-exact;o && !m;^https://www.imdb.com/find;o ) {
					push(@rep, $_);
				}
			}
			$prog->{url}=\@rep;
		}
		else {
			push(@{$prog->{url}}, [ $url2, 'TMDB' ]) if $url2;
			push(@{$prog->{url}}, [ $url,  'IMDb' ]) if $url;
		}
	}



	# squirrel away movie qualifier so it's first on the list of replacements
	my @categories;
	push(@categories, [$self->{categories}->{$idInfo->{qualifier}}, 'en']);
	if ( !defined($self->{categories}->{$idInfo->{qualifier}}) ) {
		die "how did we get here with an invalid qualifier '$idInfo->{qualifier}'";
	}


	# now done above (so we can get IMDb tt id 	### 	my $details=$self->getMovieIdDetails($idInfo->{id});
	
	if ( $details->{noDetails} ) {
		# we don't have any details on this movie
	}
	else {
		
		# ---- update directors list
		if ( $self->{updateDirectors} && defined($details->{directors}) ) {
			# only update directors if we have exactly one or if
			# it's a movie of some kind
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

				# add top 3 billing directors from TMDB data
				# preserve all existing directors from the prog + de-dupe the list
				my @list;
				if ( $self->{updateCastImage} || $self->{updateCastUrl} ) {

					# add director image
					foreach (@{ $details->{directorsplus} }) {

						my $subels = {};

						# add actor image
						# TODO : remove existing image(s) / avoid duplicates
						$subels->{image} = [[ $_->{imageurl}, {'system'=>'TMDB','type'=>'person'} ]] if $self->{updateCastImage} && $_->{imageurl} ne '';

						# add actor url
						$subels->{url} = [[ $self->{wwwUrl} . 'person/' . $_->{id}, 'TMDB' ]] if $self->{updateCastUrl};

						push(@list, [ $_->{name}, $subels ] );
					}

					# merge and dedupe the lists from incoming xml + tmdb. Give TMDB entries priority.
					@list = uniquemulti( splice(@list,0,3), map{ ref($_) eq 'ARRAY' && scalar($_) > 1 ? $_ : [ $_ ] } @{ $prog->{credits}->{director} } ); 	# 'map' because uniquemulti needs an array

					@list = map{ ( ref($_) eq 'ARRAY' && scalar(@$_) == 1 ) ? shift @$_ : $_ } @list;       # flatten any single-index arrays

				} else {
					# simple merge and dedupe
					@list = unique( splice(@{$details->{directors}},0,3), @{ $prog->{credits}->{director} } );
				}
				#
				$prog->{credits}->{director}=\@list;
			}
			else {
				$self->debug("not adding 'director'");
			}
		}


		# ---- update actors list
		if ( $self->{updateActors} && defined($details->{actors}) ) {
			if ( $self->{replaceActors} ) {
				if ( defined($prog->{credits}->{actor}) ) {
					$self->debug("replacing actor(s)");
					delete($prog->{credits}->{actor});
				}
			}

			# add top billing actors (default = 3) from TMDB
			# preserve all existing actors from the prog + de-dupe the list
			#
			my @list;
			if ( $self->{updateActorRole} || $self->{updateCastImage} || $self->{updateCastUrl} ) {

				foreach (@{ $details->{actorsplus} }) {

					# add character attribute to actor name
					my $character = ( $self->{updateActorRole} ? $_->{character} : '' );

					my $subels = {};

					# add actor image
					# TODO : remove existing image(s) / avoid duplicates
					$subels->{image} = [[ $_->{imageurl}, {'system'=>'TMDB','type'=>'person'} ]] if $self->{updateCastImage} && $_->{imageurl} ne '';

					# add actor url
					$subels->{url} = [[ $self->{wwwUrl} . 'person/' . $_->{id}, 'TMDB' ]] if $self->{updateCastUrl};

					push(@list, [ $_->{name}, $character, '', $subels ] );
				}
				
				# merge and dedupe the lists from incoming xml + tmdb. Give TMDB entries priority.
				#  note: will ignore 'role' attribute - i.e. de-dupe on 'name' only
				@list = uniquemulti( splice(@list,0,$self->{numActors}), map{ ref($_) eq 'ARRAY' && scalar($_) > 1 ? $_ : [ $_ ] } @{ $prog->{credits}->{actor} } ); 	# 'map' because uniquemulti needs an array

				@list = map{ ( scalar(@$_) == 3 && @$_[2] eq '' ) ? [ @$_[0], @$_[1] ]  : $_ } @list;   # remove blank 'image' values
				@list = map{ ( scalar(@$_) == 2 && @$_[1] eq '' ) ? @$_[0] : $_ } @list;                # remove blank 'character' values
				@list = map{ ( ref($_) eq 'ARRAY' && scalar(@$_) == 1 ) ? shift @$_ : $_ } @list;       # flatten any single-index arrays (as per the xmltv data struct)

			} else {
				# simple merge and dedupe
				@list = unique( splice(@{$details->{actors}},0,$self->{numActors}), @{ $prog->{credits}->{actor} } );
			}
			#
			$prog->{credits}->{actor}=\@list;
		}


		# ---- update presenters list
		if ( $self->{updatePresentors} && defined($details->{presenter}) ) {
			if ( $idInfo->{qualifier} eq "tv_series" ) {		# only do this for TV (not movies as 'presenter' might be a valid character)
				if ( $self->{replacePresentors} ) {
					if ( defined($prog->{credits}->{presenter}) ) {
						$self->debug("replacing presentor");
						delete($prog->{credits}->{presenter});
					}
				}
				$prog->{credits}->{presenter}=$details->{presenter};
			}
		}


		# ---- update commentators list
		if ( $self->{updateCommentators} && defined($details->{commentator}) ) {
			if ( $idInfo->{qualifier} eq "tv_series" ) {		# only do this for TV (not movies as 'commentator' might be a valid character)
				if ( $self->{replaceCommentators} ) {
					if ( defined($prog->{credits}->{commentator}) ) {
						$self->debug("replacing commentator");
						delete($prog->{credits}->{commentator});
					}
				}
				$prog->{credits}->{commentator}=$details->{commentator};
			}
		}


		# ---- update guests list
		if ( $self->{updateGuests} && defined($details->{guest}) ) {
			if ( $idInfo->{qualifier} eq "tv_series" ) {		# only do this for TV (not movies as 'guest' might be a valid character)
				if ( $self->{replaceGuests} ) {
					if ( defined($prog->{credits}->{guest}) ) {
						$self->debug("replacing guest");
						delete($prog->{credits}->{guest});
					}
				}
				$prog->{credits}->{guest}=$details->{guest};
			}
		}


		# ---- update categories (genres) list
		if ( $self->{updateCategoriesWithGenres} ) {		# deprecated?
			if ( defined($details->{genres}) ) {
				for (@{$details->{genres}}) {
					push(@categories, [$_, 'en']);
				}
			}
		}
		#
		if ( $self->{updateCategories} ) {
			if ( $self->{replaceCategories} ) {
				if ( defined($prog->{category}) ) {
					$self->debug("replacing (all) 'category'");
					delete($prog->{category});
				}
			}
			if ( defined($prog->{category}) ) {
				# merge and dedupe
				@categories = uniquemulti( @categories, @{$prog->{category}} );
				#
			}
			$prog->{category}=\@categories;
		}


		# ---- update ratings (film classifications)
		if ( $self->{updateRatings} ) {
			if ( $self->{replaceRatings} ) {
				if ( defined($prog->{rating}) ) {
					$self->debug("replacing (all) 'rating'");
					delete($prog->{rating});
				}
			}
			if ( defined($details->{classifications}) ) {
				# we need to sort the classifications to ensure a consistent order from TMDB
				@{$details->{classifications}} = sort { $a->{system} cmp $b->{system} } @{$details->{classifications}};
				#
				for (@{$details->{classifications}}) {
					push(@{$prog->{rating}}, [ $_->{rating}, $_->{system} ] );
				}
			}
		}


		# ---- update star ratings
		if ( $self->{updateStarRatings} && defined($details->{ratingRank}) ) {

			# ignore the TMDB rating if there are too few votes (to avoid skewed data).
			# what's 'too few'...good question!
			if ( $details->{ratingVotes} >= $self->{minVotes} ) {

				if ( $self->{replaceStarRatings} ) {
					if ( defined($prog->{'star-rating'}) ) {
						$self->debug("replacing 'star-rating'");
						delete($prog->{'star-rating'});
					}
					unshift( @{$prog->{'star-rating'}}, [ $details->{ratingRank} . "/10", 'TMDB User Rating' ] );
				}
				else {
					# add TMDB User Rating in front of all other star-ratings
					unshift( @{$prog->{'star-rating'}}, [ $details->{ratingRank} . "/10", 'TMDB User Rating' ] );
				}

			}
		}


		# ---- update keywords
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
				# merge and dedupe
				@keywords = unique( @keywords, @{$prog->{keyword}} );
				#
			}
			$prog->{keyword}=\@keywords;
		}


		# ---- update desc (plot)
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


		# ---- update runtime
		if ( $self->{updateRuntime} ) {
			if ( defined($details->{runtime}) ) {
				$prog->{length} = $details->{runtime} * 60;			# XMLTV.pm only accepts seconds
			}
		}


		# ---- update reference id
		if ( $self->{updateContentId} ) {
			# remove existing values
			@{$prog->{'episode-num'}} = grep ( @$_[1] !~ /tmdb_id|imdb_id/, @{$prog->{'episode-num'}} );
			# add new values
			if ( defined($details->{tmdb_id}) ) {
				push(@{$prog->{'episode-num'}}, [ $details->{tmdb_id}, 'tmdb_id' ] );
			}
			if ( defined($details->{imdb_id}) && ( $details->{imdb_id} =~ m/^tt\d*$/ ) ) {
				push(@{$prog->{'episode-num'}}, [ $details->{imdb_id}, 'imdb_id' ] );
			}
		}


		# ---- update image
		if ( $self->{updateImage} ) {
			if ( defined($details->{posterurl}) ) {
				if ( $details->{posterurl} =~ m|/w500/| ) {
					push @{$prog->{image}}, [ $details->{posterurl}, { type => 'poster', orient => 'P', size => 3, system => 'TMDB' } ];
				} else {
					push @{$prog->{image}}, [ $details->{posterurl} ];
				}
			}
			if ( defined($details->{backdropurl}) ) {
				if ( $details->{backdropurl} =~ m|/w780/| ) {
					push @{$prog->{image}}, [ $details->{backdropurl}, { type => 'backdrop', orient => 'L', size => 3, system => 'TMDB' } ];
				} else {
					push @{$prog->{image}}, [ $details->{backdropurl} ];
				}
			}
			# smaller versions
			if ( defined($details->{posterurl_sm}) ) {
				if ( $details->{posterurl_sm} =~ m|/w92/| ) {
					push @{$prog->{image}}, [ $details->{posterurl_sm}, { type => 'poster', orient => 'P', size => 1, system => 'TMDB' } ];
				} else {
					push @{$prog->{image}}, [ $details->{posterurl_sm} ];
				}
			}
			if ( defined($details->{backdropurl_sm}) ) {
				if ( $details->{backdropurl_sm} =~ m|/w300/| ) {
					push @{$prog->{image}}, [ $details->{backdropurl_sm}, { type => 'backdrop', orient => 'L', size => 2, system => 'TMDB' } ];
				} else {
					push @{$prog->{image}}, [ $details->{backdropurl_sm} ];
				}
			}
		}


		# ---- update reviews
		if ( $self->{updateReviews} ) {
			if ( $self->{replaceReviews} ) {
				if ( defined($prog->{review}) ) {
					$self->debug("replacing (all) 'reviews'");
					delete($prog->{review});
				}
			}
			if ( defined($details->{reviews}) ) {
				my $i=0;
				for (@{$details->{reviews}}) {
					last if ++$i > $self->{numReviews};
					push @{$prog->{review}}, [ $_->{content}, { reviewer=>$_->{author}, source=>'TMDB', type=>'text' } ];
					push @{$prog->{review}}, [ $_->{url},     { reviewer=>$_->{author}, source=>'TMDB', type=>'url' } ]  if $_->{url} ne '';
				}
			}
		}


	}

	return($prog);
}


# main entry point
# augment program data with TMDB data
#
# TODO: try to identify whether programme is movie or tv (e.g. via categories?)
#        and process accordingly
#
sub augmentProgram($$$)
{
	my ($self, $prog, $movies_only)=@_;

	$self->{stats}->{programCount}++;

	# assume first title in first language is the one we want.
	my $title=$prog->{title}->[0]->[0];
	
	# if no date but a date is in the title then extract it
	if ( $self->{getYearFromTitles} ) {
		if ( !defined($prog->{date}) || $prog->{date} eq '' ) {
			( $prog->{date} ) = $title =~ m/\s+\(((19|20)\d\d)\)$/; 
		}
	}
	
	# try to work out if we are a movie or a tv prog
	#  1. categories includes any of 'Movie','Films',"Film" = movie
	#    (but note 'Film' (singular) as that could be a film review talking about films e.g. "Film 2018"  TODO: fix me)
	#  2. categories includes any of 'tv*' = tv_series
	#  3. date is '(19|20)xx' = movie
	#
	my $progtype = '?';
	$progtype = 'movie'
		if ( defined($prog->{date}) && $prog->{date}=~m/^\d\d\d\d$/ )
		or ( scalar ( grep { lc(@$_[0]) =~ /movies|movie|films|film/ } @{ $prog->{category} } ) >0 );
		
	$progtype = 'tv_series'
		if ( defined($prog->{date}) && $prog->{date}=~m/^\d\d\d\d-\d\d-\d\d$/ )
		or ( scalar ( grep { lc($_ -> [0]) =~ /^tv.*/ } @{ $prog->{category} } ) >0 );
		
	$self->status("input: \"$title\"  [$progtype]");
	
	
	
	if ( defined($prog->{date}) && $prog->{date}=~m/^\d\d\d\d$/  && $progtype ne 'tv_series' ) {

		# for programs with dates we try:
		# - exact matches on movies (using title + year)
		# - exact matches on tv series (using title)
		# - close matches on movies (using title)
		#
		my ($id, $matchcount) = $self->findMovieInfo($title, $prog, $prog->{date}, 1); 	# exact match

		if (defined $matchcount && $matchcount > 1) {
			$self->status("failed to find a sole match for movie \"$title".($title=~m/\s+\((19|20)\d\d\)/?'':" ($prog->{date})")."\"");
			return(undef);
		}
		
		if ( !defined($id) ) {
			
			if ( !$movies_only  &&  $progtype ne 'movie' ) {
				$id = $self->findTVSeriesInfo($title);								# match tv series
			}

			if ( !defined($id) ) {
				($id, $matchcount) = $self->findMovieInfo($title, $prog, $prog->{date}, 0); # close match
			}
		}
		
		if ( defined($id) ) {
			$self->{stats}->{$id->{matchLevel}."Matches"}++;
			$self->{stats}->{$id->{matchLevel}}->{$id->{qualifier}}++;
			return($self->applyFound($prog, $id));
		}
		
		$self->status("failed to find a match for movie \"$title".($title=~m/\s+\((19|20)\d\d\)/?'':" ($prog->{date})")."\"");
		return(undef);
	}


	if ( !$movies_only ) {

		# for programs without dates we try:
		# - exact matches on tv series (using title)
		# - close matches on movie
		#
		
		if ( $progtype ne 'movie' ) {
			
			my $id=$self->findTVSeriesInfo($title);
		
			if ( defined($id) ) {
				$self->{stats}->{$id->{matchLevel}."Matches"}++;
				$self->{stats}->{$id->{matchLevel}}->{$id->{qualifier}}++;
				return($self->applyFound($prog, $id));
			}
			
		}

		if ( $progtype eq 'movie' ) {
			# this has hard to support 'close' results, unless we know
			# for certain we're looking for a movie (ie duration etc)
			my ($id, $matchcount) = $self->findMovieInfo($title, $prog, undef, 2); 	# any title match
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


# print some stats
#
# TODO - add in stats on other things added (urls ?, actors, directors,categories)
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
