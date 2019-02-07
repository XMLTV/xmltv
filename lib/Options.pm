package XMLTV::Options;

use strict;
use warnings;

# use version number for feature detection:
# 0.005065 : added --info / --man option (prints POD and then exits)
our $VERSION = 0.005065;

BEGIN {
    use Exporter   ();
    our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ParseOptions/;
}
our @EXPORT_OK;

=head1 NAME

XMLTV::Options - Command-line parsing for XMLTV grabbers

=head1 DESCRIPTION

Utility library that implements command-line parsing and handles a lot
of functionality that is common to all XMLTV grabbers.

=head1 EXPORTED FUNCTIONS

All these functions are exported on demand.

=cut

use XMLTV;
use XMLTV::Configure qw/LoadConfig Configure SelectChannelsStage/;

use Getopt::Long;
use Carp qw/croak/;

my %cap_options = (
		   all => [qw/
			   help|h
			   version
			   capabilities
			   description
				 info
				 man
			   /],
		   baseline => [qw/
			   days=i
			   offset=i
			   quiet
			   output=s
			   debug
			   config-file=s
			   /],
		   manualconfig => [qw/configure/],
		   apiconfig => [qw/
			   configure-api
			   stage=s
			   list-channels
			   /],
		   tkconfig => [qw/gui=s/],
		   # The cache option is normally handled by XMLTV::Memoize
		   # but in case it is not used, we handle it here as well.
		   cache => [qw/
			   cache:s
			   /],
		   share => [qw/
			   share=s
			   /],
		   preferredmethod => [qw/
			   preferredmethod
			   /],
		   lineups => [qw/
			   get-lineup
			   list-lineups
			   /],
		   );

my %cap_defaults = (
		   all => {
			   capabilities => 0,
			   help => 0,
			   version => 0,
			   info => 0,
			   man => 0,
			   },
		   baseline => {
			   quiet => 0,
			   days => 5,
			   offset => 0,
			   output => undef,
			   debug => 0,
			   gui => undef,
			   },
		   manualconfig => {
			   configure => 0,
			   },
		   apiconfig => {
			   'configure-api' => 0,
			   stage => 'start',
			   'list-channels' => 0,
			   },
		   tkconfig => {
		    },
		   cache => {
			   cache => undef,
			   },
		   share => {
			   share => undef,
			   },
		   preferredmethod => {
			   preferredmethod => 0,
			   },
		   lineups => {
			   'get-lineup' => 0,
			   'list-lineups' => 0,
			   }
		   );

=head1 USAGE

=over

=item B<ParseOptions>

ParseOptions shall be called by a grabber to parse the command-line
options supplied by the user. It takes a single hashref as a parameter.
The entries in the hash configure the behaviour of ParseOptions.

  my( $opt, $conf ) = ParseOptions( {
    grabber_name => 'tv_grab_test',
    version => '1.2',
    description => 'Sweden (tv.swedb.se)',
    capabilities => [qw/baseline manualconfig apiconfig lineups/],
    stage_sub => \&config_stage,
    listchannels_sub => \&list_channels,
    list_lineups_sub => \&list_lineups,
    get_lineup_sub => \&get_lineup,
  } );

ParseOptions returns two hashrefs:

=over

=item *

A hashref with the values for all command-line options in the
format returned by Getopt::Long (See "Storing options in a hash" in
L<Getopt::Long>). This includes both options that the grabber
must handle as well as options that ParseOptions handles for the grabber.

=item *

A hashref to the data loaded from the configuration file.
See L<XMLTV::Configure> for the format of $conf.

=back

ParseOptions handles the following options automatically without returning:

=over

=item --help

=item --info (or --man)

=item --capabilities

=item --version

=item --description

=item --preferredmethod

Handled automatically if the preferredmethod capability has been set and
the preferredmethod option has been specified in the call to ParseOptions.

=back

ParseOptions also takes care of the following options without returning,
by calling the stage_sub, listchannels_sub, list_lineups_sub and get_lineup_sub
callbacks supplied by the grabber:

=over

=item --configure

=item --configure-api

=item --stage

=item --list-channels

=item --list-lineups

=item --get-lineup

=back

ParseOptions will thus only return to the grabber when the grabber shall
actually grab data.

If the --output option is specified, STDOUT will be redirected to
the specified file.

The grabber must check the following options on its own:

=over

=item --days

=item --offset

=item --quiet

=item --debug

=back

and any other options that are grabber specific. This can be done by reading
$opt->{days} etc.

=item B<Changing the behaviour of ParseOptions>


The behaviour of ParseOptions can be influenced by passing named arguments
in the hashref. The following arguments are supported:

=over

=item grabber_name

Required. The name of the grabber (e.g. tv_grab_se_swedb). This is used
when printing the synopsis.

=item description

Required. The description for the grabber. This is returned in response to
the --description option and shall say which region the grabber returns data
for. Examples: "Sweden", or "Sweden (tv.swedb.se)" if there are several grabbers
for a region or country).

=item version

Required. The version number of the grabber to be displayed. Supported version
string formats include "x", "x.y", and "x.y.z".

