package mkrace::translationmanager;
use strict;
use warnings;
use utf8;
use Ikt::Translator;

my %langmap=(

	#map country code => language
	(map {$_=>$_} qw/mk fi sv hu no ca sl lt pt sk et nl lv pl ro sr bg fr it es tr de be ru to/),
	ua=>"uk",
	dk=>"da",
	al=>"sq",
	cz=>"cs",
	gb=>"en",
	us=>"en",
	gr=>"el",
);

sub subscribe {
	my ($self, $inp)=@_;
	unless ($inp) {
		undef $self->{lang};
		return "unsubscribed";
	}

	$inp=$langmap{$inp} if $langmap{$inp};
	return ("Unknown language. Available languages: ".join ", ", values %langmap) unless grep {$inp eq $_} values %langmap;
	$self->{lang}=$inp;
	return "Successfully subscribed to $inp translator";
}

sub translate {
	my ($self, $msg, $callback)=@_;
	return if length $msg < 5;
	Ikt::Translator::translate($self->{lang}, $msg, \&$callback);
}

1;
