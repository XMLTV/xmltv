# Channel handling package, specific to the peculiarities of the
# Ananova data.
#

package XMLTV::Ananova_Channel;
use Carp ();
use strict;
use Tie::RefHash; # 5.6 version required

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

my @all;
my %idx_a; # index by Ananova id, to 'set' of objects
tie %idx_a, 'Tie::RefHash::Nestable';
my %idx_x; # index by XMLTV id
sub new {
    my $proto = shift;
    my $class = (ref $proto) || $proto;
    my $self = {};
    bless $self, $class;
    push @all, $self;
    die if not ref $self;
    return $self;
}
sub del {
    my $self = shift;
    @all = grep { $_ ne $self } @all;
    foreach (keys %idx_a) {
	delete $idx_a{$_}->{$self};
    }
    foreach (keys %idx_x) {
	delete $idx_x{$_} if $idx_x{$_} eq $self;
    }
    # Okay the object still exists, but it's not referenced anywhere.
}

# Accessors for individual channel.

# Each channel can have one or more Ananova ids, but each Ananova id
# belongs to only one channel.
#
# If one channel has several Ananova ids, that means that the same
# listings are available on Ananova under two separate names.  For
# example 'Granada Plus' and 'Granada Plus - ITV Digital' are presumed
# to be the same channel, so they have a single channel entry with two
# Ananova ids.  That raises the question of which id should be used to
# calculate the display name of the channel.  Therefore the first id
# to be added can be fetched specially, and you should probably do
# things like setting the display name based only on the first id, and
# not again for all the other ids.
#
# Adding an Ananova id can also let you work out whether a channel is
# terrestrial and what region it belongs to.
#
sub add_ananova_id {
    my $self = shift;
    my $id = shift;

    # Warn about things that shouldn't happen.
    if (defined $self->get_variant() and defined $self->{ananova_ids} and keys %{$self->{ananova_ids}}) {
	$self->carp('cannot add another Ananova id, have variant set');
    }
    if (defined $idx_a{$id}) {
	my $v = $self->get_variant();
	foreach (keys %{$idx_a{$id}}) {
	    next if $_ eq $self;
	    my $ov = $_->get_variant();
	    next if defined $v and not defined $ov;
	    next if not defined $v and defined $ov;
	    next if $v ne $ov;

	    if (defined $v) {
		$self->carp("a channel with Ananova id $id, variant $v already exists");
	    }
	    else {
		$self->carp("a channel with Ananova id $id already exists");
	    }
	}
    }

    ++ $self->{ananova_ids}->{$id};
    $self->{first_ananova_id} = $id
      if not defined $self->{first_ananova_id};
    ++ $idx_a{$id}->{$self};

    if ($id =~ /_(\d+)$/) {
	$self->add_region($1);
    }
    else {
	my $type = $self->get_type();
	$self->carp("trying to add Ananova id $id, which has no region, to a terrestrial channel")
	  if defined $type and $type eq 'terrestrial';
    }

    return $self;
}
sub get_first_ananova_id {
    my $self = shift;
    $self->carp('no Ananova ids set')
      if not defined $self->{first_ananova_id};
    return $self->{first_ananova_id};
}
sub is_ananova_id {
    my $self = shift;
    my $id = shift;
    $self->carp('ids not set') if not defined $self->{ananova_ids};
    return $self->{ananova_ids}->{$id};
}
# get_ananova_ids() not needed?

# A channel may correspond to slightly less than one Ananova id, in
# the sense that the Ananova listings contain programmes for multiple
# 'variants'.  So the XMLTV channel is given by Ananova id plus
# variant.
#
sub set_variant {
    my $self = shift;
    my $variant = shift;
    $self->carp('cannot have variant when more than one Ananova id')
      if defined $self->{ananova_ids} and keys %{$self->{ananova_ids}} > 1;
    $self->{variant} = $variant;
}
sub get_variant {
    my $self = shift;
    return $self->{variant};
}

