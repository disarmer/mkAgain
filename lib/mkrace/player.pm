package mkrace::player;
use strict;
use warnings;
use utf8;
use Data::Dumper;
use mk::utils qw/ratelimit/;
use Ikt::Translator;
use mk::geoip;

#красота идея сложность необычность

my %cmds=(
	translate=>sub {
		my ($self, $lang)=@_;
		my @langlist=qw/ru en fr de es uk by/;
		return ("Invalid language. Available languages: ".join ", ", @langlist) if !$lang or !grep {$lang eq $_} @langlist;
		$self->{lang}=$lang;
		return "Successfully subscribed to $lang translator";
	},
);
sub new {
	my $class=shift;
	my $j=shift;
	my $self={
		lang=>undef,
		%{$j->{player}},
		@_,
	};
	for my $i (qw/clan flag ip/) {
		$self->{$i}=$j->{$i};
	}
	$self->{ts_join}=$j->{ts};

	mk::geoip::get($self->{ip}, sub {
		my $g={code=>shift, country=>shift, city=>shift};
		$self->{geoip}=$g;
		$self->{srv}->ecmd(fake=>2, $self->{id}, -1, "from $g->{country}, $g->{city}") unless ratelimit 30, $self->{ip};
		warn $cmds{translate}->($self,lc $g->{code});
	});
	return bless $self, $class;
}

sub leave {
	my ($self, $j)=@_;
	return if $self->{leaved};
	for my $i (qw/reason latencyAvg latencyMin latencyMax/) {
		$self->{$i}=$j->{$i};
	}
	$self->{ts_leave}=$j->{ts};
	$self->{leaved}=1;
	$self->DESTROY;
}

sub chathook {
	my ($self, $j)=@_;
	if ($self->{lang}) {
		Ikt::Translator::translate($self->{lang}, $j->{msg}, sub {$self->{srv}->ecmd(fake=>0, $j->{from}->{id}, $self->{id}, $_[0])});
	}
}

sub chat {
	my ($self, $j)=@_;
	if ($j->{to}->{id}<0) {
		unless (ratelimit 120, "broadchat".$j->{from}->{name}) {
			my $c=rand 1000;
			my $m=$j->{from}->{name}.": ".$j->{msg};
			$m=~s/\^\d\d\d//g;
			$m=~s/\S/"^".(sprintf "%03i", $c=($c+(rand>0.5?1:-1 * 10**int rand 3))%1000).$&/ge;
			$self->{srv}->ecmd(broadcast=>$m);
		}
	}
}

sub slashcmd {
	my ($self, $j)=@_;
	my ($cmd, @args)=split /\s+/, $j->{cmd};
	$cmd=~s%^/+%%;
	return unless $cmds{$cmd};
	$self->{srv}->ecmd(
		fake=>0,
		-1, $self->{id},
		$cmds{$cmd}->($self, @args));
}

sub DESTROY {
	shift->leave();
}
1;
