# $Id$

#
# Special thanks to Stephen Bain for helping me play catch-up with
# zap2it site changes.
#

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
	#main::errorMessage("warning: cell in row never closed, shouldn't happen\n");
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

    #main::errorMessage("item $index : ".XMLTV::ZapListings::dumpMe($thing)."\n");
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

    #main::errorMessage("item $index : ".XMLTV::ZapListings::dumpMe($thing)."\n");
    if ( $thing->{starttag}=~m/a/io) {
	return($thing->{attr}->{href}) if ( defined($thing->{attr}->{href}) );
	return($thing->{attr}->{HREF}) if ( defined($thing->{attr}->{HREF}) );
    }

    return(undef);
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
# add env_proxy flag to constructed UserAgent.
#
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_,
				  env_proxy => 1,
				  timeout => 180);
    bless ($self, $class);
    $self->agent('xmltv/0.5.7');
    return $self;
}

sub redirect_ok { 1; }

1;

########################################################
# END
########################################################

package XMLTV::ZapListings;

use strict;

use HTTP::Cookies;
use HTTP::Request::Common;
use URI;

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes

    my $code;
    $code=$self->{PostalCode} if ( defined($self->{PostalCode}) );
    $code=$self->{ZipCode} if ( defined($self->{ZipCode}) );

    if ( !defined($code) ) {
      main::errorMessage("ZapListings::new requires PostalCode or ZipCode defined\n");
	exit(1);
    }
    $self->{GeoCode}=$code;
    $self->{Debug}=0 if ( !defined($self->{Debug}) );

    $self->{cookieJar}=HTTP::Cookies->new();

    $self->{ua}=XMLTV::ZapListings::RedirPostsUA->new('cookie_jar'=>$self->{cookieJar});

    # add POST requests to redirectable mix
    push(@{$self->{ua}->requests_redirectable },'POST');

    bless($self, $type);

    if ( $self->initGeoCodeAndGetProvidersList($self->{GeoCode}) != 0 ) {
	return(undef);
    }

    return($self);
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

