#!/usr/bin/perl -w -CSDA
use strict;
use feature qw/say state/;
use utf8;
use Data::Dumper;
use JSON::XS;
use mk::logconfig;
use Module::Refresh;

use mk::opts {
	poolmin=>3,
	poolmax=>5,
};

BEGIN {push @INC, $0=~s%/[^/]+$%/lib%r}

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use AnyEvent::Util;

use mkrace::server;

my $cond=AnyEvent->condvar;
my %watchers;
my %servers;
my %stdin;

if (-t STDIN) {

	sub stdin {
		my $inp=<STDIN>;
		chomp $inp;
		my ($cmd, @args)=split /\s+/, $inp || return;
		unless (exists $stdin{$cmd}) {
			return AE::log crit=>"No such command $cmd. Possible commands: ".(join ', ', keys %stdin);
		}
		say $stdin{$cmd}->(@args);
	}
	%watchers=(stdin=>AE::io(\*STDIN, 0, \&stdin));
	%stdin=(
		dump=>sub {Dumper \%servers},
		exit=>sub {$cond->send; return "Ok"},
		loglevel=>\&mk::logconfig::loglevel,
		addserver=>sub {startserver(force=>1);},
		status=>sub    { },
		reload=>\&reload,
		list=>sub { });
}

sub reload {
	AE::log warn=>'reload invoked';
	Module::Refresh->refresh;
	for my $s (keys %servers) {
		say "before $servers{$s}";
		$servers{$s}=$servers{$s}->reload;
		say "after $servers{$s}";
	}
	AE::log warn=>'reloaded';
}

sub startserver {
	my %opts=@_;
	if (keys %servers > POOLMIN and not $opts{force}) {return AE::log warn=>"refuse to start due poolmin constraint";}
	if (keys %servers >= POOLMAX) {return AE::log warn=>"refuse to start due poolmax constraint";}
	my $confname=$opts{config};
	my $srv;
	$srv=new mkrace::server(
		config=>$confname,
		onstop=>sub {
			delete $servers{$confname};
			my $w="startwatcher".rand;
			$watchers{$w}=AE::timer 3, 0, sub {&startserver(); delete $watchers{$w};}
		},
		ondrain=>sub {$srv->stop if keys %servers>POOLMIN});
	$servers{$confname}=$srv;
	$srv->start;
}

#for (1..mk::opts::POOLMIN) {startserver}
for (<configs/[0-9]*.yml>) {
	startserver(config=>$_);
}
#startserver(config=>"configs/8383.yml");

$cond->recv;
