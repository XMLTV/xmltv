package ClickListings::ParseTable;

#
# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <jerry@matilda.com> wrote this file.  As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return.   
# ----------------------------------------------------------------------------
# always wanted to use this licence, thanks Poul-Henning Kamp.
#
# Feel free to contact me with comments, contributions,
# and the like. jerry@matilda.com 
#

#
# This package is the core scraper for schedules
# from clicktv.com and tvguide.ca.
#

# Outstanding limitations.
# - Clicktv may change their format and we play catch-up.
#
# - sometimes details that appear in () get by us. In these cases,
#   we emit a "unable to identify type of detal for '????'" to
#   STDERR. These may be qualifiers we don't yet understand, feel
#   free contribute the error message and I'll add them.
#
# - maybe we should have an option to convert names in () that appear
#   in the program description to be evaluated as names of special
#   guests. Sometime the description ends with "guest:.." or
#   "guest stars:..."
#
# - not all error messages go to stderr
#
# - sometimes actors names include nicknames in (), for instance:
#   (Kasan Butcher, Cynthia (Alex) Datcher)
#   this parses incorrectly, its more work, but we could identify these.
#
# Future
# - when scraping fails it's very hard to recreate the problem
#   especially if a day passes and the html is no longer, maybe
#   in these cases we should be saving state and inputs to
#   a file that can later be examined to determine what went
#   wrong. But... then again why plan for failure :)
#
# - add some comments, so perldoc works. Maybe later if we
#   make subpackages for Channel and Program objects.
#

use strict;

use vars qw(@ISA $infield $inrecord $intable $nextTableIsIt);

@ISA = qw(HTML::Parser);

require HTML::Parser;
use Dumpvalue;

my $dumper = new Dumpvalue;
$dumper->veryCompact(1);

my $debug=0;
my $verify=0;

sub start()
{
    my($self,$tag,$attr,$attrseq,$orig) = @_;

    # funny way of identifying the right table in the html, but this is
    # one of the only consistant ways.
    # - look for end of submit form and skip one table
    if ( $tag eq "input" ) {
	if ( $attr->{type} eq "submit" && $attr->{value}=~m/update grid/oi ) {
	    # not next one, but the following... nice variable name :)
	    $nextTableIsIt=2;
	}
    }
    elsif ($tag eq 'table') {
	$nextTableIsIt--;
	if ( $nextTableIsIt == 0 ) {
	    $self->{Table} = ();
	    $intable++;
	}
    }
    elsif ( $tag eq 'tr' ) {
	if ( $intable ) {
	    $self->{Row} = ();
	    $inrecord++ ;
	}
    }
    else {
	if ( $intable && $inrecord ) {
	    if ( $tag eq 'td' || $tag eq 'th' ) {
		$infield++;
	    }
	    if ( $infield ) {
		my $thing;

		$thing->{starttag}=$tag;
		if ( keys(%{$attr}) != 0 ) {
		    $thing->{attr}=$attr;
		}
		push(@{$self->{Field}->{things}}, $thing);
	    }
	}

    }
    if ( $debug>1 && $intable ) {
	print "start: ($tag, ";
	$dumper->dumpValue($attr);
	print ")\n";
    }

}

sub text()
{
    my ($self,$text) = @_;

    if ( $intable && $inrecord && $infield ) {
	my $thing;
    
	$thing->{text}=$text;
	push(@{$self->{Field}->{things}}, $thing);

	#$self->{Field}->{text} .= $text;
    }
}

sub massageText
{
    my ($text) = @_;

    #print "MASSAGE:\"$text\"\n";
    $text=~s/&nbsp;/ /og;
    #$text=~s/&#0//og;
    $text=HTML::Entities::decode($text);
    $text=~s/^\s+//o;
    $text=~s/\s+$//o;
    $text=~s/\s+/ /o;
    #print "MASSAGE:'$text'\n";
    return($text);
}

#
# Don't want to complain how annoying it was to hunt down some
# of the ratings things here, ends up to be hit and miss scraping
# a couple of pages and see what details don't get evaluated, then
# try and determine where they might fit.
# 
sub evaluateDetails
{
    my ($undefQualifiers, $result, @parenlist)=@_;

    for my $info (@parenlist) {
	print "Working on details: $info\n" if ( $debug );

	# special cases, if Info starts with Director, its a list.
	if ( $info=~s/^Director: //oi ) {
	    if ( defined($result->{prog_director}) ) {
		$result->{prog_director}.=",";
	    }
	    $result->{prog_director}.=$info;
	    next;
	}
	# check for (1997) being the year declaration
	elsif ( $info=~s/^(\d+)$//o ) {
	    $result->{prog_year}=$info;
	    next;
	}
	# check for duration (ie '(6 hr) or (2 hr 30 min)')
	elsif ($info=~s/^[0-9]+\s*hr$//oi ) {
	    # ignore
	    next;
	}
	elsif ($info =~s/^[0-9]+\s*hr\s*[0-9]+\s*min$//oi ) {
	    # ignore
	    next;
	}

	my $matches=0;
	my @unmatched;

	for my $i (split(/,/,$info)) {

	    $i=~s/^\s+//og;
	    $i=~s/\s+$//og;
	    print "\t checking detail: $i\n" if ( $debug > 2 );
	
	    #
	    # www.tvguidelines.org and http://www.fcc.gov/vchip/
	    for my $rating ('Y','Y7','G','PG','14','MA') {
		if ( $i eq "TV-$rating" ) {
		    $result->{prog_ratings_VCHIP}=$rating;
		    undef($i);
		    $matches++;
		    last;
		}
	    }
	    next if ( !defined($i) );

	    # Expanded VChip Ratings (see notes above)
	    for my $rating ('FV','V','S','L','D') {
		if ( $i eq $rating ) {
		    if ( $rating eq 'FV' ) {
			$result->{prog_ratings_VCHIP_Expanded}="Fantasy Violence";
		    }
		    elsif ( $rating eq 'V' ) {
			$result->{prog_ratings_VCHIP_Expanded}="Violence";
		    }
		    elsif ( $rating eq 'S' ) {
			$result->{prog_ratings_VCHIP_Expanded}="Sexual Situations";
		    }
		    elsif ( $rating eq 'L' ) {
			$result->{prog_ratings_VCHIP_Expanded}="Course Language";
		    }
		    elsif ( $rating eq 'D' ) {
			$result->{prog_ratings_VCHIP_Expanded}="Suggestive Dialogue";
		    }
		    else {
			die "coding error: how did we get here ?";
		    }
		    undef($i);
		    $matches++;
		    last;
		}
	    }
	    next if ( !defined($i) );

	    # www.filmratings.com
	    for my $rating ('G','PG','PG-13','R','NC-17','NR') {
		if ( $i eq $rating || $i eq "Rated $rating" ) {
		    $result->{prog_ratings_MPAA}=$rating;
		    undef($i);
		    $matches++;
		    last;
		}
	    }
	    next if ( !defined($i) );

	    # search for 'violence' at www.twckc.com and get:
	    #    http://www.twckc.com/inside/faq2_0116.html
	    # 
	    for my $rating ('Adult Content',
			    'Adult Humor',
			    'Adult Language', 
			    'Adult Situations',
			    'Adult Theme', 
			    'Brief Nudity',
			    'Graphic Language',
			    'Graphic Violence',
			    'Mature Theme',
			    'Mild Violence',
			    'Nudity',
			    'Profanity',
			    'Strong Sexual Content',
			    'Rape',
			    'Violence') {
		if ( $i=~m/^$rating$/i ) {
		    push(@{$result->{prog_ratings_Warnings}}, $rating);
		    undef($i);
		    $matches++;
		    last;
		}
	    }
	    next if ( !defined($i) );

	    if ( $i=~m/^debut$/i ) {
		$result->{prog_qualifiers}->{Debut}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/in progress$/i ) {
		$result->{prog_qualifiers}->{InProgress}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/finale$/i ) {
		$result->{prog_qualifiers}->{LastShowing}=$i;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/premiere$/i ) {
		$result->{prog_qualifiers}->{PremiereShowing}=$i;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^network\-/i ) {
		# ignore these
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^closed captioned$/i ) {
		$result->{prog_qualifiers}->{ClosedCaptioned}++;
		undef($i);
		$matches++;
		next;
	    }
	    # this pops up for series oriented showings
	    elsif ( $i=~m/^(part [0-9]+ of [0-9]+)$/i ) {
		$result->{prog_qualifiers}->{PartInfo}="$1";
		undef($i);
		$matches++;
		next;
	    }
	    # this pops up for series oriented showings
	    elsif ( $i=~m/^HDTV$/i ) {
		$result->{prog_qualifiers}->{HDTV}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^Taped$/i ) {
		$result->{prog_qualifiers}->{Taped}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^Dubbed$/i ) {
		$result->{prog_qualifiers}->{Dubbed}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^new$/i ) {
		# ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^live/i ) {
		$result->{prog_qualifiers}->{Live}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^repeat/i ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^subtitled/i ) {
		$result->{prog_qualifiers}->{Subtitles}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^in stereo/i ) {
		$result->{prog_qualifiers}->{InStereo}++;
		undef($i);
		$matches++;
		next;
	    }
	    # saw an instance of "In German" appear
	    elsif ( $i=~m/^in (.*)$/i ) {
		$result->{prog_qualifiers}->{Language}="$1";
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^paid program/i ) {
		$result->{prog_qualifiers}->{PaidProgram}++;
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^animated/i ) {
		$result->{prog_qualifiers}->{Animated}++;
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^black & white/i ) {
		$result->{prog_qualifiers}->{BlackAndWhite}++;
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^home video/i ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }

	    if ( defined($i) && length($i) ) {
		print "Failed to decode info: \"$i\"\n" if ( $debug );
		push(@unmatched, $i);
	    }
	}

	if (  defined(@unmatched) && scalar(@unmatched) ) {
	    # if nothing inside the () matched any of the above,
	    if ( $matches == 0 ) {
		# assume anything else is a list of actors or something to complain about
		if ( !defined($result->{prog_actors}) || scalar(@{$result->{prog_actors}}) == 0 ) {
		    #print "Actors ?: ". join(",", @unmatched)."\n";
		    push(@{$result->{prog_actors}}, @unmatched);
		}
		else {
		    my $found=0;
		    for my $k (@unmatched) {
			if ( defined($undefQualifiers->{$k}) ) {
			    $found++;
			}
		    }
		    if ( $found == scalar(@unmatched) ) {
			# all unmatched keywords are in knownUndefined, so ignore
		    }
		    else {
			if ( $found != 0 ) {
			    print "undefined qualifier(s) (or actor list may be corrupt) $info\n";
			}
			else {
			    # add unfound keywords to the list of known undefined keywords.
			    for my $k (@unmatched) {
				if ( !defined($undefQualifiers->{$k}) ) {
				    $undefQualifiers->{$k}=1;
 				    print "adding unidentified qualifier \"$k\" to filter list\n";
				}
				else {
				    $undefQualifiers->{$k}++;
				}
			    }
			}
		    }
		}
	    }
	    # if one thing in the () matched, but not others, complain they
	    # don't appear in our list of known details
	    else {
		for my $k (@unmatched) {
		    if ( ! defined($undefQualifiers->{$k}) ) {
			$undefQualifiers->{$k}=1;
			print "adding unidentified qualifier \"$k\" to filter list\n";
		    }
		    else {
			$undefQualifiers->{$k}++;
		    }
		}
	    }
	}

    }
    return($result);
}

