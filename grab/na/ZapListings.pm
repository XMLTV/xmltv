# $Id$

package XMLTV::ZapListings;

use strict;

use HTTP::Cookies;
use HTTP::Request::Common;

sub doRequest($$$$)
{
    my ($ua, $req, $debug)=@_;

    if ( $debug ) {
	print STDERR "==== req ====\n", $req->as_string();
    }

    my $cookie_jar=$ua->cookie_jar();
    if ( defined($cookie_jar) ) {
	if ( $debug ) {
	    print STDERR "==== request cookies ====\n", $cookie_jar->as_string(), "\n";
	    print STDERR "==== sending request ====\n";
	}
    }

    my $res = $ua->request($req);
    if ( $debug ) {
	print STDERR "==== got response ====\n";
    }

    $cookie_jar=$ua->cookie_jar();
    if ( defined($cookie_jar) ) {
	if ( $debug ) {
	    print STDERR "==== response cookies ====\n", $cookie_jar->as_string(), "\n";
	}
    }

    if ( $debug ) {
	print STDERR "==== status: ", $res->status_line, " ====\n";
    }

    if ( $debug ) {
	if ($res->is_success) {
	    print STDERR "==== success ====\n";
	}
	elsif ($res->is_info) {
	    print STDERR "==== what's an info response? ====\n";
	}
	else {
	    print STDERR "==== bad ====\n";
	}
	#print STDERR $res->headers->as_string(), "\n";
	#dumpPage($res->content());
	#print STDERR $res->content(), "\n";
    }
    return($res);
}

sub getProviders($$$)
{
    my ($postalcode, $zipcode, $debug)=@_;

    my $ua=XMLTV::ZapListings::RedirPostsUA->new('cookie_jar'=>HTTP::Cookies->new());
    if ( 0 && ! $ua->passRequirements($debug) ) {
	print STDERR "version of ".$ua->_agent()." doesn't handle cookies properly\n";
	print STDERR "upgrade to 5.61 or later and try again\n";
	return(undef);
    }

    my $code;
    $code=$postalcode if ( defined($postalcode) );
    $code=$zipcode if ( defined($zipcode) );

    my $req=GET("http://tvlistings2.zap2it.com/register.asp?id=form1&name=form1&zipcode=$code");

    # actually attempt twice since first time in, we get a cookie that
    # works for the second request
    my $res=&doRequest($ua, $req, $debug);

    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    # attempt after the first fails
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($ua, $req, $debug);
    }

    if ( !$res->is_success ) {
	print STDERR "zap2it failed to give us a page\n";
	print STDERR "check postal/zip code or www site (maybe they're down)\n";
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

    my @providers;
    while ( $content=~s/<SELECT(.*)(?=<\/SELECT>)//os ) {
        my $options=$1;
        while ( $options=~s/<OPTION value="(\d+)">([^<]+)<\/OPTION>//os ) {
	    my $p;
	    $p->{id}=$1;
	    $p->{description}=$2;
            #print STDERR "provider $1 ($2)\n";
	    push(@providers, $p);
        }
    }
    if ( !@providers ) {
	print STDERR "zap2it gave us a page with no service provider options\n";
	print STDERR "check postal/zip code or www site (maybe they're down)\n";
	print STDERR "(LWP::UserAgent version is ".$ua->_agent().")\n";
	return(undef);
    }
    return(@providers);
}