sub getForms($)
{
    my $content=$_[0];
    my @forms;

    while ( 1 ) {
	my $start=index($content, "<form");
	$start=index($content, "<FORM") if ( $start == -1 );

	if ( $start == -1 ) {
	    $start=index($content, $1) if ( $start=~m/(<FORM)/ios );
	}
	last if ( $start == -1 );

	my $insideContent=substr($content, $start);

	my $end=index($insideContent, "</form>");
	$end=index($insideContent, "</FORM>") if ( $end == -1 );

	if ( $end == -1 ) {
	    $end=index($content, $1) if ( $end=~m/(<FORM)/ios );
	}
	last if ( $end == -1 );

	#print STDERR "indexes are $start,$end\n";

	$end+=length("</form>");

	$insideContent=substr($insideContent, 0, $end);
	#print STDERR "inside = $insideContent\n";

	$content=substr($content, $start+$end);

	$insideContent=~s/^<form\s*([^>]+)>(.*)<\/form>$//ios;
	my $formAttrs=$1;
	my $insideForm=$2;
	
	#print STDERR "checking '$formAttrs' and '$insideForm'\n";

	#while ( $content=~s/<form\s*([^>]+)>(.*)(?!<\/form>)//ios ) {
	#my $formAttrs=$1;
	#my $insideForm=$2;

	my $form;
	while ( $formAttrs=~s/^\s*([^=]+)=//ios ) {
	    my $attr=$1;
	    $attr=~tr/[A-Z]/[a-z]/;
	    if ( $formAttrs=~m/^\"/o ) { #"
		$formAttrs=~s/^\"([^\"]*)\"\s*//o; #"
		$form->{attrs}->{$attr}=$1;
	    }
	    else {
		$formAttrs=~s/^([^\s]+)\s*//o;
		$form->{attrs}->{$attr}=$1;
	    }
	    $formAttrs=~s/\s+$//o;
	}
	while ( $insideForm=~s/<input\s*([^>]+)>//ios ) {
	    my $inputAttrs=$1;
	    my $input;
	    $input->{type}="text"; # default
	    while ( $inputAttrs=~s/^\s*([^=]+)=//ios ) {
		my $attr=$1;
		$attr=~tr/[A-Z]/[a-z]/;
		if ( $inputAttrs=~m/^\"/o ) { #"
		    $inputAttrs=~s/^\"([^\"]*)\"\s*//o; #"
		    $input->{$attr}=$1;
		}
		else {
		    $inputAttrs=~s/^([^\s]+)\s*//o;
		    $input->{$attr}=$1;
		}
		$inputAttrs=~s/\s+$//o;
	    }
	    push(@{$form->{inputs}}, $input);
	}
	
	if ( $insideForm=~m/<select/ios ) {
	    $insideForm=~s/<select/<select/ios;
	    $insideForm=~s/<\/select>/<\/select>/ios;
	    my $start;
	    while (($start=index($insideForm, "<select")) != -1 ) {
		my $end=index($insideForm, "</select>", $start)+length("</select>");
		my $above=substr($insideForm, 0, $start);
		
		my $ntext=substr($insideForm, $start, $end);
		$insideForm=$above.substr($insideForm, $end);

		while ( $ntext=~s/^<select\s*([^>]+)>(.*)(?=<\/select>)//ios ) {
		    my $selectAttrs=$1;
		    my $options=$2;
		    my $select;
		    while ( $selectAttrs=~s/^\s*([^=]+)=//ios ) {
			my $attr=$1;
			$attr=~tr/[A-Z]/[a-z]/;
			if ( $selectAttrs=~m/^\"/o ) { #"
			    $selectAttrs=~s/^\"([^\"]*)\"\s*//o; #"
			    $select->{attrs}->{$attr}=$1;
			}
			else {
			    $selectAttrs=~s/^([^\s]+)\s*//o;
			    $select->{attrs}->{$attr}=$1;
			}
			$selectAttrs=~s/\s+$//o;
		    }
		    while ( $options=~s/\s*<OPTION\s*([^>]+)>([^<]+)<\/OPTION>\s*//ios ||
			    $options=~s/\s*<OPTION\s*([^>]+)>([^<]+)\s*<OPTION>/<OPTION>/ios ||
			    $options=~s/\s*<OPTION\s*([^>]+)>([^<|]+)\s*$//ios) {
			my $optionAttrs=$1;
			my $optionValue=$2;
			my $option;
			
			$optionValue=~s/\s+$//og;

			$option->{cdata}=$optionValue;
			$option->{value}=$optionValue; # default value is contents
			while ( $optionAttrs=~s/^\s*([^=]+)=//ios ) {
			    my $attr=$1;
			    $attr=~tr/[A-Z]/[a-z]/;
			    if ( $optionAttrs=~m/^\"/o ) { #"
				$optionAttrs=~s/^\"([^\"]*)\"\s*//o; #"
				$option->{attrs}->{$attr}=$1;
			    }
			    else {
				$optionAttrs=~s/^([^\s]+)\s*//o;
				$option->{attrs}->{$attr}=$1;
			    }
			    $optionAttrs=~s/\s+$//o;
			}
			while ( $optionAttrs=~s/^\s*selected//ios ) {
			    $option->{selected}=1;
			}
			push(@{$select->{options}}, $option);
		    }
		    push(@{$form->{selects}}, $select);
		}
	    }
	}
	
	while ( $insideForm=~s/<textarea\s*([^>]+)>(.*)(?=<\/textarea>)//ios ) {
	    my $textAreaAttrs=$1;
	    my $textArea;
	    while ( $textAreaAttrs=~s/^\s*([^=]+)=//ios ) {
		my $attr=$1;
		$attr=~tr/[A-Z]/[a-z]/;
		if ( $textAreaAttrs=~m/^\"/o ) { #"
		    $textAreaAttrs=~s/^\"([^\"]*)\"\s*//o; #"
		    $textArea->{$attr}=$1;
		}
		else {
		    $textAreaAttrs=~s/^([^\s]+)\s*//o;
		    $textArea->{$attr}=$1;
		}
		$textAreaAttrs=~s/\s+$//o;
	    }
	    push(@{$form->{textAreas}}, $textArea);
	}

	# minimal validation of form attributes
	if ( !defined($form->{attrs}->{id}) &&
	     defined($form->{attrs}->{name}) ) {
	    $form->{attrs}->{id}=$form->{attrs}->{name};
	    delete($form->{attrs}->{name});
	}
	
	if ( !defined($form->{attrs}->{method}) &&
	     defined($form->{attrs}->{type}) ) {
	    $form->{attrs}->{method}=$form->{attrs}->{type};
	    delete($form->{attrs}->{type});
	}

	# minimal validation of inputs
	if ( defined($form->{inputs}) ) {
	    for my $input (@{$form->{inputs}}) {
		if ( !defined($input->{name}) &&
		     defined($input->{id}) ) {
		    $input->{name}=$input->{id};
		    delete($input->{id});
		}
		# validate input field:
		if ( $input->{type} eq "text" ) {
		    if ( !defined($input->{name}) ) {
			print STDERR dumpMe($input);
			die "Form input - 'text' missing name attr";
		    }
		    # optional attrs are maxlength,size,value
		}
		elsif ( $input->{type} eq "password" ) {
		    # no optional attrs
		    if ( !defined($input->{name}) ) {
			print STDERR dumpMe($input);
			die "Form input - missing name attr";
		    }
		}
		elsif ( $input->{type} eq "checkbox" ) {
		    if ( !defined($input->{name}) ) {
			print STDERR dumpMe($input);
			die "Form input - missing name attr";
		    }
		    if ( !defined($input->{value}) ) {
			print STDERR dumpMe($input);
			die "Form input - missing name attr";
		    }
		    # optional attrs: checked
		}
		elsif ( $input->{type} eq "radio" ) {
		    if ( !defined($input->{name}) ) {
			print STDERR dumpMe($input);
			die "Form input - missing name attr";
		    }
		    # optional attrs: checked
		}
		elsif ( $input->{type} eq "submit" ) {
		    # optional attrs: name, value
		}
		elsif ( $input->{type} eq "image" ) {
		    # optional attrs: ?.x, ?.y, src, img
		}
		elsif ( $input->{type} eq "reset" ) {
		    # optional attrs: name, value
		}
		elsif ( $input->{type} eq "button" ) {
		    # optional attrs: ??
		}
		elsif ( $input->{type} eq "file" ) {
		    # optional attrs: ??
		}
		elsif ( $input->{type} eq "hidden" ) {
		    if ( !defined($input->{name}) ) {
			#print STDERR dumpMe($input);
			#print STDERR "Form input - missing name attr\n";
			$input->{name}="unknown";
		    }
		    if ( !defined($input->{value}) ) {
			print STDERR dumpMe($input);
			die "Form input - missing value attr";
		    }
		}
	    }
	}
	push(@forms, $form);
    }
    return(@forms);
}

sub prepValue($)
{
    my $val=shift;
    if ( $val=~m/\s/o ||
	 $val=~m/\"/o ) {
	$val="\"$val\"";
    }
    return($val);
}

sub dumpForm($)
{
    my $form=shift;
    my $buf="";

    if ( defined($form->{attrs}) ) {
	$buf="<form";
	for my $attr (keys %{$form->{attrs}}) {
	    $buf.=" $attr=\"".$form->{attrs}->{$attr}."\"";
	}
	$buf.=">\n";
    }
    else {
	$buf="<form>\n";
    }
    if ( defined($form->{inputs}) ) {
	#$buf.="  <inputs>\n";
	for my $input (@{$form->{inputs}}) {
	    $buf.="  <input type=$input->{type}";
	    for my $attr (sort keys %$input) {
		next if ( $attr eq "type" );
		my $value=$input->{$attr};
		$buf.=" ".prepValue($attr)."=".prepValue($value);
	    }
	    $buf.=">\n";
	}
	#$buf.="  </inputs>\n";
    }
    if ( defined($form->{selects}) ) {
	#$buf.="  <selects>\n";
	for my $select (@{$form->{selects}}) {
	    if ( $select->{attrs} ) {
		$buf.="   <select";
		for my $attr (keys %{$select->{attrs}}) {
		    $buf.=" ".prepValue($attr)."=".prepValue($select->{attrs}->{$attr});
		}
		$buf.=">\n";
	    }
	    else {
		$buf.="   <select>\n";
	    }
	    $buf.="     <options>\n";
	    if ( defined($select->{options}) ) {
		#$buf.=" type=$input->{type}";
		for my $option (@{$select->{options}} ) {
		    $buf.="      <op cdata=".prepValue($option->{cdata}).
			" str=".prepValue($option->{value});
		    if ( defined($option->{attrs}) ) {
			for my $attr (sort keys %{$option->{attrs}}) {
			    next if ( $attr eq "type" );
			    my $value=$option->{attrs}->{$attr};
			    $buf.=" ".prepValue($attr)."=".prepValue($value);
			}
		    }
		    $buf.=">\n";
		}
	    }
	    $buf.="     </options>\n";
	    $buf.="   </select>\n";
	}
	#$buf.="     </selects>\n";
    }
    return($buf);
}