=item capabilities

Required. The capabilities that the grabber shall support. Only capabilities
that XMLTV::Options knows how to handle can be specified. Example:

  capabilities => [qw/baseline manualconfig apiconfig/],

Note that XMLTV::Options guarantees that the grabber supports the manualconfig
and apiconfig capabilities. The capabilities share and cache can be
specified if the grabber supports them. XMLTV::Options will then automatically
accept the command-line parameters --share and --cache respectively.

=item stage_sub

Required. A coderef that takes a stage-name
and a configuration hashref as a parameter and returns an
xml-string that describes the configuration necessary for that stage.
The xml-string shall follow the xmltv-configuration.dtd.

=item listchannels_sub

Required. A coderef that takes a configuration
hash as returned by XMLTV::Configure::LoadConfig as the first parameter
and an option hash as returned by
ParseOptions as the second parameter, and returns an xml-string
containing a list of all the channels that the grabber can deliver
data for using the supplied configuration. Note that the listsub
shall not use any channel-configuration from the hashref.

=item load_old_config_sub

Optional. Default undef. A coderef that takes a filename as a parameter
and returns a configuration hash in the same format as returned by
XMLTV::Configure::LoadConfig. load_old_config_sub is called if
XMLTV::Configure::LoadConfig fails to parse the configuration file. This
allows the grabber to load configuration files created with an older
version of the grabber.

=item list_lineups_sub

Optional. A coderef that takes an option hash as returned by ParseOptions
as a parameter, and returns an xml-string containing a list of all the
channel lineups for which the grabber can deliver data.
The xml-string shall follow the xmltv-lineups.xsd schema.

=item get_lineup_sub

Optional. A coderef that returns an xml-string describing the configured
lineup. The xml-string shall follow the xmltv-lineups.xsd schema.

=item preferredmethod

Optional. A value to return when the grabber is called with the
--preferredmethod parameter. Example:

  my( $opt, $conf ) = ParseOptions( {
    grabber_name => 'tv_grab_test',
    version => '1.2',
    description => 'Sweden (tv.swedb.se)',
    capabilities => [qw/baseline manualconfig apiconfig preferredmethod/],
    stage_sub => \&config_stage,
    listchannels_sub => \&list_channels,
    preferredmethod => 'allatonce',
    list_lineups_sub => \&list_lineups,
    get_lineup_sub => \&get_lineup,
  } );

=item defaults

Optional. Default {}. A hashref that contains default values for the
command-line options. It shall be in the same format as returned by
Getopt::Long (See "Storing options in a hash" in  L<Getopt::Long>).

=item extra_options

Optional. Default []. An arrayref containing option definitions in the
format accepted by Getopt::Long. This can be used to support grabber-specific
options. The use of grabber-specific options is discouraged.

=back

=back

=cut