sub endField
{
    my ($self) = @_;
    my $result;
    
    #print "push field: \n";

    my $column=0;

    if ( defined($self->{Row}) ) {
	$column=scalar(@{$self->{Row}});
    }

    #$result->{prog_title}='';

    # save cell things for later
    #$result->{cellThings}=@{$self->{Field}->{things}};

    my @thgs=@{$self->{Field}->{things}};

    if ( $debug ) {
	my $count=0;
	foreach my $entry (@thgs) {
	    print "\tPRE $count"; $count++;
	    $dumper->dumpValue($entry);
	}
    }

    if ( $verify ) {
	my $str="";

	foreach my $e (@thgs) {
	    my $understood=0;
	    if ( defined($e->{starttag}) ) {
		if ( $e->{starttag} eq "img" ) {
		    $understood++;
		    if ( $e->{attr}->{src}=~m/_prev/oi ) {
			$str.="<cont-prev>";
		    }
		    elsif ( $e->{attr}->{src}=~m/_next/oi ) {
			$str.="<cont-next>";
		    }
		    elsif ( $e->{attr}->{src}=~m/\/stars/oi ) {
			$str.="<star rating>";
		    }
		    else {
			die "unable to identify img '". keys (%{$e}) ."'";
		    }
		}
		else {
		    $str.="<$e->{starttag}>";
		    $understood++;
		}
		if ( defined($e->{attr}) ) {
		    $understood++;
		}
	    }
	    if ( defined($e->{endtag}) ) {
		$str.="</".$e->{endtag}.">";
		$understood++;
	    }
	    if ( defined($e->{text}) ) {
		$understood++;
		if ( $e->{text}=~m/^\s+$/o ) {
		    $str.="space";
		} 
		else {
		    $str.="text";
		}
	    }
	    if ( keys (%{$e}) != $understood ) {
		print "understood $understood, out of ".keys (%{$e}) ." keys of:";
		$dumper->dumpValue($e);
	    }
	}
	print "PROG SYNTAX: $str\n";
    }

    # cells always start with 'td' and end in 'td'

    my $end=scalar(@thgs);
    for (my $e=0 ; $e<$end ; $e++) {
	my $thg=$thgs[$e];
	if ( defined($thg->{starttag}) && $thg->{starttag} eq 'img' ) {
	    if ( defined($thg->{attr}->{src}) ) {
		if ( $thg->{attr}->{src}=~m/_prev/oi ) {
		    if ( $thgs[$e-1]->{starttag} eq 'a' &&
			 $thgs[$e+1]->{endtag} eq 'a' ) {
			
			# next entry should be line contains time it ends
			if ( $thgs[$e+2]->{text}=~s/^[0-9]+:[0-9]+[ap]m\s+//oi ) {
			    if ( $thgs[$e+2]->{text}=~m/^\s+$/o ) {
				splice(@thgs,$e-1,4);
			    }
			    else {
				splice(@thgs,$e-1,3);
			    }
			}
			else {
			    die "failed to find time <text> tag for previous start time";
			}
		    }
		    else {
			die "found prev line without <a></a> around";
		    }
		    #print "entry was cont from prior listing\n";
		    $result->{contFromPreviousListing}=1;
		    
		    # start again
		    $e=0;
		    next;
		}
		elsif ($thg->{attr}->{src}=~m/_next/oi ) {
		    
		    if ( $thgs[$e-1]->{starttag} eq 'a' &&
			 $thgs[$e+1]->{endtag} eq 'a' ) {
			splice(@thgs,$e-1,3);
		    }
		    else {
			die "failed to find time <text> tag for previous start time";
		    }
		    #print "entry was cont to next listing\n";
		    $result->{contToNextListing}=1;
		    
		    # start again
		    $e=0;
		    next;
		}
		elsif ($thg->{attr}->{src}=~m/\/stars_(\d+)\./oi ) {
		    $result->{prog_stars_rating}=sprintf("%.1f", int($1)/2);
		    if ( $thgs[$e-1]->{text}=~m/^\s+$/o ) {
			splice(@thgs,$e-1,2);
		    }
		    else {
			splice(@thgs,$e,1);
		    }
		    
		    # start again
		    $e=0;
		    next;
		}
		else {
		    print STDERR "img link defined with unknown image link ".$thg->{attr}->{src}."\n";
		    exit(1);
		}
		next;
	    }
	    print STDERR "img link defined without src definition $e ".$thg."\n";
	    $dumper->dumpValue($thg);
	    exit(1);
	}
	
	# nuke <b> and </b>
	if ( (defined($thg->{starttag}) && $thg->{starttag} eq 'b') ||
	     (defined($thg->{endtag}) && $thg->{endtag} eq 'b')) {
	    splice(@thgs,$e,1);
	    
	    # start again
	    $e=0;
	    next;
	}
	
	# grab space<i>text</i>space and remove surrounding space
	if ( scalar(@thgs)>$e+4 &&
	     defined($thg->{text}) && $thg->{text}=~m/^\s+$/o &&
	     defined($thgs[$e+1]->{starttag}) && $thgs[$e+1]->{starttag} eq 'i' &&
	     defined($thgs[$e+2]->{text}) &&
	     defined($thgs[$e+3]->{endtag}) && $thgs[$e+3]->{endtag} eq 'i' &&
	     defined($thgs[$e+4]->{text}) && $thgs[$e+4]->{text}=~m/^\s+$/o ) {
	    #$result->{prog_subtitle}=$thgs[$e+1]->{text};
	    # remove space entries
	    splice(@thgs,$e,1);
	    splice(@thgs,$e+3,1);
	    
	    # start again
	    $e=0;
	    next;
	}

	# grab <i>text</i> as being the subtitle
	if ( scalar(@thgs)>$e+2 &&
	     defined($thg->{starttag}) && $thg->{starttag} eq 'i' &&
	     defined($thgs[$e+1]->{text}) &&
	     defined($thgs[$e+2]->{endtag}) && $thgs[$e+2]->{endtag} eq 'i' ) {
	    $result->{prog_subtitle}=massageText($thgs[$e+1]->{text});
	    splice(@thgs,$e,3);
	    
	    # start again
	    $e=0;
	    next;
	}

	# grab <font><br> means no description was given
	# and <font>textspace<br> means text is the description
	# and <font>text<br> means text is the description
	# also check </font> combination
	if ( (defined($thg->{starttag}) && $thg->{starttag} eq 'font') ||
	     (defined($thg->{endtag}) && $thg->{endtag} eq 'font') ) {
	    if ( defined($thgs[$e+1]->{starttag}) && $thgs[$e+1]->{starttag} eq 'br') {
		$result->{prog_desc}="";
		splice(@thgs,$e+1,1);
		# start again
		$e=0;
		next;
	    }
	    elsif ( scalar(@thgs)>$e+3 && 
		    defined($thgs[$e+1]->{text}) &&
		    defined($thgs[$e+2]->{starttag}) && $thgs[$e+2]->{starttag} eq 'br') {
		$result->{prog_desc}=massageText($thgs[$e+1]->{text});
		splice(@thgs,$e+1,2);
		# start again
		$e=0;
		next;
	    }
	    elsif ( scalar(@thgs)>$e+4 && 
		    defined($thgs[$e+1]->{text}) &&
		    defined($thgs[$e+2]->{text}) &&
		    defined($thgs[$e+3]->{starttag}) && $thgs[$e+3]->{starttag} eq 'br') {
		$result->{prog_desc}=massageText($thgs[$e+1]->{text}.$thgs[$e+2]->{text});
		splice(@thgs,$e+1,3);
		# start again
		$e=0;
		next;
	    }
	}
    }

    if ( $verify ) {
	my $str="";

	foreach my $e (@thgs) {
	    my $understood=0;
	    if ( defined($e->{starttag}) ) {
		$str.="<$e->{starttag}>";
		$understood++;
		if ( defined($e->{attr}) ) {
		    $understood++;
		}
	    }
	    if ( defined($e->{endtag}) ) {
		$str.="</".$e->{endtag}.">";
		$understood++;
	    }
	    if ( defined($e->{text}) ) {
		$understood++;
		if ( $e->{text}=~m/^\s+$/o ) {
		    $str.="space";
		} 
		else {
		    $str.="text";
		}
	    }
	    if ( keys (%{$e}) != $understood ) {
		print "understood $understood, out of ".keys (%{$e}) ." keys of:";
		$dumper->dumpValue($e);
	    }
	}
	print "PROG2 SYNTAX: $str\n";
    }

    my $count=0;
    my $startEndTagCount=0;
    my @textSections;
    for ($count=0 ; $count<scalar(@thgs) ; $count++ ) {
	my $entry=$thgs[$count];
	if ( $debug > 1) { print "\tNUM $count"; $dumper->dumpValue($entry); }

	#print "entry is a ". $entry ."\n";
	#print "entry start is a ". $entry->{starttag} ."\n" if ( defined($entry->{starttag}) );

	if ( defined($entry->{starttag}) ) {
	    my $tag=$entry->{starttag};
	    my $attr=$entry->{attr};

	    #print "tag is a ". $tag ."\n";

	    if ( $tag eq "td" || $tag eq "th" ) {
		if ( !defined($result->{fieldtag}) ) {
		    $result->{fieldtag}=$tag;
		}
		if ( defined($attr->{colspan}) ) {
		    $result->{colspan}=$attr->{colspan};
		}
		else {
		    $result->{colspan}=1;
		}
	    }
	    elsif ( $tag eq "a" ) {
		die "link missing href attr" if ( !defined($attr->{href}) );
		$result->{prog_href}=$attr->{href};
		#$result->{prog_title}='';
		#$startEndTagCount++;
	    }
	    elsif ( $tag eq "i" ) {
		# ignore
	    }
	    elsif ( $tag eq "font" ) {
		$startEndTagCount++;
	    }
	    elsif ( $tag eq 'br') {
		# ignore
	    }
	    elsif ( $tag eq 'img') {
		# ignore
	    }
	    elsif ( $tag eq 'b') {
		# ignore
	    }
	    elsif ( $tag eq "!" ) {
		# ignore comments
	    }
	    else {
		print "ignoring start tag: $tag\n";
	    }
	}
	elsif ( defined($entry->{endtag}) ) {
	    $startEndTagCount++;
	    my $tag=$entry->{endtag};
	    if ($tag eq 'a') {
		#if ( !length($result->{prog_title}) ) {
		#   die "program missing a name";
		#}
		$startEndTagCount++;
	    }
	    elsif ( $tag eq 'font' ) {
		$startEndTagCount++;
	    }
	    elsif ( $tag eq 'td') {
		# ignore
	    }
	    elsif ( $tag eq "i" ) {
		# ignore
	    }
	    elsif ( $tag eq 'b') {
		# ignore
	    }
	    elsif ( $tag eq '!' ) {
		# ignore comments
	    }
	    else {
		print "ignoring end tag: $tag\n";
	    }
	}
	elsif ( defined($entry->{text}) ) {
		$textSections[$startEndTagCount].=$entry->{text};
	}
	else {
	    print "undefined thing:$count:"; $dumper->dumpValue($entry);
	    die "undefined thing";
	}
    }

    
    for my $text (@textSections) {
	next if ( !defined($text) );

	if ( !defined($result->{prog_title}) ) {
	    $result->{prog_title}=massageText($text);
	}
	elsif ( !defined($result->{prog_subtitle}) ) {
	    $result->{prog_subtitle}=massageText($text);
	}
	elsif ( !defined($result->{prog_desc}) ) {
	    $result->{prog_desc}=massageText($text);
	}
	elsif ( !defined($result->{prog_details}) ) {
	    $result->{prog_details}=massageText($text);
	}
	else {
	    print "don't have a place for extra text section '$text'\n";
	}
    }

    if ( defined($result->{prog_details}) ) {
	my $info=$result->{prog_details};
	delete($result->{prog_details});

	my @parenlist=grep (!/^\s*$/, split(/(?:\(|\))/,$info));
	if ( scalar(@parenlist) ) {
	    evaluateDetails($self->{undefQualifiers}, $result, @parenlist);
	}
    }

    # compress result removing unneeded entries or entries that have no values
    foreach my $key (keys %{$result}) {
	if ( length($result->{$key}) == 0 ) {
	    delete $result->{$key};
	}
    }

    push(@{$self->{Row}}, $result);

    if ( $debug ) {
	print "READ FIELD (col $column):"; $dumper->dumpValue($result);
    }

    #print "push field: $self->{Field}->{text} ($self->{Field}->{tag}, $self->{Field}->{colspan})\n";
    undef($self->{Field});
}

