package mkrace::server;
use strict;
use warnings;
use utf8;
use AnyEvent::Util;
use Data::Dumper;
use JSON qw/decode_json/;
use AnyEvent::Handle;
use YAML::XS;
use mk::utils qw/hash_merge/;
use mkrace::player;
use mkrace::votemanager;
use open qw(:std :utf8);

sub new {
	my $class=shift;
	my $self={
		fd=>undef,
		cv=>undef,
		players=>[],
		map=>{},
		@_
	};
	my $cfg=loadconfig($self->{config});
	$self=hash_merge($self, $cfg);
	$self->{name}=$self->{options}->{sv_name}=~y/ /_/r;
	$self->{id}=$self->{options}->{sv_port};
	$self->{outconffile}=$self->{basedir}."/configs/".$self->{id}.".conf";
	$self->{vote}=mkrace::votemanager->new(srv=>$self, %{$self->{votemanager}});

	#$self->{options}->{sv_map}=$self->{vote}->randommap;
	return bless $self, __PACKAGE__;
}

sub loadconfig {
	my ($input)=@_;
	my $conf={};
	for my $file ("configs/global.yml", "configs/secure.yml", $input) {
		my $loaded={};
		eval {$loaded=YAML::XS::LoadFile $file} or return AE::log crit=>"can't parse yaml config: $file";
		$conf=hash_merge($conf, $loaded);
	}
	return $conf;
}

sub reload {
	my $self=shift;
	my $new=__PACKAGE__->new(%{$self});
	$new->setconfig;
	$self->ecmd(exec=>"configs/".$self->{id}.".conf");
	return $new;
}

sub setconfig {
	my $self=shift;
	open my $CFG, ">", $self->{outconffile};
	print $CFG join $/, linearize($self->{options}, "");
}

sub linearize {
	my ($d, $prefix)=@_;
	my @res;
	for (sort keys %$d) {
		if (ref $d->{$_}) {
			push @res, linearize($d->{$_}, "$prefix $_");
		} else {
			push @res, join " ", grep {length} $prefix, $_, $d->{$_};
		}
	}
	return @res;
}