sub ParseOptions
{
    my( $p ) = @_;

    my @optdef=();
    my $opt={};
    my $capabilities = {};

    foreach my $cap (keys %{cap_options})
    {
	$capabilities->{$cap} = 0;
    }

    if( not defined( $p->{version} ) )
    {
	croak "No version specified in call to ParseOptions";
    }

    if( not defined( $p->{description} ) )
    {
	croak "No description specified in call to ParseOptions";
    }


    push( @optdef, @{$cap_options{all}} );
    hash_push( $opt, $cap_defaults{all} );

    $opt->{'config-file'} = XMLTV::Config_file::filename(
	 undef, $p->{grabber_name}, 1 );

    foreach my $cap (@{$p->{capabilities}})
    {
	if (not exists $cap_options{$cap})
	{
	    my @known = sort keys %cap_options;
	    croak "Unknown capability $cap (known: @known)";
	}

	push( @optdef, @{$cap_options{$cap}} );
	hash_push( $opt, $cap_defaults{$cap} );
	$capabilities->{$cap} = 1;
    }

    if( $capabilities->{preferredmethod}
	and not exists($p->{preferredmethod}) )
    {
	croak "You must specify which preferredmethod to use";
    }

    if( exists($p->{preferredmethod})
	and not $capabilities->{preferredmethod} )
    {
	croak "You must include the capability preferredmethod to specify " .
	    "which preferredmethod to use.";
    }

    push( @optdef, @{$p->{extra_options}} )
	if( defined( $p->{extra_options} ) );

    hash_push( $opt, $p->{defaults} )
	if( defined( $p->{defaults} ) );

    my $res = GetOptions( $opt, @optdef );

    if( (not $res) || $opt->{help} || scalar( @ARGV ) > 0 )
    {
	PrintUsage( $p );
	exit 1;
    }
    elsif( $opt->{capabilities} )
    {
	print join( "\n", @{$p->{capabilities}} ) . "\n";
	exit 0;
    }
    elsif( $opt->{preferredmethod} )
    {
	print $p->{preferredmethod} . "\n";
	exit 0;
    }
    elsif( $opt->{version} )
    {
	eval {
	    require XMLTV;
	    print "XMLTV module version $XMLTV::VERSION\n";
	} or print
	    "could not load XMLTV module, xmltv is not properly installed\n";

	if( $p->{version} =~ m/^(?:\d+)(?:\.\d+){0,2}$/)
	{
	    print "This is $p->{grabber_name} version $p->{version}\n";
	}
	elsif( $p->{version} =~ m!\$Id: [^,]+,v (\S+) ([0-9/: -]+)! )
	{
	    print "This is $p->{grabber_name} version $1\n";
	}
	else
	{
	    croak "Invalid version $p->{version}";
	}

	exit 0;
    }
    elsif( $opt->{description} )
    {
	print $p->{description} . "\n";
	exit 0;
    }
    elsif( $opt->{info} || $opt->{man} )
    {
      # pod2usage(-verbose => 2) doesn't work under Windows xmltv.exe (since it needs perldoc)
      if ($^O eq 'MSWin32')
      {
        require Pod::Text;
        Pod::Text->new (sentence => 0, margin => 2, width => 78)->parse_from_file($0);
      }
      else
      {
        require Pod::Usage; import Pod::Usage; pod2usage(-verbose => 2);
      }
      exit 0;
    }

    XMLTV::Ask::init($opt->{gui});

    if( defined( $opt->{output} ) )
    {
	# Redirect STDOUT to the file.
	if( not open( STDOUT, "> $opt->{output}" ) )
	{
	    print STDERR "Cannot write to $opt->{output}.\n";
	    exit 1;
	}

        # Redirect default output to STDOUT
	select( STDOUT );
    }

    if( $opt->{configure} )
    {
	Configure( $p->{stage_sub}, $p->{listchannels_sub},
		   $opt->{"config-file"}, $opt );
	exit 0;
    }

    # no config needed to list lineups supported by grabber
    if( $opt->{"list-lineups"} )
    {
        print &{$p->{list_lineups_sub}}($opt);
        exit 0;
    }

    my $conf = LoadConfig( $opt->{'config-file'} );
    if( not defined( $conf ) and defined( $p->{load_old_config_sub} ) )
    {
	$conf = &{$p->{load_old_config_sub}}( $opt->{'config-file'} );
    }

    if( $opt->{"configure-api"} )
    {
	if( (not defined $conf) and ( $opt->{stage} ne 'start' ) )
	{
	    print STDERR "You need to start configuration with the 'start' stage.\n";
	    exit 1;
	}

	if( $opt->{stage} eq 'select-channels' )
	{
	    my $chanxml = &{$p->{listchannels_sub}}($conf, $opt);
	    print SelectChannelsStage( $chanxml, $p->{grabber_name} );
	}
	else
	{
	    print &{$p->{stage_sub}}( $opt->{stage},
				      LoadConfig( $opt->{"config-file"} ) );
	}
	exit 0;
    }

    if( $opt->{"list-channels"} )
    {
	if( not defined( $conf ) )
	{
	    print STDERR "You need to configure the grabber before you can list " .
		"the channels.\n";
	    exit 1;
	}

	print &{$p->{listchannels_sub}}($conf,$opt);

	exit 0;
    }

    if( $opt->{"get-lineup"} )
    {
        if( not defined( $conf ) )
        {
            print STDERR "You need to configure the grabber before you can output " .
            "your chosen lineup.\n";
            exit 1;
        }

        print &{$p->{get_lineup_sub}}($conf,$opt);
        exit 0;
    }

    if( not defined( $conf ) )
    {
	print STDERR "You need to configure the grabber by running it with --configure \n";
	exit 1;
    }

    return ($opt, $conf);
}

sub PrintUsage
{
    my( $p ) = @_;

    my $gn = $p->{grabber_name};
    my $en = " " x length( $gn );

    print qq/
$gn --help

$gn --info

$gn --version

$gn --capabilities

$gn --description

/;

    if( supports( "baseline", $p ) )
    {
	print qq/
$gn [--config-file FILE]
$en [--days N] [--offset N]
$en [--output FILE] [--quiet] [--debug]
/;
    }

 if( supports( "manualconfig", $p ) )
 {
     print qq/
$gn --configure [--config-file FILE]
/;
 }

    if( supports( "apiconfig", $p ) )
    {
	print qq/
$gn --configure-api [--stage NAME]
$en [--config-file FILE]
$en [--output FILE]

$gn --list-channels [--config-file FILE]
$en [--output FILE] [--quiet] [--debug]
/;
    }

    if( supports( "lineups", $p ) )
    {
        print qq/
$gn --list-lineups [--output FILE]

$gn --get-lineup [--config-file FILE] [--output FILE]
/;
    }
}

sub supports
{
    my( $cap, $p ) = @_;

    foreach my $sc (@{$p->{capabilities}})
    {
	return 1 if( $sc eq $cap );
    }
    return 0;
}

sub hash_push
{
    my( $h, $n ) = @_;
    foreach my $key (keys( %{$n} ))
    {
	$h->{$key} = $n->{$key};
    }
}

1;


=head1 COPYRIGHT

Copyright (C) 2005,2006 Mattias Holmlund.

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
