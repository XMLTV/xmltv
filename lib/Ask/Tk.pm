# A few GUI routines for asking the user questions using the Tk library.

package XMLTV::Ask::Tk;
use strict;

# Use Log::TraceMessages if installed.
BEGIN {
    eval { require Log::TraceMessages };
    if ($@) {
        *t = sub {};
        *d = sub { '' };
    }
    else {
        *t = \&Log::TraceMessages::t;
        *d = \&Log::TraceMessages::d;
    }
}

use Tk;

my $main_window;
my $top_frame;
my $middle_frame;
my $bottom_frame;
my $mid_bottom_frame;

# Ask a question with a free text answer.
# Parameters:
#   current module
#   question text
#   what character to show instead of the one typed
# Returns the text entered by the user.
sub ask( $$$ ) {
    shift;
    my $question = shift;
    my $show = shift;

    my $textbox;

    $main_window = MainWindow->new;

    $main_window->title("Question");
    $main_window->minsize(qw(400 250));
    $main_window->geometry('+250+150');

    $top_frame    = $main_window->Frame()->pack;
    $middle_frame = $main_window->Frame()->pack;
    $bottom_frame = $main_window->Frame()->pack(-side => 'bottom');

    $top_frame->Label(-height => 2)->pack;

    $top_frame->Label(-text => $question)->pack;

    my $ans;

    $bottom_frame->Button(-text    => "OK",
                          -command => sub {$ans = $textbox->get(); $main_window->destroy;},
                          -width    => 10
                         )->pack(-padx => 2, -pady => 4);

    if (defined $show) {
        $textbox = $middle_frame->Entry(-show => $show)->pack();
    }
    else {
        $textbox = $middle_frame->Entry()->pack();
    }
    MainLoop();

    return $ans;
}

# Ask a question with a password answer.
# Parameters:
#   current module
#   question text
# Returns the text entered by the user.
sub ask_password( $$ ) { ask($_[0], $_[1], "*") }


# Ask a question where the answer is one of a set of alternatives.
#
# Parameters:
#   current module
#   question text
#   default choice
#   Remaining arguments are the choices available.
#
# Returns one of the choices, or undef if input could not be read.
#
sub ask_choice( $$$@ ) {
    shift;
    my $question = shift; die if not defined $question;
    my $default = shift; die if not defined $default;
    my @options = @_; die if not @options;
    t "asking question $question, default $default";
    warn "default $default not in options"
        if not grep { $_ eq $default } @options;
    return _ask_choices( $question, $default, 0, @options );
}

# Ask a yes/no question.
#
# Parameters:
#   current module
#   question text
#   default (true or false)
#
# Returns true or false, or undef if input could not be read.
#
sub ask_boolean( $$$ ) {
    shift;
    my ($text, $default) = @_;
    t "asking question $text, default $default";

    $main_window = MainWindow->new;

    $main_window->title('Question');
    $main_window->minsize(qw(400 250));
    $main_window->geometry('+250+150');

    $top_frame    = $main_window->Frame()->pack;
    $middle_frame = $main_window->Frame()->pack;
    $bottom_frame = $main_window->Frame()->pack(-side => 'bottom');

    $top_frame->Label(-height => 2)->pack;
    $top_frame->Label(-text => $text)->pack;

    my $ans = 0;

    $bottom_frame->Button(-text    => "Yes",
                          -command => sub { $ans = 1; $main_window->destroy; },
                          -width => 10,
                         )->pack(-side => 'left', -padx => 2, -pady => 4);

    $bottom_frame->Button(-text    => "No",
                          -command => sub { $ans = 0; $main_window->destroy; },
                          -width => 10
                         )->pack(-side => 'left', -padx => 2, -pady => 4);

    MainLoop();

    return $ans;
}

