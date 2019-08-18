package Ikt::Translator;
use strict;
use warnings;
use URI::Escape;
use JSON qw/decode_json/;
use AnyEvent::HTTP;

my $yakey='trnsl.1.1.20190417T191047Z.99cac0f01e2546b7.df53209e2ccb97c909f0553b7e0444e08c8ca424';
$AnyEvent::HTTP::PERSISTENT_TIMEOUT=3600;

my %inflight;

sub translate($$&) {
	my ($lang, $text, $sub)=@_;
	return if length $text < 5;
	my $k="$lang-$text";
	if($inflight{$k}){
		return push @{$inflight{$k}},$sub;
	}
	push @{$inflight{$k}},$sub;
	my $enctext=uri_escape_utf8($text);
	http_get "https://translate.yandex.net/api/v1.5/tr.json/translate?key=${yakey}&text=$enctext&lang=$lang",
	  persistent=>1,
	  keepalive=>1,
	  timeout=>10,
	  sub {
		my $j;
		eval{ $j=decode_json $_[0]} or return warn __PACKAGE__." can't parse json: ".$_[0];
		#use Data::Dumper;warn Dumper [$text, $j->{text}->[0]];
		if($text ne $j->{text}->[0]){
			for(@{$inflight{$k}}){
				$_->($j->{text}->[0]);
			}
		}
		delete $inflight{$k};
	  };
}
1;