sub end()
{
    my ($self,$tag) = @_;

    if ( $tag eq 'table' ) {
	if ( $intable ) {
	    $intable--;
	}
    }
    elsif ($tag eq 'td' || $tag eq 'th') {
	if ( $infield ) {
	    $infield--;
	    my $thing;
	    
	    $thing->{endtag}=$tag;
	    push(@{$self->{Field}->{things}}, $thing);

	    $self->endField($tag);
	}
    }
    elsif ($tag eq 'tr') {
	if ( $inrecord ) {
	    $inrecord--;
	    push @{$self->{Table}},\@{$self->{Row}};
	    undef($self->{Row});
	}
    }
    else {
	if ( $intable && $inrecord && $infield ) {
	    my $thing;
    
	    $thing->{endtag}=$tag;
	    push(@{$self->{Field}->{things}}, $thing);
	}
    }
}

package ClickListings;

#
# an attempt to read multple listing tables and merge them.
# we merge the rows, then will attempt to collaps the
# cells that spanned listing pages.
#

use strict;
use Data::Dumper;
use LWP::Simple;

sub new {
    my($type) = shift;
    my $self={ @_ };            # remaining args become attributes
    
    die "no ServiceID specified in create" if ( ! defined($self->{ServiceID}) );
    die "no URLBase specified in create" if ( ! defined($self->{URLBase}) );
    die "no DetailURLBase specified in create" if ( ! defined($self->{DetailURLBase}) );
    die "no undefQualifiers specified in create" if ( ! defined($self->{undefQualifiers}) );

    # do we trust all details in 'details' pages ?
    # For some reason the grid details are more accurate than
    # in the details page
    $self->{TrustAllDetailsEntries}=0;

    bless($self, $type);

    return($self);
}