# todo - should use encoding flag on form to decide how to submit request.
sub Form2Request($$)
{
    my $self=shift;
    my $form=shift;

    return(undef) if ( !defined($form->{attrs}) );

    my $button;
    my @pairs;

    if ( defined($form->{attrs}->{id}) &&
	 defined($form->{attrs}->{name}) ) {
	push(@pairs, $form->{attrs}->{name});
	push(@pairs, $form->{attrs}->{id});
    }

    for my $input (@{$form->{inputs}}) {
	if ( !defined($input->{type}) ) {
	  main::errorMessage("zap2it form 'input' missing type");
	    
	    return(undef);
	}
	if ( $input->{type} eq "submit" ||
	     $input->{type} eq "image") {
	    if ( defined($button) ) {
		# skip subsequent buttons
		next;
	    }
	    $button=$input;
	}
	if ( defined($input->{name}) ) {
	    if ( !defined($input->{value}) ) {
		if ( defined($self->{formSettings}->{$input->{name}}) ) {
		    $input->{value}=$self->{formSettings}->{$input->{name}};
		}
		else {
		  main::errorMessage("zap2it form has input '$input->{name}' we don't have a value for");
		    
		    return(undef);
		}
	    }
	}
	if ( $input->{type} eq "image" ) {
	    push(@pairs, $input->{name}.".x");
	    push(@pairs, "1");
	    push(@pairs, $input->{name}.".y");
	    push(@pairs, "1");
	}
	else {
	    push(@pairs, $input->{name});
	    push(@pairs, $input->{value});
	}
    }
    if ( defined($form->{selects}) ) {
	for my $select (@{$form->{selects}}) {
	    if ( defined($select->{attrs}->{name}) ) {
		my $name=$select->{attrs}->{name};
		if ( defined($self->{formSettings}->{$name}) ) {
		    push(@pairs, $name);
		    push(@pairs, $self->{formSettings}->{$name});
		}
		else {
		  main::errorMessage("zap2it form has select '$name' we don't have a value for");
		    
		    return(undef);
		}
	    }
	}
    }

    if ( $form->{attrs}->{method} eq "get" ) {
	my $url="$form->{attrs}->{action}";
	@pairs=reverse(@pairs);
	while (scalar(@pairs)) {
	    $url.="&".pop(@pairs)."=".pop(@pairs);
	}
	return(GET(URI->new_abs($url, $self->{formSettings}->{urlbase})));
    }
    elsif ( $form->{attrs}->{method} eq "post" ) {
	my $uri = URI->new('http:');
	$uri->query_form(@pairs);
	my $content = $uri->query;

	# not sure, but handing @pairs to POST (as arg #2) I guess
	# isn't the way to use this, so instead I put the args in 
	# the content of the request
	my $req=POST(URI->new_abs($form->{attrs}->{action},
				  $self->{formSettings}->{urlbase}));

	$req->header('Content-Length' =>length($content));
        $req->content($content);
	return($req)
    }
    else {
	return(undef);
    }
}

sub doRequest($$$)
{
    my ($ua, $req, $debug)=@_;
    my $cookie_jar=$ua->cookie_jar();

    if ( $debug ) {
      main::statusMessage("==== request ====\n".$req->as_string());
	if ( defined($cookie_jar) ) {
	  main::statusMessage("==== request cookies ====\n".$cookie_jar->as_string()."\n");
	}
    }

    my $res = $ua->request($req);
    if ( $debug ) {
      main::statusMessage("==== response status: ".$res->status_line." ====\n");
    }

    $cookie_jar=$ua->cookie_jar();
    if ( defined($cookie_jar) && $debug ) {
      main::statusMessage("==== response cookies ====\n".$cookie_jar->as_string()."\n");
    }

    if ( $debug ) {
	#my @forms=getForms($res->content());
	#for my $form (@forms) {
	    #$form->{dump}=dumpForm($form);
	    #print STDERR $form->{dump};
	#}

	if ($res->is_success) {
	    main::statusMessage("==== success ====\n");
	}
	elsif ($res->is_info) {
	    main::statusMessage("==== what's an info response? ====\n");
	}
	else {
	    main::statusMessage("==== bad code ".$res->code().":".HTTP::Status::status_message($res->code())."\n");
	}
	#main::statusMessage("".$res->headers->as_string()."\n");
	#dumpPage($res->content());
	#main::statusMessage("".$res->content()."\n");
    }
    return($res);
}

# todo - change to freshmeat.net/projects-xml/xmltv/xmltv.xml
#        problem is this xml doesn't include a date of the release :<
# expects the sourceforge project page url
sub getCurrentReleaseInfo($$)
{
    my $url=shift;
    my $debug=shift;
    my $ua=XMLTV::ZapListings::RedirPostsUA->new();

    my $res=doRequest($ua, GET($url), $debug);
    if ( !defined($res) ) {
	return(undef);
    }
    # html looks something like:
    #    <TR BGCOLOR="#EAECEF" ALIGN="center">
    #    <TD ALIGN="left">
    #    <B>xmltv</B></TD><TD>0.5.6
    #    </TD>
    #    <td>January 6, 2003</td>

    my $content=$res->content();
    if ( $content=~m;<TR[^>]*>\s*<TD[^>]*>\s*<B>([^<]+)</B>\s*</TD>\s*<TD>([^<]+)</TD>\s*<td>([^<]+)</td>;ois ) {
	my %ret;

	$ret{NAME}=$1;
	$ret{VERSION}=$2;
	$ret{DATESTRING}=$3;

	for my $key (keys %ret) {
	    $ret{$key}=~s/^\s+//o;
	    $ret{$key}=~s/\s+$//o;
	}
	if ( $debug ) {
            main::debugMessage("URL: $url\n");
            main::debugMessage("Returned $ret{NAME} $ret{VERSION} on $ret{DATESTRING}\n");
	}
	return(\%ret);
    }
    else {
	return(undef);
    }
}

