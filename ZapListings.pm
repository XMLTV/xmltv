package ZapListings;

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

use strict;

use HTTP::Cookies;
use HTTP::Request::Common;

use vars qw($cookieJar);

my $cookieJar=undef;

sub doRequest($$$$)
{
    my ($ua, $req, $cookie_jar, $debug)=@_;
    
    if ( $debug ) {
	print "==== req ====\n", $req->as_string();
    }
    
    if ( defined($cookie_jar) ) {
	if ( $debug ) {
	    print "==== request cookies ====\n", $cookie_jar->as_string(), "\n";
	    print "==== sending request ====\n";
	}
	$cookie_jar->add_cookie_header($req);
    }
    
    my $res = $ua->request($req);
    if ( $debug ) {
	print "==== got response ====\n";
    }

    if ( defined($cookie_jar) ) {
	$cookie_jar->extract_cookies($res);
	if ( $debug ) {
	    print "==== response cookies ====\n", $cookie_jar->as_string(), "\n";
	}
    }

    if ( $debug ) {
	print "==== status: ", $res->status_line, " ====\n";
    }
    
    if ( $debug ) {
	if ($res->is_success) {
	    print "==== success ====\n";
	}
	elsif ($res->is_info) {
	    print "==== what's an info response? ====\n";
	}
	else {
	    print "==== bad ====\n";
	}
	#print $res->headers->as_string(), "\n";
	#print $res->content(), "\n";
    }
    return($res);
}

sub getProviders($$$)
{
    my ($postalcode, $zipcode, $debug)=@_;

    $cookieJar=HTTP::Cookies->new() if ( !defined($cookieJar) );

    my $ua=ZapListings::RedirPostsUA->new();
    
    my $code;
    $code=$postalcode if ( defined($postalcode) );
    $code=$zipcode if ( defined($zipcode) );

    my $req=POST("http://tvlistings2.zap2it.com/register.asp?id=form1&name=form1&zipcode=$code", [ ]);
    
    # actually attempt twice since first time in, we get a cookie that
    # works for the second request
    my $res=&doRequest($ua, $req, $cookieJar, $debug);
    
    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    # attempt after the first fails
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($ua, $req, $cookieJar, $debug);
    }

    if ( !$res->is_success ) {
	print STDERR "zap2it failed to give us a page\n";
	print STDERR "check postal/zip code or www site (maybe their down)\n";
	return(undef);
    }

    my $content=$res->content();
    if ( $debug ) {
	open(FD, "> providers.html") || die "providers.html:$!";
	print FD $content;
	close(FD);
    }

    if ( $content=~m/(We do not have information for the zip code[^\.]+)/i ) {
	print STDERR "zap2it says:\"$1\"\n";
	print STDERR "invalid postal/zip code\n";
	return(undef);
    }

    if ( $debug ) {
	if ( !$content=~m/<Input type="hidden" name="FormName" value="edit_provider_list.asp">/ ) {
	    print STDERR "Warning: form may have changed(1)\n";
	}
	if ( !$content=~m/<input type="submit" value="See Listings" name="saveProvider">/ ) {
	    print STDERR "Warning: form may have changed(2)\n";
	}
	if ( !$content=~m/<input type="hidden" name="zipCode" value="$code">/ ) {
	    print STDERR "Warning: form may have changed(3)\n";
	}
	if ( !$content=~m/<input type="hidden" name="ziptype" value="new">/ ) {
	    print STDERR "Warning: form may have changed(4)\n";
	}
	if ( !$content=~m/<input type=submit value="Confirm Channel Lineup" name="preview">/ ) {
	    print STDERR "Warning: form may have changed(5)\n";
	}
    }

    my $providers;
    while ( $content=~s/<SELECT(.*)(?=<\/SELECT>)//os ) {
        my $options=$1;
        while ( $options=~s/<OPTION value="(\d+)">([^<]+)<\/OPTION>//os ) {
	    $providers->{$2}=$1;
            #print "provider $2 ($1)\n";
        }
    }
    if ( !defined($providers) ) {
	print STDERR "zap2it gave us a page with no service provider options\n";
	print STDERR "check postal/zip code or www site (maybe their down)\n";
	return(undef);
    }
    return($providers);
}