sub getListingURLData($$)
{
    my $self=shift;
    return(LWP::Simple::get($_[0]));
}

sub getListingURL($$$$$)
{
    my $self=shift;
    my ($hour, $day, $month, $year)=@_;

    return("$self->{URLBase}?$self->{ServiceID}&gDate=${month}A${day}A${year}&gHour=$hour");
}

sub getDetailURL($$)
{
    my $self=shift;
    return("$self->{DetailURLBase}?$self->{ServiceID}&prog_ref=$_[0]");
}

sub getDetailURLData($$)
{
    my $self=shift;
    return(LWP::Simple::get($_[0]));
}

# used for testing/debugging
sub storeListing
{
    my ($self, $filename)=@_;

    if ( ! open(FILE, "> $filename") ) {
	print STDERR "$filename: $!";
	return(0);
    }
    my %hash;

    $hash{TimeZone}=$self->{TimeZone} if ( defined($self->{TimeZone}) );
    $hash{TimeLine}=$self->{TimeLine} if ( defined($self->{TimeLine}) );
    $hash{Channels}=$self->{Channels} if ( defined($self->{Channels}) );
    $hash{Schedule}=$self->{Schedule} if ( defined($self->{Schedule}) );
    $hash{Programs}=$self->{Programs} if ( defined($self->{Programs}) );
    
    my $d=new Data::Dumper([\%hash], ['*hash']);
    $d->Purity(0);
    $d->Indent(1);
    print FILE $d->Dump();
    close FILE;
    return(1);
}

# used for testing/debugging
sub restoreListing
{
    my ($self, $filename)=@_;

    if ( ! open(FILE, "< $filename") ) {
	print STDERR "$filename: $!";
	return(0);
    }
    my %hash;

    my $saveit=$/;
    undef $/;

    eval {<FILE>};
    if ($@) {
	$/=$saveit;
	print STDERR "failed to read $filename: $@\n";
	close(FILE);
	return(1);
    }
    $/=$saveit;
    close FILE;

    $self->{TimeZone}=$hash{TimeZone} if ( defined($hash{TimeZone}) );
    $self->{TimeLine}=$hash{TimeLine} if ( defined($hash{TimeLine}) );
    $self->{Channels}=$hash{Channels} if ( defined($hash{Channels}) );
    $self->{Schedule}=$hash{Schedule} if ( defined($hash{Schedule}) );
    $self->{Programs}=$hash{Programs} if ( defined($hash{Programs}) );
    return(1);
}

# determine if this row in the table is
# a replicated "time" row.
sub isTimeRow
{
    my @row=@{$_[0]};

    for (my $col=1 ; $col < scalar(@row)-1 ; $col++ ) {
	my $field=$row[$col];
	
	if ( $field->{fieldtag} ne 'th' ||
	     ( defined($field->{prog_title}) && !($field->{prog_title}=~m/^[0-9]+:[03]0 [ap]\.m\.$/o)) ) {
	    return(0);
	}
    }
    return(1);
}

# internal check 
# currently unimplemented since I don't think we need it.
sub verifyProgramMatches($$)
{
    my ($prog, $savedprog)=@_;
    die "unimplemented\n";
}

use Date::Manip;