sub getZipCodeForm($$$)
{
    my $self=shift;
    my $geocode=shift;
    my $urlbase=shift;

    $self->{formSettings}->{zipcode}=$geocode;
    $self->{formSettings}->{urlbase}=$urlbase;

    return($self->Form2Request($self->{ZipCodeForm}));
}

sub initGeoCodeAndGetProvidersList($$)
{
    my $self=shift;
    my $geocode=shift;

    my $req = GET("http://www.zap2it.com/index");
    my $res=&doRequest($self->{ua}, $req, $self->{Debug});

    # traverse through forms on the page looking for the magic one.
    # @zap2it - locate form based on name=zipcode input on a form
    
    # todo - this should be a query instead of a dump/scan
    my @forms=getForms($res->content());
    for my $form (@forms) {
	my $dump=dumpForm($form);
	#print STDERR $dump;
	if ( $dump=~m/\s+name=zipcode/ois ) {
	    $self->{ZipCodeForm}=$form;
	    last;
	}
    }

    if ( !defined($self->{ZipCodeForm}) ) {
      main::errorMessage("zap2it top level web page doesn't have a zipcode form\n");
	return(-1);
    }

    $req=$self->getZipCodeForm($geocode, $res->base());
    if ( !defined($req) ) {
	return(-1);
    }

    $res=&doRequest($self->{ua}, $req, $self->{Debug});

    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($self->{ua}, $req, $self->{Debug});
    }

    if ( !$res->is_success ) {
	main::errorMessage("zap2it failed to give us a page: ".$res->code().":".
			 HTTP::Status::status_message($res->code())."\n");
	main::errorMessage("looks like we located the right form, check postal/zip code on zap2it.com web site (maybe they're down)\n");
	return(-1);
    }

    # reset urlbase
    $self->{formSettings}->{urlbase}=$res->base();

    my $content=$res->content();

    # todo - this should be a query instead of a dump/scan
    for my $form (getForms($content)) {
	my $dump=dumpForm($form);
	if ( $dump=~m/\s+name=provider/oi ) {
	    $self->{ProviderForm}=$form;
	    #print STDERR "Providers Form:\n$dump";
	    last;
	}
    }

    if ( !defined($self->{ProviderForm}) ) {
      main::errorMessage("zap2it failed to give us a form to choose a Provider\n");
      main::errorMessage("check with zap2it site postal/zip code $geocode is valid\n");
	return(-1);
    }

    if ( $content=~m/(We do not have information for the zip code[^\.]+)/i ) {
	main::errorMessage("zap2it says:\"$1\"\ninvalid postal/zip code\n");
	return(-1);
    }

    while ( $content=~s/<SELECT(.*)(?=<\/SELECT>)//ios ) {
        my $options=$1;
        while ( $options=~s/<OPTION value="(\d+)">([^<]+)<\/OPTION>//ios ) {
	    my $p;
	    $p->{id}=$1;
	    $p->{description}=$2;
            #main::debugMessage("provider $1 ($2)\n";
	    push(@{$self->{ProviderList}->{$self->{GeoCode}}}, $p);
        }
    }
    if ( !defined($self->{ProviderList}) ) {
	main::errorMessage("zap2it gave us a page with no service provider options\n");
	main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	main::errorMessage("(LWP::UserAgent version is ".$self->{ua}->_agent().")\n");
	return(-1);
    }

    return(0);
}

sub getProviderList($)
{
    my $self=shift;
    return(@{$self->{ProviderList}->{$self->{GeoCode}}});
}

