# A wrapper around Tk::ProgressBar

package XMLTV::ProgressBar::Tk;
use strict;

use Tk;
use Tk::ProgressBar;

my $main_window;
my $tk_progressbar;
my $pid;
my $unused;

sub new {

    my $class = shift;
    my $self = {};

    bless $self, $class;

    $self->_init(@_);

}

sub _init {

    my $self = shift;

    # Term::ProgressBar V1 Compatibility
    if (@_==2) {

        return $self->_init({count      => $_[1], name => $_[0],
                             term_width => 50,    bar_width => 50,
                             major_char => '#',   minor_char => '',
                             lbrack     => '',    rbrack     => '',
                             term       => 0, })

    }

    my %params = %{$_[0]};

    my $main_window = MainWindow->new;

    $main_window->title("Please Wait");
    $main_window->minsize(qw(400 250));
    $main_window->geometry('+250+150');

    my $top_frame    = $main_window->Frame()->pack;
    my $middle_frame = $main_window->Frame()->pack( -fill => "x" );
    my $bottom_frame = $main_window->Frame()->pack(-side => 'bottom');

    $top_frame->Label(-height => 2)->pack;

    $top_frame->Label(-text => $params{name})->pack;

    my $tk_progressbar = $middle_frame->ProgressBar(
        -width => 20,
        -height => 300,
        -from => 0,
        -to => $params{count},
        -variable => \$unused
        )->pack( -fill=>"x", -pady => 24, -padx => 8 );

    $self->{main_window} = $main_window;
    $self->{tk_progressbar} = $tk_progressbar;

    $main_window->update();

    return $self;

}

sub update {

    my $self = shift;

    my $set_to_value = shift;

    if (not $set_to_value) {

        $set_to_value = $self->{tk_progressbar}->value + 1;

    }

    $self->{tk_progressbar}->value( $set_to_value );

    $self->{main_window}->update();

}

sub finish {

    my $self = shift;

    $self->{main_window}->destroy();

}

1;
