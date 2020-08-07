package mk::geoip;
use strict;
use warnings;
use utf8;
use Data::Dumper;
use AnyEvent::DBI;

our $dbh;
sub get {
	$dbh//=new AnyEvent::DBI "dbi:Pg:dbname=mk", "", "";
	my ($addr, $sub)=@_;
	$dbh->exec(
		"select country_iso_code,country_name,city_name from geoip.blocks natural join geoip.city id where network >> ? limit 1",
		$addr,
		sub {
			my ($dbh, $rows, $rv)=@_;
			return unless defined $rows->[0];
			$sub->(@{$rows->[0]});
		});
}
1;