# now allows you to get a list of avail of channels for
# any of the valid provider ids for the give postal/zipcode
sub getChannelList($$)
{
    my $self=shift;
    my $providerId=shift;

    my $found;
    for my $p (@{$self->{ProviderList}->{$self->{GeoCode}}}) {
	if ( $p->{id} eq $providerId ) {
	    $found=$p;
	    last;
	}
    }

    if ( !defined($found) ) {
      main::errorMessage("invalid provider id ($providerId), not valid of postal/zip code $self->{GeoCode}\n");
	return(undef);
    }

    # ensure you have formSetting set up
    $self->{formSettings}->{zipcode}=$self->{GeoCode};
    $self->{formSettings}->{provider}=$providerId;

    my $req=$self->Form2Request($self->{ProviderForm});
    if ( !defined($req) ) {
	return(undef);
    }

    my $res=&doRequest($self->{ua}, $req, $self->{Debug});
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($self->{ua}, $req, $self->{Debug});

	# looks like some requests require two identical calls since
	# the zap2it server gives us a cookie that works with the second
	# attempt after the first fails
	if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	    # again.
	    $res=&doRequest($self->{ua}, $req, $self->{Debug});
	}
    }

    if ( !$res->is_success ) {
	main::errorMessage("zap2it failed to give us a page: ".$res->code().":".
			 HTTP::Status::status_message($res->code())."\n");
	main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	return(undef);
    }

    if ( !($res->content()=~m;<a href="([^\"]+)"[^>]+><B>All Channels</B></a>;ios) ) { 
	main::errorMessage("zap2it gave us a grid listings, but no <All Channels> link\n");
	return(undef);
    }
    $req=GET(URI->new_abs($1,$self->{formSettings}->{urlbase}));

    $res=&doRequest($self->{ua}, $req, $self->{Debug});
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($self->{ua}, $req, $self->{Debug});

	# looks like some requests require two identical calls since
	# the zap2it server gives us a cookie that works with the second
	# attempt after the first fails
	if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	    # again.
	    $res=&doRequest($self->{ua}, $req, $self->{Debug});
	}
    }

    if ( !$res->is_success ) {
	main::errorMessage("zap2it failed to give us a page: ".$res->code().":".
			 HTTP::Status::status_message($res->code())."\n");
	main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	return(undef);
    }

    my $content=$res->content();

    if ( $self->{Debug} ) {
	open(FD, "> channels.html") || die "channels.html: $!";
	print FD $content;
	close(FD);
    }

    # todo - this should be a query instead of a dump/scan
    for my $form (getForms($content)) {
	my $dump=dumpForm($form);
	if ( $dump=~m/\s+name=displayType/io &&
	     $dump=~m/\s+name=startDay/io &&
	     $dump=~m/\s+name=startTime/io &&
	     $dump=~m/\s+name=station/io ) {
	    $self->{ChannelByTextForm}=$form;
	    #print STDERR "ChannelByTextForm:\n$dump";
	    last;
	}
    }

    if ( !defined($self->{ChannelByTextForm}) ) {
      main::errorMessage("zap2it failed to give us a form to choose a Text Listings\n");
	return(undef);
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

	if ( $desc=~m;^<td><img><br><font><b><a><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ||
	     $desc=~m;^<td><img><br><b><a><font><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ){
	    $nchannel->{number}=$1;
	    $nchannel->{letters}=$2;

	    # img for icon
	    my $ref=$result->getSRC(2);
	    if ( !defined($ref) ) {
		main::errorMessage("row decode on item 2 failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }
	    else {
		my $icon=URI->new_abs($ref, $res->base());
		$nchannel->{icon}=$icon;
	    }

	    # <a> gives url that contains station_num
	    my $offset=0;
	    if ( $desc=~m;^<td><img><br><font><b><a>;o ) {
		$offset=6;
	    }
	    elsif ( $desc=~m;^<td><img><br><b><a>;o ) {
		$offset=5;
	    }
	    else {
	      main::errorMessage("coding error finding <a> in $desc\n");
		return(undef);
	    }
	    $ref=$result->getHREF($offset);
	    if ( !defined($ref) ) {
		main::errorMessage("row decode on item $offset failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }

	    if ( $ref=~m;listings_redirect.asp\?station_num=(\d+);o ) {
		$nchannel->{stationid}=$1;
	    }
	    else {
		main::errorMessage("row decode on item 6 href failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }
	}
	elsif ( $desc=~m;^<td><font><b><a><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ||
		$desc=~m;^<td><b><a><font><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ) {
	    $nchannel->{number}=$1;
	    $nchannel->{letters}=$2;

	    # <a> gives url that contains station_num
	    my $offset;
	    if ( $desc=~m;^<td><font><b><a>;o ) {
		$offset=4;
	    }
	    elsif ( $desc=~m;^<td><b><a>;o ) {
		$offset=3;
	    }
	    else {
	      main::errorMessage("coding error finding <a> in $desc\n");
		return(undef);
	    }
	    my $ref=$result->getHREF($offset);
	    if ( !defined($ref) ) {
		main::errorMessage("row decode on item $offset failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }
	    if ( $ref=~m;listings_redirect.asp\?station_num=(\d+);o ) {
		$nchannel->{stationid}=$1;
	    }
	    else {
		main::errorMessage("row decode on item $offset href failed on '$desc'\n");
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
	main::errorMessage("zap2it gave us a page with no channels\n");
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
	main::errorMessage("dumping HTML page to $filename\n");
	print OUT $content
	  or warn "cannot dump HTML page to $filename: $!";
	close OUT or warn "cannot close $filename: $!";
    }
    else {
	warn "cannot dump HTML page to $filename: $!";
    }
}

use HTML::Entities qw(decode_entities);

sub massageText
{
    my ($text) = @_;

    $text=~s/&nbsp;/ /og;
    $text=~s/&nbsp$/ /og;
    $text=decode_entities($text);
    $text=~s/\240/ /og;
    $text=~s/^\s+//o;
    $text=~s/\s+$//o;
    $text=~s/\s+/ /o;
    return($text);
}

sub setValue($$$$)
{
    my ($self, $hash_ref, $key, $value)=@_;
    my $hash=$$hash_ref;

    if ( $self->{Debug} ) {
	if ( defined($hash->{$key}) ) {
	    main::errorMessage("replaced value '$key' from '$hash->{$key}' to '$value'\n");
	}
	else {
	    main::errorMessage("set value '$key' to '$value'\n");
	}
    }
    $hash->{$key}=$value;
    return($hash)
}

sub decodeStars($$)
{
    my ($self, $hash_ref, $desc, $htmlsource)=@_;
    my $prog=$$hash_ref;

    if ( $desc=~s;\s*(\*+)\s*$;; ) {
	if ( length($1) > 4 ) {
	  main::statusMessage("star rating of $1 is > expected 4, notify xmltv-users\@lists.sf.net\n");
	}
	$self->setValue(\$prog, "star_rating", sprintf("%d/4", length($1)));
    }
    elsif ( $desc=~s;\s*(\*+)(\s*)(1/2)\s*$;; ||
	    $desc=~s;\s*(\*+)(\s*)(\+)\s*$;; ) {
	if ( length($1) > 4 ) {
	  main::statusMessage("star rating of $1$2$3 is > expected 4, notify xmltv-users\@lists.sf.net\n");
	}
	$self->setValue(\$prog, "star_rating", sprintf("%d.5/4", length($1)));
    }
    else {
	if ( $self->{Debug} ) {
	  main::debugMessage("FAILED to decode what we think should be star ratings\n");
	  main::debugMessage("\tsource: $htmlsource\n\tdecode failed on:'$desc'\n");
	}
    }
    return($desc);
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
			  Dene
			  Diwlai
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
			  Inunktitut
			  Inuvialuktun
			  Italian
			  Italianate
			  Iranian
			  Japanese
			  Khmer
			  Korean
			  Mandarin
			  Mi'kmaq
			  Mohawk
			  Musgamaw
			  Oji
			  Ojibwa
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
	#main::debugMessage("working on: $row\n");
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

	#main::debugMessage("IN: $rowNumber: $row\n");

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
	main::debugMessage("ROW: $rowNumber: $desc\n") if ( $self->{Debug} );

	if ( $desc=~s;^<td><b><text>([0-9]+):([0-9][0-9]) ([AP]M)</text></b></td><td></td>;;io ||
	     $desc=~s;^<td><font><b><text>([0-9]+):([0-9][0-9]) ([AP]M)</text></b></font></td><td></td>;;io ) {
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

		$preRest=$self->decodeStars(\$prog, $preRest, $htmlsource);

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
			main::debugMessage("put back details, now have '$desc'\n");
		    }
		}

		if ( 1 ) {
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

	    }
	    elsif ( $desc=~s;<font><text>(.*?)</text></td>$;;io ||
		    $desc=~s;<font><text>(.*?)</text><br><a><img></a></td>$;;io ){
		my $rest=$1;

		$rest=~s/^\&nbsp\;//o;

		$rest=$self->decodeStars(\$prog, $rest, $htmlsource);

		if ( length($rest) ) {
		    $desc.="<font><text>".$rest."</text></td>";
		    if ( $self->{Debug} ) {
			main::debugMessage("put back details, now have '$desc'\n");
		    }
		}
	    }
	    else {
	      main::errorMessage("FAILED to find/estimate endtime\n");
	      main::errorMessage("\tsource: $htmlsource\n");
	      main::errorMessage("\thtml:'$desc'\n");
	    }

	    if ( $desc=~s;<b><a><text>\s*(.*?)\s*</text></a></b>;;io ) {
		$self->setValue(\$prog, "title", massageText($1));
	    }
	    else {
		if ( $self->{Debug} ) {
		  main::debugMessage("FAILED to find title\n");
		  main::debugMessage("\tsource: $htmlsource\n\thtml:'$desc'\n");
		}
	    }
	    # <i><text>&quot;</text><a><text>Past Imperfect</text></a><text>&quot;</text></i>
	    if ( $desc=~s;<text> </text><i><text>&quot\;</text><a><text>\s*(.*?)\s*</text></a><text>&quot\;</text></i>;;io ) {
		$self->setValue(\$prog, "subtitle", massageText($1));
	    }
	    else {
		if ( $self->{Debug} ) {
		  main::debugMessage("FAILED to find subtitle\n");
		  main::debugMessage("\tsource: $htmlsource\n\thtml:'$desc'\n");
		}
	    }

	    # categories may be " / " separated
	    if ( $desc=~s;<text>\(</text><a><text>\s*(.*?)\s*</text></a><text>\)\s*;<text>;io ) {
		for (split(/\s+\/\s/, $1) ) {
		    push(@{$prog->{category}}, massageText($_));
		}
	    }
	    else {
		if ( $self->{Debug} ) {
		    main::debugMessage("FAILED to find category\n");
		    main::debugMessage("\tsource: $htmlsource\n\thtml:'$desc'\n");
		}
	    }

	    if ( $self->{Debug} ) {
		main::debugMessage("PREEXTRA: $desc\n");
	    }
	    my @extras;
	    while ($desc=~s;<text>\s*(.*?)\s*</text>;;io ) {
		push(@extras, massageText($1)); #if ( length($1) );
	    }
	    if ( $self->{Debug} ) {
		main::debugMessage("POSTEXTRA: $desc\n");
	    }
	    my @leftExtras;
	    for my $extra (reverse(@extras)) {
		my $original_extra=$extra;

		my $resultNotSure;
		my $success=1;
		my @notsure;
		my @sure;
		my @backup;
		main::debugMessage("splitting details '$extra'..\n") if ( $self->{Debug} );
		my @values;
		while ( 1 ) {
		    my $i;
		    if ( defined($extra) ) {
			if ( $extra=~s/\s*(\([^\)]+\))\s*$//o ) {
			    $i=$1;
			}
			else {
			    # catch some cases where they didn't put a space after )
			    # ex. (Repeat)HDTV
			    #
			    if ( $extra=~s/\)([A-Z-a-z]+)$/\)/o ) {
				$i=$1;
			    }
			    else {
				@values=reverse(split(/\s+/, $extra));
				$extra=undef;
				$i=pop(@values);
			    }
			}
		    }
		    else {
			if ( scalar(@values) == 0 ) {
			    last;
			}
			$i=pop(@values);
		    }
		    last if ( !defined($i) );

		    main::debugMessage("checking detail $i..\n") if ( $self->{Debug} );

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
			$prog->{ratings_VCHIP}="$1";
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
			$prog->{ratings_MPAA}="$1";
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
			$prog->{ratings_ESRB}="$1";
			# remove dashes :)
			$prog->{ratings_ESRB}=~s/\-//o;
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
			$resultNotSure->{year}=$i;
			push(@notsure, $i);
			push(@backup, $i);
			next;
		    }
		    elsif ( $i=~/\((\d\d\d\d)\)/io ) {
			$prog->{year}=$i;
			push(@sure, $i);
			push(@backup, $i);
			next;
		    }
		    elsif ( $i=~/^CC$/io ) {
			$prog->{qualifiers}->{ClosedCaptioned}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^Stereo$/io ) {
			$prog->{qualifiers}->{InStereo}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^HDTV$/io ) {
			$prog->{qualifiers}->{HDTV}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Repeat\)$/io ) {
			$prog->{qualifiers}->{PreviouslyShown}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Taped\)$/io ) {
			$prog->{qualifiers}->{Taped}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Live\)$/io ) {
			$prog->{qualifiers}->{Live}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Call-in\)$/io ) {
			push(@{$prog->{category}}, "Call-in");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Animated\)$/io ) {
			push(@{$prog->{category}}, "Animated");
			push(@sure, $i);
			next;
		    }
		    # catch commonly imbedded categories
		    elsif ( $i=~/^\(Fiction\)$/io ) {
			push(@{$prog->{category}}, "Fiction");
			next;
		    }
		    elsif ( $i=~/^\(drama\)$/io || $i=~/^\(dramma\)$/io ) { # dramma is french :)
			push(@{$prog->{category}}, "Drama");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Acci\xf3n\)$/io ) { # action in french :)
			push(@{$prog->{category}}, "Action");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Comedia\)$/io ) { # comedy in french :)
			push(@{$prog->{category}}, "Comedy");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(If necessary\)$/io ) {
			$prog->{qualifiers}->{"If Necessary"}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Subject to blackout\)$/io ) {
			$prog->{qualifiers}->{"Subject To Blackout"}++;
			push(@sure, $i);
			next;
		    }
		    # 1re de 2
		    # 2e de 7
		    elsif ( $i=~/^\((\d+)re de (\d+)\)$/io || # part x of y in french :)
			    $i=~/^\((\d+)e de (\d+)\)$/io ) { # part x of y in french :)
			$prog->{qualifiers}->{PartInfo}="Part $1 of $2";
			next;
		    }

		    # ignore sports event descriptions that include team records
		    # ex. (10-1)
		    elsif ( $i=~/^\(\d+\-\d+\)$/o ) {
			main::debugMessage("understood program detail, on ignore list: $i\n") if ( $self->{Debug} );
			# ignored
			next;
		    }
		    # ignore (Cont'd.) and (Cont'd)
		    elsif ( $i=~/^\(Cont\'d\.*\)$/io ) {
			main::debugMessage("understood program detail, on ignore list: $i\n") if ( $self->{Debug} );
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
			  main::statusMessage("identified possible candidate for new language $lang in $i\n");
			}
			if ( ! $found2 ) {
			  main::statusMessage("identified possible candidate for new language $sub in $i\n");
			}
			$prog->{qualifiers}->{Language}=$lang;
			$prog->{qualifiers}->{Subtitles}=$sub;
		    }
		    #
		    # lanuages added as we see them.
		    #
		    else {
			my $declaration=$i;
			if ( $declaration=~s/^\(//o && $declaration=~s/\)$//o ) {
			    # '(Hindi and English)'
			    # '(Hindi with English)'
			    if ( $declaration=~/^([^\s]+)\s+and\s+([^\s]+)$/io ||
				 $declaration=~/^([^\s]+)\s+with\s+([^\s]+)$/io ) {
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
				    main::statusMessage("identified possible candidate for new language $lang in $i\n");
				}
				if ( ! $found2 && $found1 ) {
				    main::statusMessage("identified possible candidate for new language $sub in $i\n");
				}
				if ( $found1 && $found2 ) {
				    $prog->{qualifiers}->{Language}=$lang;
				    $prog->{qualifiers}->{Dubbed}=$sub;
				    next;
				}
			    }
			    
			    # more language checks
			    # '(Hindi, English)'
			    # '(Hindi-English)'
			    # '(English/French)'
			    # '(English/Oji-Cree)'
			    # '(Hindi/Punjabi/Urdu)', but I'm not sure what it means.
			    if ( $declaration=~m;[/\-,];o ) {
				
				my @arr=split(/[\/]|[\-]|[,]/, $declaration);
				my @notfound;
				my $matches=0;
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
				    $prog->{qualifiers}->{Language}=$declaration;
				    next;
				}
				elsif ( $matches !=0  ) {
				    # matched 1 or more, warn about rest
				    for my $sub (@notfound) {
					main::statusMessage("identified possible candidate for new language $sub in $i\n");
				    }
				}
			    }

			    if ( 1 ) {
				# check for known languages 
				my $found;
				for my $k (@knownLanguages) {
				    if ( $declaration=~/^$k$/i ) {
					$found=$k;
					last;
				    }
				}

				if ( defined($found) ) {
				    $prog->{qualifiers}->{Language}=$found;
				    push(@sure, $declaration);
				    next;
				}

				if ( $declaration=~/^``/o && $declaration=~/''$/o ) {
				    if ( $self->{Debug} ) {
					main::debugMessage("ignoring what's probably a show reference $i\n");
				    }
				}
				else {
				    main::statusMessage("possible candidate for program detail we didn't identify $i\n")
					unless $warnedCandidateDetail{$i}++;
				}
				$success=0;
				push(@backup, $i);
			    }
			}
			else {
			   $success=0;
			   push(@backup, $i);
			}
		    }
		}

		if ( !$success ) {
		    if ( @notsure ) {
			if ( $self->{Debug} ) {
			  main::debugMessage("\thtml:'$desc'\n");
			  main::debugMessage("\tpartial match on details '$original_extra'\n");
			  main::debugMessage("\tsure about:". join(',', @sure)."\n") if ( @sure );
			  main::debugMessage("\tnot sure about:". join(',', @notsure)."\n") if ( @notsure );
			}
			# we piece the original back using space separation so that the ones
			# we're sure about are removed
			push(@leftExtras, join(' ', @backup));
		    }
		    else {
			main::debugMessage("\tno match on details '".join(',', @backup)."'\n") if ( $self->{Debug} );
			push(@leftExtras, $original_extra);;
		    }
		}
		else {
		    # if everything in this piece parsed as a qualifier, then
		    # incorporate the results, partial results are dismissed
		    # then entire thing must parse into known qualifiers
		    for (keys %$resultNotSure) {
			$self->setValue(\$prog, $_, $resultNotSure->{$_});
		    }
		}
	    }

	    # what ever is left is only allowed to be the description
	    # but there must be only one.
	    if ( @leftExtras ) {
		if ( scalar(@leftExtras) != 1 ) {
		    for (@leftExtras) {
			main::errorMessage("scraper failed with left over details: $_\n");
		    }
		}
		else {
		    $self->setValue(\$prog, "desc", pop(@leftExtras));
		    main::debugMessage("assuming description '$prog->{desc}'\n") if ( $self->{Debug} );
		}
	    }

	    #for my $key (keys (%$prog)) {
		#if ( defined($prog->{$key}) ) {
		#    main::errorMessage("KEY $key: $prog->{$key}\n");
		#}
	    #}

	    if ( $desc ne "<td><font></font>" &&
		 $desc ne "<td><font></font><font></td>" ) {
		main::errorMessage("scraper failed with left overs: $desc\n");
	    }
	    #$desc=~s/<text>(.*?)<\/text>/<text>/og;
	    #main::errorMessage("\t$desc\n");


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

    my $lastProgram;

    if ( defined($self->{lastProgramInfo}) ) {
	$lastProgram=$self->{lastProgramInfo};
	delete($self->{lastProgramInfo});

	if ( !defined($lastProgram->{end_hour}) ||
	     !defined($lastProgram->{end_min}) ) {
	    die "how did we get here ?";
	}
    }

    my @newPrograms;
    my $maxi=scalar(@programs);
    for (my $i=0 ; $i<$maxi; $i++ ) {
	my $prog=$programs[$i];

	#print "checking program $i:$prog->{title} $prog->{start_hour}:$prog->{start_min}\n";

	if ( !defined($prog->{end_hour}) ) {
	    if ( $i+1 < $maxi ) {
		# assume end times are the start times of the next program
		my $nprog=$programs[$i+1];
		$prog->{end_hour}=$nprog->{start_hour};
		$prog->{end_min}=$nprog->{start_min};
	    }
	    else {
		# todo - wait for zap2it to fix this somehow.
		# only assume last program ends at midnight if we're
		# instructed to via ASSUME_MIDNIGHT_END_TIMES set in
		# in the environment.
		if ( defined($ENV{"ASSUME_MIDNIGHT_END_TIMES"}) ) {
		   $prog->{end_hour}=24;
		   $prog->{end_min}=0;
		   my $time=sprintf("%02d:%02d", $prog->{start_hour},$prog->{start_min});
	         main::statusMessage("estimated program starting at $time ends at 24:00 on $htmlsource\n");
		}
		else {
		   $lastProgram=undef;
		}
	    }
	}

	push(@newPrograms, $prog);

	# check for program holes
	if ( defined($lastProgram) ) {

	    if ( !defined($lastProgram->{end_hour}) ||
		 !defined($lastProgram->{end_min}) ) {
		die "how did we get here ?";
	    }

	    # recalc endhour incase last prog of yesterday ended after midnight
	    my $endHour=$lastProgram->{end_hour};

	    if ( $endHour>= 24 ) {
		$endHour-=24;
	    }
	    
	    # assumes we're grabbing one day after another
	    my $EndTimeInSeconds=(3600*$endHour)+(60*$lastProgram->{end_min});
	    
	    my $startedAt=(3600*$prog->{start_hour})+(60*$prog->{start_min});
	    if ( $startedAt != $EndTimeInSeconds ) {
		my $p;
		
		$p->{start_hour}=$lastProgram->{end_hour};
		if ( $p->{start_hour}>= 24 ) {
		    $p->{start_hour}-=24;
		}
		$p->{start_min}= $lastProgram->{end_min};
		$p->{end_hour}=$prog->{start_hour};
		$p->{end_min}= $prog->{start_min};
		$p->{title}="unknown";
		
		my $range=sprintf("%02d:%02d to %02d:%02d",
				  $p->{start_hour},$p->{start_min},$p->{end_hour},$p->{end_min});
		if ( $self->{DebugListings} ) {
		    if ( $EndTimeInSeconds > $startedAt ) {
			$p->{precomment}="filler for programing hole from yesterday at $range today";
		    }
		    else {
			$p->{precomment}="filler for programing hole from $range";
		    }
		}
		push(@newPrograms, $p);
	      main::statusMessage("filled in program hole from $range on $htmlsource\n");
	    }
	}
	
	# track when the last program ended down to the second
	if ( defined($prog->{end_hour}) ) {
	   $lastProgram->{end_hour}=$prog->{end_hour};
	   $lastProgram->{end_min}=$prog->{end_min};
	}
    }
	
    if ( defined($lastProgram) ) {
       $self->{lastProgramInfo}=$lastProgram;
    }

    return(@newPrograms);
}

