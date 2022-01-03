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
#  - info()   - add 'append_to_response' param
#

package XMLTV::TMDB::API::Person;

use strict;
use warnings;
our $VERSION = '0.05';

sub info {
    my $self = shift;
    my (%params) = @_;
    $self->api->send_api( [ 'person', $params{ID} ], { ID => 1, append_to_response =>0 }, \%params );
}

sub credits {
    my $self = shift;
    my (%params) = @_;
    $self->api->send_api( [ 'person', $params{ID}, 'credits' ],
        { ID => 1, language => 0 }, \%params );
}

sub images {
    my $self = shift;
    my (%params) = @_;
    $self->api->send_api( [ 'person', $params{ID}, 'images' ],
        { ID => 1 }, \%params );
}

sub search {
    my $self = shift;
    my (%params) = @_;
    $self->api->send_api( [ 'search', 'person' ],
        { query => 1, page => 0 }, \%params );
}
1;