sub readSchedule
{
    my $self=shift;
    my (@timedefs) = @_;

    my @WholeTable;
    my @TimeLine;

    if ( defined($self->{Schedule}) ) {
	@WholeTable=@{$self->{Schedule}};
    }
    if ( defined($self->{TimeLine}) ) {
	@TimeLine=@{$self->{TimeLine}};
    }

    my $hours_per_listing=0;
    my $dataFormat;

    my $first=1;
    foreach my $timedef (@timedefs) {

	my ($hourMin, $hourMax, $nday, $nyear)=(@{$timedef});
	my @DayTable;
	undef(@DayTable);

	my @TimeTable;

	for (my $wanthour=$hourMin; $wanthour<$hourMax ; $wanthour+=$hours_per_listing) {
	    my $hour=$wanthour;
	    if ( $hour == 24 ) {
		$hour=0;
		$nday++;
	    }
	    my ($year,$month,$day,$hr,$min,$sec)=Date::Manip::Date_NthDayOfYear($nyear, $nday);

	    my $url=$self->getListingURL($hour, $day, $month, $year);
	    print "retrieving hour $hour of $month/$day/$year..\n";
	    
	    my $tbl = new ClickListings::ParseTable();
	    $tbl->{undefQualifiers}=$self->{undefQualifiers};
	    $tbl->unbroken_text(1);

	    my $urldata=$self->getListingURLData($url);
	    if ( !defined($urldata) ) {
		print STDERR "unable to read url $url\n";
		return(0);
	    }
	    else {
		print "\tread ".length($urldata). " bytes of html\n" if ( $debug );
		print "urldata:\n'$urldata'\n" if ( $debug>1 );
	    }

	    # first listing, scrape for number of hours per page
	    if ( $first ) {
		$first=0;

		if ( $url=~m/www\.clicktv\.com/o ) {
		    $dataFormat="clicktv";
		}
		elsif ($url=~m/tvguidelive\.clicktv\.com/o ) {
		    $dataFormat="tvguidelive";
		}
		else {
		    die "unknown data format from url:$url";
		}

		if ( !($urldata=~m/Next (\d+)&nbsp;hours=&gt\;<\/a>/o) ) {
		    print STDERR "error: unable to determine number of hours in each listing\n";
		    print STDERR "urldata:\n$urldata\n";
		    return(0);
		}
		else {
		    $hours_per_listing=$1;
		    print STDERR "user selected $hours_per_listing hours in each listing\n" if ( $debug );
		}

		if ( !($urldata=~m/<b>Lineup:<\/b>[^\|]+\| \d+\/\d+\/\d+ \d+:\d+\s[AP]M\s([A-Z]+) \|/o) ) {
		    print STDERR "error: time zone information missing from url source\n";
		    print STDERR "urldata:\n$urldata\n";
		    return(0);
		}
		if ( defined($self->{TimeZone}) && $self->{TimeZone} ne $1 ) {
		    print STDERR "error: attempt to add listings from two different time zones\n";
		    print STDERR "       $self->{TimeZone} != $1\n";
		    return(0);
		}
		$self->{TimeZone}=$1;
		print STDERR "user selected $self->{TimeZone} as his time zone\n" if ( $debug );
	    }

	    print "parsing ..\n" if ($debug);
	    $tbl->parse($urldata);

	    my $tablearr=$tbl->{Table};
	    if ( !defined($tablearr) ) {
		print STDERR "no tables found\n";
		print STDERR "urldata:\n$urldata\n";
		return(0);
	    }
	    
	    #my @tablearr=$tablearr[0];
	    
	    #print "RESULT:\n";
	    #$dumper->dumpValue($tablearr);
	    #print "/RESULT:\n";

	    my @noSubHeadersTable;
	    my @arr=@{$tablearr};

	    # for first row which is a 'time row' onto the array
	    push(@noSubHeadersTable, $arr[0]);

	    for (my $i=1 ; $i<scalar(@arr) ; $i++) {
		if ( $i != 0 ) {
		    my @row=@{$arr[$i]};
		    
		    if ( isTimeRow(\@row) ) {
			print "row $i is time\n" if ($debug);
		    }
		    else {
			push(@noSubHeadersTable, \@row);
		    }
		}
	    }
	
	    #print "Ended up with ". scalar(@noSubHeadersTable). " rows\n";

	    # traverse table, removing first un-usable columns
	    for (my $nrow=0 ; $nrow< scalar(@noSubHeadersTable) ; $nrow++) {
		my @row=@{$noSubHeadersTable[$nrow]};

		#print "examing row:";$dumper->dumpValue(\@row);

		# remove unneeded last column
		if ( $nrow == 0 ) {
		    # check constraints on first column of time row
		    my $field=$row[0];
		    
		    if ( $field->{colspan} != 2 || $field->{fieldtag} ne 'td' || defined($field->{prog_title})) {
			print "ROW: "; $dumper->dumpValue(\@{$noSubHeadersTable[$nrow]});
			print "FIELD: "; $dumper->dumpValue($field);
			die "column 0 failed on row $nrow";
		    }
		    # change colspan to remove virtual first column
		    $field->{colspan}=1;
		}
		else {
		    # check constraints on first column of non-time rows
		    my $field=$row[0];
		    
		    if ( $field->{colspan} != 1 || $field->{fieldtag} ne 'td' || defined($field->{prog_title}) ) {
			print "ROW: "; $dumper->dumpValue(\@{$noSubHeadersTable[$nrow]});
			print "FIELD: "; $dumper->dumpValue($field);
			die "column 0 failed on row $nrow";
		    }
		    #print "row $nrow: deleting first column entry\n";
		    # remove the first column
		    splice(@{$noSubHeadersTable[$nrow]}, 0, 1);
		}
		
		# remove unneeded last column
		if ( 1 ) {
		    @row=@{$noSubHeadersTable[$nrow]};
		    my $field=$row[scalar(@{$noSubHeadersTable[$nrow]})-1];
		    
		    if ( $nrow == 0 ) {
			# check constraints on last column of time row
			if ( $field->{colspan} != 2 || $field->{fieldtag} ne 'td' ) {
			    print "ROW: "; $dumper->dumpValue(\@{$noSubHeadersTable[$nrow]});
			    print "FIELD: "; $dumper->dumpValue($field);
			    die "column ".(scalar(@{$noSubHeadersTable[$nrow]})-1)." failed on row $nrow";
			}
			# change colspan to remove virtual last column
			$field->{colspan}=1;
		    }
		    else {
			# check constraints on last column of non-time rows
			if ( $field->{colspan} != 1 || $field->{fieldtag} ne 'td' ) {
			    print "ROW: "; $dumper->dumpValue(\@{$noSubHeadersTable[$nrow]});
			    print "FIELD: "; $dumper->dumpValue($field);
			    die "column ".(scalar(@{$noSubHeadersTable[$nrow]})-1)." failed on row $nrow";
			}
			#print "row $nrow: deleting last column entry ".(scalar(@{$noSubHeadersTable[$nrow]})-1)."\n";
			# remove the last column in the row
			splice(@{$noSubHeadersTable[$nrow]}, scalar(@{$noSubHeadersTable[$nrow]})-1, 1);
		    }
		}
		
		if ( $dataFormat eq "clicktv" ) {
		    # remove duplicated "first column" that appears in the last column that clicktv tables have
		    @row=@{$noSubHeadersTable[$nrow]};
		    my $col1=$row[0];
		    my $col2=$row[scalar(@{$noSubHeadersTable[$nrow]})-1];
		    
		    if ( $col1->{colspan}!=1 || $col1->{fieldtag} ne 'td' || 
			 (defined($col1->{prog_title}) != defined($col2->{prog_title}) || 
			  (defined($col1->{prog_title}) && $col1->{prog_title} ne $col2->{prog_title})) ) {
			print "ROW: "; $dumper->dumpValue(\@{$noSubHeadersTable[$nrow]});
			print "FIELD1: "; $dumper->dumpValue($col1);
			print "FIELD2: "; $dumper->dumpValue($col2);
			die "first/last column failed to be duplicates - row $nrow";
		    }
		    #print "row $nrow: deleting last column entry ".(scalar(@{$noSubHeadersTable[$nrow]})-1)."\n";
		    splice(@{$noSubHeadersTable[$nrow]}, scalar(@{$noSubHeadersTable[$nrow]})-1, 1);
		}
	    }

	    
	    # check/verify time row - which appears as first row
	    my @timerow=@{$noSubHeadersTable[0]};
	    splice(@timerow, 0, 1);

	    splice(@noSubHeadersTable, 0, 1);

	    # verify that first row contains the times
	    # then decode into a range of 30 minute segments
	    if ( 1 ) {
		# fix the first row of times to include the day/month/year
	    
		# ignore columns up until the one we just added
		my $field=$timerow[0];

		if ( !defined($field->{prog_title}) ) {
		    print "analizing time cell:"; $dumper->dumpValue($field);
		    die "time cell failed to give value in 'prog_title'";
		}
		
		# get starting hour from first cell
		my $curhour;
		if ( $field->{prog_title}=~m/^(\d+):(\d+)\s*([ap])\.m\.$/og ) {
		    my ($hour, $min, $am)=($1, $2, $3);
		    if ( $am eq 'a' ) { $hour=0 if ( $hour == 12 ); }
		    elsif ( $am eq 'p' ) { $hour+=12 if ( $hour!=12 );}
		    else { die "internal error how did we get '$am' ?"; }
		
		    if ( $min != 0 ) {
			die "internal error how did we start at a min $min ($field->{prog_title}) ?";
		    }
		    $curhour=$hour;
		}
		else {
		    die "no starting hour found in $field->{prog_title}";
		}
		
		# quick validation we have all segments 
		for (my $col=0 ; $col<scalar(@timerow) ; $col+=2, $curhour++) {
		    my $want1;
		    my $want2;
		    my $curday=$nday;
		
		    my $hourOfDay=$curhour;
		    if ( $curhour > 23 ) {
			$hourOfDay-=24;
			$curday++;
		    }

		    if ( $hourOfDay == 0  ) {
			$want1="12:00 a.m.";
			$want2="12:30 a.m.";
		    }
		    elsif ( $hourOfDay < 12 ) {
			$want1=sprintf("%d:00 a.m.", $hourOfDay);
			$want2=sprintf("%d:30 a.m.", $hourOfDay);
		    }
		    elsif ( $hourOfDay == 12 ) {
			$want1=sprintf("%d:00 p.m.", $hourOfDay);
			$want2=sprintf("%d:30 p.m.", $hourOfDay);
		    }
		    else {
			$want1=sprintf("%d:00 p.m.", $hourOfDay-12);
			$want2=sprintf("%d:30 p.m.", $hourOfDay-12);
		    }
		
		    #print "column $col in time row says $timerow[$col]->{prog_title}, expect $want1\n";
		    #print "  and says $timerow[$col+1]->{prog_title}, expect $want2\n";
		
		    my $field1=$timerow[$col];
		    my $field2=$timerow[$col+1];

		    if ( $field1->{prog_title} eq "$want1" ) {
			delete($field1->{prog_title});

			$field1->{timeinfo}=[$hourOfDay*60, $curday, $year];
		    }
		    else {
			die "even column $col in time row says $field1->{prog_title}, not $want1";
		    }
		    
		    if ( $field2->{prog_title} eq "$want2" ) {
			delete($field2->{prog_title});
			$field2->{timeinfo}=[$hourOfDay*60+30, $curday, $year];
		    }
		    else {
			die "odd column $col+1 in time row says $field2->{prog_title}, not $want2";
		    }
		}
	    }
	
	    #print "RESULT:\n";
	    #$dumper->dumpValue(\@noSubHeadersTable);
	    #print "/RESULT:\n";

	    push(@TimeTable, @timerow);
	    
	    # slap this table onto the start of the existing one
	    # - append each row onto the end of the existing table (or init a new one)
	    #
	    if ( !defined(@DayTable) ) {
		@DayTable=@noSubHeadersTable;
	    }
	    else {
		if ( scalar(@DayTable) != scalar(@noSubHeadersTable) ) {
		    print STDERR "$url: contained ".scalar(@noSubHeadersTable)." not ".scalar(@DayTable)."\n";
		}
		for (my $i=0 ; $i< scalar(@noSubHeadersTable) ; $i++) {
		    # append listing without first row (which is the channel row)
		    my @row=@{$noSubHeadersTable[$i]};
		    splice(@row,0,1);
		    push(@{$DayTable[$i]}, @row);
		}
	    }
	}

	my $SegmentsInTimeLine=scalar(@TimeTable);
	#print "TimeTable is :"; $dumper->dumpValue(\@TimeTable);

	# verify that:
	# - colspan total spans all columns
	# - merge cells that say cont to next, and next says cont from previous
	for (my $row=0 ; $row< scalar(@DayTable) ; $row++) {
	    my @r=@{$DayTable[$row]};
	    my $totalcolspan=0;
	    
	    for (my $i=1 ; $i<scalar(@r) ; $i++ ) {
		$totalcolspan+=$r[$i]{colspan};
	    }
	    if ( $totalcolspan != $SegmentsInTimeLine ) {
		print "ERROR: row $row has $totalcolspan column spans, not $SegmentsInTimeLine\n";
		for (my $i=1; $i<scalar(@r) ; $i++ ) {
		    print "schedule for $row $i :"; $dumper->dumpValue(\%{$r[$i]});
		}
	    }
	}

	# finished adding a day's worth of schedules

	# slap this table onto the start of the existing one
	# - append each row onto the end of the existing table (or init a new one)
	#
	my $removeChannelColumn=defined(@WholeTable);
	for (my $i=0 ; $i< scalar(@DayTable) ; $i++) {
	    if ( $removeChannelColumn) {
		my @row=@{$DayTable[$i]};
		#print "Ignoring Channel row: ";$dumper->dumpValue(\%{$row[0]});
		splice(@{$DayTable[$i]}, 0, 1);
	    }
	    push(@{$WholeTable[$i]}, @{$DayTable[$i]});
	}
	push(@TimeLine, @TimeTable);
    }
	
    # verify timeline contains 30 minute intervals all the way across
    if ( 1 ) {
	my $lasttime;
	my $timecol=0;
	foreach my $cell (@TimeLine) {
	    $timecol++;
	    my ( $minOfDay, $dayofyear, $year)=@{$cell->{timeinfo}};
	    my $minOfYear=$minOfDay+($dayofyear * 24*60);
	    if ( defined($lasttime) ) {
		if ( $minOfYear - $lasttime != 30 ) {
		    die "time cell $timecol is not 30 min later than last ($cell->{local_time},$lasttime)";
		}
		#if ( $cell->{local_time}-$lasttime == 30*60*1000 ) {
		 #   die "time cell $timecol is not 30 min later than last ($cell->{local_time},$lasttime)";
		#}
	    }
	    $lasttime=$minOfYear;
	    delete($cell->{colspan});
	    delete($cell->{fieldtag});
	}
    }

    # remove channel column (column 1) saved away
    my @Channels;
    for (my $nrow=0 ; $nrow< scalar(@WholeTable) ; $nrow++) {
	my @row=@{$WholeTable[$nrow]};

	if ( $debug > 1 ) { print "checking out row:$nrow:"; $dumper->dumpValue(\@row); }

	my $ch=$row[0];
	my $channel;
	
	die "channel info spanned more than one column" if ( $ch->{colspan} != 1);
	    
	$channel->{url}=$ch->{prog_href} if ( defined($ch->{prog_href}) );
	
	my @poss;
	push(@poss, $ch->{prog_title})    if ( defined($ch->{prog_title}));
	push(@poss, $ch->{prog_subtitle}) if ( defined($ch->{prog_subtitle}));
	push(@poss, $ch->{prog_desc})     if ( defined($ch->{prog_desc}));
		
	# if the channel number appears separately from the station id/affiliate
	# then the affiliate appears next, otherwise the station id appears with
	# the channel number
	foreach my $possible (@poss) {
	    if ( !defined($channel->{number}) ) {
		if ( $possible=~m/^([0-9]+)\s*$/o ) {
		    $channel->{number}=$1;
		    next;
		}
		elsif ( $possible=~m/^([0-9]+)\s+/o ) {
		    $channel->{number}=$1;
		    $possible=~s/^([0-9]+)\s*//o;
		    
		    if ( defined($channel->{localStation}) ) {
			die "expected $possible to be the local station here";
		    }
		    $channel->{localStation}=$possible;
		    next;
		}
	    }
	    if ( !defined($channel->{affiliate}) ) {
		$channel->{affiliate}=$possible;
	    }
	    elsif ( !defined($channel->{localStation}) ) {
		$channel->{localStation}=$possible;
	    }
	    else {
		die "don't know where to place $possible";
	    }
	}
	
	# verify and warn that the if IND appeared, it wasn't assigned to the localstation.
	if ( defined($channel->{localStation}) && $channel->{localStation} eq 'IND' ) {
	    print STDERR "warning: channel $channel->{number} has call lets IND, parse may have failed";
	}
	
	push(@Channels, $channel);
	#if ( $debug > 1 ) { print "loaded channel:"; $dumper->dumpValue($self);}

	# remove channel row
	splice(@{$WholeTable[$nrow]}, 0,1);
    }

    if ( !defined($self->{Channels}) ) {
	push(@{$self->{Channels}}, @Channels);
    }
    else {
	if ( scalar(@{$self->{Channels}}) != scalar(@Channels) ) {
	    print(STDERR "error: # of channels changed across schedules ". 
		  scalar(@{$self->{Channels}})." != ".scalar(@Channels)."\n");
	    return(0);
	}
	my @savedCh=@{$self->{Channels}};
	for (my $ch=0; $ch<scalar(@savedCh) ; $ch++ ) {
	    for my $opkey ('number', 'url', 'localStation', 'affiliate' ) {
		if ( defined($Channels[$ch]->{$opkey}) == defined($savedCh[$ch]->{$opkey}) ) {
		    if ( defined($Channels[$ch]->{$opkey}) && $Channels[$ch]->{$opkey} ne $savedCh[$ch]->{$opkey} ) {
			print(STDERR "error: channel $ch changed $opkey:".
			      $Channels[$ch]->{$opkey}." != ".$savedCh[$ch]->{$opkey}."\n");
			return(0);
		    }
		}
		else {
		    if ( defined($Channels[$ch]->{$opkey}) ) {
			print(STDERR "error: new channel $ch missing $opkey\n");
			return(0);
		    }
		    else {
			print(STDERR "error: new channel $ch has $opkey defined, different from last time\n");
			return(0);
		    }
		}
	    }
	}
    }

    # merge cells that say cont to next, and next says cont from previous
    for (my $nrow=0 ; $nrow< scalar(@WholeTable) ; $nrow++) {
	print "checking row $nrow\n" if ( $debug > 1 );
	my @row=@{$WholeTable[$nrow]};

	for (my $col=0 ; $col<scalar(@row)-1 ; $col++ ) {
	    my $cell1=$row[$col];
	    my $cell2=$row[$col+1];

	    if ( defined($cell1->{contToNextListing}) ) {
		if ( !defined($cell2->{contFromPreviousListing}) ) {
		    print STDERR "cell [col,row] [$col+1,$nrow] missing link to previous listing\n";
		}
		if ( defined($cell1->{prog_title}) && defined($cell2->{prog_title}) &&
		     $cell1->{prog_title} eq $cell2->{prog_title} ) {
		    if ( defined($cell2->{contToNextListing}) ) {
			$cell1->{contToNextListing}=$cell2->{contToNextListing};
		    }
		    else {
			delete($cell1->{contToNextListing});
		    }
		    $cell1->{colspan}+=$cell2->{colspan};
		    splice(@{$WholeTable[$nrow]}, $col+1, 1);
		    @row=@{$WholeTable[$nrow]};
		    $col--;
		    next;
		}
	    }
	}
    }

    # traverse WholeTable and:
    # - calculate prog ref # as needed
    # - move programs off into separate Programs hash
    # - remove some hash entries we no longer need
    for (my $nrow=0 ; $nrow< scalar(@WholeTable) ; $nrow++) {
	my @row=@{$WholeTable[$nrow]};

	if ( $debug > 1 ) { print "checking out row:$nrow:"; $dumper->dumpValue(\@row); }

	for (my $col=0 ; $col<scalar(@row) ; $col++ ) {
	    my $cell=$row[$col];

	    $cell->{prog_duration}=$cell->{colspan}*30;
	    if ( defined($cell->{prog_href}) ) {
		if ( $cell->{prog_href}=~m/prog_ref=([0-9]+)/o ) {
		    $cell->{pref}=$1;
		}
		delete($cell->{prog_href});
	    }
	    else {
		# for programs which don't have ref #s, we assign program ref #
		# based on program title and duration, we ignore all other differences.
		
		my $key="$cell->{prog_title}:$cell->{prog_duration}";
		
		if ( defined($self->{ProgByRefNegative}->{$key}) ) {
		    $cell->{pref}=$self->{ProgByRefNegative}->{$key};
		}
		else {
		    $self->{lastNegative_ProgByRef}--;
		    $self->{ProgByRefNegative}->{$key}=$self->{lastNegative_ProgByRef};
		    $cell->{pref}=$self->{lastNegative_ProgByRef};
		}
	    }
	    
	    my $prog;

	    foreach my $key ('duration',
			     'title',
			     'subtitle',
			     'desc',
			     'ratings_VCHIP', 
			     'ratings_VCHIP_Expanded', 
			     'ratings_MPAA',
			     'ratings_warnings', 
			     'qualifiers',
			     'director',
			     'year',
			     'actors',
			     'stars_rating') {
		if ( defined($cell->{"prog_$key"}) ) {
		    $prog->{$key}=$cell->{"prog_$key"};
		    delete($cell->{"prog_$key"});
		}
	    }
	    $prog->{refNumber}=$cell->{pref};
	    if ( defined($self->{Programs}->{$cell->{pref}}) ) {
		if ( $verify ) {
		    verifyProgramMatches($prog, $self->{Programs}->{$cell->{pref}});
		}
	    }
	    else {
		$self->{Programs}->{$cell->{pref}}=$prog;
	    }
	    
	    # remove some no-unneeded entires
	    delete($cell->{fieldtag});
	    # rename colspan to 'numberOf30MinSegments'
	    $cell->{numberOf30MinSegments}=$cell->{colspan};
	    delete($cell->{colspan});
	}
    }

    $self->{Schedule}=\@WholeTable;
    $self->{TimeLine}=\@TimeLine;
    
    print "Read Schedule with:";
    print "".scalar(@{$self->{Channels}})." channels, ";
    print "".scalar((keys %{$self->{Programs}}))." programs, ";
    print "".(scalar(@{$self->{TimeLine}})/2)." hours\n";
	    
    return(1);
}

