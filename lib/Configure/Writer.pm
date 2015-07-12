package XMLTV::Configure::Writer;

use strict;
use warnings;

# use version number for feature detection:
# 0.005065 : can use 'constant' in write_string()
our $VERSION = 0.005065;

BEGIN {
    use Exporter   ();
    our (@ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw//;
}
our @EXPORT_OK;

use XML::Writer 0.600;
use base 'XML::Writer';
use Carp;

=pod

=encoding utf8

=head1 NAME

XMLTV::Configure::Writer - Configuration file writer for XMLTV grabbers

=head1 DESCRIPTION

Utility class that helps grabbers write configuration descriptions.

=head1 SYNOPSIS

  use XMLTV::Configure::Writer;

  my $result;
  my $writer = new XMLTV::Writer::Configure( OUTPUT => \$result,
                                             encoding => 'iso-8859-1' );
  $writer->start( { grabber => 'tv_grab_xxx' } );
  $writer->write_string( {
    id => 'username',
    title => [ [ 'Username', 'en' ],
               [ 'Användarnamn', 'sv' ] ],
    description => [ [ 'The username for logging in to DataDirect.', 'en' ],
                     [ 'Användarnamn hos DataDirect', 'sv' ] ],
    } );
  $writer->start_selectone( {
    id => 'lineup',
    title => [ [ 'Lineup', 'en' ],
               [ 'Programpaket', 'sv' ] ],
    description => [ [ 'The lineup of channels for your region.', 'en' ],
                     [ 'Programpaket för din region', 'sv' ] ],
    } );

  $writer->write_option( {
    value=>'eastcoast',
    text=> => [ [ 'East Coast', 'en' ],
                [ 'Östkusten', 'sv' ] ]
  } );

  $writer->write_option( {
    value=>'westcoast',
    text=> => [ [ 'West Coast', 'en' ],
                [ 'Västkusten', 'sv' ] ]
  } );

  $writer->end_selectone();

  $writer->end();

  print $result;

=head1 EXPORTED FUNCTIONS

None.

=cut

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %args = @_;
    croak 'OUTPUT requires a filehandle, not a filename or anything else'
	if exists $args{OUTPUT} and not ref $args{OUTPUT};
    my $encoding = delete $args{encoding};
    my $self = $class->SUPER::new(DATA_MODE => 1, DATA_INDENT => 2, %args);
    bless($self, $class);

    if (defined $encoding) {
	$self->xmlDecl($encoding);
    }
    else {
	# XML::Writer puts in 'encoding="UTF-8"' even if you don't ask
	# for it.
	#
	warn "assuming default UTF-8 encoding for output\n";
	$self->xmlDecl();
    }

#    {
# What is a correct doctype???
#	local $^W = 0; $self->doctype('tv', undef, 'xmltv.dtd');
#    }

    $self->{xmltv_state} = 'new';
    return $self;
}

=head1 METHODS

=over

=item start()

Write the start of the <xmltvconfiguration> element.  Parameter is
a hashref which gives the attributes of this element.

=cut

sub start {
    my $self = shift;
    die 'usage: XMLTV::Writer->start(hashref of attrs)' if @_ != 1;
    my $attrs = shift;

    $self->{xmltv_state} eq 'new'
	or croak 'cannot call start() more than once on XMLTV::Writer';

    $self->startTag( 'xmltvconfiguration', %{$attrs} );
    $self->{xmltv_state}='root';
}

=item write_string()

Write a <string> element. Parameter is a hashref with the data for the
element:

  $writer->write_string( {
    id => 'username',
    title => [ [ 'Username', 'en' ],
               [ 'Användarnamn', 'sv' ] ],
    description => [ [ 'The username for logging in to DataDirect.', 'en' ],
                     [ 'Användarnamn hos DataDirect', 'sv' ] ],
    default => "",
    } );


To add a constant use 'constant' key:
	If constant value is empty then revert to 'ask' procedure.

  $writer->write_string( {
    id => 'version',
    title => [ [ 'Version number', 'en' ] ],
    description => [ [ 'Automatically added version number - no user input', 'en' ] ],
    constant => '123',
    } );

=back

=cut

sub write_string {
    my ($self, $ch) = @_;
    $self->write_string_tag( 'string', $ch );
}

sub write_secretstring {
    my ($self, $ch) = @_;
    $self->write_string_tag( 'secretstring', $ch );
}

