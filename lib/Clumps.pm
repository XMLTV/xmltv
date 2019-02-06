# Routines for handling the 'clump index' associated with some
# programmes.  This is a way of working around missing information in
# some listings sources by saying that two or more programmes share a
# timeslot, they appear in a particular order, but we don't know the
# exact time when one stops and the next begins.
#
# For example if the listings source gives at 11:00 'News; Weather'
# then we know that News has start time 11:00 and clumpidx 0/2, while
# Weather has start time 11:00 and clumpidx 1/2.  We know that Weather
# follows News, and they are both in the 11:00 timeslot, but not more
# than that.
#
# This clumpidx stuff does its job, but it's ugly to deal with - as
# demonstrated by the existence of this library.  I plan to replace it
# soonish.
#
# The purpose of this module is to let you alter or delete programmes
# which are part of a clump without having to worry about updating the
# others.  The module exports routines for building a symmetric
# 'relation' relating pairs of scalars; you should use that to relate
# programmes which share a clump.  Then after modifying a programme
# which has a clumpidx set, call fix_clumps() passing in the relation,
# and it will modify the other programmes in the clump.
#
# Again, this all works but a better mechanism is needed.

package XMLTV::Clumps;
use XMLTV::Date;
use Date::Manip; # no Date_Init(), that can be done by the app
use Tie::RefHash;

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

# Won't Memoize, you can do that yourself.
use base 'Exporter';
our @EXPORT_OK = qw(new_relation related relate unrelate nuke_from_rel
		    relatives clump_relation fix_clumps);

sub new_relation();
sub related( $$$ );
sub relate( $$$ );
sub unrelate( $$$ );
sub nuke_from_rel( $$ );
sub relatives( $$ );
sub clump_relation( $ );
sub fix_clumps( $$$ );
sub check_same_channel( $ ); # private


# Routines to handle a symmmetric 'relation'.  This is used to keep
# track of which programmes are sharing a clump so that fix_clumps()
# can sort them out if needed.
#
# FIXME make this OO.
#
sub new_relation() {
    die 'usage: new_relation()' if @_;
    my %h; tie %h, 'Tie::RefHash';
    return \%h;
}
sub related( $$$ ) {
    die 'usage: related(relation, a, b)' if @_ != 3;
    my ($rel, $a, $b) = @_;
    my $list = $rel->{$a};
    return 0 if not defined $list;
    foreach (@$list) {
	return 1 if "$_" eq "$b";
    }
    return 0;
}
sub relate( $$$ ) {
    die 'usage: related(relation, a, b)' if @_ != 3;
    my ($rel, $a, $b) = @_;
    unless (related($rel, $a, $b)) {
	check_same_channel([$a, $b]);
	push @{$rel->{$a}}, $b;
	push @{$rel->{$b}}, $a;
    }
}
sub unrelate( $$$ ) {
    die 'usage: related(relation, a, b)' if @_ != 3;
    my ($rel, $a, $b) = @_;
    die unless related($rel, $a, $b) and related($rel, $b, $a);
    @{$rel->{$a}} = grep { "$_" ne "$b" } @{$rel->{$a}};
    @{$rel->{$b}} = grep { "$_" ne "$a" } @{$rel->{$b}};
}
sub nuke_from_rel( $$ ) {
    die 'usage: nuke_from_rel(relation, a)' if @_ != 2;
    my ($rel, $a) = @_;
    die unless ref($rel) eq 'HASH';
    foreach (@{relatives($rel, $a)}) {
	die unless related($rel, $a, $_);
	unrelate($rel, $a, $_);
    }

    # Tidy up by removing from hash
    die if defined $rel->{$a} and @{$rel->{$a}};
    delete $rel->{$a};
}
sub relatives( $$ ) {
    die 'usage: relatives(relation, a)' if @_ != 2;
    my ($rel, $a) = @_;
    die unless ref($rel) eq 'HASH';
    if ($rel->{$a}) {
	return [ @{$rel->{$a}} ]; # make a copy
    }
    else {
	return [];
    }
}


# Private.  Wrappers for Date::Manip and XMLTV::Date;
sub pd( $ ) {
    for ($_[0]) {
	return undef if not defined;
	return parse_date($_);
    }
}


# Make a relation grouping together programmes sharing a clump.
#
# Parameter: reference to list of programmes
#
# Returns: a relation saying which programmes share clumps.
#
sub clump_relation( $ ) {
    my $progs = shift;
    my $related = new_relation();
    my %todo;
    foreach (@$progs) {
	my $clumpidx = $_->{clumpidx};
	next if not defined $clumpidx or $clumpidx eq '0/1';
	push @{$todo{$_->{channel}}->{pd($_->{start})}}, $_;
    }
    t 'updating $related from todo list';
    foreach my $ch (keys %todo) {
	our %times; local *times = $todo{$ch};
	my $times = $todo{$ch};
	foreach my $t (keys %times) {
	    t "todo list for channel $ch, time $t";
	    my @l = @{$times{$t}};
	    t 'list of programmes: ' . d(\@l);
	    foreach my $ai (0 .. $#l) {
		foreach my $bi ($ai+1 .. $#l) {
		    my $a = $l[$ai]; my $b = $l[$bi];
		    t "$a and $b related";
		    die if "$a" eq "$b";
		    warn "$a, $b over-related" if related($related, $a, $b);
		    relate($related, $a, $b);
		}
	    }
	}
    }
    return $related;
}


