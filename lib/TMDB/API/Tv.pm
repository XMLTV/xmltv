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
#  - new package for XMLTV - not in WWW::TMDB::API
#

package XMLTV::TMDB::API::Tv;

use strict;
use warnings;
our $VERSION = '0.05';

sub info {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'tv', $params{ID} ],
        { ID => 1, language => 0, append_to_response =>0 }, \%params );
}

sub search {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'search', 'tv' ],
        { query => 1, page => 0, language => 0, 'include_adult' => 0 },
        \%params );
}

sub alternative_titles {
	my $self = shift;
	my (%params) = @_;
	$self->{api}->send_api( [ 'tv', $params{ID}, 'alternative_titles' ],
		{ ID => 1, country => 0 }, \%params );
}

sub credits {
	my $self = shift;
	my (%params) = @_;
	$self->{api}->send_api( [ 'tv', $params{ID}, 'credits' ], { ID => 1 },
		\%params );
}

sub images {
	my $self = shift;
	my (%params) = @_;
	$self->{api}->send_api( [ 'tv', $params{ID}, 'images' ],
		{ ID => 1, language => 0 }, \%params );
}

sub keywords {
	my $self = shift;
	my (%params) = @_;
	$self->{api}->send_api( [ 'tv', $params{ID}, 'keywords' ],
		{ ID => 1 }, \%params );
}

sub translations {
	my $self = shift;
	my (%params) = @_;
	$self->{api}->send_api( [ 'tv', $params{ID}, 'translations' ],
		{ ID => 1 }, \%params );
}

sub content_ratings {
	my $self = shift;
	my (%params) = @_;
	$self->{api}->send_api( [ 'tv', $params{ID}, 'content_ratings' ],
		{ ID => 1 }, \%params );
}

sub reviews {
    my $self = shift;
    my (%params) = @_;
    $self->{api}->send_api( [ 'tv', $params{ID}, 'reviews' ],
        { ID => 1, language => 1 }, \%params );
}

sub latest {
	my $self = shift;
	my (%params) = @_;
	$self->{api}->send_api( [ 'tv', 'latest' ] );
}

1;
