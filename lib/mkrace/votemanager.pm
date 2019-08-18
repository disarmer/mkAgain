package mkrace::votemanager;
use strict;
use warnings;
use utf8;
use Data::Dumper;

sub new {
	my $class=shift;
	my $self={
		mapoffset=>0,
		globalmapfilter=>".",
		@_
	};
	return bless $self, __PACKAGE__;
}

sub ecmd {
	my $self=shift;
	$self->{srv}->ecmd(@_);
}

sub voteswitch {
	my $self=shift;
	for my $key (keys %{$self->{voteswitch}}) {
		my @arr=@{$self->{voteswitch}->{$key}};
		print Dumper $self->{switchpos}->{$key}, scalar @arr;
		my $pos=($self->{switchpos}->{$key} // 0) % @arr;
		my $h=$arr[$pos];
		print Dumper \@arr, $pos, $self->{switchpos}->{$key};
		my ($title, $string)=each %$h;
		$self->ecmd('add_vote', "$key $title", "echo voteswitch:$key; $string");
	}
}

sub setvote {
	my ($self, $j)=@_;
	my $counter=0;
	my @maps=$self->maplist;

	$self->ecmd('clear_votes');
	$self->ecmd('add_vote', "random map", "sv_map ".$self->randommap);
	$self->voteswitch;
	my $pp=$self->{mapsperpage};
	my $numpages=int(0.001+@maps/$pp);
	for my $i (1..$numpages) {
		$self->ecmd('add_vote', "maplist: ".$maps[$i*$pp], "echo mapoffset: ".$i*$pp);
	}
	map {$self->ecmd('add_vote', "map: $_", "sv_map $_")} splice @maps, $self->{mapoffset}, $pp;
}

sub votecall {
	my ($self, $j)=@_;
	if ($j->{cmd}=~m/^echo mapoffset: (.+)/) {
		$self->{mapoffset}=$1;
		$self->ecmd(qw'vote yes');
		$self->setvote;
		return;
	}
	$self->{voters}={};
	$self->{vote_line}='';
	$j->{vote}=1;
	$self->vote($j);
}

sub voteend {
	my ($self, $j)=@_;
	return if $j->{type} == 6;
	if ($j->{cmd}=~m/voteswitch:(\w+)/) {
		$self->{switchpos}->{$1}++;
	}
	$self->setvote;
}

sub vote {
	my ($self, $j)=@_;
	return if $self->{voters}->{$j->{player}->{name}}++;
	$self->{vote_line}.=sprintf "^%03d%s ", $j->{vote}>0 ? 90 : 900, $j->{player}->{name};
	$self->ecmd(broadcast=>$self->{vote_line});
}

sub maplist {
	my ($self, $filter, $limit)=@_;
	opendir my $D, $self->{mapdir} or return AE::log warn=>"cant open mapdir: $!";
	my @l;
	while (my $f=readdir $D) {
		next unless $f=~s/\.map$//;
		next if $filter and not $filter->($f);
		next unless $f=~qr/$self->{globalmapfilter}/i;
		next if $f eq ($self->{srv}->{map}->{map}//'');
		push @l, $f;
	}
	@l=sort {uc($a) cmp uc($b)} @l;
	return splice @l, 0, $limit if $limit;
	return @l;
}

sub randommap {
	my ($self)=@_;
	my @m=$self->maplist;
	return $m[int rand @m];
}
1;
