package XMLTV::Configure;

# use version number for feature detection:
# 0.005065 : can use 'constant' in write_string()
# 0.005065 : comments in config file not restricted to starting in first column
# 0.005066 : make writes to the config-file atomic
our $VERSION = 0.005066;

BEGIN {
    use Exporter   ();
    our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/LoadConfig SaveConfig Configure SelectChannelsStage/;
}
our @EXPORT_OK;

use XMLTV::Ask;
use XMLTV::Config_file;
use XML::LibXML;

=head1 NAME

XMLTV::Configure - Configuration file handling for XMLTV grabbers

=head1 DESCRIPTION

Utility library that helps grabbers read from configuration files
and implement a configuration method that can be run from the
command-line.

=head1 EXPORTED FUNCTIONS

All these functions are exported on demand.

=over 4

=cut

=item LoadConfig

Takes the name of the configuration file to load as a parameter.

Returns a hashref with configuration fieldnames as keys. Note
that the values of the hash are references to an array of values.

Example:
  {
    username => [ 'mattias' ],
    password => [ 'xxx' ],
    channel => [ 'svt1.svt.se', 'kanal5.se' ],
    no_channel => ['svt2.svt.se' ],
  }

Note that unselected options from a selectmany are collected
in an entry named after the key with a prefix of 'no_'. See
the channel and no_channel entry in the example. They are the
result of a selectmany with id=channel.

The configuration file must be in the format described in
the file "ConfigurationFiles.txt". If the file does not
exist or if the format is wrong, LoadConfig returns undef.

=cut

