package XMLTV::Options;

use strict;
use warnings;

BEGIN {
    use Exporter   ();
    our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ParseOptions/;
}
our @EXPORT_OK;

use XMLTV;
use XMLTV::Configure qw/LoadConfig Configure SelectChannelsStage/;

use Getopt::Long;
use Carp qw/croak/;
use IO::Wrap qw/wraphandle/;
use IO::Scalar;

my %cap_options = (
		   all => [qw/
			   help|h
			   version
			   capabilities
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
		   newchannels => [qw/channel-updates=s/],
		   );

my %cap_defaults = (
		    all => { 
			capabilities => 0,
			help => 0,
			version => 0,
		    },
		    baseline => {
			quiet => 0,
			days => 5, 
			offset => 0,
			output => undef,
			debug => 0,
		    },
		    manualconfig => {
			configure => 0,
		    },
		    apiconfig => {
			'configure-api' => 0,
			stage => 'start',
			'list-channels' => 0,
		    },
		    );


=pod
    
my( $opt, $conf ) = ParseOptions( { 
  grabber_name => 'tv_grab_test',
  defaults => {},
  capabilities => [qw/baseline manualconfig apiconfig/],
  stage_sub => \&config_stage,
  listchannels_sub => \&list_channels,
  extra_options => {},
  extra_help => "",
} );

$opt is a hashref with the values for all command-line options in the
format returned by Getopt::Long (See "Storing options in a hash" in 
perldoc Getopt::Long).

$conf is a hashref to the data loaded from the configuration file.
See perldoc XMLTV::Configure.

ParseOptions handles the following options automatically without returning:

--help
--capabilities
--version (note that --version is better handled with the XMLTV::Version
module)

If the grabber supplies a stage_sub and a listchannels_sub, ParseOptions
also takes care of the following options:
--configure
--configure-api
--list-channels
--stage

If the --output option is specified, STDOUT will be redirected to
the specified file.

The grabber must check the following options on its own:
--days
--offset
--quiet
--debug

and any other options that are grabber specific. This can be done by reading
$opt->{days} etc.

=cut

sub ParseOptions
{
    my( $p ) = @_;
    
    my @optdef=();
    my $opt={};
    
    push( @optdef, @{$cap_options{all}} );
    hash_push( $opt, $cap_defaults{all} );
    
    $opt->{'config-file'} = XMLTV::Config_file::filename(
	 undef, $p->{grabber_name}, 1 );
    
    foreach my $cap (@{$p->{capabilities}})
    {
	croak "Unknown capability $cap" unless exists $cap_options{$cap};
	
	push( @optdef, @{$cap_options{$cap}} );
	hash_push( $opt, $cap_defaults{$cap} );
    }
    
    push( @optdef, @{$p->{extra_options}} )
	if( defined( $p->{extra_options} ) );
    
    hash_push( $opt, $p->{defaults} )
	if( defined( $p->{defaults} ) );
    
    my $res = GetOptions( $opt, @optdef );
    
    if( (not $res) || $opt->{help} )
    {
	PrintUsage( $p );
	exit 1;
    }
    elsif( $opt->{capabilities} )
    {
	print join( "\n", @{$p->{capabilities}} ) . "\n";
	exit 0;
    }
    elsif( $opt->{version} )
    {
	# This is only a fallback for when the grabber author has forgotten
	# to load the XMLTV::Version module.
	print "XMLTV module version $XMLTV::VERSION\n";
	exit 0;
    }
    
    if( defined( $opt->{output} ) )
    {
	if( not open( OUT, "> $opt->{output}" ) )
	{
	    print STDERR "Cannot write to $opt->{output}.";
	    exit 1;
	}
	
	# Redirect STDOUT to the file.
	select( OUT );
    }
    
    if( $opt->{configure} )
    {
	Configure( $p->{stage_sub}, $p->{listchannels_sub},
		   $opt->{"config-file"}, $opt );
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
   
    if( not defined( $conf ) )
    {
	print STDERR "You need to configure the grabber by running it with --configure";
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
	
$gn --version

$gn --capabilities
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
