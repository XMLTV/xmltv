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

1;    # End of XMLTV::TMDB::API
