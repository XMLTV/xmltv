#
# Lightweight package to retrieve movie/tv programme data from The Movie Database (http://www.themoviedb.org/ )
#
# This is a custom version of the CPAN package :
#   WWW::TMDB::API - TMDb API (http://api.themoviedb.org) client
#   Version 0.04 (2012)
#   Author Maria Celina Baratang, <maria at zambale.com>
#   https://metacpan.org/pod/WWW::TMDB::API
#
# Modified for XMLTV use to 
#  - fix broken methods
#  - add methods for TV programmes, and Configuration
#  - 'version' changed to be 0.05
#
# Modifications: Geoff Westcott, December 2021
#

# Package changes for XMLTV
#  - search() - now 'movie'(not 'movies')
#  - search() - added 'year' attribute
#  - casts()  - now called 'credits'
#  - images() - add 'include_image_language' 
#  - latest() - endpoint is now 'movie/latest'
#  - releases()- now called release_dates()
#  - trailers()- now called videos()
#  - info()   - add 'append_to_response' param
#  - reviews()- new endpoint 

package XMLTV::TMDB::API::Movie;

use strict;
use warnings;
our $VERSION = '0.05';

sub info {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID} ],
        { ID => 1, language => 0, append_to_response =>0 }, \%params );
}

sub search {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'search', 'movie' ],
        { query => 1, page => 0, language => 0, 'include_adult' => 0, year => 0 },
        \%params );
}

sub alternative_titles {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'alternative_titles' ],
        { ID => 1, country => 0 }, \%params );
}

sub credits {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'credits' ], { ID => 1 },
        \%params );
}

sub images {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'images' ],
        { ID => 1, language => 0, include_image_language => 0 }, \%params );
}

sub keywords {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'keywords' ],
        { ID => 1 }, \%params );
}

sub release_dates {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'release_dates' ],
        { ID => 1 }, \%params );
}

sub translations {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'translations' ],
        { ID => 1 }, \%params );
}

sub videos {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'videos' ],
        { ID => 1, language => 1 }, \%params );
}

sub reviews {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', $params{ID}, 'reviews' ],
        { ID => 1, language => 1 }, \%params );
}

sub latest {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'movie', 'latest' ] );
}

1;
