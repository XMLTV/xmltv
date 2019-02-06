# Supplement to ExtUtils::MakeMaker to add back some rudimentary
# uninstall functionality.  This needs to be called with an extra
# 'uninstall' target in the Makefile, for which you will need to
# modify your Makefile.PL.  I kept well away from the deprecated and
# no-longer-working uninstall stuff in MakeMaker itself.

package Uninstall;
use strict;
use base 'Exporter'; our @EXPORT = qw(uninstall);
use File::Find;

sub uninstall( % ) {
    my %h = @_;
    my %seen_pl;
    foreach (qw(read write)) {
	my $pl = delete $h{$_};
	if (defined $pl and not $seen_pl{$pl}++) {
	    warn "ignoring packlist $pl\n";
	}
    }
    foreach my $from (keys %h) {
	next if not -e $from;
	my $to = $h{$from};
	print "uninstalling contents of $from from $to\n";
	find(sub {
		 for ($File::Find::name) {
#		     return if not -f; # why doesn't this work?

		     # The behaviour of File::Find seems different
		     # under 5.005.
		     #
		     s!^\Q$from\E/*!!
		       or ($[ < 5.006)
			 or die "filename '$_' doesn't start with $from/";

		     return if not length; # skip directory itself
		     return if m!(?:/|^)\.exists!;
		     my $inside_to = "$to/$_";
		     if (-e $inside_to) {
			 if (-f $inside_to) {
			     print "unlinking $inside_to\n";
			     unlink $inside_to or warn "cannot unlink $inside_to: $!";
			 }
			 elsif (-d $inside_to) {
			     print "not removing directory $inside_to\n";
			 }
			 else {
			     print "not removing special file $inside_to\n";
			 }
		     }
		     else {
			 print "$inside_to is not installed\n";
		     }
		 }
	     }, $from);
    }
}