sub getChannelList($$$$)
{
    my ($postalcode, $zipcode, $provider, $debug)=@_;

    my $code;
    $code=$postalcode if ( defined($postalcode) );
    $code=$zipcode if ( defined($zipcode) );

    my $ua=XMLTV::ZapListings::RedirPostsUA->new('cookie_jar'=>HTTP::Cookies->new());
    if ( 0 && ! $ua->passRequirements($debug) ) {
	print STDERR "version of ".$ua->_agent()." doesn't handle cookies properly\n";
	print STDERR "upgrade to 5.61 or later and try again\n";
	return(undef);
    }

    my $req=POST('http://tvlistings2.zap2it.com/edit_provider_list.asp?id=form1&name=form1',
		 [FormName=>"edit_provider_list.asp",
		  zipCode => "$code", 
		  provider => "$provider", 
		  saveProvider => 'See Listings' ]);

    my $res=&doRequest($ua, $req, $debug);
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($ua, $req, $debug);
    }

    $req=GET('http://tvlistings2.zap2it.com/listings_redirect.asp?spp=0');
    $res=&doRequest($ua, $req, $debug);

    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    # attempt after the first fails
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($ua, $req, $debug);
    }

    if ( !$res->is_success ) {
	print STDERR "zap2it failed to give us a page\n";
	print STDERR "check postal/zip code or www site (maybe they're down)\n";
	return(undef);
    }

    my $content=$res->content();
    if ( 0 && $content=~m/>(We are sorry, [^<]*)/ig ) {
	my $err=$1;
	$err=~s/\n/ /og;
	$err=~s/\s+/ /og;
	$err=~s/^\s+//og;
	$err=~s/\s+$//og;
	print STDERR "ERROR: $err\n";
	exit(1);
    }
    #$content=~s/>\s*</>\n</g;

    # Probably this is not needed?  I think that calling dumpPage() if
    # an error occurs is probably better.  -- epa
    # 
    if ( $debug ) {
	open(FD, "> channels.html") || die "channels.html: $!";
	print FD $content;
	close(FD);
    }

    my @channels;

    my $rowNumber=0;
    my $html=$content;
    $html=~s/<TR/<tr/og;
    $html=~s/<\/TR/<\/tr/og;

    for my $row (split(/<tr/, $html)) {
	# nuke everything leading up to first >
	# which amounts to html attributes of <tr used in split
	$row=~s/^[^>]*>//so;
	$row=~s/<\/tr>.*//so;

	$rowNumber++;

	# remove space from leading space (and newlines) on every line of html
	$row=~s/[\r\n]+\s*//og;

	my $result=new XMLTV::ZapListings::ScrapeRow()->parse($row);

	my $desc=$result->summarize();
	next if ( !$desc );

	my $nchannel;

	if ( $desc=~m;^<td><img><br><font><b><a><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ){
	    $nchannel->{number}=$1;
	    $nchannel->{letters}=$2;

	    # img for icon
	    my $ref=$result->getSRC(2);
	    if ( !defined($ref) ) {
		print STDERR "row decode on item 2 failed on '$desc'\n";
		dumpPage($content);
		return(undef);
	    }
	    else {
		#print "got channel icon $ref\n";
		$nchannel->{icon}=$ref;
	    }

	    # <a> gives url that contains station_num
	    $ref=$result->getHREF(6);
	    if ( !defined($ref) ) {
		print STDERR "row decode on item 6 failed on '$desc'\n";
		dumpPage($content);
		return(undef);
	    }

	    if ( $ref=~m;listings_redirect.asp\?station_num=(\d+);o ) {
		$nchannel->{stationid}=$1;
	    }
	    else {
		print STDERR "row decode on item 6 href failed on '$desc'\n";
		dumpPage($content);
		return(undef);
	    }
	}
	elsif ( $desc=~m;^<td><font><b><a><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ) {
	    $nchannel->{number}=$1;
	    $nchannel->{letters}=$2;

	    # <a> gives url that contains station_num
	    my $ref=$result->getHREF(4);
	    if ( !defined($ref) ) {
		print STDERR "row decode on item 4 failed on '$desc'\n";
		dumpPage($content);
		return(undef);
	    }
	    if ( $ref=~m;listings_redirect.asp\?station_num=(\d+);o ) {
		$nchannel->{stationid}=$1;
	    }
	    else {
		print STDERR "row decode on item 4 href failed on '$desc'\n";
		dumpPage($content);
		return(undef);
	    }
	}
	else {
	    # ignored
	}

	if ( defined($nchannel) ) {
	    push(@channels, $nchannel);
	}
    }

    if ( ! @channels ) {
	print STDERR "zap2it gave us a page with no channels\n";
	dumpPage($content);
	return(undef);
    }

    foreach my $channel (@channels) {
	# default is channel is in listing
	if ( defined($channel->{number}) && defined($channel->{letters}) ) {
	    $channel->{description}="$channel->{number} $channel->{letters}"; 
	}
	else {
	    $channel->{description}.="$channel->{number}" if ( defined($channel->{number}) );
	    $channel->{description}.="$channel->{letters}" if ( defined($channel->{letters}) );
	}
	$channel->{station}=$channel->{description};
    }

    return(@channels);
}

# Write an offending HTML page to a file for debugging.
my $dumpPage_counter;
sub dumpPage($)
{
    my $content = shift;
    $dumpPage_counter = 0 if not defined $dumpPage_counter;
    $dumpPage_counter++;
    my $filename = "ZapListings.dump.$dumpPage_counter";
    local *OUT;
    if (open (OUT, ">$filename")) {
	print STDERR "dumping HTML page to $filename\n";
	print OUT $content
	  or warn "cannot dump HTML page to $filename: $!";
	close OUT or warn "cannot close $filename: $!";
    }
    else {
	warn "cannot dump HTML page to $filename: $!";
    }
}

