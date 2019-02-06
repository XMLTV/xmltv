# A wrapper around Data::Recursive::Encode from Tokuhiro Matsuno
# http://search.cpan.org/~tokuhirom/Data-Recursive-Encode-0.04/lib/Data/Recursive/Encode.pm
#
package XMLTV::Data::Recursive::Encode;
#####################################

#package Data::Recursive::Encode;
##use 5.008001;  # in e-mails the author has said he can't support versions <5.8.1 but he can't see why it won't work in earlier versions
use strict;
use warnings FATAL => 'all';

our $VERSION = '0.04';

use Encode ();
use Carp ();
use Scalar::Util qw(blessed refaddr);

sub _apply {
    my $code = shift;
    my $seen = shift;

    my @retval;
    for my $arg (@_) {
        if(my $ref = ref $arg){
            my $refaddr = refaddr($arg);
            my $proto;

            if(defined($proto = $seen->{$refaddr})){
                 # noop
            }
            elsif($ref eq 'ARRAY'){
                $proto = $seen->{$refaddr} = [];
                @{$proto} = _apply($code, $seen, @{$arg});
            }
            elsif($ref eq 'HASH'){
                $proto = $seen->{$refaddr} = {};
                %{$proto} = _apply($code, $seen, %{$arg});
            }
            elsif($ref eq 'REF' or $ref eq 'SCALAR'){
                $proto = $seen->{$refaddr} = \do{ my $scalar };
                ${$proto} = _apply($code, $seen, ${$arg});
            }
            else{ # CODE, GLOB, IO, LVALUE etc.
                $proto = $seen->{$refaddr} = $arg;
            }

            push @retval, $proto;
        }
        else{
            push @retval, defined($arg) ? $code->($arg) : $arg;
        }
    }

    return wantarray ? @retval : $retval[0];
}

sub decode {
    my ($class, $encoding, $stuff, $check) = @_;
    $encoding = Encode::find_encoding($encoding)
        || Carp::croak("$class: unknown encoding '$encoding'");
    $check ||= 0;
    _apply(sub { $encoding->decode($_[0], $check) }, {}, $stuff);
}

sub encode {
    my ($class, $encoding, $stuff, $check) = @_;
    $encoding = Encode::find_encoding($encoding)
        || Carp::croak("$class: unknown encoding '$encoding'");
    $check ||= 0;
    _apply(sub { $encoding->encode($_[0], $check) }, {}, $stuff);
}

sub decode_utf8 {
    my ($class, $stuff, $check) = @_;
    _apply(sub { Encode::decode_utf8($_[0], $check) }, {}, $stuff);
}

sub encode_utf8 {
    my ($class, $stuff) = @_;
    _apply(sub { Encode::encode_utf8($_[0]) }, {}, $stuff);
}

sub from_to {
    my ($class, $stuff, $from_enc, $to_enc, $check) = @_;
    @_ >= 4 or Carp::croak("Usage: $class->from_to(OCTET, FROM_ENC, TO_ENC[, CHECK])");
    $from_enc = Encode::find_encoding($from_enc)
        || Carp::croak("$class: unknown encoding '$from_enc'");
    $to_enc = Encode::find_encoding($to_enc)
        || Carp::croak("$class: unknown encoding '$to_enc'");
    _apply(sub { Encode::from_to($_[0], $from_enc, $to_enc, $check) }, {}, $stuff);
    return $stuff;
}

1;
__END__

=encoding utf8

=head1 NAME

XMLTV::Data::Recursive::Encode - Encode/Decode Values In A Structure

=head1 SYNOPSIS

    use XMLTV::Data::Recursive::Encode;

    XMLTV::Data::Recursive::Encode->decode('euc-jp', $data);
    XMLTV::Data::Recursive::Encode->encode('euc-jp', $data);
    XMLTV::Data::Recursive::Encode->decode_utf8($data);
    XMLTV::Data::Recursive::Encode->encode_utf8($data);
    XMLTV::Data::Recursive::Encode->from_to($data, $from_enc, $to_enc[, $check]);

=head1 DESCRIPTION

XMLTV::Data::Recursive::Encode visits each node of a structure, and returns a new
structure with each node's encoding (or similar action). If you ever wished
to do a bulk encode/decode of the contents of a structure, then this
module may help you.

=head1 METHODS

=over 4

=item decode

    my $ret = XMLTV::Data::Recursive::Encode->decode($encoding, $data, [CHECK]);

Returns a structure containing nodes which are decoded from the specified
encoding.

=item encode

    my $ret = XMLTV::Data::Recursive::Encode->encode($encoding, $data, [CHECK]);

Returns a structure containing nodes which are encoded to the specified
encoding.

=item decode_utf8

    my $ret = XMLTV::Data::Recursive::Encode->decode_utf8($data, [CHECK]);

Returns a structure containing nodes which have been processed through
decode_utf8.

=item encode_utf8

    my $ret = XMLTV::Data::Recursive::Encode->encode_utf8($data);

Returns a structure containing nodes which have been processed through
encode_utf8.

=item from_to

    my $ret = XMLTV::Data::Recursive::Encode->from_to($data, FROM_ENC, TO_ENC[, CHECK]);

Returns a structure containing nodes which have been processed through
from_to.

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom AAJKLFJEF GMAIL COME<gt>

gfx

=head1 SEE ALSO

This module is inspired from L<Data::Visitor::Encode>, but this module depended to too much modules.
I want to use this module in pure-perl, but L<Data::Visitor::Encode> depend to XS modules.

L<Unicode::RecursiveDowngrade> does not supports perl5's Unicode way correctly.

=head1 LICENSE

Copyright (C) 2010 Tokuhiro Matsuno All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
