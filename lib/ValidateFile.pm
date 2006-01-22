package XMLTV::ValidateFile;

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
use File::Slurp;

my $dtd, $parser;

=head1 NAME

XMLTV::ValidateFile

=head1 DESCRIPTION

Utility library that validates that a file is correct according to 
http://membled.com/twiki/bin/view/Main/XmltvFileFormat.


=head1 EXPORTED FUNCTIONS

All these functions are exported on demand.

=over 4

=cut

sub w;

=item LoadDtd

=cut

sub LoadDtd
{ 
    my( $dtd_file ) = @_;
    
    my $dtd_str = read_file($dtd_file);
    $dtd = XML::LibXML::Dtd->parse_string($dtd_str);
    
    $parser = XML::LibXML->new();
    $parser->line_numbers(1);
    
}

sub ValidateFile
{
    my( $file ) = @_;

    die "ValidateFile called without previous call to LoadDtd" 
	unless defined $dtd;

    my $errors = 0;
    
    my $doc;
    
    eval { $doc = $parser->parse_file( $file ); };
    
    if ( $@ )
    {
	w "The file is not well-formed xml:\n$@ ";
	return 1;
    }
    
    eval { $doc->validate( $dtd ) };  
    if ( $@ )
    {
	w "The file is not valid according to the xmltv dtd:\n $@";
	return 1;
    }

    my $w = sub 
    { 
	w "Line " . $_[0]->line_number() . " $_[1]";
	$errors++;
    };
    
    my %channels;
    
    my $ns = $doc->find( "//channel" );
    foreach my $ch ($ns->get_nodelist)
    {
	my $channelid = $ch->findvalue('@id');
	my $display_name = $ch->findvalue('display-name/text()');
	
	
	$w->( $ch, "Illegal channel-id $channelid" )
	    if $channelid !~ /^[-a-zA-Z0-9]+(\.[-a-zA-Z0-9]+)+$/;
	
	$w->( $ch, "Duplicate channel-tag for $channelid" )
	    if defined( $channels{$channelid} );
	
	$channels{$channelid} = $display_name;
    }
    
    $ns = $doc->find( "//programme" );
    
    foreach my $p ($ns->get_nodelist)
    {
	my $channelid = $p->findvalue('@channel');
	my $start = $p->findvalue('@start');
	my $stop = $p->findvalue('@stop');
	my $title = $p->findvalue('title/text()');
	my $desc = $p->findvalue('desc/text()');
		
	if ( not defined( $channels{$channelid} ))
	{
	    $w->( $p, "Channel $channelid does not have a <channel>-entry." );
	    $channels{$channelid} = "auto";
	    $errors++;
	}
	
	$w->( $p, "Empty title" )    
	    if $title =~ /^\s*$/;
	
	$w->( $p, "Illegal start-time $start" )
	    if not verify_time( $start );
	
	$w->( $p, "Illegal stop-time $stop" )
	    if $stop ne "" and not verify_time( $stop );
    }
    
    return $errors;
}

sub verify_time
{
    my( $time ) = @_;

    return $time =~ /^\d{12,14}(\s+([A-Z]+|[+-]\d{4}))$/;
}

sub w
{
    print "$_[0]\n";
}

1;

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