sub getAndParseDetails($$)
{
    my ($self, $prog_ref)=@_;
    my $nprog;

    my $url=$self->getDetailURL($prog_ref);
    print "retrieving: $url..\n";
		
    my $urldata=$self->getDetailURLData($url);
    if ( !defined($urldata) ) {
	print STDERR "unable to read url $url\n";
	return(undef);
    }

    if ( $debug ) {
	print "\tread ".length($urldata). " bytes of html\n";
	print "urldata:\n'$urldata'\n" if ( $debug>1 );
    }

    # grab url at imdb if one exists
    # looks like: <A href="http://us.imdb.com/M/title-exact?Extreme%20Prejudice%20%281987%29" target="IMDB">
    if ( $urldata=~s;<A href=\"(http://[^.]+\.imdb\.com/M/title-exact\?[^\"])+\" target=\"IMDB\">;;og ) { 
	#$url=$1;
    }
    
    if ( $urldata=~s;<font style=\"EpisodeTitleFont\"> - ([^<]+)</font></td></TR>;;ogi ) { # "
	$nprog->{subtitle}=$1;
    }
    
    study($urldata);

    # remove some html tags for easier parsing
    $urldata=~s/<\/*nobr>//ogi;
    $urldata=~s///og;
    $urldata=~s/\n//og;
    $urldata=~s/<font [^>]+>//ogi;
    $urldata=~s/<\/font>//ogi;
    $urldata=~s/<\/*a[^>]*>//og;
    $urldata=~s/<![^>]+>//og;
		  
    #print STDERR "detail url contains='$urldata'\n";
    while ( $urldata=~s/<TD[^>]*>([a-zA-Z]+):<\/TD><T[DR]>([^<]+)<\/T[DR]>//oi ) {
	my $field=$1;
	my $desc=$2;
	
	# convert html tags and the like, removing write space etc.
	$desc=ClickListings::ParseTable::massageText($desc);
	
	#print STDERR "detail: $field: $desc\n";
	if ( $field eq "Type" ) {
	    if ( $desc=~s/\s*\(([0-9]+)\)//o ) {
		my $str=$1;
		$nprog->{year}=$str;
	    }
	    my @arr=split(/\s*\/\s*/, $desc);
	    #print STDERR "warning: ignoring Type defined as ". join(",", @arr)."\n";
	    foreach my $a (@arr) {
		$nprog->{category}->{$a}++;
	    }
	    #push(@{$nprog->{category}}, @arr);
	}
	elsif ( $field eq "Duration" ) {
	    # ignore - don't need this
	    # check for duration (ie '(6 hr) or (2 hr 30 min)')
	    my $min;
	    if ($desc =~m/([0-9]+)\s*hr/oi ) {
		$min=$1*60;
	    }
	    elsif ($desc =~m/([0-9]+)\s*hr\s*([0-9]+)\s*min/oi ) {
		$min=$1*60+$2;
	    }
	    elsif ($desc =~m/([0-9]+)\s*min/oi ) {
		$min=$1;
	    }
	    else {
		print "warning: failed to parse Duration field $desc\n";
	    }
	    # don't replace duration, believe what is in the schedule grid instead.
	    $nprog->{duration}=$min if ( defined($min) );
	}
	elsif ( $field eq "Description" ) {
	    my @details;
	    
	    #print STDERR "parsing $desc..\n";
	    while ( $desc=~m/\(([^\)]+)\)$/og ) {
		my $detail=$1;
		#print STDERR "parsing got $detail\n";
		
		# strip off what we found and any white space
		$desc=~s/\s*\([^\)]+\)$//og;
		push(@details, $detail);
	    }
	    if ( defined(@details) ) {
		$nprog->{details}=\@details;
	    }
	    if ( length($desc) ) {
		$nprog->{desc}=$desc;
	    }
	}
	elsif ( $field eq "Director" ) {
	    $desc=~s/,\s+/,/og;
	    $nprog->{director}=$desc;
	}
	elsif ( $field eq "Performers" ) {
	    my @actors=split(/\s*,\s*/, $desc);
	    $nprog->{actors}=\@actors;
	}
	# Parental Ratings are:
	#     TV-Y, TV-Y7, TV-G, TV-PG, TV-14, TV_MA.
	# 
	elsif ( $field eq "Parental Rating" ) {
	    push(@{$nprog->{ratings}}, "Parental Rating:$desc");
	}
	# Expanded ratings are:
	#     Adult Language
	#     Adult Situations
	#     Brief Nudity
	#     Graphic Violence
	#     Mild Violence
	#     Nudity
	#     Strong Sexual Content
	#     Violence
	elsif ( $field eq "Expanded Rating" ) {
	    push(@{$nprog->{ratings}}, "Expanded Rating:$desc");
	}
	# 
	# MPAA ratings include:
	#  G, PG, PG-13, R, Mature,NC-17, NR(not rated), GP, X.
	#
	elsif ( $field eq "Rated" ) {
	    push(@{$nprog->{ratings}}, "MPAA Rating:$desc");
	}
	else {
	    print STDERR "$prog_ref: unidentified field '$field' has desc='$desc'\n";
	}
    }

    if ( defined($nprog->{category}) ) {
	my $value=join(',', keys (%{$nprog->{category}}) );
	delete($nprog->{category});
	push(@{$nprog->{category}}, split(',', $value));
    }
    else {
	#print STDERR "\t program detail produced no Type info.. defaulting to Other\n" if ($debug);
	push(@{$nprog->{category}}, "Other");
    }
    return($nprog);
}

