#!/usr/bin/perl -wT
# 
# pick.cgi
# 
# Web page for the user to pick which programmes he wants to watch.
# 
# The idea is to get TV listings for the next few days and store them
# as XML in the file $LISTINGS.  Then 'run' this program (install it
# as a CGI script and view it in a web browser, or use Lynx's
# CGI emulation) to pick which programmes you want to watch.
# 
# Your preferences will be stored in the file $PREFS_FILE, and if a
# programme title is listed in there, you won't be asked about it.  So
# although you may get hundreds of programmes to wade through the
# first time, the second time round most of them will be listed in the
# preferences file and you'll be asked only about new ones.
# 
# The final list of programmes to watch is stored in $TOWATCH.
# Unfortunately at the moment this needs post-processing with
# pick_process, due to sloppiness in writing this program.  I will do
# things properly soon.
# 
# So to use this CGI script to plan your TV viewing, here's what
# you'll typically need to do:
#
# - Get listings for the next few days using the appropriate backend,
# for example if you want British listings do:
# 
# % getlistings_pa >tv.xml
# 
# - Optionally, filter these listings to remove programmes which have
# already been broadcast:
# 
# % filter_shown <tv.xml >tmp; mv tmp tv.xml
# 
# - Install this file as a CGI script, and make sure that the
# Configuration section below points to the correct filenames.
# 
# - View the page from a web browser, and choose your preferences for
# the shows listed.  If you choose 'never' or 'always' as your
# preference, you won't be asked about that programme ever again, so
# 'no' or 'yes' would be a more cautious choice, since that will mean
# you are asked again next time.
# 
# - Submit the form and go on to the next page.  Repeat until you have
# got to the end of the listings ('Finished').
# 
# - Now the numbers of programmes you want to watch are stored in
# $TOWATCH.  Process it to get an XML listing:
# 
# % pick_process <towatch >towatch.xml
# 
# and you might want to print out this XML file:
# 
# % listings_to_latex <towatch.xml >towatch.tex
# % latex towatch.tex
# % dvips towatch.dvi
# 
# - Also look at $PREFS_FILE to see all the programmes you have
# killfiled (including those you 'always' want to see without
# prompting).  This list can only get bigger, there's currently no way
# to unkill a programme except by editing the file by hand.
# 
# The first time you do this, you might find that you accidentally say
# 'never' to a programme you wanted to watch.  So it would be best to
# print out a full copy of the TV listings from tv.xml and
# double-check that everything you want is listed in towatch.xml.
# Remember, once you've said 'never' to watch a programme, it becomes
# as if it does not exist at all!
# 
# -- Ed Avis, epa98@doc.ic.ac.uk, 2000-06-30
#  

# Since this program runs with taint mode on, it won't pick up changes
# in PERL5LIB.  So if you have installed modules somewhere
# non-standard (such as your home directory), you have to add the
# paths here explicitly.
# 
# For example, the following lines :-)
# 
use lib '/homes/epa98/lib/perl5/5.00503';
use lib '/homes/epa98/lib/perl5/site_perl';
use lib '/homes/epa98/lib/perl5/site_perl/5.005';

use strict;
use CGI qw<:standard -newstyle_urls>;
use CGI::Carp qw<fatalsToBrowser carpout>; BEGIN { carpout(\*STDOUT) }
use XML::Simple;
use Fcntl ':flock';
use Date::Manip;
use File::Copy;
use Log::TraceMessages qw<t d>; Log::TraceMessages::check_argv();
$Log::TraceMessages::CGI = 1;

########
# Configuration

# Maximum number of programmes to display in a single page
my $CHUNK_SIZE = 100;

# Input file containing all TV listings
my $LISTINGS = './tv.xml'; # path needed for XML::Simple strangeness

# Output file where programme numbers to watch will be placed
my $TOWATCH = 'towatch';

# Input file containing preferences (killfiled programmes, etc)
my $PREFS_FILE = 'tvprefs';

