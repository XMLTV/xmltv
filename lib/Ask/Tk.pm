# A few GUI routines for asking the user questions.
#
#

package XMLTV::Ask::Tk;
use strict;
use base 'Exporter';
our @EXPORT = qw(ask
                 askQuestion
                 askBooleanQuestion
                 askManyBooleanQuestions
                 say
                );
use Carp qw(croak);
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

sub ask( $ );
sub askQuestion( $$@ );
sub askBooleanQuestion( $$ );
sub askManyBooleanQuestions( $@ );
sub askBooleanOptions( $$$@ );
sub say( $ );

sub ask( $ ) {
    my $question = shift;
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
	
    $bottom_frame->Button(-text    => "OK",
			  -command => sub { goto(answer_ok2) },
			  width    => 10
			 )->pack(padx => 2, pady => 4);
								
    $textbox = $middle_frame->Entry()->pack();
    MainLoop();
	
  answer_ok2:
    my $ans = $textbox->get();
    $main_window->destroy;
    return $ans;
}


# Ask a question where the answer is one of a set of alternatives.
#
# Parameters:
#   question text
#   default choice
#   Remaining arguments are the choices available.
#
# Returns one of the choices, or undef if input could not be read.
#
sub askQuestion( $$@ ) {
    my $question = shift; die if not defined $question;
    my $default = shift; die if not defined $default;
    my @options = @_; die if not @options;
    t "asking question $question, default $default";
    croak "default $default not in options"
      if not grep { $_ eq $default } @options;
    return askBooleanOptions( $question, $default, 0, @options );
}

# Ask a yes/no question.
#
# Parameters: question text,
#             default (true or false)
#
# Returns true or false, or undef if input could not be read.
#
sub askBooleanQuestion( $$ ) {
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
	
    $bottom_frame->Button(-text    => "Yes",
			  # -command => sub {
                          #     recreate_frames;
			  #     draw_download_channels();
                          # },
			  -command => sub { goto(answer_yes) },
			  width => 10,
			 )->pack(-side => 'left', padx => 2, pady => 4);
	
    $bottom_frame->Button(-text    => "No",
			  # -command => sub { exit(0) },
			  -command => sub { goto(answer_no) },
			  width => 10
			 )->pack(-side => 'left', padx => 2, pady => 4);
	
    MainLoop();
	
  answer_no:
    $main_window->destroy;
    return 0;
	
  answer_yes:
    $main_window->destroy;
    return 1;
}

# Ask yes/no questions with option 'default to all'.
#
# Parameters: default (true or false),
#             question texts (one per question).
#
# Returns: lots of booleans, one for each question.  If input cannot
# be read, then a partial list is returned.
#
sub askManyBooleanQuestions( $@ ) {
    my $default=shift;
    my @options = @_;
    return askBooleanOptions('', $default, 1, @options);
}

sub askBooleanOptions( $$$@ ) {
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
	   width => 10,
	  )->pack(-side => 'left');
	
	$select_none_button = $mid_bottom_frame->Button
	  (-text => 'Select None',
	   -command => sub { $listbox->selectionClear(0, 1000) },
	   width => 10,
	  )-> pack(-side => 'right');
    }
    else {
	$listbox->configure(-selectmode => 'single');
	$listbox->selectionSet(indexArray($default, @options));
    }
	
    $listbox->pack(-fill => 'x', -padx => '5', -pady => '2');
	
    $bottom_frame = $main_window->Frame()->pack(-side => 'bottom');
	
    $bottom_frame->Button(-text    => 'OK',
			  -command => sub { goto(answer_ok); },
			  width    => 10,
			 )->pack(padx => 2, pady => 4);
								
    MainLoop();

  answer_ok:
    if( $allowedMany ) {
	my @choices;
	my @choice_numbers = $listbox->curselection;
			
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
			
	$main_window->destroy;
	return @choices;
	
    }
    else {
	my $ans = $options[$listbox->curselection];
	$main_window->destroy;
	return $ans;
    }
}

sub say( $ ) {
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
			  -command => sub { goto(answer_ok3) },
			  width    => 10,
			 )->pack(padx => 2, pady => 4);
	
    MainLoop();
	
  answer_ok3:
    $main_window->destroy;
}


sub indexArray($@)
{
    my $s=shift;
    my @array = @_;
	
    for (my $i = 0; $i < $#array; $i++) {
	return $i if $array[$i] eq $s;
    }
	
    return -1;
}

1;