sub _getChannelList($$$$)
{
    if ( 0 ) {
    my ($postalcode, $zipcode, $provider, $debug)=@_;

    $cookieJar=HTTP::Cookies->new() if ( !defined($cookieJar) );

    my $code;
    $code=$postalcode if ( defined($postalcode) );
    $code=$zipcode if ( defined($zipcode) );

    $cookieJar->set_cookie(0, 'TVListings', 
			   "zipcode=$code&ProviderID=$provider&vstr%2D1",
			   '/', 'tvlistings2.zap2it.com');

    my $ua=ZapListings::RedirPostsUA->new();

    my $req=POST('http://tvlistings2.zap2it.com/listings_redirect.asp?spp=0', [ ]);
    my $res=&doRequest($ua, $req, $cookieJar, $debug);

    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    # attempt after the first fails
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($ua, $req, $cookieJar, $debug);
    }

    if ( !$res->is_success ) {
	print STDERR "zap2it failed to give us a page\n";
	print STDERR "check postal/zip code or www site (maybe their down)\n";
	return(undef);
    }

    my $content=$res->content();
    if ( 0 && $content=~m/<p>(We are sorry, but your session has timed out[^<]*)/g ) {
	my $err=$1;
	$err=~s/\n/ /og;
	$err=~s/\s+/ /og;
	$err=~s/^\s+//og;
	$err=~s/\s+$//og;
	print STDERR "ERROR: $err\n";
	exit(1);
    }
    #$content=~s/>\s*</>\n</g;
    if ( $debug ) {
	open(FD, "> channels.html") || die "channels.html: $!";
	print FD $content;
	close(FD);
    }

    my $channels;
    my @lines=reverse(split(/\n/, $content));
    while (@lines) {
	my $l=pop(@lines);
	if ( $l=~m;<a href="listings_redirect.asp\?station_num=(\d+)">(\d+)<br><nobr>(\w+)</nobr></a>;o ) {
	    my $station=$1;
	    my $number=$2;
	    my $letters=$3;;
	    if ( !defined($channels->{$station}) ) {
		push(@{$channels->{$station}}, $number);
		push(@{$channels->{$station}}, $letters);
	    }
	}
    }
    if ( !defined($channels) ) {
	print STDERR "zap2it gave us a page with no channels\n";
	return(undef);
    }
    return($channels);
}
}

sub getChannelList($$$$)
{
    my ($postalcode, $zipcode, $provider, $debug)=@_;

    $cookieJar=HTTP::Cookies->new() if ( !defined($cookieJar) );

    my $code;
    $code=$postalcode if ( defined($postalcode) );
    $code=$zipcode if ( defined($zipcode) );

    my $ua=ZapListings::RedirPostsUA->new();
    my $req=POST('http://tvlistings2.zap2it.com/edit_provider_list.asp?id=form1&name=form1',
		 [FormName=>"edit_provider_list.asp",
		  zipCode => "$code", 
		  provider => "$provider", 
		  saveProvider => 'See Listings' ]);

    my $res=&doRequest($ua, $req, $cookieJar, $debug);
    #$res=&doRequest($ua, $req, $cookieJar, $debug);
    
    $req=POST('http://tvlistings2.zap2it.com/listings_redirect.asp?spp=0', [ ]);
    $res=&doRequest($ua, $req, $cookieJar, $debug);

    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    # attempt after the first fails
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($ua, $req, $cookieJar, $debug);
    }

    if ( !$res->is_success ) {
	print STDERR "zap2it failed to give us a page\n";
	print STDERR "check postal/zip code or www site (maybe their down)\n";
	return(undef);
    }

    my $content=$res->content();
    if ( 0 && $content=~m/<p>(We are sorry, but your session has timed out[^<]*)/g ) {
	my $err=$1;
	$err=~s/\n/ /og;
	$err=~s/\s+/ /og;
	$err=~s/^\s+//og;
	$err=~s/\s+$//og;
	print STDERR "ERROR: $err\n";
	exit(1);
    }
    #$content=~s/>\s*</>\n</g;
    if ( $debug ) {
	open(FD, "> channels.html") || die "channels.html: $!";
	print FD $content;
	close(FD);
    }

    my $channels;
    my @lines=reverse(split(/\n/, $content));
    while (@lines) {
	my $l=pop(@lines);
	if ( $l=~m;<a href="listings_redirect.asp\?station_num=(\d+)">(\d+)<br><nobr>(\w+)</nobr></a>;o ) {
	    my $station=$1;
	    my $number=$2;
	    my $letters=$3;;
	    if ( !defined($channels->{$station}) ) {
		push(@{$channels->{$station}}, $number);
		push(@{$channels->{$station}}, $letters);
	    }
	}
    }
    if ( !defined($channels) ) {
	print STDERR "zap2it gave us a page with no channels\n";
	return(undef);
    }
    return($channels);
}

