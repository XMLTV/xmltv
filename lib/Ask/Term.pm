# A few routines for asking the user questions.  Used in --configure
# and also by Makefile.PL, so this file should not depend on any
# nonstandard libraries.
#
#
package XMLTV::Ask::Term;
use strict;
use Carp qw(croak carp);
use Term::ReadKey;

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

sub ask( $$ );
sub ask_password( $$ );
sub ask_choice( $$$@ );
sub ask_boolean( $$$ );
sub ask_many_boolean( $$@ );
sub say( $$ );

# Ask a question with a free text answer.
# Parameters:
#   current module
#   question text
# Returns the text entered by the user.
sub ask( $$ )
{
    shift;
    my $prompt = shift;
    chomp $prompt;
    $prompt .= ' ' if $prompt !~ /\s$/;
    print STDERR $prompt;
    my $r = <STDIN>;
    for ($r) {
        return undef if not defined;
        s/^\s+//;
        s/\s+$//;
        return $_;
    }
}

# Ask a question with a password answer.
# Parameters:
#   current module
#   question text
# Returns the text entered by the user.
sub ask_password( $$ )
{
    shift;
    my $prompt = shift;
    chomp $prompt;
    $prompt .= ' ' if $prompt !~ /\s$/;
    print STDERR $prompt;
    Term::ReadKey::ReadMode('noecho');
    chomp( my $r = <STDIN> );
    Term::ReadKey::ReadMode('restore');
    print STDERR "\n";
    return $r;
}

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
sub ask_choice( $$$@ )
{
    shift;
    my $question=shift(@_); die if not defined $question;
    chomp $question;
    my $default=shift(@_); die if not defined $default;
    my @options=@_; die if not @options;
    t "asking question $question, default $default";
    croak "default $default not in options"
      if not grep { $_ eq $default } @options;

    my $options_size = length("@options");
    t "size of options: $options_size";
    my $all_digits = not ((my $tmp = join('', @options)) =~ tr/0-9//c);
    t "all digits? $all_digits";
    if ($options_size < 20 or $all_digits) {
        # Simple style, one line question.
        my $str = "$question [".join(',',@options)." (default=$default)] ";
        while ( 1 ) {
            my $res=ask(undef, $str);
            return undef if not defined $res;
            return $default if $res eq '';
            # Single character shortcut for yes/no questions
            return 'yes' if $res =~ /^y$/i;
            return 'no' if $res =~ /^n$/i;

            # Check for exact match, then for substring matching.
            foreach (@options) {
                return $_ if $_ eq $res;
            }
            my @poss;
            foreach (@options) {
                push @poss, $_ if /\Q$res\E/i;
            }
            if (@poss == 1) {
                # Unambiguous substring match.
                return $poss[0];
            }

            print STDERR "invalid response, please choose one of ".join(',', @options)."\n\n";
        }
    }
    else {
        # Long list of options, present as numbered multiple choice.
        print STDERR "$question\n";
        my $optnum = 0;
        my (%num_to_choice, %choice_to_num);
        foreach (@options) {
            print STDERR "$optnum: $_\n";
            $num_to_choice{$optnum} = $_;
            $choice_to_num{$_} = $optnum;
            ++ $optnum;
        }
        $optnum--;
        my $r=undef;
        my $default_num = $choice_to_num{$default};
        die if not defined $default_num;
        until (defined $r) {
            $r = ask_choice(undef, 'Select one:', $default_num, 0 .. $optnum);
            return undef if not defined $r;
            for ($num_to_choice{$r}) { return $_ if defined }
            print STDERR "invalid response, please choose one of " .0 .. $optnum."\n\n";
            undef $r;
        }
    }
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
sub ask_boolean( $$$ )
{
    shift;
    my ($text, $default) = @_;
    my $r = ask_choice(undef, $text, ($default ? 'yes' : 'no'), 'yes', 'no');
    return undef if not defined $r;
    return 1 if $r eq 'yes';
    return 0 if $r eq 'no';
    die;
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
sub ask_many_boolean( $$@ )
{
    shift;
    my $default = shift;

    # Catch a common mistake - passing the answer string as default
    # instead of a Boolean.
    #
    carp "default is $default, should be 0 or 1"
        if $default ne '0' and $default ne '1';

    my @r;
    while (@_) {
        my $q = shift @_;
        my $r = ask_choice(undef, $q, ($default ? 'yes' : 'no'),
                           'yes', 'no', 'all', 'none');
        last if not defined $r;
        if ($r eq 'yes') {
            push @r, 1;
        }
        elsif ($r eq 'no') {
            push @r, 0;
        }
        elsif ($r eq 'all' or $r eq 'none') {
            my $bool = ($r eq 'all');
            push @r, $bool;
            foreach (@_) {
                print STDERR "$_ ", ($bool ? 'yes' : 'no'), "\n";
                push @r, $bool;
            }
            last;
        }
        else { die }
    }
    return @r;
}

# Give some information to the user
# Parameters:
#   current module
#   text to show to the user
sub say( $$ )
{
    shift;
    my $question = shift;
    print STDERR "$question\n";
}

1;