sub set_xmltv_id {
    my $self = shift;
    my $id = shift;
    for ($self->{xmltv_id}) {
	$self->carp("cannot set XMLTV id to $id, already set to $_")
	  if defined and $_ ne $id;
    }
    if (defined $idx_x{$id} and $idx_x{$id} ne $self) {
	$self->carp("a channel with XMLTV id $id already exists");
    }
    $self->{xmltv_id} = $id;
    $idx_x{$id} = $self;
    return $self;
}
sub get_xmltv_id {
    my $self = shift;

#     if (not defined $self->{xmltv_id}) {
# 	# Invent an RFC2838-style name.
# 	my $display = $self->get_main_display_name();
# 	die if not defined $display;
# 	my $munged = $display;
# 	for ($munged) {
# 	    tr/ _/-/s;
# 	    tr/a-zA-Z0-9-//cd;
# 	    tr/A-Z/a-z/;
# 	}
# 	my $new = "$munged.tv-listings.ananova.com";
#
# 	# We just hope that the same name was not picked for some
# 	# other channel.
# 	#
# 	$self->set_xmltv_id($new);
#     }

    return $self->{xmltv_id};
}

sub set_type {
    my $self = shift;
    my $type = shift;
    for ($self->{type}) {
	$self->carp("cannot set type to $type, already set to $_")
	  if defined and $_ ne $type;
    }
    $self->{type} = $type;
    return $self;
}
sub get_type {
    my $self = shift;
    # Okay for type to be undef.
    return $self->{type};
}
sub guess_type {
    my $self = shift;
    for ($self->{type}) {
	if (defined) {
	    $self->carp("cannot guess type, already set to $_");
	}
	else {
	    # If it were terrestrial this would have been set already
	    # (when the Ananova id was set).  We can guess based on
	    # the display name.
	    #
	    my $dn = $self->get_main_display_name();
	    if (not defined $dn) {
		$self->carp("cannot guess type, main display name not set");
	    }
	    else {
		if ($dn =~ /\bradio\b/i or $dn =~ /\bFM\b/) {
		    $_ = 'radio';
		}
		else {
		    # Default.
		    $_ = 'satellite';
		}
	    }
	}
	return $_;
    }
}

# Similarly to Ananova id, region can be multivalued.
sub add_region {
    my $self = shift;
    my $region = shift;

    # FIXME there's one channel, TV3, which is both region and
    # 'satellite'.  So for now, having a region does not imply type
    # 'terrestrial'.
    #
    #$self->set_type('terrestrial');

    ++ $self->{regions}->{$region};
    return $self;
}
sub is_region {
    my $self = shift;
    my $region = shift;
    for ($self->{regions}) {
	return $_->{$region} if defined;
	return 0; # non-terrestrial chs belong to no region, okay.
    }
}
# all_regions() not needed I think.

sub set_main_display_name {
    my $self = shift;
    my $new_name = shift;
    die if @_;

    my $v = $self->get_variant();
    if (defined $v) {
	# Magically append the variant to the name.
	$new_name .= " ($v)";
    }

    $self->{main_display_name} = $new_name;
    return $self;
}
# Add additional display names to a channel.  This is an ordered list,
# but duplicates are silently removed.
#
sub add_extra_display_names {
    my $self = shift;
    my %used;
    foreach (@{$self->{extra_display_names}}) {
	$used{$_}++ && die;
    }
    foreach (@_) {
	unless ($used{$_}++) {
	    push @{$self->{extra_display_names}}, $_;
	}
    }
    return $self;
}
sub get_display_names {
    my $self = shift;
    my $main = $self->{main_display_name};
    $self->carp('main display name not set')
      if not defined $main;
    my @r = ($main);

    # Add the extra display names to the list.  These are without
    # duplicates but we never bothered to check they didn't clash with
    # the main name.  So weed out that kind of duplication now.
    #
    my %used;
    foreach (@{$self->{extra_display_names}}) {
	warn if not defined;
	warn if $used{$_}++;
	if (defined and ($_ ne $main)) {
	    push @r, $_;
	}
    }
    return @r;
}
sub remove_extra_display_names {
    my $self = shift;
    delete $self->{extra_display_names};
}
sub get_main_display_name {
    my $self = shift;
    # Okay to return undef.
    return $self->{main_display_name};
}
# Get some kind of display name to show to the user in error messages.
sub get_a_display_name {
    my $self = shift;
    foreach (qw(main_display_name xmltv_id ananova_id)) {
	return $self->{$_} if defined $self->{$_};
    }
    $self->carp('channel with no name whatsoever'); return '(unknown)';
}