1;


########################################################
#
# little LWP::UserAgent that accepts redirects
#
########################################################
package ZapListings::RedirPostsUA;
use HTTP::Request::Common;
use LWP::UserAgent;

use vars qw(@ISA);
@ISA = qw(LWP::UserAgent);

sub redirect_ok { 1; }
1;

########################################################
# END
########################################################

package ZapListings::ScrapeRow;

use strict;

use vars qw(@ISA);

@ISA = qw(HTML::Parser);

require HTML::Parser;

sub start($$$$$)
{
    my($self,$tag,$attr,$attrseq,$orig) = @_;

    if ( $tag=~/^t[dh]$/io ) {
	$self->{infield}++;
    }

    if ( $self->{infield} ) {
	my $thing;
	$thing->{starttag}=$tag;
	if ( keys(%{$attr}) != 0 ) {
	    $thing->{attr}=$attr;
	}
	push(@{$self->{Cell}->{things}}, $thing);
    }
}

sub text($$)
{
    my ($self,$text) = @_;

    if ( $self->{infield} ) {
	my $thing;
    
	$thing->{text}=$text;
	push(@{$self->{Cell}->{things}}, $thing);
    }
}

sub end($$)
{
    my ($self,$tag) = @_;

    if ( $tag=~/^t[dh]$/io ) {
	$self->{infield}--;

	my $thing;
	    
	$thing->{endtag}=$tag;
	push(@{$self->{Cell}->{things}}, $thing);

	push(@{$self->{Row}}, @{$self->{Cell}->{things}});
	delete($self->{Cell});
    }
    else {
	if ( $self->{infield} ) {
	    my $thing;
	    
	    $thing->{endtag}=$tag;
	    push(@{$self->{Cell}->{things}}, $thing);
	}
    }
}

#
# summarize in a single string the html we found.
#
sub summarize($)
{
    my $self=shift;

    if ( defined($self->{Cell}) ) {
	#print STDERR "warning: cell in row never closed, shouldn't happen\n";
	return("");
	#push(@{$self->{Row}}, @{$self->{Cell}->{things}});
	#delete($self->{Cell});
    }
    
    my @arr=reverse();
    my $desc="";
    foreach my $thing (@{$self->{Row}}) {
	if ( $thing->{starttag} ) {
	    $desc.="<$thing->{starttag}>";
	}
	elsif ( $thing->{endtag} ) {
	    $desc.="</$thing->{endtag}>";
	}
	elsif ( $thing->{text} ) {
	    $desc.="<text>$thing->{text}</text>";
	}
    }
    return($desc);
}

1;

package ZapListings::Scraper;

use HTTP::Request::Common;

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes
    
    if ( ! defined($self->{PostalCode}) &&
	 ! defined($self->{ZipCode}) ) {
	die "no PostalCode or ZipCode specified in create";
    }
    
    # since I know we don't care, lets pretend theirs only one code :)
    if ( defined($self->{PostalCode}) ) {
	$self->{ZipCode}=$self->{PostalCode};
	delete($self->{PostalCode});
    }

    die "no ProviderID specified in create" if ( ! defined($self->{ProviderID}) );
    
    $self->{cookieJar}=HTTP::Cookies->new() if ( !defined($cookieJar) );
    
    my $ua=ZapListings::RedirPostsUA->new();
    
    my $req=POST('http://tvlistings2.zap2it.com/edit_provider_list.asp?id=form1&name=form1',
		 [FormName=>"edit_provider_list.asp",
		  zipCode => "$self->{ZipCode}", 
		  provider => "$self->{ProviderID}",
		  saveProvider => 'See Listings' ]);

    my $res=&ZapListings::doRequest($ua, $req, $self->{cookieJar}, $self->{Debug});
    $res=&ZapListings::doRequest($ua, $req, $self->{cookieJar}, $self->{Debug});

    bless($self, $type);
    return($self);
}

use HTML::Entities qw(decode_entities);

