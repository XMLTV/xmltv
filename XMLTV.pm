#
# $Id$
#
# Routines for reading and writing XMLTV files from Perl.
#
# See release notes and/or cvs logs entries for module history
#

package XMLTV;
use strict;
use XML::DOM;
use XML::Writer;
use Log::TraceMessages qw(t d);
use Date::Manip;
use UK_TZ;
use Memoize;
use Lingua::Preferred qw(which_lang);

use base 'Exporter'; use vars qw(@EXPORT @EXPORT_OK);
@EXPORT = qw(read_data write_data);
@EXPORT_OK = qw(best_name);

# Handlers for different subelements of programme.  First value is the
# name of the element, second is a subroutine which turns the DOM node
# into a scalar, third is one to write the scalar given an XML::Writer
# object and element name.  The last value specifies the multiplicity
# of the element: * (any number) and + (one or more) will give a list
# of values while '?' (maybe one) will give a scalar or undef and ''
# (exactly one) will give a scalar.
#
# The ordering of @Handlers gives the order in which these elements
# must appear in the DTD.  In fact, this just duplicates information
# in the DTD and adds details of what handlers to call.
#
my @Handlers = ([ 'title',            \&read_with_lang,   \&write_with_lang,   '+' ],
		[ 'sub-title',        \&read_with_lang,   \&write_with_lang,   '*' ],
		[ 'desc',             \&read_with_lang,   \&write_with_lang,   '*' ],
		[ 'credits',          \&read_credits,     \&write_credits,     '?' ],
		[ 'date',             \&read_date,        \&write_date,        '?' ],
		[ 'category',         \&read_with_lang,   \&write_with_lang,   '*' ],
		[ 'language',         \&read_with_lang,   \&write_with_lang,   '?' ],
		[ 'orig-language',    \&read_with_lang,   \&write_with_lang,   '?' ],
		[ 'length',           \&read_length,      \&write_length,      '?' ],
		[ 'icon',             \&read_icon,        \&write_icon,        '*' ],
		[ 'url',              \&read_url,         \&write_url,         '*' ],
		[ 'country',          \&read_with_lang,   \&write_with_lang,   '*' ],
		[ 'episode-num',      \&read_episode_num, \&write_episode_num, '?' ],
		[ 'video',            \&read_video,       \&write_video,       '?' ],
		[ 'audio',            \&read_audio,       \&write_audio,       '?' ],
		[ 'previously-shown', \&read_prev_shown,  \&write_prev_shown,  '?' ],
		[ 'premiere',         \&read_with_lang,   \&write_with_lang,   '?' ],
		[ 'last-chance',      \&read_with_lang,   \&write_with_lang,   '?' ],
		[ 'new',              \&read_new,         \&write_new,         '?' ],
		[ 'subtitles',        \&read_subtitles,   \&write_subtitles,   '*' ],
		[ 'rating',           \&read_rating,      \&write_rating,      '*' ],
		[ 'star-rating',      \&read_star_rating, \&write_star_rating, '?' ]);
sub Handlers { @Handlers }