# Channel finding.  Looking up by Ananova id can give several channel
# objects in the case that one Ananova page has several 'variants'.
#
sub find_by_ananova_id {
    my $class = shift; warn 'usage' if not defined $class;
    my $id = shift; warn 'usage' if not defined $id;
    for ($idx_a{$id}) {
	return () if not defined;
	return keys %$_;
    }
}
sub find_by_xmltv_id {
    my $class = shift; warn 'usage' if not defined $class;
    my $id = shift; warn 'usage' if not defined $id;
    return $idx_x{$id};
}
sub all {
    my $class = shift; warn 'usage' if not defined $class;
    return @all;
}
sub ananova_id_to_xmltv_id {
    my $class = shift; warn 'usage' if not defined $class;
    my $aid = shift; warn 'usage' if not defined $aid;
    my @os = $class->find_by_ananova_id($aid);
    return undef if not @os;
    my %found_xmltv_ids;
    foreach (@os) { ++ $found_xmltv_ids{$_->get_xmltv_id()} }

    my @keys = keys %found_xmltv_ids;
    if (@keys == 0) {
	die;
    }
    elsif (@keys == 1) {
	return $keys[0];
    }
    elsif (@keys >= 2) {
	# FIXME
	die "several different XMLTV ids for Ananova id $aid";
    }
    else { die }
}

# Debugging.
sub dump_all {
    my $class = shift;
    foreach ($class->all()) {
	print STDERR $_->stringify(), "\n";
    }
}

# Cloning does not copy the ids since they are meant to be unique (for
# XMLTV ids) or at least not shared between channel objects (for
# Ananova ids).
#
sub clone {
    my $obj = shift;
    my $new = { %$obj };
    bless $new, ref($obj);
    delete $new->{xmltv_id};
    delete $new->{ananova_ids};
    delete $new->{first_ananova_id};
    return $new;
}

sub stringify {
    my $self = shift;
    my @r;
    my $add = sub( $ ) { push @r, defined $_[0] ? $_[0] : '?' };
    $add->($self->{xmltv_id});
    $add->((sort keys %{$self->{ananova_ids}})[0]);
    $add->($self->get_type());
    $add->($self->get_main_display_name());
    return '[' . join(', ', @r) . ']'
}

# Writing a single channel as XMLTV format.  Parameters:
#   XMLTV::Writer object
#   Language used for display names
#
sub write {
    my $self = shift;
    t 'writing channel: ' . d $self;
    my ($writer, $lang) = @_;
    my $id = $self->get_xmltv_id();
    my @names = $self->get_display_names();
    t 'writing display names: ' . d \@names;
    my @out;
    foreach (@names) {
	if (not tr/0-9//c) {
	    # Just digits, doesn't need a language.
	    push @out, [ $_ ];
	}
	else {
	    push @out, [ $_, $lang ];
	}
    }
    my %ch = ( id => $id, 'display-name' => \@out );
    t 'writing channel hash: ' . d \%ch;
    $writer->write_channel(\%ch);
}

sub croak {
    my $self = shift;
    my $msg = shift;
    Carp::croak($self->stringify() . ": $msg");
}
sub carp {
    my $self = shift;
    my $msg = shift;
    Carp::carp($self->stringify() . ": $msg");
}

1;