sub write_string_tag {
    my ($self, $tag, $ch) = @_;
    croak 'undef parameter hash passed' if not defined $ch;
    croak "expected a hashref, got: $ch" if ref $ch ne 'HASH';

    for ($self->{xmltv_state}) {
	if ($_ eq 'new') {
	    croak 'must call start() on XMLTV::Configure::Writer first';
	}
	elsif ($_ eq 'root') {
	    # Okay.
	}
	elsif ($_ eq 'selectone') {
	    croak 'cannot write string inside selectone';
	}
	elsif ($_ eq 'selectmany') {
	    croak 'cannot write string inside selectmany';
	}
	elsif ($_ eq 'end') {
	    croak 'cannot write string after end()';
	}
	else { die }
    }

    my %ch = %$ch; # make a copy
    my $id = delete $ch{id};
    die "missing 'id' in string" if not defined $id;

    my %h = ( id => $id );
    my $default = delete $ch{default};

    $h{default} = $default if defined $default;

    my $constant = delete $ch{constant};
    $h{constant} = $constant if defined $constant;

    $self->startTag( $tag, %h );

    my $titles = delete $ch{title};
    die "missing 'title' in string" if not defined $titles;

    $self->write_lang_tag( 'title', $titles );

    my $descriptions = delete $ch{description};
    die "missing 'description' in string" if not defined $descriptions;

    $self->write_lang_tag( 'description', $descriptions );

    $self->endTag( $tag )
    }

sub start_selectone {
    my ($self, $ch) = @_;
    $self->start_select( 'selectone', $ch );
}

sub start_selectmany {
    my ($self, $ch) = @_;
    $self->start_select( 'selectmany', $ch );
}

sub end_selectone {
    my $self = shift;
    $self->end_select( 'selectone' );
}

sub end_selectmany {
    my $self = shift;
    $self->end_select( 'selectmany' );
}

sub start_select {
    my ($self, $tag, $ch) = @_;
    croak 'undef parameter hash passed' if not defined $ch;
    croak "expected a hashref, got: $ch" if ref $ch ne 'HASH';

    for ($self->{xmltv_state}) {
	if ($_ eq 'new') {
	    croak 'must call start() on XMLTV::Configure::Writer first';
	}
	elsif ($_ eq 'root') {
	    # Okay.
	}
	elsif ($_ eq 'selectone') {
	    croak "cannot write $tag inside selectone";
	}
	elsif ($_ eq 'selectmany') {
	    croak "cannot write $tag inside selectmany";
	}
	elsif ($_ eq 'end') {
	    croak "cannot write $tag after end()";
	}
	else { die }
    }

    my %ch = %$ch; # make a copy
    my $id = delete $ch{id};
    die "missing 'id' in $tag" if not defined $id;

    my %h = ( id => $id );
    my $default = delete $ch{default};

    $h{default} = $default if defined $default;

    $self->startTag( $tag, %h );

    my $titles = delete $ch{title};
    die "missing 'title' in string" if not defined $titles;

    $self->write_lang_tag( 'title', $titles );

    my $descriptions = delete $ch{description};
    die "missing 'description' in string" if not defined $descriptions;

    $self->write_lang_tag( 'description', $descriptions );

    $self->{xmltv_state} = $tag;
}

sub end_select {
    my( $self, $tag ) = @_;

    if( $self->{xmltv_state} ne $tag )
    {
	croak "cannot write end-tag for $tag without a matching start-tag";
    }

    $self->endTag( $tag );
    $self->{xmltv_state} = 'root';
}

sub write_option {
    my $self = shift;
    my( $data ) = @_;

    for ($self->{xmltv_state}) {
	if ($_ eq 'new') {
	    croak 'must call start() on XMLTV::Configure::Writer first';
	}
	elsif ($_ eq 'root') {
	    croak "cannot write option outside of selectone or selectmany";
	}
	elsif ($_ eq 'selectone') {
	    # Okay
	}
	elsif ($_ eq 'selectmany') {
	    # Okay
	}
	elsif ($_ eq 'end') {
	    croak "cannot write option after end()";
	}
	else { die }
    }

    my $value = delete $data->{value};
    croak "Missing value for option-tag" unless defined $value;

    $self->startTag( 'option', value => $value );
    $self->write_lang_tag( 'text', $data->{text} );
    $self->endTag( 'option' );

}

sub write_lang_tag
{
    my $self = shift;
    my( $tag, $aref ) = @_;

    foreach my $texts (@{$aref})
    {
	my $text =$texts->[0];
	my $lang = $texts->[1];
	$self->startTag( $tag, lang => $lang );
	$self->characters( $text );
	$self->endTag( $tag );
    }
}

sub end {
    my $self = shift;
    my( $nextstage ) = @_;

    if( not defined $nextstage )
    {
	croak "must supply a nextstage parameter to end()";
    }

    for ($self->{xmltv_state}) {
	if ($_ eq 'new') {
	    croak 'must call start() first';
	}
	elsif ($_ eq 'end') {
	    croak 'cannot call end twice';
	}
    }

    $self->emptyTag( 'nextstage', ( stage => $nextstage ) );

    $self->endTag('xmltvconfiguration');
    $self->SUPER::end(@_);
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