sub start {
	my $self=shift;
	my $prevbuf="";

	$self->setconfig;
	$self->{cv}=run_cmd $self->{args},
	  '$$'=>$self->{pid},
	  '>'=>sub {
		my $buf=$prevbuf.$_[0];
		while ($buf=~s/.+\n//) {
			my $s=$&;
			chomp $s;
			next unless $s=~m/^\{/;

			AE::log trace=>"$self->{name}: $s";
			my $j;
			unless (eval {$j=decode_json $s }) {
				$self->badjson($s);
				next;
			}
			my $event=$j->{event};
			my $targ=$event=~m/vote/ ? $self->{vote} : $self;
			$targ->can($event) or $event="default";
			$targ->$event($j);
		}
		$prevbuf=$buf;
	  };
	$self->{econwatcher}=AE::timer 3, 0, sub {$self->econconnect()};
	$self->{cv}->cb(sub {$self->stop(shift->recv)});
	return $self;
}

use Encode;

sub ecmdraw {
	my ($self, @cmd)=@_;
	my $cmd=join ' ', map {Encode::encode_utf8($_)} @cmd;
	AE::log note=>"$self->{name}: ecmd ".Dumper $cmd;
	$self->{econ}->push_write($cmd."\n");
}

sub enquote($) {
	local $_=shift;
	s/\\/\\\\/g;
	s/"/\\"/g;
	return qq/"$_"/;
}

sub ecmd {
	my ($self, @cmd)=@_;
	map {$_=enquote($_)} @cmd[1..$#cmd];
	$self->ecmdraw(@cmd);
}

sub onstart {
	my ($self)=@_;
	$self->ecmdraw($self->{options}->{ec_password});
	$self->{vote}->setvote;
}

sub econconnect {
	my $self=shift;
	$self->{econ}=AnyEvent::Handle->new(
		connect=>["127.0.0.1", $self->{options}->{ec_port}],
		keepalive=>1,
		on_connect=>sub {
			AE::log note=>"$self->{name}: econ connected";
			$self->onstart;
		},
		on_connect_error=>sub {
			AE::log crit=>"econ connect failed: $self->{options}->{ec_port} - $_[1]";

			#return $self->stop();
			$self->{econwatcher}=AE::timer 3, 0, sub {$self->econconnect()};
		},
		on_error=>sub {
			my ($out_hdl, $fatal, $msg)=@_;
			AE::log crit=>"$self->{name}: econ error: $msg";
			$self->{econwatcher}=AE::timer 3, 0, sub {$self->econconnect()};
		},
		on_read=>sub {
			my ($fd)=@_;
			$fd->unshift_read(
				line=>sub {
					my ($hdl, $data)=@_;
					AE::log trace=>"$self->{name}: data from econ: $data";
				});
		});
}

sub flushsessions {
	my ($self, $reason, $time)=@_;
	AE::log note=>"flush sessions";
	map {$self->leave({player=>{id=>$_->{id}}, reason=>$reason, ts=>$time})} grep {defined $_} @{$self->{players}};
	$self->{players}=[];
	$self->dumpplrs;
	AE::log note=>"flush sessions ok";
}

sub plrformat(%) {
	return "" unless $_[0]->{name};
	return sprintf "%2d %18s | %s\n", $_[0]->{id}, $_[0]->{name}, $_[0]->{clan} // "";
}

sub dumpplrs {
	my $self=shift;
	print "player list: ", $self->{name}, $/;
	map {print "\t", plrformat $_} grep {defined $_} @{$self->{players}};
}

sub stop {
	my $self=shift;
	my $ec=shift;
	$ec=$ec % 256;
	AE::log warn=>"$self->{name}: stopping handler, exitcode=$ec";
	$self->flushsessions("server stop $ec", time);
	$self->{onstop}->();
}

#only json handlers after that line
sub joined {
	my ($self, $j)=@_;
	AE::log info=>"$self->{name}: player enters = ".plrformat $j->{player};
	my $slot=\$self->{players}->[$j->{player}->{id}];
	if ($$slot) {
		AE::log crit=>"player already exists:", Dumper $$slot, $j;
		exit;
	}
	$$slot=mkrace::player->new($j, srv=>$self);
	$self->dumpplrs;
}

sub leave {
	my ($self, $j)=@_;
	return if $j->{reason} eq "removing dummy";         #FIXME
	return if $j->{player}->{name} eq "(connecting)";
	AE::log info=>"$self->{name}: player leaves = ".plrformat $j->{player};

	$self->dumpplrs;
	my $slot=\$self->{players}->[$j->{player}->{id}];
	return AE::log warn=>"undefined player leaves" unless $$slot;
	$$slot->leave($j);
	undef $$slot;
}

sub default {
	my ($self, $j)=@_;
	AE::log debug=>"$self->{name}: unknown event $j->{event}";
}

sub badjson {
	my ($self, $s)=@_;
	AE::log info=>"$self->{name}: badjson: $s";
	exit;
}

sub map {
	my ($self, $j)=@_;
	$self->{map}->{$_}=$j->{$_} for qw/map sha256 ts/;
	$self->flushsessions("nextmap", $j->{ts});
	$self->{vote}->setvote;
}
sub death  { }
sub emote  { }
sub finish { }

sub chat {
	my ($self, $j)=@_;
	return if $j->{from}->{id} == -1;

	#AE::log info=>"$self->{name}: chat:". Dumper $j;
	for my $p (@{$self->{players}}) {
		next unless $p;
		next if $j->{whisper};
		$p->chathook($j);
	}
	my $plr=$self->{players}->[$j->{from}->{id}];
	return unless $plr;
	$plr->chat($j);
}

sub slashcmd {
	my ($self, $j)=@_;
	my $plr=$self->{players}->[$j->{player}->{id}];
	return unless $plr;
	$plr->slashcmd($j);
}

1;
