package XMLTV::ValidateFile;

use strict;

BEGIN {
    use Exporter   ();
    our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/LoadDtd ValidateFile/;
}
our @EXPORT_OK;

use XML::LibXML;
use File::Slurp qw/read_file/;
use XMLTV::Supplement qw/GetSupplement/;

our $REQUIRE_CHANNEL_ID=1;

my( $dtd, $parser );

=head1 NAME

XMLTV::ValidateFile - Validates an XMLTV file

=head1 DESCRIPTION

Utility library that validates that a file is correct according to
http://wiki.xmltv.org/index.php/XMLTVFormat.


=head1 EXPORTED FUNCTIONS

All these functions are exported on demand.

=over 4

=cut

=item LoadDtd

Load the xmltv dtd. Takes a single parameter which is the name of
the xmltv dtd file.

LoadDtd must be called before ValidateFile can be called.

=cut

sub LoadDtd {
    my( $dtd_file ) = @_;

    my $dtd_str = read_file($dtd_file)
	or die "Failed to read $dtd_file";

    $dtd = XML::LibXML::Dtd->parse_string($dtd_str);
}

=item ValidateFile

Validate that a file is valid according to the XMLTV dtd and try to check
that it contains valid information. ValidateFile takes a filename as parameter
and optionally also a day and an offset and prints error messages to STDERR.

ValidateFile returns a list of errors that it found with the file. Each
error takes the form of a keyword:

ValidateFile checks the following:

=over

=item notwell

The file is not well-formed XML.

=item notvalid

The file does not follow the XMLTV DTD.

=item invalidid

An xmltvid does not look like a proper id, i.e. it does not match
/^[-a-zA-Z0-9]+(\.[-a-zA-Z0-9]+)+$/.

=item duplicateid

More than one channel-entry found for a channelid.

=item unknownid

No channel-entry found for a channelid that is used in a programme-entry.

=item noprogrammes

No programme entries were found in the file.

=item emptytitle

A programme entry with an empty or missing title was found.

=item emptydescription

A programme entry with an empty desc-element was found. The desc-element
shall be omitted if there is no description.

=item badstart

A programme entry with an invalid start-time was found.

=item badstop

A programme entry with an invalid stop-time was found.

=item badepisode

A programme entry with an invalid episode number was found.

=item missingtimezone

The start/stop time for a programme entry does not include a timezone.

=item invalidtimezone

The start/stop time for a programme entry contains an invalid timezone.

=item badiso8859

The file is encoded in iso-8859 but contains characters that
have no meaning in iso-8859 (or are control characters).
If it's iso-8859-1 (aka Latin 1) it might be some characters in windows-1252 encoding.

=item badutf8

The file is encoded in utf-8 but contains characters that look strange.
1) Mis-encoded single characters represented with [EF][BF][BD] bytes
2) Mis-encoded single characters represented with [C3][AF][C2][BF][C2][BD] bytes
3) Mis-encoded single characters in range [C2][80-9F]

=item badentity

The file contains one or more undefined XML entities.

=back

If no errors are found, an empty list is returned.

=cut

my %errors;
my %timezoneerrors;