sub mergeDetails($$)
{
    my($self, $prog, $nprog)=@_;

    # if we've decided to, only trust certain details when they appear
    # in the listing and ignore them in the 'details' reference page.
    # - sometimes these entries in the details page are in-accurate
    #   or out of date.
    if ( !$self->{TrustAllDetailsEntries} ) {
	for my $key ( 'details', 'subtitle', 'desc', 'director',
		     'actors', 'ratings' ) {
	    delete($nprog->{$key}) if ( defined($nprog->{$key}) );
	}
    }

    if ( defined($nprog->{subtitle}) ) {
	if ( defined($prog->{subtitle}) && $nprog->{subtitle} ne $prog->{subtitle} ) {
	    print "warning: subtitle of $prog->{title} is different\n";
	    print "warning: '$nprog->{subtitle}' != '$prog->{subtitle}'\n";
	}
	$prog->{subtitle}=$nprog->{subtitle};
	delete($nprog->{subtitle});
    }
    
    if ( defined($nprog->{year}) ) {
	if ( defined($prog->{year}) && $nprog->{year} ne $prog->{year} ) {
	    print "warning: year of $prog->{title} is different\n";
	    print "warning: '$nprog->{year}' != '$prog->{year}'\n";
	}
	#print STDERR "$prog->{prog_ref}: year is $str\n";
	$prog->{year}=$nprog->{year};
	delete($nprog->{year});
    }
    
    if ( defined($nprog->{category}) ) {
	push(@{$prog->{category}}, @{$nprog->{category}});
	delete($nprog->{category});
    }
    
    if ( defined($nprog->{duration}) ) {
	if ( defined($prog->{duration}) ) {
	    if ( $nprog->{duration} ne $prog->{duration} ) {
		if ( $debug ) {
		    print "warning: duration of $prog->{title} is different\n";
		    print "warning: '$nprog->{duration}' != '$prog->{duration}'\n";
		    if ( defined($prog->{contFromPreviousListing}) ) {
			print "warning: was expected (cont from previous listing)\n";
		    }
		}
	    }
	}
	# don't replace duration, believe what is in the schedule grid instead.
	#$prog->{duration}=$min if ( defined($min) );
	delete($nprog->{duration});
    }
    
    if ( defined($nprog->{details}) ) {
      ClickListings::ParseTable::evaluateDetails($prog, @{$nprog->{details}});
	delete($nprog->{details});
    }

    if ( defined($nprog->{desc}) ) {
	if ( defined($prog->{desc}) && $nprog->{desc} ne $prog->{desc} ) {
	    print "warning: description of $prog->{title} is different\n";
	    print "warning: '$nprog->{desc}' != '$prog->{desc}'\n";
	}
	#print STDERR "$prog->{prog_ref}: description is $nprog->{desc}\n";
	if ( length($nprog->{desc}) ) {
	    $prog->{desc}=$nprog->{desc};
	}
	delete($nprog->{desc});
    }

    if ( defined($nprog->{director}) ) {
	if ( defined($prog->{director}) && $nprog->{director} ne $prog->{director} ) {
	    print "warning: director of $prog->{title} is different\n";
	    print "warning: '$nprog->{director}' != '$prog->{director}'\n";
	}
	#print STDERR "$prog->{prog_ref}: director is $nprog->{director}\n";
	$prog->{director}=$nprog->{director};
	delete($nprog->{director});
    }
    if ( defined($nprog->{actors}) ) {
	my @actors=@{$nprog->{actors}};
	if ( defined($prog->{actors}) ) {
	    my @lactors=@{$prog->{actors}};
	    my $out=0;
	    if ( scalar(@lactors) != scalar(@actors) ) {
		print "warning: actor list different size\n";
		$out++;
	    }
	    my $top=scalar(@lactors);
	    if ( scalar(@actors) > $top ) {
		$top=scalar(@actors);
	    }
	    for (my $num=0; $num<$top ; $num++ ) {
		if ( $lactors[$num] ne $actors[$num] ) {
		    print "warning: actor $num '".$lactors[$num]." != ".$actors[$num]."\n";
		    $out++;
		}
	    }
	    print "warning: actor list different for $prog->{title} in $out ways\n" if ( $out );
	}
	$prog->{actors}=\@actors;
	#print STDERR "$prog->{prog_ref}: actors defined as ". join(",", @actors)."\n";
	delete($nprog->{actors});
    }

    if ( defined($nprog->{ratings}) ) {
	if ( !defined($prog->{ratings}) ) {
	    push(@{$prog->{ratings}}, @{$nprog->{ratings}});
	}
	delete($nprog->{ratings});
    }
    if ( scalar(keys %{$nprog}) != 0 ) {
	print "$prog->{pref}: ignored scaped values of nprog:"; 
	$dumper->dumpValue($nprog);
    }
    return($prog);
}

