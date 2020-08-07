package mkrace::localize;
use strict;
use warnings;
use utf8;
use YAML::XS;

my $data;
sub new {
	my $class=shift;
	my $self={
		file=>"configs/localization.yml",
		lang=>"en",
		@_,
	};
	eval {$data=YAML::XS::LoadFile $self->{file}} or die "cant load $self->{file}: $!";
	return bless $self, __PACKAGE__;
}

sub get {
	my ($self,$id,@args)=@_;
	return sprintf $data->{$id}->{$self->{lang}}//$data->{$id}->{en}, @args;
}
1;