# Ask yes/no questions with option 'default to all'.
#
# Parameters:
#   current module
#   default (true or false),
#   question texts (one per question).
#
# Returns: lots of booleans, one for each question.  If input cannot
# be read, then a partial list is returned.
#
sub ask_many_boolean( $$@ ) {
    shift;
    my $default=shift;
    my @options = @_;
    return _ask_choices('', $default, 1, @options);
}

# A helper routine used to create the listbox for both
# ask_choice and ask_many_boolean
sub _ask_choices( $$$@ ) {
    my $question=shift;
    my $default=shift;
    my $allowedMany=shift;
    my @options = @_;

    return if not @options;

    my $select_all_button;
    my $select_none_button;

    my $listbox;
    my $i;

    $main_window = MainWindow->new;

    $main_window->title('Question');
    $main_window->minsize(qw( 400 250 ));
    $main_window->geometry('+250+150');

    $top_frame    = $main_window->Frame()->pack;
    $middle_frame = $main_window->Frame()->pack(-fill => 'both');

    $top_frame->Label(-height => 2)->pack;

    $top_frame->Label(-text => $question)->pack;

    $listbox = $middle_frame->ScrlListbox();

    $listbox->insert(0, @options);

    if ($allowedMany) {
        $listbox->configure( -selectmode => 'multiple' );

        if ($default) {
            $listbox->selectionSet( 0, 'end' );
        }

        $mid_bottom_frame = $main_window->Frame()->pack();

    $select_all_button = $mid_bottom_frame->Button
        (-text => 'Select All',
         -command => sub { $listbox->selectionSet(0, 1000) },
         -width => 10,
        )->pack(-side => 'left');

    $select_none_button = $mid_bottom_frame->Button
        (-text => 'Select None',
         -command => sub { $listbox->selectionClear(0, 1000) },
         -width => 10,
        )-> pack(-side => 'right');
    }
    else {
        $listbox->configure(-selectmode => 'single');
        $listbox->selectionSet(_index_array($default, @options));
    }

    $listbox->pack(-fill => 'x', -padx => '5', -pady => '2');

    $bottom_frame = $main_window->Frame()->pack(-side => 'bottom');

    my @cursel;

    $bottom_frame->Button(-text    => 'OK',
                          -command => sub { @cursel = $listbox->curselection; $main_window->destroy; },
                          -width    => 10,
                         )->pack(-padx => 2, -pady => 4);

    MainLoop();

    if ($allowedMany) {
        my @choices;
        my @choice_numbers = @cursel;

        $i=0;
        foreach (@options) {
            push @choices, 0;
            foreach( @choice_numbers ) {
                if ($options[$_] eq $options[$i]) {
                    $choices[$i] = 1;
                }
            }
            $i++;
        }

        return @choices;
    }
    else {
        my $ans = $options[$cursel[0]];
        return $ans;
    }
}

# Give some information to the user
# Parameters:
#   current module
#   text to show to the user
sub say( $$ ) {
    shift;
    my $question = shift;

    $main_window = MainWindow->new;

    $main_window->title("Information");
    $main_window->minsize(qw(400 250));
    $main_window->geometry('+250+150');

    $top_frame    = $main_window->Frame()->pack;
    $middle_frame = $main_window->Frame()->pack;
    $bottom_frame = $main_window->Frame()->pack(-side => 'bottom');

    $top_frame->Label(-height => 2)->pack;
    $top_frame->Label(-text => $question)->pack;

    $bottom_frame->Button(-text    => "OK",
                          -command => sub { $main_window->destroy; },
                          -width    => 10,
                         )->pack(-padx => 2, -pady => 4);

    MainLoop();
}

# A hekper routine that returns the index in an array
# of the supplied argument
# Parameters:
#     the item to find
#     the array to find it in
# Returns the index of the item in the array, or -1 if not found
sub _index_array($@)
{
    my $s=shift;
    my @array = @_;

    for (my $i = 0; $i < $#array; $i++) {
        return $i if $array[$i] eq $s;
    }

    return -1;
}

1;