1;


########################################################
#
# little LWP::UserAgent that accepts redirects
#
########################################################
package XMLTV::ZapListings::RedirPostsUA;
use HTTP::Request::Common;

# include LWP separately to verify minimal requirements on version #
use LWP 5.62;
use LWP::UserAgent;

use vars qw(@ISA);
@ISA = qw(LWP::UserAgent);

#
# manually check requirements on LWP (libwww-perl) installation
# leaving this subroutine here in case we need something less
# strict or more informative then what 'use LWP 5.60' gives us.
# 
sub passRequirements($$)
{
    my ($self, $debug)=@_;
    my $haveVersion=$LWP::VERSION;

    print STDERR "requirements check: have $self->_agent(), require 5.61\n" if ( $debug );

    if ( $haveVersion=~/(\d+)\.(\d+)/ ) {
	if ( $1 < 5 || ($1 == 5 && $2 < 61) ) {
	    die "$0: requires libwww-perl version 5.61 or later, (you have $haveVersion)";
	    return(0);
	}
    }
    # pass
    return(1);
}

#
# add env_proxy flag to constructed UserAgent.
#
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_, env_proxy => 1);
    bless ($self, $class);
    return $self;
}

sub redirect_ok { 1; }
1;

########################################################
# END
########################################################

package XMLTV::ZapListings::ScrapeRow;

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

sub getSRC($$)
{
    my ($self, $index)=@_;

    my @arr=@{$self->{Row}};
    my $thing=$arr[$index-1];

    #print STDERR "item $index : ".XMLTV::ZapListings::Scraper::dumpMe($thing)."\n";
    if ( $thing->{starttag}=~m/img/io ) {
	return($thing->{attr}->{src}) if ( defined($thing->{attr}->{src}) );
	return($thing->{attr}->{SRC}) if ( defined($thing->{attr}->{SRC}) );
    }
    return(undef);
}

sub getHREF($$)
{
    my ($self, $index)=@_;

    my @arr=@{$self->{Row}};
    my $thing=$arr[$index-1];

    #print STDERR "item $index : ".XMLTV::ZapListings::Scraper::dumpMe($thing)."\n";
    if ( $thing->{starttag}=~m/a/io) {
	return($thing->{attr}->{href}) if ( defined($thing->{attr}->{href}) );
	return($thing->{attr}->{HREF}) if ( defined($thing->{attr}->{HREF}) );
    }

    return(undef);
}

1;

package XMLTV::ZapListings::Scraper;

use HTTP::Request::Common;

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes

    if ( ! defined($self->{PostalCode}) &&
	 ! defined($self->{ZipCode}) ) {
	die "no PostalCode or ZipCode specified in create";
    }

    # since I know we don't care, lets pretend there's only one code :)
    if ( defined($self->{PostalCode}) ) {
	$self->{ZipCode}=$self->{PostalCode};
	delete($self->{PostalCode});
    }

    die "no ProviderID specified in create" if ( ! defined($self->{ProviderID}) );

    $self->{cookieJar}=HTTP::Cookies->new();

    my $ua=XMLTV::ZapListings::RedirPostsUA->new('cookie_jar'=>$self->{cookieJar});

    my $req=POST('http://tvlistings2.zap2it.com/edit_provider_list.asp?id=form1&name=form1',
		 [FormName=>"edit_provider_list.asp",
		  zipCode => "$self->{ZipCode}", 
		  provider => "$self->{ProviderID}",
		  saveProvider => 'See Listings' ]);

    # initialize cookies
    my $res=&XMLTV::ZapListings::doRequest($ua, $req, $self->{Debug});
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&XMLTV::ZapListings::doRequest($ua, $req, $self->{Debug});
    }

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

sub setValue($$$$)
{
    my ($self, $hash_ref, $key, $value)=@_;
    my $hash=$$hash_ref;

    if ( $self->{Debug} ) {
	if ( defined($hash->{$key}) ) {
	    print STDERR "replaced value '$key' from '$hash->{$key}' to '$value'\n";
	}
	else {
	    print STDERR "set value '$key' to '$value'\n";
	}
    }
    $hash->{$key}=$value;
    return($hash)
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
my %warnedCandidateDetail;
sub scrapehtml($$$)
{
    my ($self, $html, $htmlsource)=@_;

    # declare known languages here so we can more precisely identify
    # them in program details
    my @knownLanguages=qw(
			  Aboriginal
			  Arabic
			  Armenian
			  Cambodian
			  Cantonese
			  Chinese
			  Colonial
			  Cree
			  English
			  Farsi
			  French
			  German
			  Greek
			  Gujarati
			  Hindi
			  Hmong
			  Hungarian
			  Innu
			  Inuktitut
			  Inkutitut
			  Inukutitut
			  Inuvialuktun
			  Italian
			  Italianate
			  Iranian
			  Japanese
			  Korean
			  Mandarin
			  Mi'kmaq
			  Mohawk
			  Musgamaw
			  Oji
			  Panjabi
			  Polish
			  Portuguese
			  Punjabi
			  Quechuan
			  Romanian
			  Russian
			  Spanish
			  Swedish
			  Tagalog
			  Tamil
			  Tlingit
			  Ukrainian
			  Urdu
			  Vietnamese
			  );

    my $rowNumber=0;
    $html=~s/<TR/<tr/og;
    $html=~s/<\/TR/<\/tr/og;

    my @programs;
    for my $row (split(/<tr/, $html)) {
	# nuke everything leading up to first >
	# which amounts to html attributes of <tr used in split
	$row=~s/^[^>]*>//so;

	# skipif the split didn't end with a row end </tr>
	#next if ( !($row=~s/[\n\r\s]*<\/tr>[\n\r\s]*$//iso));
	$row=~s/<\/tr>.*//so;
	#print STDERR "working on: $row\n";
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

	#print STDERR "IN: $rowNumber: $row\n";

	# run it through our row scaper that separates out the html
	my $result=new XMLTV::ZapListings::ScrapeRow()->parse($row);

	# put together a summary of what we found
	my $desc=$result->summarize();
	next if ( !$desc );

	# now we have something that resembles:
	# <td><b><text>....</text></b><td> etc.
	# 
	my $prog;
	if ( $self->{DebugListings} ) {
	   $prog->{precomment}=$desc;
 	}
	print STDERR "ROW: $rowNumber: $desc\n" if ( $self->{Debug} );
	if ( $desc=~s;^<td><b><text>([0-9]+):([0-9][0-9]) ([AP]M)</text></b></td><td></td>;;io ) {
	    my $posted_start_hour=scalar($1);
	    my $posted_start_min=scalar($2);
	    my $pm=($3=~m/^p/io); #PM

	    $prog=$self->setValue(\$prog, "start_hour", $posted_start_hour);
	    $prog=$self->setValue(\$prog, "start_min", $posted_start_min);

	    if ( $pm && $prog->{start_hour} != 12 ) {
		$self->setValue(\$prog, "start_hour", $prog->{start_hour}+12);
	    }
	    elsif ( !$pm && $prog->{start_hour} == 12 ) {
		# convert 24 hour clock ( 12:??AM to 0:??AM )
		$self->setValue(\$prog, "start_hour", 0);
	    }

	    if ( $desc=~s;<font><text>(.*?)\s*\(ends at ([0-9]+):([0-9][0-9])\)(.*?)</text></td>$;;io ||
		 $desc=~s;<font><text>(.*?)\s*\(ends at ([0-9]+):([0-9][0-9])\)\&nbsp\;(.*?)</text><br><a><img></a></td>$;;io){
		my $preRest=$1;
		my $posted_end_hour=$2;
		my $posted_end_min=$3;
		my $postRest=$4;

		$self->setValue(\$prog, "end_hour", scalar($2));
		$self->setValue(\$prog, "end_min", $3);

		if ( defined($postRest) && length($postRest) ) {
		    $postRest=~s/^\&nbsp\;//o;
		}
		if ( !defined($postRest) || !length($postRest) ) {
		    $postRest="";
		}

		if ( defined($preRest) && length($preRest) ) {
		    #if ( $self->{Debug} ) {
			#print STDERR "prereset: $preRest\n";
		    #}
		    if ( $preRest=~s;\s*(\*+)\s*$;; ) {
			$self->setValue(\$prog, "star_rating", sprintf("%d/4", length($1)));
		    }
		    elsif ( $preRest=~s;\s*(\*+)\s*1/2\s*$;; ) {
			$self->setValue(\$prog, "star_rating", sprintf("%d.5/4", length($1)));
		    }
		    else {
			if ( $self->{Debug} ) {
		           print STDERR "FAILED to decode what we think should be star ratings\n";
		           print STDERR "\tsource: $htmlsource\n";
		           print STDERR "\tdecode failed on:'$preRest'\n"
			}
		    }
		}
		if ( length($preRest) || length($postRest) ) {
		    $desc.="<font><text>";
		    if ( length($preRest) && length($postRest) ) {
			$desc.="$preRest&nbsp;$postRest";
		    }
		    elsif ( length($preRest) ) {
			$desc.="$preRest";
		    }
		    else {
			$desc.="$postRest";
		    }
		    # put back reset of the text since sometime the (ends at xx:xx) is tacked on
		    $desc.="</text></td>";
		    if ( $self->{Debug} ) {
			print STDERR "put back details, now have '$desc'\n";
		    }
		}
	    }
	    else {
		print STDERR "FAILED to find endtime\n";
		print STDERR "\tsource: $htmlsource\n";
		print STDERR "\thtml:'$desc'\n"
	    }

	    if ( defined($prog->{end_hour}) ) {
		# anytime end hour is < start hour, end hour is next morning
		# posted start time is 12 am and end hour is also 12 then adjust
		if ( $prog->{start_hour} == 0 && $prog->{end_hour}==12 ) {
		    $self->setValue(\$prog, "end_hour", 0);
		}
		# prog starting after 6 with posted start > end hour
		elsif ( $prog->{start_hour} > 18 && $posted_start_hour > $prog->{end_hour} ) {
		    $self->setValue(\$prog, "end_hour", $prog->{end_hour}+24);
		}
		# if started in pm and end was not 12, then adjustment to 24 hr clock
		elsif ( $prog->{start_hour} > $prog->{end_hour} ) {
		    $self->setValue(\$prog, "end_hour", $prog->{end_hour}+12);
		}
	    }

	    if ( $desc=~s;<b><a><text>\s*(.*?)\s*</text></a></b>;;io ) {
		$self->setValue(\$prog, "title", massageText($1));
	    }
	    else {
		if ( $self->{Debug} ) {
		    print STDERR "FAILED to find title\n";
		    print STDERR "\tsource: $htmlsource\n";
		    print STDERR "\thtml:'$desc'\n";
		}
	    }
	    # <i><text>&quot;</text><a><text>Past Imperfect</text></a><text>&quot;</text></i>
	    if ( $desc=~s;<text> </text><i><text>&quot\;</text><a><text>\s*(.*?)\s*</text></a><text>&quot\;</text></i>;;io ) {
		$self->setValue(\$prog, "subtitle", massageText($1));
	    }
	    else {
		if ( $self->{Debug} ) {
		    print STDERR "FAILED to find subtitle\n";
		    print STDERR "\tsource: $htmlsource\n";
		    print STDERR "\thtml:'$desc'\n";
		}
	    }

	    # categories may be " / " separated
	    if ( $desc=~s;<text>\(</text><a><text>\s*(.*?)\s*</text></a><text>\)\s+;<text>;io ) {
		for (split(/\s+\/\s/, $1) ) {
		    push(@{$prog->{category}}, massageText($_));
		}
	    }
	    else {
		if ( $self->{Debug} ) {
		    print STDERR "FAILED to find category\n";
		    print STDERR "\tsource: $htmlsource\n";
		    print STDERR "\thtml:'$desc'\n";
		}
	    }

	    if ( $self->{Debug} ) {
		print STDERR "PREEXTRA: $desc\n";
	    }
	    my @extras;
	    while ($desc=~s;<text>\s*(.*?)\s*</text>;;io ) {
		push(@extras, massageText($1)); #if ( length($1) );
	    }
	    if ( $self->{Debug} ) {
		print STDERR "POSTEXTRA: $desc\n";
	    }
	    my @leftExtras;
	    for my $extra (reverse(@extras)) {
		my $original_extra=$extra;

		my $result;
		my $resultSure;
		my $success=1;
		my @notsure;
		my @sure;
		my @backup;
		print STDERR "splitting details '$extra'..\n" if ( $self->{Debug} );
		my @values;
		while ( 1 ) {
		    my $i;
		    if ( defined($extra) ) {
			if ( $extra=~s/\s*(\([^\)]+\))\s*$//o ) {
			    $i=$1;
			}
			else {
			    @values=reverse(split(/\s+/, $extra));
			    $extra=undef;
			    $i=pop(@values);
			}
		    }
		    else {
			if ( scalar(@values) == 0 ) {
			    last;
			}
			$i=pop(@values);
		    }
		    last if ( !defined($i) );

		    print STDERR "checking detail $i..\n" if ( $self->{Debug} );

		    # General page about ratings systems, one at least :)
		    # http://www.attadog.com/splash/rating.html
		    #
		    # www.tvguidelines.org and http://www.fcc.gov/vchip/
		    if ( $i=~m/^TV(Y)$/oi ||
			 $i=~m/^TV(Y7)$/oi ||
			 $i=~m/^TV(G)$/oi ||
			 $i=~m/^TV(PG)$/oi ||
			 $i=~m/^TV(14)$/oi ||
			 $i=~m/^TV(M)$/oi ||
			 $i=~m/^TV(MA)$/oi ) {
			$resultSure->{ratings_VCHIP}="$1";
			push(@sure, $i);
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
			$resultSure->{ratings_MPAA}="$1";
			push(@sure, $i);
			next;
		    }
		    # ESRB ratings http://www.esrb.org/esrb_about.asp
		    elsif ( $i=~/^(AO)$/io || #adults only
			    $i=~/^(EC)$/io || #early childhood
			    $i=~/^(K-A)$/io || # kids to adults
			    $i=~/^(KA)$/io || # kids to adults
			    $i=~/^(E)$/io || #everyone
			    $i=~/^(T)$/io || #teens
			    $i=~/^(M)$/io  #mature
			    ) {
			$resultSure->{ratings_ESRB}="$1";
			# remove dashes :)
			$resultSure->{ratings_ESRB}=~s/\-//o;
			push(@sure, $i);
			next;
		    }
		    # we're not sure about years that appear in the
		    # text unless the entire content of the text is
		    # found to be valid and "understood" program details
		    # ( so years that appear in the middle of program descriptions 
		    #   don't count, only when they appear by themselves or in text
		    #   like "CC Stereo 1969" for instance).
		    #
		    elsif ( $i=~/^\d\d\d\d$/io ) {
			$result->{year}=$i;
			push(@notsure, $i);
			push(@backup, $i);
			next;
		    }
		    elsif ( $i=~/\((\d\d\d\d)\)/io ) {
			$resultSure->{year}=$i;
			push(@sure, $i);
			push(@backup, $i);
			next;
		    }
		    elsif ( $i=~/^CC$/io ) {
			$resultSure->{qualifiers}->{ClosedCaptioned}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^Stereo$/io ) {
			$resultSure->{qualifiers}->{InStereo}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Repeat\)$/io ) {
			$resultSure->{qualifiers}->{PreviouslyShown}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Taped\)$/io ) {
			$resultSure->{qualifiers}->{Taped}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Live\)$/io ) {
			$resultSure->{qualifiers}->{Live}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Call-in\)$/io ) {
			$resultSure->{qualifiers}->{CallIn}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(animated\)$/io ) {
			$resultSure->{qualifiers}->{Animated}++;
			push(@sure, $i);
			next;
		    }
		    # catch commonly imbedded categories
		    elsif ( $i=~/^\(fiction\)$/io ) {
			push(@{$prog->{category}}, "Fiction");
			next;
		    }
		    elsif ( $i=~/^\(drama\)$/io || $i=~/^\(dramma\)$/io ) { # dramma is french :)
			push(@{$prog->{category}}, "Drama");
			next;
		    }
		    elsif ( $i=~/^\(Acción\)$/io ) { # action in french :)
			push(@{$prog->{category}}, "Action");
			next;
		    }
		    elsif ( $i=~/^\(Comedia\)$/io ) { # comedy in french :)
			push(@{$prog->{category}}, "Comedy");
			next;
		    }

		    # ignore sports event descriptions that include team records
		    # ex. (10-1)
		    elsif ( $i=~/^\(\d+\-\d+\)$/o ) {
			print STDERR "understood program detail, on ignore list: $i\n" if ( $self->{Debug} );
			# ignored
			next;
		    }
		    # ignore (Cont'd.) and (Cont'd)
		    elsif ( $i=~/^\(Cont\'d\.*\)$/io ) {
			print STDERR "understood program detail, on ignore list: $i\n" if ( $self->{Debug} );
			# ignored
			next;
		    }

		    # example "French with English subtitles"
		    # example "French and English subtitles"
		    # example "Japanese; English subtitles"
		    elsif ( $i=~/^\(([^\s]+)\s+with\s+([^\s]+) subtitles\)$/io ||
			    $i=~/^\(([^\s]+)\s+and\s+([^\s]+) subtitles\)$/io ||
			    $i=~/^\(([^\s|;|,|\/]+)[\s;,\/]*\s*([^\s]+) subtitles\)$/io) {
			my $lang=$1;
			my $sub=$2;

			my $found1=0;
			my $found2=0;
			for my $k (@knownLanguages) {
			    $found1++ if ( $k eq $lang );
			    $found2++ if ( $k eq $sub );
			}

			if ( ! $found1 ) {
			    print STDERR "identified possible candidate for new language $lang in $i\n";
			}
			if ( ! $found2 ) {
			    print STDERR "identified possible candidate for new language $sub in $i\n";
			}
			$resultSure->{qualifiers}->{Language}=$lang;
			$resultSure->{qualifiers}->{Subtitles}->{Language}=$sub;
		    }
		    #
		    # lanuages added as we see them.
		    #
		    else {
			my $localmatch=0;

			# 'Hindi and English'
			# 'Hindi with English'
			if ( $i=~/^\(([^\s]+)\s+and\s+([^\s]+)\)$/io ||
			     $i=~/^\(([^\s]+)\s+with\s+([^\s]+)\)$/io ) {
			    my $lang=$1;
			    my $sub=$2;

			    my $found1=0;
			    my $found2=0;
			    for my $k (@knownLanguages) {
				$found1++ if ( $k eq $lang );
				$found2++ if ( $k eq $sub );
			    }

			    # only print message if one matched and the other didn't
			    if ( ! $found1 && $found2 ) {
				print STDERR "identified possible candidate for new language $lang in $i\n";
			    }
			    if ( ! $found2 && $found1 ) {
				print STDERR "identified possible candidate for new language $sub in $i\n";
			    }
			    if ( $found1 && $found2 ) {
				$resultSure->{qualifiers}->{Language}=$lang;
				$resultSure->{qualifiers}->{Dubbed}=$sub;
				$localmatch++;
			    }
			}

			# more language checks
			# 'Hindi, English'
			# 'Hindi-English'
			# 'English/French'
			# 'English/Oji-Cree'
			# 'Hindi/Punjabi/Urdu', but I'm not sure what it means.
			if ( ! $localmatch && $i=~m;[/\-,];o) {
			    my $declaration=$i;
			    $declaration=~s/^\(\s*//o;
			    $declaration=~s/\s*\)$//o;

			    my @arr=split(/[\/]|[\-]|[,]/, $declaration);
			    my @notfound;
			    my $matches;
			    for my $lang (@arr) {
				# chop off start/end spaces
				$lang=~s/^\s*//o;
				$lang=~s/\s*$//o;

				my $found=0;
				for my $k (@knownLanguages) {
				    if ( $k eq $lang ) {
					$found++;
					last;
				    }
				}
				if ( !$found ) {
				    push(@notfound, $lang);
				}
				$matches+=$found;
			    }
			    if ( $matches == scalar(@arr) ) {
				# put "lang/lang/lang" in qualifier since we don't know
				# what it really means.
				$resultSure->{qualifiers}->{Language}=$declaration;
				$localmatch++;
			    }
			    elsif ( $matches !=0  ) {
				# matched 1 or more, warn about rest
				for my $sub (@notfound) {
				    print STDERR "identified possible candidate for new language $sub in $i\n";
				}
			    }
			}

			if ( ! $localmatch ) {
			    # check for known languages 
			    my $found;
			    for my $k (@knownLanguages) {
				if ( $i=~/^\($k\)$/i ) {
				    $found=$k;
				    last;
				}
			    }
			    if ( defined($found) ) {
				$resultSure->{qualifiers}->{Language}=$found;
				push(@sure, $i);
				next;
			    }

			    if ( $i=~/^\(/o && $i=~/\)$/o ) {
				if ( $i=~/^\(``/o && $i=~/''\)$/o ) {
				   if ( $self->{Debug} ) {
				      print STDERR "ignoring what's probably a show reference $i\n";
				   }
				}
				else {
				   print STDERR "possible candidate for program detail we didn't identify $i\n"
				       unless $warnedCandidateDetail{$i}++;
				}
			    }

			    $success=0;
			    push(@backup, $i);
			}
		    }
		}

		# always copy the ones we're sure about
		for (keys %$resultSure) {
		    $self->setValue(\$prog, $_, $resultSure->{$_});
		}
		if ( !$success ) {
		    if ( @notsure ) {
			if ( $self->{Debug} ) {
			    print STDERR "\thtml:'$desc'\n" if ( $self->{Debug} );
			    print STDERR "\tpartial match on details '$original_extra'\n";
			    print STDERR "\tsure about:". join(',', @sure)."\n" if ( @sure );
			    print STDERR "\tnot sure about:". join(',', @notsure)."\n" if ( @notsure );
			}
			# we piece the original back using space separation so that the ones
			# we're sure about are removed
			push(@leftExtras, join(' ', @backup));
		    }
		    else {
			print STDERR "\tno match on details '$original_extra'\n" if ( $self->{Debug} );
			push(@leftExtras, $original_extra);;
		    }
		}
		else {
		    # if everything in this piece parsed as a qualifier, then
		    # incorporate the results, partial results are dismissed
		    # then entire thing must parse into known qualifiers
		    for (keys %$result) {
			$self->setValue(\$prog, $_, $result->{$_});
		    }
		}
	    }

	    # what ever is left is only allowed to be the description
	    # but there must be only one.
	    if ( @leftExtras ) {
		if ( scalar(@leftExtras) != 1 ) {
		    for (@leftExtras) {
			print STDERR "scraper failed with left over details: $_\n";
		    }
		}
		else {
		    $self->setValue(\$prog, "desc", pop(@leftExtras));
		    print STDERR "assuming description '$prog->{desc}'\n" if ( $self->{Debug} );
		}
	    }

	    #for my $key (keys (%$prog)) {
		#if ( defined($prog->{$key}) ) {
		#    print STDERR "KEY $key: $prog->{$key}\n";
		#}
	    #}

	    if ( $desc ne "<td><font></font>" &&
		 $desc ne "<td><font></font><font></td>" ) {
		print STDERR "scraper failed with left overs: $desc\n";
	    }
	    #$desc=~s/<text>(.*?)<\/text>/<text>/og;
	    #print STDERR "\t$desc\n";


	    # final massage.

	    my $title=$prog->{title};
	    if ( defined($title) ) {
		# look and pull apart titles like: Nicholas Nickleby   Part 1 of 2
		# putting 'Part X of Y' in PartInfo instead
		if ( $title=~s/\s+Part\s+(\d+)\s+of\s+(\d+)\s*$//o ) {
		    $prog->{qualifiers}->{PartInfo}="Part $1 of $2";
		    $self->setValue(\$prog, "title", $title);
		}
	    }

	    push(@programs, $prog);
	}
    }
    return(@programs);
}