sub ValidateFile {
    my( $file ) = @_;

    if( not defined( $parser ) ) {
	$parser = XML::LibXML->new();
	$parser->line_numbers(1);
    }

    if( not defined( $dtd ) ) {
	my $dtd_str = GetSupplement( undef, 'xmltv.dtd');
	$dtd = XML::LibXML::Dtd->parse_string( $dtd_str );
    }

    %errors = ();

    my $doc;

    eval { $doc = $parser->parse_file( $file ); };

    if ( $@ ) {
	w( "The file is not well-formed xml:\n$@ ", 'notwell');
	return (keys %errors);
    }

    eval { $doc->validate( $dtd ) };
    if ( $@ ) {
	w( "The file is not valid according to the xmltv dtd:\n $@",
	   'notvalid' );
	return (keys %errors);
    }

    if( $doc->encoding() =~ m/^iso-8859-\d+$/i ) {
	verify_iso8859xx( $file, $doc->encoding() );
    } elsif( $doc->encoding() =~ m/^utf-8$/i ) {
	verify_utf8( $file );
    }
    verify_entities( $file );

    my $w = sub {
	my( $p, $msg, $id ) = @_;
	w( "Line " . $p->line_number() . " $msg", $id );
    };

    my %channels;

    my $ns = $doc->find( "//channel" );

    foreach my $ch ($ns->get_nodelist) {
	my $channelid = $ch->findvalue('@id');
	my $display_name = $ch->findvalue('display-name/text()');

	$w->( $ch, "Invalid channel-id '$channelid'", 'invalidid' )
	    if $channelid !~ /^[-a-zA-Z0-9]+(\.[-a-zA-Z0-9]+)+$/;

	$w->( $ch, "Duplicate channel-tag for '$channelid'", 'duplicateid' )
	    if defined( $channels{$channelid} );

	$channels{$channelid} = 0;
    }

    $ns = $doc->find( "//programme" );
    if ($ns->size() == 0) {
	w( "No programme entries found.", 'noprogrammes' );
	return (keys %errors);
    }

    foreach my $p ($ns->get_nodelist) {
	my $channelid = $p->findvalue('@channel');
	my $start = $p->findvalue('@start');
	my $stop = $p->findvalue('@stop');
	my $title = $p->findvalue('title/text()');
	my $desc;
	$desc = $p->findvalue('desc/text()')
	    if $p->findvalue( 'count(desc)' );

	my $xmltv_episode = $p->findvalue('episode-num[@system="xmltv_ns"]' );

	if ($REQUIRE_CHANNEL_ID and not exists( $channels{$channelid} )) {
	    $w->( $p, "Channel '$channelid' does not have a <channel>-entry.",
		  'unknownid' );
	    $channels{$channelid} = 0;
	}

	$channels{$channelid}++;

	$w->( $p, "Empty title", 'emptytitle' )
	    if $title =~ /^\s*$/;

	$w->( $p, "Empty description", 'emptydescription' )
	    if defined($desc) and $desc =~ /^\s*$/;

	$w->( $p, "Invalid start-time '$start'", 'badstart' )
	    if not verify_time( $start );

	$w->( $p, "Invalid stop-time '$stop'", 'badstop' )
	    if $stop ne "" and not verify_time( $stop );

	if( $xmltv_episode =~ /\S/ ) {
	    $w->($p, "Invalid episode-number '$xmltv_episode'", 'badepisode' )
		if $xmltv_episode !~ /^\s*\d* (\s* \/ \s*\d+)? \s* \.
		                       \s*\d* (\s* \/ \s*\d+)? \s* \.
		                       \s*\d* (\s* \/ \s*\d+)? \s* $/x;
	}
    }

    foreach my $channel (keys %channels) {
	if ($channels{$channel} == 0) {
	    w( "No programme entries found for $channel",
	       'channelnoprogramme' );
	}
    }

    return (keys %errors);
}

sub verify_time
{
    my( $timestamp ) = @_;

    # $tz is optional per the XMLTV DTD
    my( $date, $time, $tz ) =
	($timestamp =~ /^(\d{8})(\d{4,6})(\s+([A-Z]+|[+-]\d{4}))?$/ );

    return 0 unless defined $date;
    return 0 unless defined $time;
    return 1;
}

sub verify_iso8859xx
{
    # code points not used in iso-8859 according to http://de.wikipedia.org/wiki/ISO_8859
    my %unused_iso8859 = (
        'iso-8859-1'  => undef,
        'iso-8859-2'  => undef,
        'iso-8859-3'  => '\xa5\xae\xbe\xc3\xd0\xe3\xf0',
        'iso-8859-4'  => undef,
        'iso-8859-5'  => undef,
        'iso-8859-6'  => '\xa1-\xa3\xa5-\xab\xae-\xba\xbc-\xbe\xc0\xdb-\xdf\xf3-xff',
        'iso-8859-7'  => '\xae\xd2\xff',
        'iso-8859-8'  => '\xa1\xbf-\xde\xfb-\xfc\xff',
        'iso-8859-9'  => undef,
        'iso-8859-10' => undef,
        'iso-8859-11' => '\xdb-\xde\xfc-\xff',
        'iso-8859-12' => undef,
        'iso-8859-13' => undef,
        'iso-8859-14' => undef,
        'iso-8859-15' => undef,
    );
    # code points of unusual control characters used in iso-8859 according to http://de.wikipedia.org/wiki/ISO_8859
    my %unusual_iso8859 = (
        'iso-8859-1'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-2'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-3'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-4'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-5'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-6'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-7'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-8'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-9'  => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-10' => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-11' => '\x00-\x08\x0b-\x1f\x7f-\xa0',
        'iso-8859-12' => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-13' => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-14' => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
        'iso-8859-15' => '\x00-\x08\x0b-\x1f\x7f-\xa0\xad',
    );
    my( $filename, $encoding ) = @_;
    $encoding = lc( $encoding );

    my $file_str = read_file($filename);
    my $unusual = $unusual_iso8859{$encoding};
    my $unused = $unused_iso8859{$encoding};

    if( defined( $unusual ) ) {
        if( $file_str =~ m/[$unusual]+/ ) {
            my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})([$unusual]+)(.{0,15})/ );
            w( "file contains unexpected control characters"
               . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
               . sprintf( "\n%*s", 12+length( $hintpre ) , "^" )
               , 'badiso8859' );
        }
    }

    if( defined( $unused ) ) {
        if( $file_str =~ m/[$unused]+/ ) {
            my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})([$unused]+)(.{0,15})/ );
            w( "file contains bytes without meaning in " . $encoding
               . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
               . sprintf( "\n%*s", 12+length( $hintpre ) , "^" )
               , 'badiso8859' );
        }
    }

    return 1;
}