use Fcntl qw(:DEFAULT);
use DB_File;

sub expandDetails
{
    my ($self, $cachePath)=@_;

    my %ptypeHash;
    my $foundInCache=0;

    my $ptypedb;

    if ( defined($cachePath) && length($cachePath) ) {
	$ptypedb=tie (%ptypeHash, "DB_File", $cachePath, O_RDWR|O_CREAT) || die "$cachePath: $!";
    }

    my $count=scalar((keys %{$self->{Programs}}));

    my $done=0;
    foreach my $refNumber (keys %{$self->{Programs}}) {
	$done++;
	my $percentDone=($done*100)/$count;
	if ( $percentDone > 1 && $percentDone%10 == 0 ) {
	    printf "resolved %.0f%% of the programs.. %d to go\n", $percentDone, $count-$done;
	}
	if ( $done % 10 == 0 ) {
	    # flush db every now and again
	    $ptypedb->sync() if ( defined($ptypedb) );
	}

	my $prog=$self->{Programs}->{$refNumber};
	if ( $refNumber >= 0 ) {
	    
 	    my $key=$prog->{title};
	    #$key.=":";
	    #$key.="$prog->{subtitle}" if ( defined($prog->{subtitle}) );
	    #$key.=":";
	    #$key.="$prog->{desc}" if ( defined($prog->{desc}) );
	    
	    my $value=$ptypeHash{$key};
	    if ( defined($value) ) {
		my %info;
		eval($value);
		my $nprog=\%info;
		
		$self->{Programs}->{$refNumber}=$self->mergeDetails($prog, $nprog);
		$foundInCache++;
	    }
	    else {
		print STDERR "$prog->{title}: missing program type, looking it up...\n" if ($debug);
		my $info=$self->getAndParseDetails($refNumber);
		if ( !defined($info) ) {
		    print STDERR "\t failed to parse url\n" if ($debug);
		}
		else {
		    # only add things to the db if the cache is enabled
		    if ( defined($ptypedb) ) {
			my $d=new Data::Dumper([\%{$info}], ['*info']);
			$d->Purity(0);
			$d->Indent(0);
			$ptypeHash{$key}=$d->Dump();
		    }
		    
		    $self->{Programs}->{$refNumber}=$self->mergeDetails($prog, $info);
		}
	    }
	}
	else {
	    print STDERR "$prog->{title}: missing program type and ref#, defaulting to <undef>\n" if ($debug);
	}
    }
    if ( defined($ptypedb) ) {
	untie(%ptypeHash);
    }
    return($foundInCache);
}

sub getChannelList
{
    my ($self)=@_;

    return(@{$self->{Channels}})
}

# create a conversion string
sub createDateString($$$$$)
{
    my ($minuteOfDay, $dayOfYear, $year, $additionalMin, $time_zone)=@_;
    
    if ( $additionalMin != 0 ) {
	$minuteOfDay+=$additionalMin;

	# deal with case where additional minutes pushes us over end of day
	if ( $minuteOfDay > 24*60 ) {
	    $minuteOfDay-=24*60;
	    $dayOfYear++;

	    # check and deal with case where this pushes us past end of year
	    my $isleap=&Date_LeapYear($year);
	    if ($dayOfYear >= ($isleap ? 367 : 366)) {
		$year++;
		$dayOfYear-=($isleap ? 367 : 366);
	    }
	}
    }

    # calculate year,month and day from nth day of year info
    my ($pYEAR,$pMONTH,$pDAY,$pHR,$pMIN,$pSEC)=Date::Manip::Date_NthDayOfYear($year, $dayOfYear);

    # set HR and MIN to what they should really be
    $pHR=int($minuteOfDay/60);
    $pMIN=$minuteOfDay-($pHR*60);

    return(sprintf("%4d%02d%02d%02d%02d00 %s", $pYEAR, $pMONTH, $pDAY, $pHR, $pMIN, $time_zone));
}

sub getProgramStartTime
{
    my ($self)=@_;
    my @timerow=@{$self->{TimeLine}};
    my ($progMinOfDay, $progDayOfYear, $progYear) = @{$timerow[0]->{timeinfo}};
    return(createDateString($progMinOfDay, $progDayOfYear, $progYear, 0, $self->{TimeZone}));
}

sub getProgramsOnChannel
{
    my ($self, $channelindex)=@_;
    my @channels=$self->getChannelList();
    my @schedule=@{$self->{Schedule}};
    my @timerow=@{$self->{TimeLine}};

    my @programs;
    
    my $timecol=0;
    my @row=@{$schedule[$channelindex]};

    for (my $col=0 ; $col<scalar(@row) ; $col++ ) {
	my $cell=$row[$col];
	
	my ($progMinOfDay, $progDayOfYear, $progYear) = @{$timerow[$timecol]->{timeinfo}};

	# as an optimization create start date string and cache it, since it won't change
	if ( !defined($timerow[$timecol]->{timeinfo_DateString}) ) {
	    $timerow[$timecol]->{timeinfo_DateString}=createDateString($progMinOfDay, $progDayOfYear, $progYear, 0, $self->{TimeZone});
	}
	my $ret;
	
	$ret->{start_time}=$timerow[$timecol];
	$ret->{start}=$timerow[$timecol]->{timeinfo_DateString};
	$ret->{end}=createDateString($progMinOfDay, $progDayOfYear, $progYear, ($cell->{numberOf30MinSegments}*30), $self->{TimeZone});
	$ret->{channel}=$channels[$channelindex];
	$ret->{program}=$self->{Programs}->{$cell->{pref}};
	$ret->{durationMin}=int($cell->{numberOf30MinSegments}*30);

	if ( defined($cell->{contFromPreviousListing}) ) {
	    $ret->{contFromPreviousListing}=$cell->{contFromPreviousListing};
	}
	if ( defined($cell->{contToNextListing}) ) {
	    $ret->{contToNextListing}=$cell->{contToNextListing};
	}

	push(@programs, $ret);

	# adjust timecol depending on how long the program is.
	$timecol+=($cell->{numberOf30MinSegments});
    }
    return(@programs);
}

1;
