package XMLTV;
use strict;
use XML::DOM;
use XML::Writer;
use Log::TraceMessages qw(t d);
use Date::Manip;
use UK_TZ;
use Memoize;
foreach (qw/parse_uk_date date_to_uk
            ParseDate UnixDate DateCalc Date_Cmp
            ParseDateDelta/)
  {
      Memoize::memoize($_) or die "cannot memoize $_: $!";
  }

use base 'Exporter'; use vars '@EXPORT';
@EXPORT = qw(read_programmes write_programmes write_programme
	     read_credits
	     read_channels write_channels);


# Private.
sub node_to_programme($) {
    my $node = shift;
    my %programme;
    
    foreach (qw<start stop channel>) {
	my $v = $node->getAttribute($_);
	$programme{$_} = $v unless $v eq '';
    }
    
    my @titles = ();
    foreach ($node->getElementsByTagName('title', 0)) {
	push @titles, $_->getFirstChild()->getData();
    }
    $programme{title} = \@titles;
    
    my @sub_titles = ();
    foreach ($node->getElementsByTagName('sub-title', 0)) {
	push @sub_titles, $_->getFirstChild()->getData();
    }
    $programme{sub_title} = \@sub_titles;
    
    return \%programme;
}


# read_programmes()
# 
# Read an XMLTV file and get out the relevant information for each
# programme.
# 
# Parameter: filename to read from
# Returns: ref to list of hashes with start, titles, etc.
# 
# NOTE: this isn't finished yet, it doesn't read all the information.
# 
sub read_programmes($) {
    my $p = new XML::DOM::Parser;
    my $doc = $p->parsefile(shift);
    my $nodes = $doc->getElementsByTagName('programme');
    my $n = $nodes->getLength();

    my @programmes = ();
    for (my $i = 0; $i < $n; $i++) {
	my $node = $nodes->item($i);
	push @programmes, node_to_programme($node);
    }
    return \@programmes;
}


# read_credits()
# 
# Get the source and other info from an XMLTV file.
# 
# Parameter: filename to read from
# Returns: attributes of <tv> element (key => value)
# 
sub read_credits($) {
    my @attrs;
    my $p = new XML::Parser(Handlers => { Start => sub {
				     if ($_[1] eq 'tv') {
					 push @attrs, @_[2 .. $#_];
				     }
				 } });
    $p->parsefile(shift);
    return @attrs;
}


# write_programmes()
# 
# Write several programmes as a complete XMLTV file to stdout.
# 
# Parameter: reference to list of programme hashrefs
# 
sub write_programmes($) {
    my $progs = shift;

    my $writer = new XML::Writer(DATA_MODE   => 1,
				 DATA_INDENT => 2 );
    $writer->xmlDecl();
    { local $^W = 0; $writer->doctype('tv', undef, 'xmltv.dtd') }
    $writer->startTag('tv');
    write_programme($writer, $_) foreach @$progs;
    $writer->endTag('tv');
}


# write_programme()
# 
# Write details for a single programme as XML.  This is called by
# write_programmes() but you can also call it yourself if you want.
# 
# Parameters:
#   XML::Writer object
#   reference to hash of programme details (a 'programme')
# 
sub write_programme($$) {
    die 'usage: write_programme(XML::Writer, programme)' if @_ != 2;
    my $w = shift;
    my %p = %{shift()}; # make a copy
    t('write_programme(' . d($w) . ', ' . d(\%p) . ') ENTRY');

    # The way we work is to delete keys from the hash as we output
    # them.  Then at the end we can check to see if there are any keys
    # left that we didn't handle.
    # 
    my $start = delete $p{start};
    if (not defined $start) {
	warn "programme missing start time, skipping";
	return;
    }

    # The dates are converted to the appropriate timezone for output.
    my %attrs = (start => join(' ', @{date_to_uk($start)}));
    if (defined(my $val = delete $p{stop})) {
	$attrs{stop} = join(' ', @{date_to_uk($val)});
    }
    foreach (qw(channel clumpidx)) {
	my $val = delete $p{$_};
	$attrs{$_} = $val if defined $val;
    }
    t "beginning 'programme' element";
    $w->startTag('programme', %attrs);

    # Source (probably a URL or filename) is only for debugging and
    # not actually part of the file format.
    # 
    if (defined(my $val = delete $p{source})) {
	$w->comment("source: $val");
    }

    my $titles = delete $p{title};
    if (defined($titles) and @$titles) {
	t 'titles';
	$w->dataElement('title', $_) foreach @$titles;
    }
    else {
	warn "programme missing title, skipping";
	return;
    }

    if (defined(my $val = delete $p{sub_title})) {
	t 'sub-titles';
	$w->dataElement('sub-title', $_) foreach @$val;
    }

    if (defined(my $val = delete $p{desc})) {
	t 'descriptions';
	$w->dataElement('desc', $_) foreach @$val;
    }

    if (defined(my $val = delete $p{credits})) {
	t 'credits';
	$w->startTag('credits');
	foreach (qw[director actor writer adapter producer presenter
		    commentator guest] )
	{
	    next unless defined $val->{$_};
	    my @people = @{delete $val->{$_}};
	    foreach my $person (@people) {
		die if not defined $person;
		$w->dataElement($_, $person);
	    }
	}
	$w->endTag('credits');

	foreach (keys %$val) {
	    warn "unknown credit: $_";
	}
    }

    if (defined(my $val = delete $p{date})) {
	t 'date';
	$w->dataElement('date', $val);
    }

    if (defined(my $val = delete $p{category})) {
	t 'categories';
	$w->dataElement('category', $_) foreach @$val;
    }

    # Language not handled.

    if (defined(my $val = delete $p{orig_language})) {
	t 'original language';
	$w->dataElement('orig-language', $val);
    }

    if (defined(my $val = delete $p{length})) {
	t 'length';
	$w->dataElement('length', $val);
    }

    if (defined(my $val = delete $p{url})) {
	t 'urls';
	$w->dataElement('url', $_) foreach @$val;
    }

    if (defined(my $val = delete $p{country})) {
	t 'countries';
	$w->dataElement('country', $_) foreach @$val;
    }
    
    if (defined(my $val = delete $p{episode_num})) {
	t 'episode number';
	$w->dataElement('episode-num', $val, system => 'xmltv_ns');
    }
    
    if (defined(my $val = delete $p{colour})) {
	t "'video' element (colour)";
	$w->startTag('video');
	# FIXME DTD inconsistency with 'stereo'
	$w->dataElement('present', 'yes');
	$w->dataElement('colour', $val ? 'yes' : 'no');
	$w->endTag('video');
    }

    # Old-style {stereo} hash element.  Now we use $p{audio}{present}
    # and $p{audio}{stereo}, which better reflect the DTD.
    # 
    if (delete $p{stereo}) {
	warn "deprecated {stereo} hash element";
	t "'audio' element (stereo) - deprecated";
	$w->startTag('audio');
	# I should use the emptyTag() method, but my nsgmls doesn't
	# like that, even when I give it the -wxml option.  So we
	# stick with the older <present></present> style for now.
	# 
	$w->dataElement('present', '');
	$w->dataElement('stereo', 'stereo');
	$w->endTag('audio');
    }
    else {
	# Well, we could explicitly say that it's mono, but why
	# bother?  (Or maybe there is no sound at all...)
	# 
    }

    if (defined(my $audio = delete $p{audio})) {
	t "'audio' element: " . d $audio;
	$w->startTag('audio');
	if (defined(my $val = delete $audio->{present})) {
	    if ($val) {
		$w->emptyTag('present');
		if (defined(my $val = delete $audio->{stereo})) {
		    if ($val eq 'mono') {
			$w->dataElement('stereo', 'mono');
		    }
		    elsif ($val eq 'stereo') {
			$w->dataElement('stereo', 'stereo');
		    }
		    elsif ($val eq 'surround') {
			$w->dataElement('stereo', 'surround');
		    }
		    else {
			warn "bad value for 'stereo': $val";
		    }
		}
	    }
	    else {
		# Not present makes it meaningless to have anything
		# else like stereo.
		# 
	    }
	}
	foreach (keys %$audio) {
	    warn "unused key in 'audio' hash: $_";
	}
	$w->endTag('audio');
    }

    if (delete $p{previously_shown}) {
	t 'previously shown';
	$w->dataElement('previously-shown', '');
    }

    # Premiere and last-chance not currently used, I think.
    if (defined(my $val = delete $p{premiere})) {
	die "don't know how to write 'premiere' details";
    }
    if (defined(my $val = delete $p{last_chance})) {
	die "don't know how to write 'last-chance' details";
    }

    if (delete $p{new}) {
	t 'new';
	$w->dataElement('new', '');
    }

    # Subtitles limited to teletext, in English, for now.
    if (defined(my $val = delete $p{subtitles})) {
	t 'subtitles';
	foreach (@$val) {
	    $w->startTag('subtitles', type => $_);
	    # Language not handled.
	    $w->endTag('subtitles');
	}
    }

    # Rating not used.
    if (defined(my $val = delete $p{rating})) {
	die "don't know how to write 'rating' details";
    }

    t "ending 'programme' element";
    $w->endTag('programme');

    foreach (keys %p) {
	warn "unknown key in programme hash: $_";
    }
}


# read_channels()
# 
# Read the channels.xml file and return a list of channel
# information.
# 
# Returns: hashref looking like:
#   { 'radio-4.bbc.co.uk' => [ [ 'en',  'BBC Radio 4' ],
#                              [ 'en',  'Radio 4'     ],
#                              [ undef, '4'           ] ] }
# 
# in other words mapping channel ID to a list of [ language, pretty
# name ] pairs.
# 
sub read_channels() {
    print STDERR "reading channels.xml\n";
    my $p = new XML::DOM::Parser;
    my $doc = $p->parsefile('channels.xml');
    if (not defined $doc) {
	die "couldn't read channels.xml: $!";
    }
    my $nodes = $doc->getElementsByTagName('channel');
    my $n = $nodes->getLength();

    my %channels;
    for (my $i = 0; $i < $n; $i++) {
	my $node = $nodes->item($i);
	my $id = $node->getAttribute('id');
	my @display_names = ();
	foreach ($node->getElementsByTagName('display-name', 0)) {
	    my $lang = $_->getAttribute('lang');
	    undef $lang if $lang eq '';
	    my $name = $_->getFirstChild()->getData();
	    push @display_names, [ $lang, $name ];
	}
	warn "channel with id $id seen twice"
	  if defined $channels{$id};
	$channels{$id} = \@display_names;
    }
    return \%channels;
}


# write_channels()
# 
# Write channels data as channels.dtd XML to file 'channels.xml'.
# 
# Parameter: channels data hashref
# 
sub write_channels($) {
    my $channels = shift;

    my $fh = new IO::File '>channels.xml'
      or die "cannot write to channels.xml: $!";
    my $w = new XML::Writer(OUTPUT      => $fh,
			    DATA_MODE   => 1,
			    DATA_INDENT => 2 );
    $w->xmlDecl();
    { local $^W = 0; $w->doctype('channels', undef, 'channels.dtd') }
    $w->startTag('channels');
    foreach (sort keys %$channels) {
	my $id = $_;
	my $names = $channels->{$_};
	if (not @$names) {
	    warn "channel $id has no display names, not writing";
	    next;
	}
	$w->startTag('channel', id => $id);
	foreach (@$names) {
	    my ($lang, $text) = @$_;
	    my %attrs;
	    $attrs{lang} = $lang if defined $lang;
	    $w->dataElement('display-name', $text, %attrs);
	}
	$w->endTag('channel');
    }
    $w->endTag('channels');
    print STDERR "wrote channels.xml\n";
}
1;