# Private.
sub node_to_programme( $ ) {
    my $node = shift;
    my %programme;
#    local $Log::TraceMessages::On = 1;

    # Attributes of programme element.  No checking done.
    %programme = %{dom_attrs($node)};
    t 'attributes: ' . d \%programme;

    # Check the required attributes are there.  As with most checking,
    # this isn't an alternative to using a validator but it does save
    # some headscratching during debugging.
    #
    foreach (qw(start channel)) {
	if (not defined $programme{$_}) {
	    warn "programme missing '$_' attribute\n";
	}
    }
    my @known_attrs = qw(start stop pdc-start vps-start showview
			 videoplus channel clumpidx);
    my %ka; ++$ka{$_} foreach @known_attrs;
    foreach (keys %programme) {
	unless ($ka{$_}) {
	    warn "deleting unknown attribute '$_'";
	    delete $programme{$_};
	}
    }

    t 'going through each child of programme';

    # Current position in Handlers.  We expect to read the subelements
    # in the correct order as specified by the DTD.
    #
    my $handler_pos = 0;

    SUBELEMENT: foreach (dom_subelements($node)) {
	t 'doing subelement';
	my $name = $_->getTagName();
	t "tag name: $name";

	# Search for a handler - from $handler_pos onwards.  But
	# first, just warn if somebody is trying to use an element in
	# the wrong place (trying to go backwards in the list).
	my $found_pos;
	foreach my $i (0 .. $handler_pos - 1) {
	    if ($name eq $Handlers[$i]->[0]) {
		warn "element $name not expected here";
		next SUBELEMENT;
	    }
	}
	for (my $i = $handler_pos; $i < @Handlers; $i++) {
	    if ($Handlers[$i]->[0] eq $name) {
		t 'found handler';
		$found_pos = $i;
		last;
	    }
	    else {
		t "doesn't match name $Handlers[$i]->[0]";
		my ($handler_name, $r, $w, $multiplicity)
		  = @{$Handlers[$i]};
		die if not defined $handler_name;
		die if $handler_name eq '';

		# Before we skip over this element, check that we got
		# the necessary values for it.
		#
		if ($multiplicity eq '?') {
		    # Don't need to check whether this set.
		}
		elsif ($multiplicity eq '') {
		    if (not defined $programme{$handler_name}) {
			warn "no element $handler_name found";
		    }
		}
		elsif ($multiplicity eq '*') {
		    # It's okay if nothing was ever set.  We don't
		    # insist on putting in an empty list.
		}
		elsif ($multiplicity eq '+') {
		    if (not defined $programme{$handler_name}) {
			warn "no element $handler_name found";
		    }
		    elsif (not @{$programme{$handler_name}}) {
			warn "strangely, empty list for $handler_name";
		    }
		}
		else {
		    warn "bad value of $multiplicity: $!";
		}
	    }
	}
	if (not defined $found_pos) {
	    warn "unknown element $name";
	    next;
	}
	# Next time we begin searching from this position.
	$handler_pos = $found_pos;

	# Call the handler.
	t 'calling handler';
	my ($handler_name, $reader, $writer, $multiplicity)
	  = @{$Handlers[$found_pos]};
	die if $handler_name ne $name;
	my $result = $reader->($_);
	t 'result: ' . d $result;

	# Now set the value.  We can't do multiplicity checking yet
	# because there might be more elements of this type still to
	# come.
	#
	if ($multiplicity eq '?' or $multiplicity eq '') {
	    warn "seen $name twice"
	      if defined $programme{$name};
	    $programme{$name} = $result;
	}
	elsif ($multiplicity eq '*' or $multiplicity eq '+') {
	    push @{$programme{$name}}, $result;
	}
	else {
	    warn "bad multiplicity: $multiplicity";
	}
    }

    return \%programme;
}


# read_data()
#
# Read an XMLTV file and return source, channel and programme
# information.
#
# Parameter: filename to read from
# Returns: something a bit like
#    [ 'UTF-8',
#      { 'source-info-name' => 'Ananova', 'generator-info-name' => 'XMLTV' },
#      { 'radio-4.bbc.co.uk' => [ [ 'en',  'BBC Radio 4' ],
#                                 [ 'en',  'Radio 4'     ],
#                                 [ undef, '4'           ] ], ... },
#      [ { start => '200111121800', title => 'Simpsons' }, ... ] ]
#
# In other words, a reference to a list with four elements.  The
# second is source information (a hash), the third is channel
# information (a hash mapping internal name to display names), and the
# fourth is programmes (a list of hashes, one per programme).
#
# The first gives the character set in which the other data is stored.
# At present this will always be UTF-8, since that's what XML::Parser
# returns no matter what encoding the input file used.  It's really
# just there for symmetry with write_data().
#
sub read_data( $ ) {
    my $filename = shift;
    my $p = new XML::DOM::Parser;
    my $doc = $p->parsefile($filename);
    die "cannot parse $filename" if not defined $doc;

    # We assume that the XMLTV document is valid, but some errors are
    # caught anyway.  Running the file through read_data() is a good
    # thing to do *in addition to* validating with nsgmls.
    #

    # Encoding.
    my $encoding = 'UTF-8';

    # Get the source info - attributes of <tv>.
    my $nodes = $doc->getElementsByTagName('tv');
    die "document should have exactly one 'tv' element"
      if $nodes->getLength() != 1;
    my $tv = $nodes->item(0);
    my $credits = dom_attrs($tv);

    # Channels.
    $nodes = $doc->getElementsByTagName('channel');
    my $n = $nodes->getLength();
    my %channels;
    my %known_channel_id;
    for (my $i = 0; $i < $n; $i++) {
	my $node = $nodes->item($i);
	my $attrs = dom_attrs($node);
	my $id = $attrs->{id};
	my @display_names = ();
	foreach ($node->getElementsByTagName('display-name', 0)) {
	    my $lang = $_->getAttribute('lang');
	    undef $lang if $lang eq '';
	    my $name = dom_text($_);
	    push @display_names, [ $name, $lang ];
	}
	warn "channel with id $id seen twice"
	  if defined $channels{$id};
	$channels{$id} = \@display_names;
    }

    # Finally the programmes themselves.
    my @programmes;
    $nodes = $doc->getElementsByTagName('programme');
    $n = $nodes->getLength();
    for (my $i = 0; $i < $n; $i++) {
	my $node = $nodes->item($i);
	push @programmes, node_to_programme($node);
    }

    return [ $encoding, $credits, \%channels, \@programmes ];
}


# write_data()
#
# Write a complete XMLTV file to stdout.
#
# Parameters:
#   listref of four elements as returned by read_data()
#   arguments to be passed on to XMLTV::Writer's constructor
# 
# For example write_data($data, OUTPUT => 'out.xml');
#
sub write_data( $;@ ) {
    my $data = shift;
    my $writer = new XMLTV::Writer(encoding => $data->[0], @_);
    $writer->start($data->[1]);
    $writer->write_channels($data->[2]);
    $writer->write_programme($_) foreach @{$data->[3]};
    $writer->end();
}


# dom_attrs()
#
# Given a DOM node, return a hashref of its attributes.
#
sub dom_attrs( $ ) {
    my $node = shift;
    my $attrs = $node->getAttributes();
    my $num_attrs = $attrs->getLength();
    my %r;
    for (my $i = 0; $i < $num_attrs; $i++) {
	my $node = $attrs->item($i);
	die if not defined $node;
	my $name = $node->getName();
	warn "seen attribute $name twice" if exists $r{$name};
	$r{$name} = $node->getValue();
    }
    return \%r;
}


# dom_text()
#
# Given a DOM node containing only text, return that text (with
# whitespace either side stripped).
#
sub dom_text( $ ) {
    my $node = shift;
    my $child = $node->getFirstChild();
    if (not defined $child) {
	# Decided that it's okay to call dom_text() on an empty
	# element; it should return the empty string.
	#
	return '';
    }
    if ($child->getNodeTypeName() ne 'TEXT_NODE') {
	warn 'first child of text node has wrong type';
	return undef;
    }
    my $text = $child->getData();
    $text =~ s/^\s+//; $text =~ s/\s+$//;
    return $text;
}


# dom_subelements()
#
# Return a list of all subelements of an XML::DOM node.  Whitespace is
# ignored; anything else that isn't a subelement is warned about.
#
sub dom_subelements( $ ) {
    local $Log::TraceMessages::On = 0;
    my $node = shift;
    my @r;
    foreach ($node->getChildNodes()) {
	my $type = $_->getNodeTypeName();
	t "\$type=$type";
	if ($type eq 'ELEMENT_NODE') {
	    t 'element node, okay';
	    push @r, $_;
	}
	elsif ($type eq 'TEXT_NODE') {
	    # We allow whitespace between elements.
	    t 'text node, check is whitespace and skip';
	    my $content = $_->getData();
	    if ($content !~ /^\s*$/) {
		warn "ignoring text '$content' where element expected";
	    }
	    next;
	}
	elsif ($type eq 'COMMENT_NODE') {
	    # Ignore.
	    next;
	}
	else {
	    t 'unknown node type, warn and skip';
 	    warn "ignoring node of type $type where element expected";
	    next;
	}
    }
    return @r;
}
	
# dom_dump_node
#
# Return some information about a node for debugging.
#
sub dom_dump_node($) {
    my $n = shift;
    my $r = '';
    $r .= 'type: ' . $n->getNodeTypeName() . "\n";
    $r .= 'name: ' . $n->getNodeName() . "\n";
    for (trunc($n->getNodeValue())) {
	$r .= "value: $_\n" if defined;
    }
    return $r;
}
sub trunc {
    local $_ = shift;
    return undef if not defined;
    if (length > 1000) {
	return substr($_, 0, 1000) . '...';
    }
    return $_;
}


# The following helper routines for read_data() take an XML::DOM node
# representing a particular subelement of 'programme' and extract its
# data.  They warn and return undef if error.
#

# For each subelement of programme, we define a subroutine to read it
# and one to write it.  The reader takes an XML::DOM node for a single
# subelement and returns its value as a Perl scalar (warning and
# returning undef if error).  The writer takes an XML::Writer, an
# element name and a scalar value and writes a subelement for that
# value.  Note that the element name is passed in to the writer just
# for symmetry, so that neither the writer or the reader have to know
# what their element is called.
#

# Credits
sub read_credits( $ ) {
    my $node = shift;
    my @roles = qw(director actor writer adapter producer presenter
		   commentator guest);
    my %known_role; ++$known_role{$_} foreach @roles;
    my %r;
    foreach (dom_subelements($node)) {
	my $role = $_->getNodeName();
	if (not $known_role{$role}++) {
	    warn "unknown thing in credits: $role";
	    next;
	}
	push @{$r{$role}}, dom_text($_);
    }
    return \%r;
}
sub write_credits( $$$ ) {
    my ($w, $e, $v) = @_;
    my %v = %$v;
    t 'writing credits: ' . d \%v;
    $w->startTag($e);
    foreach (qw[director actor writer adapter producer presenter
		commentator guest] ) {
	next unless defined $v{$_};
	my @people = @{delete $v{$_}};
	foreach my $person (@people) {
	    die if not defined $person;
	    $w->dataElement($_, $person);
	}
    }
    $w->endTag($e);
    foreach (keys %v) {
	warn "unknown credit: $_";
    }
}

# Date.  We do not parse the date (with Date::Manip or anything else)
# because dates in XMLTV files may be partially specified.  For
# example '2001' means that only the year is known; it is not the same
# as 2001-01-01 which most systems would parse it as.
#
sub read_date( $ ) {
    my $node = shift;
    return dom_text($node);
}
sub write_date( $$$ ) {
    my ($w, $e, $v) = @_;
    t 'date';
    $w->dataElement($e, $v);
}

# Length - converted into seconds.
sub read_length( $ ) {
    my $node = shift;
    my %attrs = %{dom_attrs($node)};
    my $d = dom_text($node);
    if ($d !~ tr/0-9// or $d =~ tr/0-9//c) {
	warn "bad content of 'length' element: $d";
	return undef;
    }
    my $units = $attrs{units};
    if (not defined $units) {
	warn "missing 'units' attr in 'length' element";
	return undef;
    }
    # We want to return a length in seconds.
    if ($units eq 'seconds') {
	# Okay.
    }
    elsif ($units eq 'minutes') {
	$d *= 60;
    }
    elsif ($units eq 'hours') {
	$d *= 60 * 60;
    }
    else {
	warn "bad value of 'units': $units";
	return undef;
    }
    return $d;
}
sub write_length( $$$ ) {
    my ($w, $e, $v) = @_;
    t 'length';
    my $units;
    if ($v % 3600 == 0) {
	$units = 'hours';
	$v /= 3600;
    }
    elsif ($v % 60 == 0) {
	$units = 'minutes';
	$v /= 60;
    }
    else {
	$units = 'seconds';
    }
    $w->dataElement($e, $v, units => $units);
}

# URL
sub read_url( $ ) {
    my $node = shift;
    return dom_text($node);
}
sub write_url( $$$ ) {
    my ($w, $e, $v) = @_;
    $w->dataElement($e, $v);
}

# Episode number - pair of [ content, system ].
sub read_episode_num( $ ) {
    my $node = shift;
    my %attrs = %{dom_attrs($node)};
    my $system = $attrs{system};
    $system = 'onscreen' if not defined $system;
    my $content = dom_text($node);
    if ($system eq 'xmltv') {
	# Make it look nice.
	$content =~ s/\s+//g;
	$content =~ s/\./ . /g;
    }
    return [ $content, $system ];
}
sub write_episode_num( $$$ ) {
    my ($w, $e, $v) = @_;
    t 'episode number';
    my ($content, $system) = @$v;
    $w->dataElement($e, $content, system => $system);
}

# Video - converted to a hash.
sub read_video( $ ) {
    my $node = shift;
    my %r;
    foreach (dom_subelements($node)) {
	my $name = $_->getNodeName();
	my $value = dom_text($_);
	if ($name eq 'present') {
	    warn "'present' seen twice" if defined $r{present};
	    $r{present} = decode_boolean($value);
	}
	elsif ($name eq 'colour') {
	    warn "'colour' seen twice" if defined $r{colour};
	    $r{colour} = decode_boolean($value);
	}
	elsif ($name eq 'aspect') {
	    warn "'aspect' seen twice" if defined $r{aspect};
	    $value =~ /^\d+:\d+$/ or warn "bad aspect ratio: $value";
	    $r{aspect} = $value;
	}
    }
    return \%r;
}
sub write_video( $$$ ) {
    my ($w, $e, $v) = @_;
    t "'video' element";
    my %h = %$v;
    $w->startTag($e);
    if (defined (my $val = delete $h{present})) {
	$w->dataElement('present', encode_boolean($val));
    }
    if (defined (my $val = delete $h{colour})) {
	$w->dataElement('colour', encode_boolean($val));
    }
    if (defined (my $val = delete $h{aspect})) {
	$w->dataElement('aspect', encode_boolean($val));
    }
    foreach (sort keys %h) {
	warn "unknown key in video hash: $_";
    }
    $w->endTag($e);
}

# Audio - a hash.
sub read_audio( $ ) {
    my $node = shift;
    my %r;
    foreach (dom_subelements($node)) {
	my $name = $_->getNodeName();
	my $value = dom_text($_);
	if ($name eq 'present') {
	    warn "'present' seen twice" if defined $r{present};
	    $r{present} = decode_boolean($value);
	}
	elsif ($name eq 'stereo') {
	    warn "'stereo' seen twice" if defined $r{stereo};
	    if ($value eq '') {
		warn "empty 'stereo' element not permitted, should be <stereo>stereo</stereo>";
		$value = 'stereo';
	    }
	    warn "bad value for 'stereo': '$value'"
	      if ($value ne 'mono' and $value ne 'stereo'
		  and $value ne 'surround');
	    $r{stereo} = $value;
	}
    }
    return \%r;
}
sub write_audio( $$$ ) {
    my ($w, $e, $v) = @_;
    my %h = %$v;
    $w->startTag($e);
    if (defined (my $val = delete $h{present})) {
	$w->dataElement('present', encode_boolean($val));
    }
    if (defined (my $val = delete $h{stereo})) {
	$w->dataElement('stereo', $val);
    }
    foreach (sort keys %h) {
	warn "unknown key in video hash: $_";
    }
    $w->endTag($e);
}

# Previously shown.  The presence of a value for this key means the
# programme has been shown before; the value is a hash with
# (optionally) 'start' and/or 'channel' keys.
#
sub read_prev_shown( $ ) {
    my $node = shift;
    my %attrs = %{dom_attrs($node)};
    my $r = {};
    foreach (qw(start channel)) {
	my $v = delete $attrs{$_};
	$r->{$_} = $v if defined $v;
    }
    foreach (keys %attrs) {
	warn "unknown attribute $_ in previously-shown";
    }
    return $r;
}
sub write_prev_shown( $$$ ) {
    my ($w, $e, $v) = @_;
    $w->emptyTag($e, %$v);
}

# New - boolean.
sub read_new( $ ) {
    my $node = shift;
    # The 'new' element is empty, it signifies newness by its very
    # presence.
    #
    return 1;
}
sub write_new( $$$ ) {
    my ($w, $e, $v) = @_;
    if (not $v) {
	# Not new, so don't create an element.
    }
    else {
	$w->emptyTag($e);
    }
}

# Subtitles - a hash.
sub read_subtitles( $ ) {
    my $node = shift;
    my %attrs = %{dom_attrs($node)};
    my %r;
    $r{type} = $attrs{type} if defined $attrs{type};
    foreach (dom_subelements($node)) {
	my $name = $_->getNodeName();
	my $value = dom_text($_);
	if ($name eq 'language') {
	    warn "'language' seen twice" if defined $r{language};
	    $r{language} = $value;
	}
	else {
	    warn "bad content of 'subtitles' element: $name";
	}
    }
    return \%r;
}
sub write_subtitles( $$$ ) {
    my ($w, $e, $v) = @_;
    t 'subtitles';
    my ($type, $language) = ($v->{type}, $v->{language});
    if (defined $type) {
	$w->startTag($e, type => $type);
    }
    else {
	$w->startTag($e);
    }
    if (defined $language) {
	$w->dataElement('language', $language);
    }
    $w->endTag($e);
}

# Rating - tuple of [ rating, system, icons ].  The last element is
# itself a listref of 'icon' structures.
#
sub read_rating( $ ) {
    my $node = shift;
    my %attrs = %{dom_attrs($node)};
    my $system = delete $attrs{system} if exists $attrs{system};
    warn "unknown attribute in rating: $_" foreach keys %attrs;
    my @children = dom_subelements($node);

    # First child node is value.
    my $value_node = shift @children;
    if (not defined $value_node) {
	warn "missing 'value' element inside rating";
	return undef;
    }
    if ((my $name = $value_node->getNodeName()) ne 'value') {
	warn "expected 'value' node inside rating, got '$name'";
	return undef;
    }

    my $rating = read_value($value_node);

    # Remaining children are icons.
    my @icons = map { read_icon($_) } @children;
	
    return [ $rating, $system, \@icons ];
}
sub write_rating( $$$ ) {
    my ($w, $e, $v) = @_;
    my ($rating, $system, $icons) = @$v;
    if (defined $system) {
	$w->startTag($e, system => $system);
    }
    else {
	$w->startTag($e);
    }

    write_value($w, 'value', $rating);
    write_icon($w, 'icon', $_) foreach @$icons;
    $w->endTag($e);
}

# Star rating - a string 'X/Y' plus a list of icons.  Returned as
# [ rating, icons ].
#
sub read_star_rating( $ ) {
    my $node = shift;
    my @children = dom_subelements($node);

    # First child node is value.
    my $value_node = shift @children;
    if (not defined $value_node) {
	warn "missing 'value' element inside star-rating";
	return undef;
    }
    if ((my $name = $value_node->getNodeName()) ne 'value') {
	warn "expected 'value' node inside star-rating, got '$name'";
	return undef;
    }
    my $rating = read_value($value_node);

    # Remaining children are icons.
    my @icons = map { read_icon($_) } @children;
	
    return [ $rating, \@icons ];
}
sub write_star_rating( $$$ ) {
    my ($w, $e, $v) = @_;
    my ($rating, $icons) = @$v;
    $w->startTag($e);
    write_value($w, 'value', $rating);
    write_icon($w, 'icon', $_) foreach @$icons;
    $w->endTag($e);
}

# An icon is like the <img> element in HTML.  Returned as a hashref
# with src and optionally width and height.
#
sub read_icon( $ ) {
    my $node = shift;
    my %attrs = %{dom_attrs($node)};
    warn "missing 'src' attribute in icon" if not defined $attrs{src};
    return \%attrs;
}
sub write_icon( $$$ ) {
    my ($w, $e, $v) = @_;
    $w->emptyTag($e, $v);
}

# To keep things tidy some elements that can have icons store their
# textual content inside a subelement called 'value'.  These two
# routines are a bit trivial but they're here for consistency.
#
sub read_value( $ ) {
    my $value_node = shift;
    my $v = dom_text($value_node);
    if (not defined $v or $v eq '') {
	warn "no content of 'value' element";
	return undef;
    }
    return $v;
}
sub write_value( $$$ ) {
    my ($w, $e, $v) = @_;
    $w->dataElement($e, $v);
}


# Booleans in XMLTV files are 'yes' or 'no'.
sub decode_boolean( $ ) {
    my $value = shift;
    if ($value eq 'no') {
	return 0;
    }
    elsif ($value eq 'yes') {
	return 1;
    }
    else {
	warn "bad boolean: $value";
	return undef;
    }
}
sub encode_boolean( $ ) {
    shift() ? 'yes' : 'no';
}


# One value but with language.  This will be either [value, language]
# or just [value] if language is not given.  (Having undef as the
# language is okay too.)
#
# (I don't like the XML::Simple way of alternating between plain
# scalars and listrefs - it leaves too much scope for things to
# break later because a different type starts to be returned.)
#
sub read_with_lang( $ ) {
    my $node = shift;
    my $value = dom_text($node);
    my %attrs = %{dom_attrs($node)};
    my $lang = $attrs{lang} if exists $attrs{lang};

    if (defined $lang) {
	return [ $value, $lang ];
    }
    else {
	return [ $value ];
    }
}
sub write_with_lang( $$$ ) {
    my ($w, $e, $v) = @_;
    if (@$v == 1) {
	$w->dataElement($e, $v->[0]);
    }
    elsif (@$v == 2) {
	my ($text, $lang) = @$v;
	if (defined $lang) {
	    $w->dataElement($e, $text, lang => $lang);
	}
	else {
	    $w->dataElement($e, $text);
	}
    }
    else {
	warn "bad text-with-language scalar";
    }
}


# best_name()
#
# Given a list of acceptable languages and a list of [string,
# language] pairs, find the best one to use.  This means first finding
# the appropriate language and then picking the 'best' string in that
# language.  The best is normally defined as the first one found in a
# usable language, since the XMLTV format puts the most canonical
# versions first.  But you can pass in your own comparison function.
#
# Parameters:
#     reference to list of languages (in Lingua::Preferred format),
#     reference to list of [string, language] pairs, or undef.
#     (optional) function that compares two strings of text and
#       returns 1 if its first argument is better than its second
#       argument, or 0 if equally good, or -1 if first argument worse.
#
# Returns: [s, l] pair, where s is the best of the strings to use and
# l is its language.  This pair is 'live' - it is one of those from
# the list passed in.
#
# There could be some more fancy scheme where both length and language
# are combined into some kind of goodness measure, rather than
# filtering by language first and then length, but that's overkill for
# now.
#
sub best_name( $$;$ ) {
    my $wanted_langs = shift;
    my $pairs = shift; return undef if not defined $pairs;
    my @pairs = @$pairs;
    my $compare = shift;

    my @avail_langs;
    my (%seen_lang, $seen_undef);
    foreach (map { $_->[1] } @pairs) {
	if (defined) {
	    next if $seen_lang{$_}++;
	} else {
	    next if $seen_undef++;
	}
	push @avail_langs, $_;
    }

    my $pref_lang = which_lang($wanted_langs, \@avail_langs);

    # Gather up [text, lang] pairs which have the desired language.
    my @candidates;
    foreach (@pairs) {
	my ($text, $lang) = @$_;
	next unless ((not defined $lang)
		     or (defined $pref_lang and $lang eq $pref_lang));
	push @candidates, $_;
    }

    return undef if not @candidates;

    # If a comparison function was passed in, use it to compare the
    # text strings from the candidate pairs.
    #
    @candidates = sort { $compare->($a->[0], $b->[0]) } @candidates
      if defined $compare;

    # Pick the first candidate.  This will be the one ordered first by
    # the comparison function if given, otherwise the earliest in the
    # original list.
    #
    return $candidates[0];
}


####
# XMLTV::Writer
#

# An XMLTV::Writer lets you write out parts of the XMLTV file (in
# particular, individual programmes) with method calls.  It inherits
# from XML::Writer and uses the @Handlers from XMLTV.
#
package XMLTV::Writer;
use base 'XML::Writer';
use Log::TraceMessages qw(t d);

# Constructor.  Arguments (apart from class name) are passed to
# XML::Writer's constructor, except that the 'encoding' key if present
# is used for the encoding in the XML declaration.
#
# Example: new XMLTV::Writer(encoding => 'ISO-8859-1')
#
# If encoding is not specified, XML::Writer's default is used
# (currently UTF-8).
#
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my %args = @_;
    my $encoding = delete $args{encoding};
    my $self = $class->SUPER::new(DATA_MODE => 1, DATA_INDENT => 2, %args);
    bless($self, $class);

    if (defined $encoding) {
	$self->xmlDecl($encoding);
    }
    else {
	$self->xmlDecl();
    }

    {
	local $^W = 0; $self->doctype('tv', undef, 'xmltv.dtd');
    }
    return $self;
}

sub start {
    my $self = shift;
    die 'usage: XMLTV::Writer->start(hashref of attrs)' if @_ != 1;
    my $attrs = shift;
    $self->startTag('tv', order_attrs(%{$attrs}));
}

# write_channels()
#
# Write details for channels.
#
# Parameters:
#   reference to hash of channel details
#
sub write_channels {
    my ($w, $channels) = @_;
    t('write_channels(' . d($w) . ', ' . d($channels) . ') ENTRY');
    foreach (sort keys %$channels) {
	my $id = $_;
	t "writing channel with id $id";
	my $names = $channels->{$_};
	write_channel($w, $id, $names);
    }
    t('write_channels() EXIT');
}

# write_channel()
#
# Write a single channel.  Unlike programmes, channels are not
# self-contained lumps floating about in a big list: they are indexed
# in a hash by channel id for easy lookup.  This means that when
# writing them out, you need to know the id as well as the data it
# points to.  Accordingly the parameters are:
#
# XMLTV::Writer object
# id of channel
# channel data (at present, a list of display names)
#
# You can call this routine if you want, but most of the time
# write_channels() is a better interface.
#
# FIXME extend this module for icons and stuff.
# In fact for all recent changes to the DTD.
#
sub write_channel {
    my ($w, $id, $names) = @_;
    if (not @$names) {
	warn "channel $id has no display names, not writing";
	return;
    }
    $w->startTag('channel', id => $id);
    foreach (@$names) {
	my ($text, $lang) = @$_;
	my %attrs;
	$attrs{lang} = $lang if defined $lang;
	warn "writing undefined channel name for channel $id"
	  if not defined $text;
	$w->dataElement('display-name', $text, %attrs);
    }
    $w->endTag('channel');
}

# Private.
# write_programme()
#
# Write details for a single programme as XML.
#
# Parameters:
#   reference to hash of programme details (a 'programme')
#
sub write_programme {
#    local $Log::TraceMessages::On = 1;
    my $self = shift;
    die 'usage: XMLTV::Writer->write_programme(programme hash)' if @_ != 1;

    # We make a copy of the programme hash and delete elements from it
    # as they are dealt with; then we can easily spot any unhandled
    # elements at the end.
    #
    my %p = %{shift()};

    t('write_programme(' . d($self) . ', ' . d(\%p) . ') ENTRY');

    # First deal with those hash keys that refer to metadata on when
    # the programme is broadcast.  After taking those out of the hash,
    # we can use the handlers to output individual details.
    #
    my $start = delete $p{start};
    if (not defined $start) {
	warn "programme missing start time, skipping";
	return;
    }
    # Just output dates as strings (see comment at read_date()).
    my %attrs = (start => $start);
    if (defined(my $val = delete $p{stop})) {
	$attrs{stop} = $val;
    }
    foreach (qw(channel clumpidx)) {
	my $val = delete $p{$_};
	$attrs{$_} = $val if defined $val;
    }
    t "beginning 'programme' element";
    $self->startTag('programme', order_attrs(%attrs));

    # Source (probably a URL or filename) is only for debugging and
    # not actually part of the file format.
    #
    if (defined(my $val = delete $p{source})) {
	$self->comment("source: $val");
    }

    # Now do the subelements.
    t 'doing each Handler in turn';
    foreach (XMLTV::Handlers()) {
	my ($name, $reader, $writer, $multiplicity) = @$_;
	t "doing handler for $name$multiplicity";
	t "do we need to write any $name elements?";
	if (not defined $p{$name}) {
	    t "nope, not defined";
	    next;
	}

	my $val = delete $p{$name};
	if ($multiplicity eq '') {
	    t 'exactly one element';
	    if (not defined $val) {
		warn "missing value for $name in programme hash";
		next;
	    }
	    $writer->($self, $name, $val);
	}
	elsif ($multiplicity eq '?') {
	    t 'maybe one element';
	    if (defined $val) {
		$writer->($self, $name, $val);
	    }
	}
	elsif ($multiplicity eq '*') {
	    t 'any number';
	    if (not defined $val) {
		warn "missing value for $name in programme hash (expected list)";
		next;
	    }
	    if (ref($val) ne 'ARRAY') {
		die "expected array of values for $name";
	    }
	    foreach (@{$val}) {
		t 'writing value: ' . d $_;
		$writer->($self, $name, $_);
		t 'finished writing multiple values';
	    }
	}
	elsif ($multiplicity eq '+') {
	    t 'at least one';
	    if (not defined $val) {
		warn "missing value for $name in programme hash (expected list)";
		next;
	    }
	    if (ref($val) ne 'ARRAY') {
		die "expected array of values for $name";
	    }
	    if (not @$val) {
		warn "empty list of $name properties in programme hash";
		next;
	    }
	    foreach (@{$val}) {
		t 'writing value: ' . d $_;
		$writer->($self, $name, $_);
		t 'finished writing multiple values';
	    }
	}
	else {
	    warn "bad multiplicity specifier: $multiplicity";
	}
    }

    t "ending 'programme' element";
    $self->endTag('programme');
}


# end(): say you've finished writing programmes.
sub end {
    my $self = shift;
    $self->endTag('tv');
    $self->SUPER::end(@_);
}


# Private.
# order_attrs()
#
# In XML the order of attributes is not significant.  But to make
# things look nice we try to output them in the same order as given in
# the DTD.
#
# Takes a list of (key, value, key, value, ...) and returns one with
# keys in a nice-looking order.
#
sub order_attrs {
    die "expected even number of elements, from a hash"
      if @_ % 2;
    # This is copied from the ATTRLISTs for programme and tv.
    my @a = (qw(start stop pdc-start vps-start showview videoplus
		channel clumpidx),
	     qw(date source-info-url source-info-name source-data-url
		generator-info-name generator-info-url));

    my @r;
    my %in = @_;
    foreach (@a) {
	if (exists $in{$_}) {
	    my $v = delete $in{$_};
	    push @r, $_, $v;
	}
    }

    foreach (sort keys %in) {
	warn "unknown attribute $_";
	push @r, $_, $in{$_};
    }

    return @r;
}


1;