sub readSchedule($$$$$)
{
    my ($self, $stationid, $station_desc, $day, $month, $year)=@_;

    my $content;
    my $cacheFile;

    if ( -f "urldata/$stationid/content-$month-$day-$year.html" &&
	 open(FD, "< urldata/$stationid/content-$month-$day-$year.html") ) {
	main::statusMessage("cache enabled, reading urldata/$stationid/content-$month-$day-$year.html..\n");
	my $s=$/;
	undef($/);
	$content=<FD>;
	close(FD);
	$/=$s;
    }
    else {

	# magic zapit state, we anticipate matching
	$self->{formSettings}->{displayType}="Text";
	$self->{formSettings}->{duration}="1";
	$self->{formSettings}->{startDay}="$month/$day/$year";
	$self->{formSettings}->{startTime}="0";
	$self->{formSettings}->{category}="0";
	$self->{formSettings}->{station}="$stationid";

	my $req=$self->Form2Request($self->{ChannelByTextForm});
	if ( !defined($req) ) {
	    return(-1);
	}
	
	my $res=&doRequest($self->{ua}, $req, $self->{Debug});

	# looks like some requests require two identical calls since
	# the zap2it server gives us a cookie that works with the second
	# attempt after the first fails
	if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	    # again.
	    $res=&doRequest($self->{ua}, $req, $self->{Debug});
	}

	if ( !$res->is_success ) {
	    main::errorMessage("zap2it failed to give us a page: ".$res->code().":".
			     HTTP::Status::status_message($res->code())."\n");
	    main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	    return(-1);
	}
	$content=$res->content();
        if ( $content=~m/>(We are sorry, [^<]*)/ig ) {
	   my $err=$1;
	   $err=~s/\n/ /og;
	   $err=~s/\s+/ /og;
	   $err=~s/^\s+//og;
	   $err=~s/\s+$//og;
	   main::errorMessage("ERROR: $err\n");
	   return(-1);
        }
	if ( -d "urldata" ) {
	    $cacheFile="urldata/$stationid/content-$month-$day-$year.html";
	    if ( ! -d "urldata/$stationid" ) {
		mkdir("urldata/$stationid", 0775) || warn "failed to create dir urldata/$stationid:$!";
	    }
	    if ( open(FD, "> $cacheFile") ) {
		print FD $content;
		close(FD);
	    }
	    else {
		warn("unable to write to cache file: $cacheFile");
	    }
	}
    }

    if ( $self->{Debug} ) {
	main::debugMessage("scraping html for $year-$month-$day on station $stationid: $station_desc\n");
    }

    if ( defined($self->{scrapeState}) &&
	 defined($self->{scrapeState}->{$stationid}) ) {
	$self->{lastProgramInfo}=delete($self->{scrapeState}->{$stationid});
    }

    @{$self->{Programs}}=$self->scrapehtml($content, "$year-$month-$day on station $station_desc (id $stationid)");
    if ( defined($self->{lastProgramInfo}) ) {
	$self->{scrapeState}->{$stationid}=delete($self->{lastProgramInfo});
    }

    if ( scalar(@{$self->{Programs}}) == 0 ) {
	unlink($cacheFile) if ( defined($cacheFile) );

	main::statusMessage("zap2it page format looks okay, but no programs found (no available data yet ?)\n");
	# return un-retry-able
	return(-2);
    }

    # emit delayed message so we only see it when we succeed
    if ( defined($cacheFile) ) {
      main::statusMessage("cache enabled, writing $cacheFile..\n");
    }

  main::statusMessage("Day $year-$month-$day schedule for station $station_desc has:".
		      scalar(@{$self->{Programs}})." programs\n");
    
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
########################################################
# END
########################################################