# inspired by utf8 fixups in _uk_rt
sub verify_utf8 {
    my( $filename ) = @_;

    my $file_str = read_file($filename);

    # 1) Mis-encoded single characters represented with [EF][BF][BD] bytes
    if( $file_str =~ m/\xEF\xBF\xBD]/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})(\xEF\xBF\xBD)(.{0,15})/ );
        w( "file contains misencoded characters"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre ) , "^^^" )
           , 'badutf8' );
    }

    # 2) Mis-encoded single characters represented with [C3][AF][C2][BF][C2][BD] bytes
    if( $file_str =~ m/\xC3\xAF\xC2\xBF\xC2\xBD/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})(\xC3\xAF\xC2\xBF\xC2\xBD)(.{0,15})/ );
        w( "file contains misencoded characters"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre ) , "^^^^^^" )
           , 'badutf8' );
    }

    # 3) Mis-encoded single characters in range [C2][80-9F]
    if( $file_str =~ m/\xC2[\x80-\x9F]/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})(\xC2[\x80-\x9F])(.{0,15})/ );
        w( "file contains unexpected control characters, misencoded windows-1252?"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre ) , "^^" )
           , 'badutf8' );
    }

    # 4) The first two (C0 and C1) could only be used for overlong encoding of basic ASCII characters.
    if( $file_str =~ m/[\xC0-\xC1]/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})([\xC0-\xC1])(.{0,15})/ );
        w( "file contains bytes that should never appear in utf-8"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre ) , "^" )
           , 'badutf8' );
    }

    # 5) start bytes of sequences that could only encode numbers larger than the 0x10FFFF limit of Unicode.
    if( $file_str =~ m/[\xF5-\xFF]/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})([\xF5-\xFF])(.{0,15})/ );
        w( "file contains bytes that should never appear in utf-8"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre ) , "^" )
           , 'badutf8' );
    }

    # 6) first continuation byte missing after start of sequence
    if( $file_str =~ m/[\xC2-\xF4][\x00-\x7F\xC0-\xFF]/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})([\xC2-\xF4][\x00-\x7F\xC0-\xFF])(.{0,15})/ );
        w( "file contains an utf-8 sequence with missing continuation bytes"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre )+1 , "^" )
           , 'badutf8' );
    }

    # 7) second continuation byte missing after start of sequence
    if( $file_str =~ m/[\xE0-\xF4][\x80-\xBF][\x00-\x7F\xC0-\xFF]/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})([\xE0-\xF4][\x80-\xBF][\x00-\x7F\xC0-\xFF])(.{0,15})/ );
        w( "file contains an utf-8 sequence with missing continuation bytes"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre )+2 , "^" )
           , 'badutf8' );
    }

    # 8) third continuation byte missing after start of sequence
    if( $file_str =~ m/[\xF0-\xF4][\x80-\xBF][\x80-\xBF][\x00-\x7F\xC0-\xFF]/ ) {
        my ($hintpre, $hint, $hintpost) = ( $file_str =~ m/(.{0,15})([\xF0-\xF4][\x80-\xBF][\x80-\xBF][\x00-\x7F\xC0-\xFF])(.{0,15})/ );
        w( "file contains an utf-8 sequence with missing continuation bytes"
           . "\nlook here \"" . $hintpre . $hint . $hintpost . "\""
           . sprintf( "\n%*s", 11+length( $hintpre )+3 , "^" )
           , 'badutf8' );
    }

    return 1;
}

sub verify_entities
{
    my( $filename ) = @_;

    my $file_str = read_file($filename);

    if( $file_str =~ m/&[^#].+?;/ ) {
        my ($entity) = ( $file_str =~ m/&([^#].+?);/ );
        my %fiveentities = ('quot' => 1, 'amp' => 1, 'apos' => 1, 'lt' => 1, 'gt' => 1);
        if (!exists($fiveentities{$entity})) {
            w( "file contains undefined entity: $entity", 'badentity' );
        }
    }

    return 1;
}

sub w {
    my( $msg, $id ) = @_;
    print "$msg\n";
    $errors{$id}++ if defined $id;
}


1;

=back

=head1 BUGS

It is currently necessary to specify the path to the xmltv dtd-file.
This should not be necessary.

=head1 COPYRIGHT

Copyright (C) 2006 Mattias Holmlund.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

=cut

### Setup indentation in Emacs
## Local Variables:
## perl-indent-level: 4
## perl-continued-statement-offset: 4
## perl-continued-brace-offset: 0
## perl-brace-offset: -4
## perl-brace-imaginary-offset: 0
## perl-label-offset: -2
## cperl-indent-level: 4
## cperl-brace-offset: 0
## cperl-continued-brace-offset: 0
## cperl-label-offset: -2
## cperl-extra-newline-before-brace: t
## cperl-merge-trailing-else: nil
## cperl-continued-statement-offset: 2
## indent-tabs-mode: t
## End:
