# This is intended mostly as a helper library for tv_grep and not for
# general purpose use (yet).

package XMLTV::Grep;
use strict;
use XMLTV;
use base 'Exporter'; our @EXPORT_OK;
@EXPORT_OK = qw(get_matcher);

my %key_type = %{XMLTV::list_programme_keys()};

# Parameters:
#   key found in programme hashes
#   ignore-case flag
#
# Returns:
#   extra argument type needed to filter on this key:
#     undef: no extra argument required
#     'regexp': extra argument should be regexp
#     'empty': extra argument must be the empty string, and is ignored
#
#   subroutine which may take an argument (depending on whether
#   argument type is 'regexp'), and matches a programme hash in $_.
#
sub get_matcher( $$ ) {
    my ($key, $ignore_case) = @_;
    my ($handler, $mult) = @{$key_type{$key}};
    if ($handler eq 'presence') {
	die "bad multiplicity $mult for 'presence'"
	  if $mult ne '?';
	return [ undef, sub { exists $_->{$key} } ];
    }
    elsif ($handler eq 'scalar') {
	if ($mult eq '?') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 return 0 if not exists $_->{$key};
			 return 1 if $regexp eq '';
			 if ($ignore_case) {
			     return $_->{$key} =~ /$regexp/i;
			 }
			 else {
			     return $_->{$key} =~ /$regexp/;
			 }
		     } ];
	}
	elsif ($mult eq '1') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 die if not exists $_->{$key};
			 return 1 if $regexp eq '';
			 if ($ignore_case) {
			     return $_->{$key} =~ /$regexp/i;
			 }
			 else {
			     return $_->{$key} =~ /$regexp/;
			 }
		     } ];
	}
	elsif ($mult eq '*') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 # It is possible (though unusual) for the key
			 # to exist but be an empty list.
			 #
			 return 0 if not exists $_->{$key} or not @{$_->{$key}};
			 return 1 if $regexp eq '';
			 foreach (@{$_->{$key}}) {
			     return 1 if ($ignore_case ? /$regexp/i : /$regexp/);
			 }
			 return 0;
		     } ];
	}
	elsif ($mult eq '+') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 die if not @{$_->{$key}};
			 return 1 if $regexp eq '';
			 foreach (@{$_->{$key}}) {
			     return 1 if ($ignore_case ? /$regexp/i : /$regexp/);
			 }
			 return 0;
		     } ];
	}
	else { die }
    }
    elsif ($handler =~ m!^with-lang(?:/[a-z]*)?$!) {
	if ($mult eq '?') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 return 0 if not exists $_->{$key};
			 return 1 if $regexp eq '';
			 for ($_->{$key}->[0]) {
			     return 0 if not defined;
			     if ($ignore_case) {
				 return /$regexp/i;
			     }
			     else {
				 return /$regexp/;
			     }
			 }
		     } ];
	}
	elsif ($mult eq '1') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 die if not exists $_->{$key};
			 return 1 if $regexp eq '';
			 for ($_->{$key}->[0]) {
			     if (not defined) {
				 warn "undef text for $key";
				 return 0;
			     }
			     if ($ignore_case) {
				 return /$regexp/i;
			     }
			     else {
				 return /$regexp/;
			     }
			 }
		     } ];
	}
	elsif ($mult eq '*') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 return 0 if not exists $_->{$key} or not @{$_->{$key}};
			 return 1 if $regexp eq '';
			 foreach (map { $_->[0] } @{$_->{$key}}) {
			     if (not defined) {
				 warn "undef text for $key";
				 next;
			     }
			     return 1 if ($ignore_case ? /$regexp/i : /$regexp/);
			 }
			 return 0;
		     } ];
	}
	elsif ($mult eq '+') {
	    return [ 'regexp', sub {
			 my $regexp = shift;
			 die if not @{$_->{$key}};
			 return 1 if $regexp eq '';
			 foreach (map { $_->[0] } @{$_->{$key}}) {
			     if (not defined) {
				 warn "undef text for $key";
				 next;
			     }
			     return 1 if ($ignore_case ? /$regexp/i : /$regexp/);
			 }
			 return 0;
		     } ];
	}
	else { die }
    }
    elsif ($handler eq 'icon'
	   or $handler eq 'credits'
	   or $handler eq 'length'      # TODO
	   or $handler eq 'episode-num' # TODO
	   or $handler eq 'video'
	   or $handler eq 'audio'
	   or $handler eq 'previously-shown'
	   or $handler eq 'subtitles'
	   or $handler eq 'rating'      # TODO
	   or $handler eq 'star-rating' # TODO
	   or $handler eq 'review'      # TODO
	   or $handler eq 'url'         # TODO
	   or $handler eq 'image'       # TODO
	  ) {
	# Cannot query on this except for presence.  But empty string
	# argument for future expansion.
	#
	return [ 'empty', sub { exists $_->{$key} } ];
    }
    else { die }
}

1;