sub LoadConfig
{
    my( $config_file ) = @_;

    my $data = {};

    open IN, "< $config_file" or return undef;

    foreach my $line (<IN>)
    {
	$line =~ tr/\n\r//d;
	next if $line =~ /^\s*$/;
	next if $line =~ /^\s*#/;

	# Only accept lines with key=value or key!value.
	# No white-space is allowed before
	# the equal-sign. White-space after the equal-sign is considered
	# part of the value, except for white-space at the end of the line
	# which is ignored.
	my( $key, $sign, $value ) = ($line=~ /^(\S+?)([=!])(.*?)\s*(#.*)?$/ );

	return undef unless defined $key;
	if( $sign eq '=' )
	{
	    push @{$data->{$key}}, $value;
	}
	else
	{
	    push @{$data->{"no_$key"}}, $value;
	}
    }

    close IN;
    return $data;
}

=item SaveConfig

Write a configuration hash in the format returned by LoadConfig to
a file that can be loaded with LoadConfig. Takes two parameters, a reference
to a configuration hash and a filename.

Note that a grabber should normally never have to call SaveConfig. This
is done by the Configure-method.

=cut

sub SaveConfig
{
    my( $conf, $config_file ) = @_;

    # Test if configuration file is writeable
    if (-f $config_file && !(-w $config_file)) { die "Cannot write to $config_file"; }

    # Create temporary configuration file.
    open OUT, "> $config_file.TMP"
	or die "Failed to open $config_file.TMP for writing.";

    foreach my $key (keys %{$conf})
    {
	next if $key eq "channel";
    next if $key eq "lineup";
	foreach my $value (@{$conf->{$key}})
	{
	    print OUT "$key=$value\n";
	}
    }

    if (exists $conf->{lineup}) {
        print OUT "lineup=$conf->{lineup}[0]\n";
    }
    elsif( exists( $conf->{channel} ) )
    {
	foreach my $value (@{$conf->{channel}})
	{
	    print OUT "$key=$value\n";
	}
    }

    close OUT;

    # Store temporary configuration file
    rename "$config_file.TMP", $config_file or die "Failed to write to $config_file";
}

=item Configure

Generates a configuration file for the grabber.

Takes three parameters: stagesub, listsub and the name of the configuration
file.

stagesub shall be a coderef that takes a stage-name or undef
and a configuration hashref as a parameter and returns an
xml-string that describes the configuration necessary for that stage.
The xml-string shall follow the xmltv-configuration.dtd.

listsub shall be a coderef that takes a configuration hash as returned
by LoadConfig as the first parameter and an option hash as returned by
ParseOptions as the second parameter and returns an xml-string
containing a list of all the channels that the grabber can deliver
data for using the supplied configuration. Note that the listsub
shall not use any channel-configuration from the hashref.

=cut

sub Configure
{
    my( $stagesub, $listsub, $conffile, $opt ) = @_;

    # How can we read the language from the environment?
    my $lang = 'en';

    my $nextstage = 'start';

    # Test if configuration file is writeable
    if (-f $conffile && !(-w $conffile)) { die "Cannot write to $conffile"; }

    # Create temporary configuration file.
    open OUT, "> $conffile.TMP" or die "Failed to write to $conffile.TMP";
    close OUT;

    do
    {
	my $stage = &$stagesub( $nextstage, LoadConfig( "$conffile.TMP" ) );
	$nextstage = configure_stage( $stage, $conffile, $lang );
    } while ($nextstage ne "select-channels" );

    # No more nextstage. Let the user select channels. Do not present
    # channel selection if the configuration is using lineups where
    # channels are determined automatically
    my $conf = LoadConfig( "$conffile.TMP" );
    if (! exists $conf->{lineup}) {
        my $channels = &$listsub( $conf, $opt );
        select_channels( $channels, $conffile, $lang );
    }

    # Store temporary configuration file
    rename "$conffile.TMP", $conffile or die "Failed to write to $conffile";
}

sub configure_stage
{
    my( $stage, $conffile, $lang ) = @_;

    my $nextstage = undef;

    open OUT, ">> $conffile.TMP"
	or die "Failed to open $conffile.TMP for writing";

    my $xml = XML::LibXML->new;
    my $doc = $xml->parse_string($stage);

    binmode(STDERR, ":utf8") if ($doc->encoding eq "utf-8");

    my $ns = $doc->find( "//xmltvconfiguration/*" );

    foreach my $p ($ns->get_nodelist)
    {
	my $tag = $p->nodeName;
	if( $tag eq "nextstage" )
	{
	    $nextstage = $p->findvalue( '@stage' );
	    last;
	}

	my $id = $p->findvalue( '@id' );
	my $title = getvalue( $p, 'title', $lang );
	my $description = getvalue( $p, 'description', $lang );
	my $default = $p->findvalue( '@default' );
	my $constant = $p->findvalue( '@constant' );

	my $value;

	my $q = $default ne '' ? "$title: [$default]" :
	                              "$title:";

	say( "$description" ) if $constant eq '';
	if( $tag eq 'string' )
	{
	    $value = $constant if $constant ne '';
	    $value = ask( "$q" ) if $constant eq '';
	    $value = $default if $value eq "";
	    print OUT "$id=$value\n";
	}
	elsif( $tag eq 'secretstring' )
	{
	    $value = ask_password( "$q" );
	    $value = $default if $value eq "";
	    print OUT "$id=$value\n";
	}


	# This must be a selectone or selectmany

	my( @optionvalues, @optiontexts );

	my $ns2 = $p->find( "option" );

	foreach my $p2 ($ns2->get_nodelist)
	{
	    push @optionvalues, $p2->findvalue( '@value' );
	    push @optiontexts, getvalue( $p2, 'text', $lang );
	}

	if( $tag eq "selectone" )
	{
	    my $selected = ask_choice( "$title:", $optiontexts[0],
                                       @optiontexts );
	    for( my $i=0; $i<scalar( @optiontexts ); $i++ )
	    {
		if( $optiontexts[$i] eq $selected )
		{
		    $value=$optionvalues[$i];
		}
	    }
	    print OUT "$id=$value\n";
	}
	elsif( $tag eq "selectmany" )
	{
	    my @answers = ask_many_boolean( 0, @optiontexts );
	    for( my $i=0; $i < scalar( @answers ); $i++ )
	    {
		if( $answers[$i] )
		{
		    print OUT "$id=$optionvalues[$i]\n";
		}
		else
		{
		    print OUT "$id!$optionvalues[$i]\n";
		}
	    }
	}

    }

    close OUT;
    return $nextstage;
}

sub select_channels
{
    my( $channels,  $conffile, $lang ) = @_;

    open OUT, ">> $conffile.TMP"
	or die "Failed to open $conffile.TMP for writing";

    my $xml = XML::LibXML->new;
    my $doc;
    $doc = $xml->parse_string($channels);

    my $ns = $doc->find( "//channel" );

    my @channelname;
    my @channelid;

    foreach my $p ($ns->get_nodelist)
    {
	push @channelid, $p->findvalue( '@id' );
	push @channelname, getvalue($p, "display-name", $lang );
    }

    # We need to internationalize this string.
    say( "Select the channels that you want to receive data for." );

    my @answers = ask_many_boolean( 0, @channelname );
    for( my $i=0; $i < scalar( @answers ); $i++ )
    {
	if( $answers[$i] )
	{
	    print OUT "channel=$channelid[$i]\n";
	}
	else
	{
	    print OUT "channel!$channelid[$i]\n";
	}

    }

    close OUT;
}

sub SelectChannelsStage
{
    my( $channels, $grabber_name ) = @_;

    my $xml = XML::LibXML->new;
    my $doc;
    $doc = $xml->parse_string($channels);
    my $encoding = $doc->encoding;

    my $ns = $doc->find( "//channel" );

    my $result;
    my $writer = new XMLTV::Configure::Writer( OUTPUT => \$result,
					       encoding => $encoding );
    $writer->start( { grabber => $grabber_name } );
    $writer->start_selectmany( {
	id => 'channel',
	title => [ [ 'Channels', 'en' ] ],
	description => [
	 [ "Select the channels that you want to receive data for.",
	   'en' ] ],
     } );

    foreach my $p ($ns->get_nodelist)
    {
	# FIXME: Preserve all languages for the display-name
	$writer->write_option( {
	    value=>$p->findvalue( '@id' ),
	    text=> => [ [ getvalue($p, "display-name", 'en' ),
			  'en'] ],
	} );
    }
    $writer->end_selectmany();
    $writer->end( 'end' );

    return $result;
}

sub getvalue
{
    my( $p, $field, $lang ) = @_;

    # Try the correct language first
    my $value = $p->findvalue( $field . "[\@lang='$lang']");

    # Use English if there is no value for the correct language.
    $value = $p->findvalue( $field . "[\@lang='en']")
	unless length( $value ) > 0;

    # Take the first available value as a last resort.
    $value = $p->findvalue( $field . "[1]")
	unless length( $value ) > 0;

    $value =~ s/^\s+//;
    $value =~ s/\s+$//;
    $value =~ tr/\n\r /   /s;

    return $value;
}

=back

=head1 COPYRIGHT

Copyright (C) 2005 Mattias Holmlund.

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
