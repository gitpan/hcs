# $Id: Safari.pm,v 1.9 2005/10/13 22:19:18 comdog Exp $
package HTTP::Cookies::Safari;
use strict;

=head1 NAME

HTTP::Cookies::Safari - Cookie storage and management for Safari

=head1 SYNOPSIS

	use HTTP::Cookies::Safari;

	$cookie_jar = HTTP::Cookies::Safari->new;

	# otherwise same as HTTP::Cookies

=head1 DESCRIPTION

This package overrides the load() and save() methods of HTTP::Cookies
so it can work with Safari cookie files.

Note: If the source Safari cookie file specifies and expiry date past
the unix 32-bit epoch, this file changes the expiry date to 0xFFFFFFFF
in unix seconds. That should be enough for anyone, at least to the next
release.

See L<HTTP::Cookies>.

=head1 SOURCE AVAILABILITY

This source is part of a SourceForge project which always has the
latest sources in CVS, as well as all of the previous releases.

	http://sourceforge.net/projects/brian-d-foy/

If, for some reason, I disappear from the world, one of the other
members of the project can shepherd this module appropriately.

=head1 AUTHOR

brian d foy, C<< <bdfoy@cpan.org> >>

=head1 CREDITS

Jon Orwant pointed out the problem with dates too far in the future

=head1 COPYRIGHT

Copyright 2003-2005, brian d foy, All rights reserved

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

#<array>
#	<dict>
#		<key>Domain</key>
#		<string>usatoday.com</string>
#		<key>Expires</key>
#		<date>2020-02-19T14:28:00Z</date>
#		<key>Name</key>
#		<string>v1st</string>
#		<key>Path</key>
#		<string>/</string>
#		<key>Value</key>
#		<string>3E1B9B935912A908</string>
#	</dict>

use base qw( HTTP::Cookies );
use vars qw( $VERSION );

use constant TRUE  => 'TRUE';
use constant FALSE => 'FALSE';

$VERSION = sprintf "%2d.%02d", q$Revision: 1.9 $ =~ m/ (\d+) \. (\d+) /xg;

use Date::Calc;
use Mac::PropertyList;

sub load
	{
    my( $self, $file ) = @_;

    $file ||= $self->{'file'} || return;

    local $_;
    local $/ = "\n";  # make sure we got standard record separator

    open my( $fh ), $file or return;

    my $data = do { local $/; <$fh> };

    my $plist = Mac::PropertyList::parse_plist( $data );

 	my $cookies = $plist->value;

 	foreach my $hash ( @$cookies )
    	{
    	my $cookie = $hash->value;

    	my @bits  = map { $cookie->{$_}->value }
    		qw( Domain Path Name Value Expires );
    		#     0     1    2     3      4

		my $expires = $bits[4];

		my( $y, $m, $d, $h, $mn, $s ) = $expires =~
			m/(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z/g;

		$expires = eval {
			&Date::Calc::Mktime( $y, $m, $d, $h, $mn, $s ) } || 0xFFFFFFFF;

		# XXX: Convert Expires date to unix epoch

		#print STDERR "@bits\n";

		my $secure = FALSE;

		$self->set_cookie(undef, @bits[2,3,1,0], undef,
			0, 0, $expires - time, 0);
    	}

    close $fh;

    1;
	}

sub save
	{
    my( $self, $file ) = @_;

    $file ||= $self->{'file'} || return;

	my $plist = Mac::PropertyList::array->new( [] );
	print STDERR "plist is $plist\n";
	
    $self->scan(
    	do {
    	my $array = $plist->value;

    	sub {
			my( $version, $key, $val, $path, $domain, $port,
				$path_spec, $secure, $expires, $discard, $rest ) = @_;

			return if $discard && not $self->{ignore_discard};

			return if time > $expires;

			$expires = do {
				unless( $expires ) { 0 }
				else
					{
					my @times = localtime( $expires );
					$times[5] += 1900;
					$times[4] += 1;

					sprintf "%4d-%02d-%02dT%02d:%02d:%02dZ",
						@times[5,4,3,2,1,0];
					}
				};

			$secure = $secure ? TRUE : FALSE;

			my $bool = $domain =~ /^\./ ? TRUE : FALSE;

			my $hash = {
				Value   => Mac::PropertyList::string->new( $val     ),
				Path    => Mac::PropertyList::string->new( $path    ),
				Domain  => Mac::PropertyList::string->new( $domain  ),
				Name    => Mac::PropertyList::string->new( $key     ),
				Expires => Mac::PropertyList::date  ->new( $expires ),
				};

			push @$array, Mac::PropertyList::dict->new( $hash );
    		}
		} );
	
	open my $fh, "> $file" or die "Could not write file [$file]! $!\n";
    print $fh ( Mac::PropertyList::plist_as_string( $plist ) );
    close $fh;
	}

1;