# fix_clumps()
#
# When a programme sharing a clump has been modified or replaced,
# patch things up so that other things in the clump are consistent.
#
# Parameters:
#   original programme
#   (ref to) list of new programmes resulting from it
#   clump relation
#
# Modifies the programme and others in its clump as necessary.
#
sub fix_clumps( $$$ ) {
    die 'usage: fix_clumps(old programme, listref of replacements, clump relation)' if @_ != 3;
    my ($orig, $new, $rel) = @_;
    # Optimize common case.
    return if not defined $orig->{clumpidx} or $orig->{clumpidx} eq '0/1';
    die if ref($rel) ne 'HASH';
    die if ref($new) ne 'ARRAY';
    our @new; local *new = $new;
#    local $Log::TraceMessages::On = 1;
    t 'fix_clumps() ENTRY';
    t 'original programme: ' . d $orig;
    t 'new programmes: ' . d \@new;
    t 'clump relation: ' . d $rel;

    sub by_start { Date_Cmp(pd($a->{start}), pd($b->{start})) }
    sub by_clumpidx {
	$a->{clumpidx} =~ m!^(\d+)/(\d+)$! or die;
	my ($ac, $n) = ($1, $2);
	$b->{clumpidx} =~ m!^(\d+)/$n$! or die;
	my $bc = $1;
	if ($ac == $bc) {
	    t 'do not sort: ' . d($a) . ' and ' . d($b);
	    warn "$a->{clumpidx} and $b->{clumpidx} do not sort";
	}
	$ac <=> $bc;
    }
    sub by_date {
	by_start($a, $b)
	  || by_clumpidx($a, $b)
	    || warn "programmes do not sort";
    }

    my @relatives = @{relatives($rel, $orig)};
    if (not @relatives) {
#	local $Log::TraceMessages::On = 1;
	t 'programme without relatives: ' . d $orig;
	warn "programme has clumpidx of $orig->{clumpidx}, but cannot find others in same clump\n";
	return;
    }
    check_same_channel(\@relatives);
    @relatives = sort by_date @relatives;
    t 'relatives of orig (sorted): ' . d \@relatives;
    check_same_channel(\@new); # could relax this later
    t 'orig turned into: ' . d \@new;

    t 'how many programmes has $prog been split into?';
    if (@new == 0) {
	t 'deleted programme entirely!';
	nuke_from_rel($rel, $orig);

	if (@relatives == 0) {
	    die;
	}
	elsif (@relatives == 1) {
	    delete $relatives[0]->{clumpidx};
	}
	elsif (@relatives >= 2) {
	    # Just decrement the index of all following programmes.
	    my $orig_clumpidx = $orig->{clumpidx};
	    $orig_clumpidx =~ /^(\d+)/ or die;
	    $orig_clumpidx = $1;
	    foreach (@relatives) {
		my $rel_clumpidx = $_->{clumpidx};
		$rel_clumpidx =~ /^(\d+)/ or die;
		$rel_clumpidx = $1;
		-- $rel_clumpidx if $rel_clumpidx > $orig_clumpidx;
		$_->{clumpidx} = "$rel_clumpidx/" . scalar @relatives;
	    }
	}
	else { die }
    }
    elsif (@new >= 1) {
#	local $Log::TraceMessages::On = 1;
	t 'split into one or more programmes';
	@new = sort by_date @$new;
	nuke_from_rel($rel, $orig);

	if (@relatives) {
	    # Find where the original programme slotted into the clump
	    # and insert the new programmes there.
	    #
	    my @old_all = sort by_date ($orig, @relatives);
	    check_same_channel(\@old_all);
	    t 'old clump sorted by date (incl. orig): ' . d \@old_all;
	    @new = sort by_date @new;
	    t 'new shows sorted by date: ' . d \@new;

	    # Fix the start and end times of the other shows in the
	    # clump.  The shows in @new may give different (narrower)
	    # times to the one show they came from, so that we have
	    # more information about the start and end times of the
	    # other shows in the clump.  Eg 09:30 0/2 '09:30 AAA,
	    # 10:00 BBB' sharing a clump with 09:30 1/2 'CCC'.  When
	    # the first programme gets split into two, we know that
	    # the start time for C must be 10:00 at the earliest.
	    # Clear?
	    #
	    # Keep around both parsed and unparsed versions of the
	    # same date, to keep timezone information.  This needs to
	    # be handled better.
	    #
	    my $start_new_unp = $new->[0]->{start};
	    my $start_new = pd($start_new_unp);
	    t "new shows start at $start_new";

	    # The known stop time for @new is the last date
	    # mentioned.  Eg if the last show ends at 10:00 we know
	    # @new as a whole ends at 10:00.  But if the last show has
	    # no stop time but starts at 09:30 then we know @new as a
	    # whole ends at *at the earliest* 09:30.
	    #
	    my $stop_new;
	    foreach (reverse @new) {
		foreach (pd($_->{start}), pd($_->{stop})) {
		    next if not defined;
		    if (not defined $stop_new
			or Date_Cmp($_, $stop_new) > 0) {
			$stop_new = $_;
		    }
		}
	    }
	    t "lub of new shows is $stop_new";

	    # However if other shows shared a clump, they do not start
	    # at the stop time of @new!  They overlap with it.  The
	    # shows coming later in the clump will have the same start
	    # time as the last show of @new.
	    #
	    # For example, two shows in a clump from 10:00 to 11:00.
	    # The first is split into something at 10:00 and something
	    # at 10:30.  The second part of the original clump will
	    # now 'start' at 10:30 and overlap with the last of the
	    # new shows.
	    #
	    my $start_last_new_unp = $new[-1]->{start};
	    my $start_last_new = pd($start_last_new_unp);
	    t 'last of the new programmes starts at: ' . d $start_last_new;

	    # Add the programmes coming before @new to the output.
	    # These should have stop times before @new's start.
	    #
	    my @new_all;
	    t 'add shows coming before replaced one';
	    while (@old_all) {
		my $old = shift @old_all;
		last if $old eq $orig;
		t "adding 'before' show: " . d $old;
		die if not defined $old->{start};
		die if not defined $start_new;
		die unless Date_Cmp(pd($old->{start}), $start_new) <= 0;
		my $old_stop = pd($old->{stop});
		t 'has stop time: ' . d $old_stop;
# 		if (defined $old_stop) {
# 		    die if not defined $stop_new;
# 		    die "stop time $old_stop of old programme is earlier than lub of new shows $stop_new"
# 		      if Date_Cmp($old_stop, $stop_new) < 0;
# 		    die "stop time $old_stop of old programme is earlier than start of new shows $start_new"
# 		      if Date_Cmp($old_stop, $start_new) < 0;
# 		}
		$old->{stop} = $start_new_unp;
		t "set stop time to $old->{stop}";

		push @new_all, $old;
	    }

	    # Slot in the new programmes.
	    t 'got to orig show, slot in new programmes';
	    push @new_all, @new;
	    t 'so far, list of new programmes: ' . d \@new_all;

	    # Now the shows at the end, after the programme which was
	    # split.
	    #
	    t 'do shows coming after the orig one';
	    while (@old_all) {
		my $old = shift @old_all;
		t "doing 'after' show: " . d $old;
		my $old_start = pd($old->{start});
		die if not defined $old_start;
		t "current start time: $old_start";
		die if not defined $start_new;
		die if not defined $stop_new;
		die unless Date_Cmp($start_new, $old_start) <= 0;
		die unless Date_Cmp($old_start, $stop_new) <= 0;

		# These shows overlapped with the old programme.  So
		# now they will overlap with the last of the shows it
		# was split into.
		#
		$old->{start} = $start_last_new_unp;
		t "set start time to $old->{start}";
		t 'adding programme to list: ' . d $old;

		push @new_all, $old;
	    }

	    t 'new list of programmes from original clump: ' . d \@new_all;
	    check_same_channel(\@new_all);

	    t 'now regenerate the clumpidxes';
	    while (@new_all) {
		my $first = shift @new_all;
		t 'taking first programme from list: ' . d $first;
		t 'building clump for this programme';
		my @clump = ($first);
		my $start = pd($first->{start});
		die if not defined $start;
		while (@new_all) {
		    my $next = shift @new_all;
		    die if not defined $next->{start};
		    if (not Date_Cmp(pd($next->{start}), $start)) {
			push @clump, $next;
		    }
		    else {
			unshift @new_all, $next;
			last;
		    }
		}
		t 'clump is: ' . d \@clump;
		my $clump_size = scalar @clump;
		t "$clump_size shows in clump";
		for (my $i = 0; $i < $clump_size; $i++) {
		    my $c = $clump[$i];
		    if ($clump_size == 1) {
			t 'deleting clumpidx from programme';
			delete $c->{clumpidx};
		    }
		    else {
			$c->{clumpidx} = "$i/$clump_size";
			t "set clumpidx for programme to $c->{clumpidx}";
		    }
		}

		t 're-relating programmes in this clump (if more than one)';
		foreach my $a (@clump) {
		    foreach my $b (@clump) {
			next if $a == $b;
			relate($rel, $a, $b);
		    }
		}
	    }
	    t 'finished regenerating clumpidxes';
	}
    }
}


# Private.
sub check_same_channel( $ ) {
    my $progs = shift;
    my $ch;
    foreach my $prog (@$progs) {
	for ($prog->{channel}) {
	    if (not defined) {
		t 'no channel! ' . d $prog;
		die 'programme has no channel';
	    }
	    if (not defined $ch) {
		$ch = $_;
	    }
	    elsif ($ch eq $_) {
		# Okay.
	    }
	    else {
		t 'same clump, different channels: ' . d($progs->[0]) . ' and ' . d($prog);
		die "programmes in same clump have different channels: $_, $ch";
	    }
	}
    }
}


1;