sub readSchedule($$$$$)
{
    my ($self, $stationid, $station_desc, $day, $month, $year)=@_;

    my $content;

    if ( -f "urldata/$stationid/content-$month-$day-$year.html" &&
	 open(FD, "< urldata/$stationid/content-$month-$day-$year.html") ) {
	print STDERR "cache enabled, reading urldata/$stationid/content-$month-$day-$year.html..\n";
	my $s=$/;
	undef($/);
	$content=<FD>;
	close(FD);
	$/=$s;
    }
    else {
	my $ua=XMLTV::ZapListings::RedirPostsUA->new('cookie_jar'=>$self->{cookieJar});

	if ( 0 && ! $ua->passRequirements($self->{Debug}) ) {
	    print STDERR "version of ".$ua->_agent()." doesn't handle cookies properly\n";
	    print STDERR "upgrade to 5.61 or later and try again\n";
	    return(-1);
	}

	my $req=POST('http://tvlistings2.zap2it.com/listings_redirect.asp',
		     [ displayType => "Text",
		       duration => "1",
		       startDay => "$month/$day/$year",
		       startTime => "0",
		       category => "0",
		       station => "$stationid",
		       goButton => "GO"
		       ]);

	my $res=&XMLTV::ZapListings::doRequest($ua, $req, $self->{Debug});

	# looks like some requests require two identical calls since
	# the zap2it server gives us a cookie that works with the second
	# attempt after the first fails
	if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	    # again.
	    $res=&XMLTV::ZapListings::doRequest($ua, $req, $self->{Debug});
	}

	if ( !$res->is_success ) {
	    print STDERR "zap2it failed to give us a page\n";
	    print STDERR "check postal/zip code or www site (maybe they're down)\n";
	    return(-1);
	}
	$content=$res->content();
        if ( $content=~m/>(We are sorry, [^<]*)/ig ) {
	   my $err=$1;
	   $err=~s/\n/ /og;
	   $err=~s/\s+/ /og;
	   $err=~s/^\s+//og;
	   $err=~s/\s+$//og;
	   print STDERR "ERROR: $err\n";
	   return(-1);
        }
	if ( -d "urldata" ) {
	    my $file="urldata/$stationid/content-$month-$day-$year.html";
	    if ( ! -f $file ) {
		print STDERR "cache enabled, writing $file..\n";
		if ( ! -d "urldata/$stationid" ) {
		    mkdir("urldata/$stationid", 0775) || warn "failed to create dir urldata/$stationid:$!";
		}
		if ( open(FD, "> $file") ) {
		    print FD $res->content();
		    close(FD);
		}
	    }
	}
    }

    if ( $self->{Debug} ) {
	print STDERR "scraping html for $year-$month-$day on station $stationid: $station_desc\n";
    }
    @{$self->{Programs}}=$self->scrapehtml($content, "$year-$month-$day on station $station_desc (id $stationid)");

    print STDERR "Day $year-$month-$day schedule for station $station_desc has:".
	scalar(@{$self->{Programs}})." programs\n";

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