# Preferred languages - if information is available in several
# languages, the ones in this list are used if possible.  List in
# order of preference.  Devious things happen with different dialects
# of the same language, eg 'en' vs 'en_GB', 'en_CA' and so on - see
# which_lang() for details. 
# 
my @PREF_LANGS;

# Hopefully the environment variable $LANG will be set
my $el = $ENV{LANG};
if (defined $el and $el =~ /\S/) {
    $el =~ s/\..+$//; # remove character set
    @PREF_LANGS = ($el);
}
else {
    @PREF_LANGS = ('en'); # change for your language - or just set $LANG
}

########
# End of configuration

# Prototype declarations
sub store_prefs($$);
sub display_form($);
sub print_date_for($;$);                                                 
sub which_lang($$);
sub get_text($);

# Keep the taint checking happy (the Cwd module runs pwd(1))
$ENV{PATH} = '/bin:/usr/bin';

# Newer versions of CGI.pm have support for <meta http-equiv> stuff.
# But for the moment, we'll keep compatibility with older ones.
# 
print header({ expires => 'now',
	       'Content-Type' => 'text/html; charset=UTF-8' });

print <<END
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML//EN">
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <title>TV listings</title>
  </head>
END
;

# FIXME: what if we read one XML file to display the form, and then it
# has changed by the time the user submits the form?
# 
my $xml = XMLin($LISTINGS, forcearray => 1);
t 'read xml: ' . d($xml);
my @programmes = @{$xml->{programme}};

# %wanted
# 
# Does the user wish to watch a programme?
# 
# Maps title to:
#   undef     -  this programme is not known
#   'never'   -  no, the user never watches this programme
#   'no'      -  probably not, but ask
#   'yes'     -  probably, but ask
#   'always'  -  yes, the user always watches this programme
# 
# Read in from the file $PREFS_FILE.
# 
my %wanted = ();

# Open for 'appending' - but really we just want to create an empty
# file if needed.
# 
open(PREFS, "+>>$PREFS_FILE") or die "cannot open $PREFS_FILE: $!";
flock(PREFS, LOCK_SH);
seek PREFS, 0, 0;
while (<PREFS>) {
    s/^\s+//; s/\s+$//;
    s/\#.*//;
    next if $_ eq '';
#    t("got line from $PREFS_FILE: " . d($_));
    if (/^(never|no|yes|always|maybe): (.+)$/) {
	my ($pref, $prog) = ($1, $2);
	$pref = 'yes' if $pref eq 'maybe'; # maybe is deprecated
	$wanted{$prog} = $pref;
    }
    else { die "$PREFS_FILE:$.: bad line (remnant is $_)\n" }
}
#t('\%wanted=' . d(\%wanted));

my ($skip, $next) = (url_param('skip'), url_param('next'));
foreach ($skip, $next) {
    die "bad URL parameter $_" if defined and tr/0-9//c;
}
#t('$skip=' . d($skip) . ', $next=',  d($next));

if (defined $skip and defined $next) {
    # Must be that the user has submitted some preferences.
    store_prefs($skip, $next);
}
elsif (defined $skip and not defined $next) {
    # This is one of the form pages, skipping some programmes already
    # seen. 
    # 
    close PREFS;
    display_form($skip);
}
elsif (not defined $skip and not defined $next) {
    # Initial page, corresponding to skip=0.
    if (-e $TOWATCH) {
	print p("The output file $TOWATCH already exists - "
		. 'refusing to overwrite it');
	print end_html();
	exit();
    }

    # Should really have file locking here
    open(TOWATCH, ">>$TOWATCH") 
      or die "cannot append to $TOWATCH: $!";
    print TOWATCH <<END
# 'towatch' file
# 
# This file was created by $0 and contains the numbers of programmes
# that the user has chosen to watch, either by giving a preference of
# 'yes' or 'always', or because the stored preference for that
# programme was 'always'.
# 
# The format is 'filename/number' on each line.
# 
# Process this file with pick_process to get the actual XML listings.
# Note that if the XML file referenced changes, then so will the
# results from processing this file.
# 

END
  ;
    close TOWATCH;

    close PREFS;
    display_form(0);
}
else { die 'bad URL parameters' }


