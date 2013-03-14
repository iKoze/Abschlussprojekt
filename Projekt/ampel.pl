#!/usr/bin/perl -w
#
# ampel.pl by Florian Schießl <florian@trans.net>
#
# Dev-Start 12.3.2013
#
use strict;
use Proc::Background;
use Getopt::Long qw( :config no_ignore_case bundling );
use Time::HiRes qw( usleep );
##################
# Konfiguration
my $control = "clewarecontrol";
my $colors = {
	0 => 0,
	rot => 0,
	red => 0,
	1 => 1,
	gelb => 1,
	yellow => 1,
	2 => 2,
	gruen => 2,
	green => 2,
	'grün' => 2,
};
my $frequency = 0;
my $color = -1;

##########
# Start

# Root-Check
die "This script must be run as root" if $> != 0;

GetOptions(
	'c|color:s' => \$color,
	'f|frequency:s' => \$frequency,
);

$color = lc($color);

die "Unknown color!" unless defined $colors->{$color};

my $half1 = 0;
my $half2 = 0;

$frequency =~ s/,/\./;

if ($frequency =~ m{/})
{
	($half1,$half2) = split("/",$frequency);
	$half1 = $half1 * 1000000;
	$half2 = $half2 * 1000000;
}
elsif ($frequency eq '')
{
	$frequency = 0;
}
elsif ($frequency !~ m/^[0-9]*\.?[0-9]+$/)
{
	die "Invalid frequency! (".$frequency.")";
}
elsif ($frequency > 0)
{
	$half1 = 1000000 / $frequency / 2;
	$half2 = $half1;
}

# Exit Signale abfangen
$SIG{INT} = \&exittsk;
$SIG{TERM} = \&exittsk;
$SIG{QUIT} = \&exittsk;
$SIG{ABRT} = \&exittsk;
$SIG{HUP} = \&exittsk;

my $command = $control." -c 1 -as ".$colors->{$color}." ";

while(1)
{
	system($command."1 > /dev/null 2>&1");
	if($frequency ne "0")
	{
		usleep($half1);
		system($command."0 > /dev/null 2>&1");
		usleep($half2);
	}
	else
	{
		sleep 10;
	}
}

#########
# Subs

sub exittsk
{
	system($command."0 > /dev/null 2>&1");
	exit 0;
}

__END__

# Das nachfolgende ist eine Plain old Documentation (POD) dieses Scripts. Um sie besser betrachten zu 
# können, schaue sie über pod2text, pod2html oder einen anderen POD-Renderer an.

=head1 NAME

B<ampel.pl> - Script zum ansteuern einer einzelnen Farbe einer Cleware Ampel.

=head1 BESCHREIBUNG

Dieses Script schaltet eine Farbe der Ampel entsprechend der gegebenen Frequenz ein und aus, solange, bis 
es beendet wird.

=head1 GEBRAUCH

	ampel.pl -c <farbe> -f <frequenz>
	ampel.pl -c gelb -f 1.2

=head1 OPTIONEN

=over

=item C<-c, --color>

Die Farbe, welche benuzt werden soll.

B<Farben und deren Aliase>:

	ROT: 0, rot, red
	GELB: 1, gelb, yellow
	GRÜN: 2, grün, gruen, green

=item C<-f, --frequency>

Die Frequenz in Hertz (Hz), mit welcher geblinkt werden soll. Falls ausgelassen oder 0, wird geleuchtet.

Asynchrones Blinken (z.B. kurz an, lang aus), kann wie folgt angegeben werden:

	-f 0.1/0.9

Zum Beispiel bedeutet für 0.1 Sekunden einschalten, dann für 0.9 Sekunden ausschalten.

=back

=head1 FUNKTIONSWEISE

Zuerst wird überprüft, ob dieses Script als root ausgeführt wird. Die Ausführung als root ist notwendig, 
da das Programm 'B<clewarecontrol>' auf ein Device unter '/dev/usb' zugreifen muss und diese normalerweise 
nur für root zugänglich sind.

Danach wird die Farbe und die Frequenz auf ihre Gültigkeit überprüft. Ist eines von beiden ungültig, so 
wird das Script beendet. Der übergebene Wert für die Frequenz wird zuerst darauf überprüft, ob er einen 
Schrägstrich (/) enthält. Falls dies der Fall ist, wird der Wert vor und hinter dem Schrägstrich 
benutzt, um daraus die Wartezeit 1 (C<$half1>) und Wartezeit 2 (C<$half2>) zu berechnen. Die Wartezeit 1 
vergeht, nachdem die Lampe eingeschaltet wurde und die Wartezeit 2 nachdem die Lampe ausgeschaltet wurde. 
Bei beiden Wartezeiten handelt es sich um Mikrosekunden (1.000.000 µs = 1 s). Enthält der Wert hingegen 
keinen Schrägstrich, so wird von einer Frequenz ausgegangen und anhand derer die Wartezeit zwischen dem 
Ein- und Ausschalten errechnet.

Die Funktion C<exittsk()> wird mit den Signalen I<INT>, I<TERM>, I<QUIT>, I<ABRT> und I<HUP> 
verlinkt. Das bewirkt, dass sich dieses Script nicht sofort beendet, sondern zuerst noch 
die Lampe ausgeschaltet werden kann.

Nach all dem wird eine Endlosschleife gestartet, in welcher die Lampe ein und ausgeschaltet wird, bis 
das Script beendet wird. Soll die Lampe nur leuchten, so wird alle 10 Sekunden ein "an" Befehl an 
die Lampe geschickt.

=head1 AUTOR

B<ampel.pl> - Geschrieben von Florian Schießl (florian@trans.net) im Rahmen des 
Projektes zur IHK Abschlussprüfung zum Fachinformatiker für Systemintegration Sommer 2013. 
Entwicklungsbeginn ist der 12.3.2013.