sub massageText
{
    my ($text) = @_;

    $text=~s/&nbsp;/ /og;
    $text=decode_entities($text);
    $text=~s/^\s+//o;
    $text=~s/\s+$//o;
    $text=~s/\s+/ /o;
    return($text);
}

sub dumpMe($)
{
    require Data::Dumper;
    my $s = $_[0];
    my $d = Data::Dumper::Dumper($s);
    $d =~ s/^\$VAR1 =\s*//;
    $d =~ s/;$//;
    chomp $d;
    return $d;
}

#
# scraping html, here's the theory behind this madness.
# 
# heres the pseudo code is something like:
#    separate the rows of all html tables
#    for each row that looks like a listings row
#      parse and summarize the row in a single string
#      of xml, with start/end elements (no attributes)
#      that correspond with the html start/end tags
#      along with "text" elements around text html elements.
#
#    This gives us a single string we can do regexp against
#    to pull out the information based on the tags around
#    elements.
#
#    benefit of this approach is we get to pull elements out
#    if we can decipher how the html encoder is dealing with
#    them, for instance, subtitles at zap2it appear with <i>
#    tags around them, we can use this to know for certain
#    we're getting the subtitle of the program. Another one is
#    the title of the program is always bolded (<b>) so that
#    makes it easier.
#
#    Anything we can't decipher for certain gets the text pulled
#    out and we see if it only contains program qualifiers. If
#    so, we decode them and move on. If not we make some assumptions
#    about what the text might be, based on its position in the
#    html. The problem here is we can't decipher all qualifiers
#    because the entire list isn't known to us. We add as we go.
#
#    In the end anything left over we match against what we've
#    had left over after successful scrapes and if it differs
#    we emit an error since it means either the format has
#    changed or it contains info we didn't scrape properly.
#    
sub scrapehtml($$)
{
    my ($self, $html)=@_;

    my $rowNumber=0;
    $html=~s/<TR/<tr/og;
    $html=~s/<\/TR/<\/tr/og;

    my @programs;
    for my $row (split(qw/<tr/, $html)) {
	# nuke everything leading up to first >
	# which amounts to html attributes of <tr used in split
	$row=~s/^[^>]*>//so;
	
	# skipif the split didn't end with a row end </tr>
	#next if ( !($row=~s/[\n\r\s]*<\/tr>[\n\r\s]*$//iso));
	$row=~s/<\/tr>.*//so;
	#print "working on: $row\n";
	#next if ( !($row=~s/<\/tr>[\n\r\s]*$//iso));

	# ignore if more than one ending </tr> because they signal
	# imbedded tables - I think.
	next if ( $row=~m/<\/tr>/io);
	#$row=~s/(<\/tr>).*/$1/og;

	$rowNumber++;

	# remove space from leading space (and newlines) on every line of html
	$row=~s/[\r\n]+\s*//og;

	# should now be similar to:
	# <TD width="15%" valign="top" align="right"><B>12:20 AM</B></TD>
	# <TD width="5%"></TD><TD width="80%" valign="top">
	# <FONT face="Helvetica,Arial" size="2">
	# <B><A href="progdetails.asp\?prog_id=361803">Open Mike With Mike Bullard</A></B>
	# (<A href="textone.asp\?station_num=15942\&amp;cat_id=31">Talk / Tabloid</A>)
	#     CC Stereo  </FONT><FONT face="Helvetica,Arial" size="-2">  (ends at 01:20)
	#</TD>

	#print "IN: $rowNumber: $row\n";

	# run it through our row scaper that separates out the html
	my $result=new ZapListings::ScrapeRow()->parse($row);

	# put together a summary of what we found
	my $desc=$result->summarize();
	next if ( !$desc );

	# now we have something that resembles:
	# <td><b><text>....</text></b><td> etc.
	# 
	my $prog;
	#print "ROW: $rowNumber: $desc\n";
	if ( $desc=~s;^<td><b><text>([0-9]+):([0-9][0-9]) ([AP]M)</text></b></td><td></td>;;io ) {
	    my $posted_start_hour=$1;
	    $prog->{start_hour}=$1;
	    $prog->{start_min}=$2;
	    my $pm=($3=~m/^p/io); #PM

	    if ( $pm && $prog->{start_hour} != 12 ) {
		$prog->{start_hour}+=12;
	    }
	    elsif ( !$pm && $prog->{start_hour} == 12 ) {
		# convert 24 hour clock ( 12:??AM to 0:??AM )
		$prog->{start_hour}=0;
	    }

	    if ( $desc=~s;<font><text>(.*?)\s*\(ends at ([0-9]+):([0-9][0-9])\)</text></td>$;;io ||
		 $desc=~s;<font><text>(.*?)\s*\(ends at ([0-9]+):([0-9][0-9])\)\&nbsp\;</text><br><a><img></a></td>$;;io ) {
		$prog->{end_hour}=scalar($2);
		$prog->{end_min}=$3;

		if ( length($1) ) {
		    my $text=$1;
		    if ( $text=~s;\s*(\*+)\s*$;; ) {
			$prog->{prog_stars_rating}=sprintf("%d.0", length($1));
		    }
		    if ( $text=~s;\s*(\*+) 1/2\s*$;; ) {
			$prog->{prog_stars_rating}=sprintf("%d.5", length($1));
		    }
		    if ( length($text) ) {
			# put back reset of the text since sometime the (ends at xx:xx) is tacked on
			$desc.="<font><text>$text</text></td>";
		    }
		}
	    }
	    else {
		print "FAILED to find endtime\n";
	    }

	    if ( defined($prog->{end_hour}) ) {
		# anytime end hour is < start hour, end hour is next morning
		# posted start time is 12 am and end hour is also 12 then adjust
		if ( $prog->{start_hour} == 0 && $prog->{end_hour}==12 ) {
		    $prog->{end_hour}=0;
		}
		# prog starting after 6 with posted start > end hour
		elsif ( $prog->{start_hour} > 18 && $posted_start_hour > $prog->{end_hour} ) {
		    $prog->{end_hour}=$prog->{end_hour}+24;
		}
		# prog started in pm and ended at 12 (assume am)
		elsif ( $pm && $prog->{end_hour} == 12 ) {
		    $prog->{end_hour}+=12;
		}
		# if started in pm, then assume end hour needs adjustment to 24 hr clock
		elsif ( $pm ) {
		    $prog->{end_hour}+=12;
		}
	    }

	    if ( $desc=~s;<b><a><text>\s*(.*?)\s*</text></a></b>;;io ) {
		$prog->{title}=massageText($1);
	    }
	    else {
		print "FAILED to find title\n";
	    }
	    # <i><text>&quot;</text><a><text>Past Imperfect</text></a><text>&quot;</text></i>
	    if ( $desc=~s;<text> </text><i><text>&quot\;</text><a><text>\s*(.*?)\s*</text></a><text>&quot\;</text></i>;;io ) {
		$prog->{subtitle}=massageText($1);
	    }
	    else {
		print "FAILED to find subtitle\n" ( $self->{Debug} );
	    }

	    # categories may be " / " separated
	    if ( $desc=~s;<text>\(</text><a><text>\s*(.*?)\s*</text></a><text>\)\s+;<text>;io ) {
		for (split(/\s+\/\s/, $1) ) {
		    push(@{$prog->{category}}, massageText($_));
		}
	    }
	    else {
		print "FAILED to find category\n" ( $self->{Debug} );
	    }

	    #print "PREEXTRA: $desc\n";
	    my @extras;
	    while ($desc=~s;<text>\s*(.*?)\s*</text>;;io ) {
		push(@extras, massageText($1)); #if ( length($1) );
	    }

	    for (my $e=0 ; $e<scalar(@extras) ; $e++) {
		my $extra=$extras[$e];

		my $result;
		my $success=1;
		for my $i (split(/\s+/, $extra)) {
		    #
		    # www.tvguidelines.org and http://www.fcc.gov/vchip/
		    if ( $i=~m/^TV(Y)$/oi ||
			 $i=~m/^TV(Y7)$/oi ||
			 $i=~m/^TV(G)$/oi ||
			 $i=~m/^TV(PG)$/oi ||
			 $i=~m/^TV(14)$/oi ||
			 $i=~m/^TV(M)$/oi ||
			 $i=~m/^TV(MA)$/oi ) {
			$result->{prog_ratings_VCHIP}="$1";
			next;
		    }
		    # www.filmratings.com
		    elsif ( $i=~m/^(G)$/oi ||
			    $i=~m/^(PG)$/oi ||
			    $i=~m/^(PG-13)$/oi ||
			    $i=~m/^(R)$/oi ||
			    $i=~m/^(NC-17)$/oi ||
			    $i=~m/^(NR)$/oi ||
			    $i=~m/^Rated (G)$/oi ||
			    $i=~m/^Rated (PG)$/oi ||
			    $i=~m/^Rated (PG-13)$/oi ||
			    $i=~m/^Rated (R)$/oi ||
			    $i=~m/^Rated (NC-17)$/oi ||
			    $i=~m/^Rated (NR)$/oi ) {
			$result->{prog_ratings_MPAA}="$1";
			next;
		    }
		    elsif ( $i=~/^\d\d\d\d$/io ) {
			$result->{prog_year}=$i;
			next;
		    }
		    elsif ( $i=~/^CC$/io ) {
			$result->{prog_qualifiers}->{ClosedCaptioned}++;
			next;
		    }
		    elsif ( $i=~/^Stereo$/io ) {
			$result->{prog_qualifiers}->{InStereo}++;
			next;
		    }
		    elsif ( $i=~/^\(Repeat\)$/io ) {
			# understand, but ignore
			next;
		    }
		    elsif ( $i=~/^\(Taped\)$/io ) {
			$result->{prog_qualifiers}->{Taped}++;
			next;
		    }
		    elsif ( $i=~/^\(Live\)$/io ) {
			$result->{prog_qualifiers}->{Live}++;
			next;
		    }
		    else {
			$success=0;
			last;
		    }
		}
		# if everything in this piece parsed as a qualifier, then
		# incorporate the results, partial results are dismissed
		# then entire thing must parse into known qualifiers
		if ( $success ) {
		    for (keys %$result) {
			$prog->{$_}=$result->{$_};
		    }
		    splice(@extras, $e,1);
		}
	    }

	    # what ever is left is only allowed to be the description
	    # but there must be only one.
	    if ( @extras ) {
		if ( scalar(@extras) != 1 ) {
		    for (@extras) {
			print STDERR "scraper failed with left over details: $_\n";
		    }
		}
		else {
		    $prog->{desc}=pop(@extras);
		}
	    }

	    #for my $key (keys (%$prog)) {
		#if ( defined($prog->{$key}) ) {
		#    print "KEY $key: $prog->{$key}\n";
		#}
	    #}

	    if ( $desc ne "<td><font></font>" &&
		 $desc ne "<td><font></font><font></td>" ) {
		print STDERR "scraper failed with left overs: $desc\n";
	    }
	    #$desc=~s/<text>(.*?)<\/text>/<text>/og;
	    #print "\t$desc\n";
	    
	    push(@programs, $prog);
	}
    }
    return(@programs);
}

