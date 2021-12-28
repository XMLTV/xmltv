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

package XMLTV::TMDB::API;

# Package changes for XMLTV
#  - add new namespace for package Tv.pm and Config.pm
#  - remove ID= url parameter (since it's already added to the URL path)
#  - add http response to return array
#  - add 'soft' param to constructor to return http errors instead of carp
#

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = '0.05';
use utf8;
use LWP::UserAgent;
use HTTP::Request;
use JSON;
use URI;

our @namespaces = qw( Person Movie Tv Config );
for (@namespaces) {
    my $package = __PACKAGE__ . "::$_";
    my $name    = "\L$_";
    eval qq(
    use $package;
    sub $name {
      my \$self = shift;
      if ( \$self->{'_$name'} ) {
        return \$self->{'_$name'};
      }else{
        \$self->{'_$name'} = $package->new( api => \$self );
      }
    };

    package $package;
    sub api {
      return shift->{api};
    };

    sub new {
      my ( \$class, \%params ) = \@_;
      my \$self = bless \\\%params, \$class;
      \$self->{api} = \$params{api};
      return \$self;
    };

    1;
  );
    croak "Cannot create namespace $name: $@\n" if $@;
}

sub send_api {
    my ( $self, $command, $params_spec, $params ) = @_;

    $self->check_parameters( $params_spec, $params );
    my $url = $self->url( $command, $params );
    my $request = HTTP::Request->new( GET => $url );
    $request->header( 'Accept' => 'application/json' );
    my $json_response = $self->{ua}->request($request);
    if ( $json_response->is_success ) {
        return [ decode_json( $json_response->content() ),
						  { 'code' => $json_response->code(),
							'msg'  => $json_response->status_line,
							'url'  => $url
						  } ];
    }
    elsif ( $json_response->is_error && $self->{soft} ) {
		return [ {},  { 'code' => $json_response->code(),
						'msg'  => $json_response->status_line,
						'url'  => $url
			    } ];
    }
    else {
        croak
            sprintf( "%s returned by %s", $json_response->status_line, $url );
    }
}

# Checks items that will be sent to the API($input)
# $params - an array that identifies valid parameters
#     example :
#     {'ID' => 1 }, 1- field is required, 0- field is optional
sub check_parameters {
    my $self = shift;
    my ( $params, $input ) = @_;

    foreach my $k ( keys(%$params) ) {
        croak "Required parameter $k missing."
            if ( $params->{$k} == 1 and !defined $input->{$k} );
    }
    foreach my $k ( keys(%$input) ) {
        croak "Unknown parameter - $k." if ( !defined $params->{$k} );
    }
}

sub url {
    my $self = shift;
    my ( $command, $params ) = @_;
    my $url = new URI( $self->{url} );
    $url->path_segments( $self->{ver}, @$command );
    $params->{api_key} = $self->{api_key};
    delete $params->{ID} if defined $params->{ID};
    $url->query_form($params);
    return $url->as_string();
}

sub new {
    my $class = shift;
    my (%params) = @_;

    croak "Required parameter api_key not provided." unless $params{api_key};
    if ( !defined $params{ua} ) {
        $params{ua} =
            LWP::UserAgent->new( 'agent' => "Perl-WWW-TMDB-API/$VERSION", );
    }
    else {
        croak "LWP::UserAgent expected."
            unless $params{ua}->isa('LWP::UserAgent');
    }

    my $self = {
        api_key => $params{api_key},
        ua      => $params{ua},
        ver     => '3',
        url     => 'http://api.themoviedb.org',
        soft    => (defined $params{soft} ? $params{soft} : 0),
    };

    bless $self, $class;
    return $self;
}

=head1 NAME