# store_prefs()
# 
# Store the user's preferences for $CHUNK_SIZE programmes starting
# from 'skip'.
# 
# Parameters:
#   number of programmes to skip from the beginning of @programmes
#   the new value of 'skip' for the next page in the list
# 
sub store_prefs($$) {
    die 'usage: store_prefs(skip, next)' if @_ != 2;
    my ($skip, $next) = @_;

    for (my $i = 0; $i < @programmes; $i++) {
	my $val = param("prog$i");
	if (defined $val) {
	    # Check that this programme really did appear in the
	    # previous page.
	    # 
	    die "bad programme number $i for skip $skip, next $next"
	      unless $skip <= $i and $i < $next;
	    
	    my $title = get_text($programmes[$i]->{title});
	    print "$title: $val<br>\n";

	    my $found = 0;
	    foreach (qw[never no yes always]) {
		if ($val eq $_) {
		    $wanted{$title} = $val;
		    $found = 1;
		    last;
		}
	    }
	    die "bad preference '$val' for prog$i" unless $found;
	}
    }

    # Update $PREFS_FILE with preferences.  'yes' or 'no' preferences
    # are still worth storing because they let us pick the default
    # radio button next time.
    # 
    copy($PREFS_FILE, "$PREFS_FILE.old")
      or die "cannot copy $PREFS_FILE to $PREFS_FILE.old: $!";
    flock(PREFS, LOCK_EX);
    truncate PREFS, 0 or die "cannot truncate $PREFS_FILE: $!";
    print PREFS <<END
# 'prefs' file
# 
# This file contains stored preferences for programme titles, so that
# the user need never be bothered about these shows again.  It's like
# a killfile.  But as well as saying you 'never' want to watch 'That's
# Esther', you can have a preference of 'always' watching some
# programmes, without being asked.
# 
# A 'yes' or 'no' preference will change the default choice, but the
# user will be asked again to check.
# 
# Generated by $0.
# 

END
  ;
    foreach (sort keys %wanted) {
	my $pref = $wanted{$_};
	print PREFS "$pref: $_\n";
    }
    
    print p(strong("Preferences saved in $PREFS_FILE"));

    # Write out the list of programmes that the user wants to watch
    # this week.  For the time being, we do this as a list of numbers
    # that must be processed later - but really we should write out
    # XML programme details.  To do this we'd need to dump XML::Simple
    # and perhaps use XML::DOM both for reading programme details and
    # writing out selected programmes.
    # 
    open(TOWATCH, ">>$TOWATCH") or die "cannot append to $TOWATCH: $!";
    flock(TOWATCH, LOCK_EX);
    for (my $i = $skip; $i < $next; $i++) {
	my $val = param("prog$i");
	my $title = get_text($programmes[$i]->{title});
	if ((defined $wanted{$title} and $wanted{$title} eq 'always')
            or (defined $val and $val eq 'yes') )
        {
	    print TOWATCH "$LISTINGS/$i\n";
	    print br(), "Planning to watch $title\n";
	}
    }
    close TOWATCH;
    print p(strong("List of programme numbers to watch added to $TOWATCH"));

    if ($next >= @programmes) {
	print p('Finished.');
    }
    else {
	my $url = url(-relative => 1);
	print a({ href => "$url?skip=$next" }, "Next page");
    }
    print end_html();
    exit();
}


# display_form()
# 
# Parameters:
#   number of programmes to skip at start of @programmes
# 
sub display_form($) {
    die 'usage: display_form(skip)' if @_ != 1;
    my $skip = shift;

    my @nums_to_show = ();
    my $i;
    for ($i = $skip;
	 $i < @programmes and @nums_to_show < $CHUNK_SIZE;
	 $i++ )
    {
	my $prog = $programmes[$i];
	my $title = get_text($prog->{title});
	for ($wanted{$title}) {
	    if (not defined or $_ eq 'no' or $_ eq 'yes') {
		push @nums_to_show, $i;
	    }
	    elsif ($_ eq 'never' or $_ eq 'always') {
		# Don't bother the user with this programme
	    }
	    else { die }
	}
    }

    # Now actually print the things, we had to leave it until now
    # because we didn't know what the new 'skip' would be.
    # 
    print start_form(-action => url(-relative => 1) .
		     "?skip=$skip;next=$i");

    print '<table border="1">', "\n";
    my $prev;
    foreach my $n (@nums_to_show) {
	my %h = %{$programmes[$n]};
	my ($start, $stop, $channel) = @h{qw(start stop channel)};
	$stop = '' if not defined $stop;
	my $title     = get_text($h{title});
	my $sub_title = get_text($h{sub_title}) if $h{sub_title};
	my $desc      = get_text($h{desc})      if $h{desc};
	
	if (defined $prev) {
	    print_date_for(\%h, $prev);
	}
	else {
	    print_date_for(\%h);
	}

	print "<tr>\n";
	print "<td>\n";
	print "<strong>$title</strong>\n";
	print "<em>$sub_title</em>\n" if defined $sub_title;
	print "<p>\n$desc\n</p>\n" if defined $desc;
	print "</td>\n";
	
	my $default;
	for ($wanted{$title}) {
	    if (not defined) {
		$default = 'never'; # Pessmistic!
	    }
	    elsif ($_ eq 'yes' or $_ eq 'no') {
		$default = $_;
	    }
	    else {
		die "bad pref for $title: $wanted{$title}";
	    }
	}

	foreach (qw<never no yes always>) {
	    print "<td>\n";
	    my $checked = ($_ eq $default) ? 'checked' : '';
	    print qq[<input type="radio" name="prog$n" $checked value="$_">$_</input>\n];
	    print "</td>\n";
	}
	print "</tr>\n";
	$prev = \%h;
    }
    
    print "</table>\n";
    print submit();
    print end_form();
    print end_html();
}


# print_date_for()
# 
# Print the date for a programme as part of the form, so that the
# reader will have some idea of when the programmes will be shown.
# 
# Printing the date ends the current table, prints the date, and then
# starts a new table.  But it won't happen unless it is needed, ie the
# date has changed since the previous programme.
# 
# Parameters:
#   (ref to) programme to print
#   (optional) (ref to) previous programme
# 
# If the previous programme is not given, the date will always be
# printed.
# 
# Printing the date also (at least ATM) ends the current HTML table
# and begins a new one after the date.
# 
sub print_date_for($;$) {
    local $Log::TraceMessages::On = 0;
    die 'usage: print_date_for(programme, [prev programme])'
      unless 1 <= @_ and @_ < 3;
    my ($prog, $prev) = @_;
    t('$prog=' . d($prog));
    t('$prev=' . d($prev));

    my $DAY_FMT = '%A'; # roughly as for date(1)

    my $day = UnixDate($prog->{start}, $DAY_FMT);
    my $prev_day = defined $prev ? UnixDate($prev->{start}, $DAY_FMT) : undef;
    t('$day=' . d($day));
    t('$prev_day=' . d($prev_day));

    if ((not defined $prev_day) or ($day ne $prev_day)) {
	print "</table>\n";
	print h1($day);
	print '<table border="1">', "\n";
    }
}


# which_lang()
# 
# Parameters:
#   reference to list of preferred languages (first is
#     best).  Here, a language is a string like 'en' or 'fr_CA', or
#     'fr_*' which is any dialect of French except plain 'fr'.
# 
#   reference to non-empty list of available languages.  Here, a
#     language can be like 'en', 'en_CA', or '' meaning 'unknown'.
# 
# Returns: which language to use.  Can be 'en', 'fr_CA' or ''.
# 
# So for example:
#   You know English and prefer US English:
#     [ 'en_US' ]
# 
#   You know English and German, German/Germany is preferred:
#     [ 'en', 'de_DE' ]
# 
#   You know English and German, but preferably not Swiss German:
#     [ 'en', 'de', 'de_*', 'de_CH' ]
#   Here any dialect of German (eg de_DE, de_AT) is preferable to de_CH.
# 
sub which_lang($$) {
    die 'usage: which_lang(listref of preferred langs, listref of available)'
      if @_ != 2;
    my ($pref, $avail) = @_;

    my (%explicit, %implicit);
    my $pos = 0;
    my $add_explicit = sub {
	die "preferred language $_ listed twice"
	  if defined $explicit{$_[0]};
	delete $implicit{$_[0]};
	$explicit{$_[0]} = $pos++;
    };
    my $add_implicit = sub {
	$implicit{$_[0]} = $pos++ unless defined $explicit{$_[0]};
    };
    
    foreach (@$pref) {
	$add_explicit->($_);

	if (/^[a-z][a-z]$/) {
	    $add_implicit->($_ . '_*');
	}
	elsif (/^([a-z][a-z])_([A-Z][A-Z])$/) {
	    $add_implicit->($1);
	    $add_implicit->($1 . '_*');
	}
	elsif (/^([a-z][a-z])_\*$/) {
	    $add_implicit->($1);
	}
	else { die "bad language '$_'" } # FIXME support 'English' etc
    }

    my %ranking = (reverse(%explicit), reverse(%implicit));
    my @langs = @ranking{sort { $a <=> $b } keys %ranking};
    my %avail;
    foreach (@$avail) {
	$avail{$_}++ && die "available language $_ listed twice";
    }

    while (defined (my $lang = shift @langs)) {
	if ($lang =~ /^([a-z][a-z])_\*$/) {
	    # Any dialect of $1 (but not standard).  Work through all
	    # of @$avail in order trying to find a match.  (So there
	    # is a slight bias towards languages appearing earlier in
	    # @$avail.)
	    # 
	    my $base_lang = $1;
	    AVAIL: foreach (@$avail) {
		if (/^\Q$base_lang\E_/) {
		    # Well, it matched... but maybe this dialect was
		    # explicitly specified with a lower priority.
		    # 
		    foreach my $lower_lang (@langs) {
			next AVAIL if (/^\Q$lower_lang\E$/);
		    }
			
		    return $_;
		}
	    }
	}
	else {
	    # Exact match
	    return $lang if $avail{$lang};
	}
    }
    
    # Couldn't find anything - pick first available language.
    return $avail->[0];
}


# get_text()
# 
# This is specific to XML::Simple and the file format we use.  Given a
# reference to a list of XML elements (maybe with just one element)
# each of which is a hash with 'content' and maybe 'lang', pick the
# correct text based on the user's preferred language.
# 
sub get_text($) {
    die 'usage: get_text(gunk from XML::Simple)' if @_ != 1;
    die if not $_[0];
    my @bits = @{$_[0]};
    t 'get_text(), bits are: ' . d(\@bits);
    my @langs;
    my %seen;
    foreach (@bits) {
	my $lang = $_->{lang};
	if (defined $lang) {
	    die "two bits of text both with lang '$lang'"
	      if $seen{$lang}++;
	    push @langs, $lang;
	}
	else {
	    die "two bits of text both with no language"
	      if $seen{''}++;
	    push @langs, '';
	}
    }
    my $which = which_lang(\@PREF_LANGS, \@langs);
    foreach (@bits) {
	if ($_->{lang} eq $which) {
	    t 'found bit with lang ' . d($which) . ': ' . d($_);
	    my $content = $_->{content};

	    # XML::Simple 1.04 and below had a bug with the
	    # 'forcearray' option making text content into an array
	    # (with one element, I think).
	    # 
	    my $type = ref($content);
	    if ($type eq 'ARRAY') {
		die 'expected exactly one element in text content array'
		  if @$content != 1;
		return $content->[0];
	    }
	    elsif (not $type) {
		return $content;
	    }
	    else {
		die "unexpected structure $type for text content";
	    }
	}
    }
    die;
}
