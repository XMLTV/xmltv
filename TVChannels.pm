# copyright 2000 by Gottfried Szing e9625460@stud3.tuwien.ac.at
#
# version 0.02
# 
package TVChannels;

use strict;



BEGIN {
	use Exporter   ();
	use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

	$VERSION     = "0.02";

	@ISA         = qw(Exporter);
	@EXPORT      = qw(&new &getdisplayname &getalldisplaynames &getuniqename &loadfile);
	%EXPORT_TAGS = ( );     

	# exported package globals 
	@EXPORT_OK   = qw(&loadfile &new &getdisplayname &getalldisplaynames &getuniqename);
}

use vars @EXPORT_OK;
use XML::Simple;
use Data::Dumper;
use IO::File;
use Carp;
use Log::TraceMessages qw(t d);

sub new
{
	my ($class, $language) = @_;

	my	$self = {};

	# if empty check ENV
	if ($language eq "")
	{
		$language = $ENV{"LANG"};

		# default locale ==> use en
		$language = "en" if ($language eq "C");
	}

	$self->{LANG}		= $language;
	$self->{CHANNELS}	= {};

	bless ($self, $class);

	$self->init();

	return $self;
}

sub init
{
	my $self    = shift;
	my $lang	= $self->{LANG};
	my $channels= $self->{CHANNELS};

	my $HOME	= getHomeDir();

	$self->loadfile("/usr/share/xmltv/channels.xml")
	  or $self->loadfile("$HOME/.xmltv/channels.xml")
	    or $self->loadfile("./channels.xml")
	      or die 'cannot find channels.xml anywhere';
}

# translates a unique name to a display name
# optional parametere is the language which 
# overides default language setting
#
# Examples:
# getdisplayname("sat1.de")
# getdisplayname("sat1.de", "en")
#
sub getdisplayname
{
	my $self = shift;
	my $id   = shift || croak("getdisplayname", "missing unique name");
	my $lang = shift || $self->{'LANG'};

	my %channels= %{$self->{'CHANNELS'}};

	my $data = $channels{$id};
	if (defined $data)
	{
	    t "channel data for $id: " . d $data;;
	    foreach my $display ( @{$data->{'display-name'}} )
	      {
		  t 'doing lump: ' . d $display;
		  if ($display->{lang} eq $lang)
		    {
		        for ($display->{content}) {
			    return $_ if not ref;
			    return join(' ', @$_) if ref eq 'ARRAY';
			    die;
			}
		    }
	      }
	}

	return "$id.$lang";
}

# returns all translations for a unique name
# optional a language 
#
# returns an array which contains anonymous arrays
#
# Example output of Dumper:
#$VAR1 = [
#			'de',
#			'SAT.1'
#		];
#$VAR2 = [
#			'en',
#			'SAT.1'
#		];
sub getalldisplaynames
{
    my $self	= shift;
	my $id		= shift || croak("getalldisplaynames", "missing unique name");

	my %channels		= %{$self->{'CHANNELS'}};
	my @translations;

	if (exists $channels{"$id"})
	{
		foreach my $display ( @{$channels{$id}->{'display-name'}} )
		{
			push @translations, [ ($display->{'lang'}, $display->{'content'}->[0]) ];
		}

		return @translations;
	}

	return undef;
}

# returns the display name to a unique name
# the first entry found is returned if the display name
# esists multiple times
#
# optional a language specifuer
sub getuniqename
{
   	my $self = shift;
	my $name = shift
	  || croak("getuniqename", "missing display name to translate");
	my $lang = shift || $self->{'LANG'};

	foreach my $id (keys %{$self->{'CHANNELS'}})
	{
		my @channels = @{$self->{'CHANNELS'}->{$id}->{'display-name'}};

		foreach my $channelname (@channels)
		{
			if ($channelname->{'lang'} eq "$lang")
			{
			    for ($channelname->{content}) {
				if ((ref eq 'ARRAY' and $_->[0] eq $name)
				    or (not ref))
				{
				    return $id;
				}
			    }
			}
		}
	}

	# if supplied language not equal to default
	# search with default language
	$name  =~ /^(\w+)/;

	return "$1.$lang";
}

# overides the default language setting
sub setlanguage
{
   	my $self	= shift;
	my $lang	= shift || $self->{LANG};

	$self->{LANG} = $lang;
}

# returns the currently used language
sub getlanguage
{
   	my $self	= shift;
	return $self->{LANG};
}

sub getHomeDir()
{
	if (exists $ENV{ HOME }) 
	{
		return $ENV{ HOME };
	}
	else
	{
		return (getpwuid($<))[7];
	}
}

# loads a file and merges it to current
# stored translations
#
# existing entries are replaced
# 
# returns: success or failure
sub loadfile
{
	my $self = shift;
	my $file = shift;
	croak("loadfile", "missing file name of xml to load")
	  if not defined $file;

	my %channels= $self->{CHANNELS};

	my $fileh = new IO::File("$file");
	(carp("cannot load $file"), return 0) unless $fileh;

	# load xml
	my $xml = XMLin($fileh, forcearray => 1 );
	t d($xml);
	$fileh->close();
	
	(carp("cannot parse XML from $file"), return 0) unless $xml;

	foreach my $channel (keys %{$xml->{channel}})
	{
		$self->{CHANNELS}->{$channel} = $xml->{channel}->{$channel};
	}

	return 1;
}

1;

#package main;

#use Data::Dumper;

#my $channels = TVChannels->new("de");

#print "Testing Language settinngs\n";
#print "==========================\n";
#print "\nDefault Language: ", $channels->getlanguage();
#$channels->setlanguage("de");
#print "\nAfter setlanguage: ", $channels->getlanguage();


#$channels->loadfile('./channels1.xml');

#print "\n\nTesting translations\n";
#print "====================\n";