WWW::TMDB::API - TMDb API (http://api.themoviedb.org) client

=head1 VERSION

Version 0.04

=head1 SYNOPSIS

        use WWW::TMDB::API;

        # The constructor has 2 parameters - the api_key and the optional LWP::UserAgent object, ua.
        my $tmdb_client = WWW::TMDB::API->new( 'api_key' => 'your tmdb api key' );

        #  Retrieve information about the person with ID == 287
        $tmdb_client->person->info( ID => 287 );

        # Searches the themoviedb.org database for an actor, actress or production member with name 'Brad+Pitt'
        $tmdb_client->person->search( query => 'Brad+Pitt' );

        # Searches the themoviedb.org database for an actor, actress or production member with name 'Brad'
        $tmdb_client->person->search( query => 'Brad' );

        #  Determines the last movie created in the themoviedb.org database.
        $tmdb_client->movie->latest();


=head1 DESCRIPTION

This module implements version 3 of the TMDb API. See L<http://help.themoviedb.org/kb/api/about-3> for the documentation.
The module uses the same parameter names used by the API. 
The method names have been slightly changed. Here's the mapping of the method names used by this this module and the corresponding method names in the TMDb API:

                                      TMDB API                           WWW::TMDB::API
                                      ----------------------             -------------------
    Search Movies                     search/movie	                 movie->search() 
    Search People                     search/person                      person->search()
    Movie Info                        movie/[TMDb ID]                    movie->info()
    Movie Alternative Titles          movie/[TMDb ID]/alternative_titles movie->alternative_titles()
    Movie Casts                       movie/[TMDb ID]/casts              movie->casts()
    Movie Images                      movie/[TMDb ID]/images             movie->images()
    Movie Keywords                    movie/[TMDb ID]/keywords           movie->keywords()
    Movie Release Info                movie/[TMDb ID]/releases           movie->releases()
    Movie Trailers                    movie/[TMDb ID]/trailers           movie->trailers()
    Movie Translations                movie/[TMDb ID]/translations       movie->translations()
    Person Info                       person/[TMDb ID]/info              person->info()
    Person Credits                    person/[TMDb ID]/credits           person->credits()
    Person Images                     person/[TMDb ID]/images            person->images()
    Latest Movie                      latest/movie                       movie->latest()


The API requires an API key which can be generated from http://api.themoviedb.org.
This module converts the API output to Perl data structure using the module JSON.
This module does not support update the method, Movie Add Rating.

=head1 SUBROUTINES/METHODS

=head2 new( %params )

Returns a new instance of the B<WWW::TMDB::API> class.

=over 4

=item * B<api_key>

Required. This is the TMDb API key. Go to the L<http://api.themoviedb.org> to signup and generate an API key.

=item * B<ua>

Optional. The LWP::UserAgent used to communicate with the TMDb server.


        my $tmdb_client = WWW::TMDB::API->new( 'api_key' => 'your tmdb api key' );

        require LWP::UserAgent;
        $ua = LWP::UserAgent->new(
                'agent'        => "Perl-WWW-TMDB-API",
        );

        my $tmdb_client =
                WWW::TMDB::API->new( 'api_key' => 'your tmdb api key', 'ua' => $ua );


=back

=head2  movie->search( %params )

Searches for movies.

=over 4

=item * B<query>

Required. This is the search text. The query can include the year the movie was released (e.g. B<Transformers+2007>) to narrow the search results.

=item * B<page>

Optional. Use this parameter to iterate through the search results. Search results that exceed 20 items are paginated.

=item * B<language>

Optional. This limits the result to items tagged with the specified language. The expected value is a ISO 639-1 code.

=item * B<include_adult>

Optional. [true/false, defaults to false if unspecified]. Set this to true to include adult items in the search results.

=back
         $result = $api->movie->search( 'query' => 'Cool Hand' );


=head2  person->search( %params )

Searches for actors, actresses, or production members.

=over 4

=item * B<query>

Required. This is the search text.


=item * B<page>

Optional. Use this parameter to iterate through the search results. Search results that exceed 20 items are paginated.

=back

        $result = $api->person->search( 'query' => 'Newman' );


=head2  movie->info( %params )

Retrieves basic information about a movie.
Building image urls from the file_paths returned by this method is discussed in the document L<http://help.themoviedb.org/kb/api/configuration>.

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=item * B<language>

Optional. This limits the result to items tagged with the specified language. The expected value is a ISO 639-1 code.

=back

        $result = $api->movie->info( ID => 903 );


=head2 movie->alternative_titles( %params )

Retrieves a movie's alternative titles.

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=item * B<country>

Optional. This limits the result to items tagged with the specified country. The expected value is a ISO 3166-1 code.

=back

        $result = $api->movie->alternative_titles( ID => 903 );
        $result = $api->movie->alternative_titles( ID => 903, 'language' => 'fr' );


=head2 movie->casts( %params )

Retrieves a movie's cast information.

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=back

        $result = $api->movie->casts( ID => 903 );


=head2 movie->images( %params )

Retrieves all of the images for a particular movie.
Building image urls from the file_paths returned by this method is discussed in the document:
L<http://help.themoviedb.org/kb/api/configuration> 

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=item * B<language>

Optional. This limits the result to items tagged with the specified language. The expected value is a ISO 639-1 code.

=back

        $result = $api->movie->images( ID => 903 );
        $result = $api->movie->images( ID => 903, 'language' => 'en' );


=head2 movie->keywords( %params )

Retrieves the keywords for a movie.

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=back

        $result = $api->movie->keywords( ID => 903 );

=head2 movie->releases( %params )

Retrieves release and certification data for a specific movie.

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=back

        $result = $api->movie->releases( ID => 903 );


=head2 movie->trailers( %params )

Retrieves the trailers for a movie.

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=item * B<language>

Optional. This limits the result to items tagged with the specified language. The expected value is a ISO 639-1 code.

=back

        $result = $api->movie->trailers( ID => 903 );


=head2 movie->translations( %params )

Retrieves the list of translations for a movie.

=over 4

=item * B<ID>

Required. The TMDb ID of the movie.

=back

        $result = $api->movie->translations( ID => 903 );


=head2  person->info( %params )

Retrieves basic information about a person.
Building image urls from the file_paths returned by this method is discussed in the document:
L<http://help.themoviedb.org/kb/api/configuration>

=over 4

=item * B<ID>

Required. The TMDb ID of the person.

=back

         $result = $api->person->info( ID => 3636 );

=head2  person->credits( %params )

Retrieves the movies that have cast or crew credits for  a person.

=over 4

=item * B<ID>

Required. The TMDb ID of the person.

=item * B<language>

Optional. This limits the result to items tagged with the specified language. The expected value is a ISO 639-1 code.

=back

         $result = $api->person->credits( ID => 3636 );


=head2  person->images( %params )

Retrieves all the profile images of the person.
Building image urls from the file_paths returned by this method is discussed in the document:
L<http://help.themoviedb.org/kb/api/configuration>] 

=over 4

=item * B<ID>

Required. The TMDb ID of the person.

=back

         $result = $api->person->images( ID => 3636 );


=head2  movie->latest( )

Returns the newest movie created in the themoviedb.org database.


=head1 AUTHOR

Maria Celina Baratang, C<< <maria at zambale.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-www-tmdb-api at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WWW-TMDB-API>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::TMDB::API


You can also look for information at:


=over 4

=item * TMDb The open movie database

L<http://themoviedb.org/>

=item * themoviedb.org API Documentation

L<http://api.themoviedb.org/>
L<http://help.themoviedb.org/kb/api/about-3>

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WWW-TMDB-API>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WWW-TMDB-API>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WWW-TMDB-API>

=item * Search CPAN

L<http://search.cpan.org/dist/WWW-TMDB-API/>

=back


=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2012 Maria Celina Baratang.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of WWW::TMDB::API