sub readSchedule($$$$$$$)
{
    my ($self, $station, $startHour, $endHour, $day, $month, $year)=@_;

    my $content;
    if ( -f "urldata/content-$station-$month-$day-$year.html" &&
	 open(FD, "< urldata/content-$station-$month-$day-$year.html") ) {
	my $s=$/;
	undef($/);
	$content=<FD>;
	close(FD);
	$/=$s;
    }
    else {
	my $ua=ZapListings::RedirPostsUA->new();
    
	my $req=POST('http://tvlistings2.zap2it.com/listings_redirect.asp',
		     [ displayType => "Text",
		       duration => "1",
		       startDay => "$month/$day/$year",
		       startTime => "0",
		       category => "0",
		       station => "$station",
		       goButton => "GO"
		       ]);

	my $res=&ZapListings::doRequest($ua, $req, $self->{cookieJar}, $self->{Debug});

	# looks like some requests require two identical calls since
	# the zap2it server gives us a cookie that works with the second
	# attempt after the first fails
	if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	    # again.
	    $res=&ZapListings::doRequest($ua, $req, $cookieJar, $self->{Debug});
	}
	
	if ( !$res->is_success ) {
	    print STDERR "zap2it failed to give us a page\n";
	    print STDERR "check postal/zip code or www site (maybe their down)\n";
	    return(0);
	}
	if ( -d "urldata" ) {
	    open(FD, "> urldata/content-$station-$month-$day-$year.html");
	    print FD $res->content();
	    close(FD);
	}
	$content=$res->content();
    }
    @{$self->{Programs}}=$self->scrapehtml($content);
    return(scalar(@{$self->{Programs}}));
}

sub getPrograms($)
{
    my $self=shift;
    my @ret=@{$self->{Programs}};
    delete($self->{Programs});
    return(@ret);
}

1;


