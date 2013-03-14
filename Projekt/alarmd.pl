#!/usr/bin/perl -w
# 
# alarmd.pl by Florian Schießl <florian@trans.net>
#
# Dev-Start 11.3.2013
#
use strict;
use IO::Socket;
use threads;
use threads::shared;
use Thread::Queue;
use Data::Dumper;
use Proc::Background;
use FindBin;
use YAML::Tiny;
##################
# Konfiguration
my $yaml = YAML::Tiny->read($FindBin::Bin.'/alarmd.yml'); # Config File einlesen

my $port = $yaml->[0]->{config}->{port};
my $password = $yaml->[0]->{config}->{pass};
my $ampel = $yaml->[0]->{config}->{ampel};
my $sep = $yaml->[0]->{config}->{separator}; 
my $alarms = $yaml->[0]->{alarms};
my $start = $yaml->[0]->{config}->{start};
my $error = $yaml->[0]->{config}->{error};
my $stop = $yaml->[0]->{config}->{stop};
my $verbose = $yaml->[0]->{config}->{verbose};

my $null = $verbose == 1 ? '' : ' > /dev/null 2>&1';

##########
# Start

# Root-Check
die "This script must be run as root" if $> != 0;

# In das Verzeichnis wechseln, in welchem sich dieses Script befindet.
chdir $FindBin::Bin;

# Exit Signale abfangen
$SIG{INT} = \&exittsk;
$SIG{TERM} = \&exittsk;
$SIG{QUIT} = \&exittsk;
$SIG{ABRT} = \&exittsk;
$SIG{HUP} = \&exittsk;

my $inqueue = Thread::Queue->new();

my $socket = new IO::Socket::INET (
	LocalPort => $port,
	Type => SOCK_STREAM,
	Listen => SOMAXCONN,
	Reuse => 5,
);
if(!defined ($socket))
{
	print "Unable to setup socket: $!\n";
	&exittsk(1);
}

threads->new(\&worker)->detach();

Proc::Background->new($start.$null) if defined($start);

while (my $conn = $socket->accept)
{
	my $peerhost = $conn->peerhost();
	threads->new(\&connhandler,$conn,$peerhost)->detach();
}

############
# Threads

sub connhandler
{
	my $conn = shift;
	my $peerhost = shift;
	&debug("new connection from ".$peerhost."\n");
	while(<$conn>)
	{
		chomp;
		my @data = split($sep,$_);
		&debug(join(',',@data)."\n");
		last unless shift(@data) eq $password; # Clients mit falschem Passwort sofort kicken
		
		# Unvollständige Anfragen ignorieren
		if(!(defined($data[0]) && defined($data[1]) && defined($data[2])))
		{
			print $conn "err\n"; # Client benachrichtigen
			Proc::Background->new($error.$null); # Fehler-Ton abspielen
			next;
		}
		
		# Unbekannte Anfragen auch ignorieren
		if(!defined($alarms->{$data[0]}->{$data[1]}))
		{
			print $conn "unknown\n"; # Client benachrichtigen
			Proc::Background->new($error.$null); # Fehler-Ton abspielen
			next;
		}
		
		# Anfrage ok
		print $conn "ok\n";
		$inqueue->enqueue(join($sep,@data)); # Anfrage in Warteschlange schicken
	}
	close($conn);
	&debug("lost connection from ".$peerhost."\n");
}

sub worker
{
	# Enthält alle aktuell anliegenden Signale
	# Nach Farbe und Priorität sortiert
	my $signal = {
		rot => {
			1 => {},
			2 => {},
			3 => {},
		},
		gelb => {
			1 => {},
			2 => {},
			3 => {},
		},
		gruen => {
			1 => {},
			2 => {},
			3 => {},
		},
	};
	
	my $procs = {}; # Prozesse / Farbe
	
	$procs->{green} = Proc::Background->new($ampel." -c green"); # Initial grün leuchten

	# Anfragen bearbeiten
	while (my $item = $inqueue->dequeue())
	{
		(my $client, my $type, my $active) = split($sep,$item);
		
		# Signal aus Datenbank holen
		my $todo = $alarms->{$client}->{$type};
		next unless defined($todo); # Falls es nix zu tun gibt, lassen wir es auch.

		# Audiosignal aus todo holen
		my $audio = $todo->{audio};
		
		# Ampelsignal aus todo holen
		my $newampel = $todo->{ampel};

		my $color;
		my $prio;
		my $freq;
		if(defined($newampel))
		{
			# Ampelsignal zerlegen
			$color = $newampel->{color};
			$prio = $newampel->{prio};
			$freq = $newampel->{freq} ? $newampel->{freq} : 0; # Leuchten, falls keine Frequenz gegeben
		}

		# Ampelsignal setzen/löschen
		if($active == 1)
		{
			$signal->{$color}->{$prio}->{$client.":".$type} = $freq if defined($newampel);
			# Ton abspielen
			Proc::Background->new($audio->{in}.$null) if defined($audio->{in});
		}
		elsif ($active == 0)
		{
			delete $signal->{$color}->{$prio}->{$client.":".$type} if defined($newampel);
			# Ton abspielen
			Proc::Background->new($audio->{quit}.$null) if defined($audio->{quit});
		}
		&debug(Dumper($signal));
		next unless defined($newampel); # Falls kein neues Ampelsignal gesetzt wurde, können wir uns den Rest auch sparen.
		
		# Frequenz mit höchster Priorität für Farbe ausfindig machen
		my $final = {};
		foreach my $color (keys $signal)
		{
			my $highest;
			foreach my $prio (keys $signal->{$color})
			{
				my $last = (keys $signal->{$color}->{$prio})[-1];
				if (defined($last))
				{
					#print $last;
					$highest->{$color}[$prio] = $signal->{$color}->{$prio}->{$last};
				}
			}
			$final->{$color} = $highest->{$color}[-1]."\n" if defined $highest->{$color}[-1];
		}

		# Alle Lampenprozesse killen
		foreach my $color (keys $procs)
		{
			$procs->{$color}->die if defined $procs->{$color};
		}
		
		my $colorset = 0; # ob eine Farbe gesetzt wurde
		# Und neu starten mit neuen Frequenzen
		foreach my $color (keys $final)
		{
			my $command = $ampel." -c ".$color." -f ".$final->{$color};
			$procs->{$color} = Proc::Background->new($command);
			$colorset = 1;
		}
		$procs->{green} = Proc::Background->new($ampel." -c green") if $colorset == 0;
	}
}

#########
# Subs

sub debug
{
	print shift if $verbose == 1;
}

sub exittsk
{
	my $status = shift;
	$status = 0 unless defined($status);
	if ($status ne '1')
	{
		Proc::Background->new($stop.$null);
		exit 0;
	}
	else
	{
		Proc::Background->new($error.$null);
		exit 1;
	}
}

__END__

# Das nachfolgende ist eine Plain old Documentation (POD) dieses Scripts. Um sie besser betrachten zu 
# können, schaue sie über pod2text, pod2html oder einen anderen POD-Renderer an.

=head1 NAME

B<alarmd.pl> - Übertragene Alarme verarbeiten und entsprechend die Ampel ansteuern und akustischen Alarm geben.

=head1 BESCHREIBUNG

Der B<alarmd.pl> Server lauscht auf einem konfigurierten Netzwerk-Port, um Alarme von Client-Scripten anzunehmen. Sendet ein Client einen 
Alarm, so wird anhand der Konfiguration entschieden, wie die Ampel leuchten soll und welcher Sound dazu abgespielt wird. Sind keine Alarme
vorhanden, so leuchtet die Ampel grün.

=head1 KONFIGURATION

Die Konfiguration erfolgt über die Konfigurationsdatei 'C<alarmd.yml>', welche in dem selben Ordner wie der B<alarmd.pl> Server 
selbst erwartet wird. Die Konfigurationsdatei ist im YAML Format.

Bei dem YAML Format können mehrere Werte "zusammengefasst" werden. Hierbei ist die Anzahl der Leerzeichen 
oder Tabulatoren für einen Abschnitt immer gleich zu halten.

Kommentare beginnen in YAML mit einer Raute (#).

Die verschiedenen Alarme werden unter dem Abschnitt 'C<alarms>' beschrieben. Unter dem Abschnitt C<alarms> folgt ein neuer Abschnitt für den 
entsprechenden Client (Clientname). Unter diesem wiederrum die Alarme, welche ein Client auslösen kann. Unter den Alarmen gibt es jeweils 
zwei neue Abschnitte: 'C<ampel>' und 'C<audio>'. Diese können auch ausgelassen werden, falls notwendig.

Unter 'C<ampel>' wird die Farbe (C<color>), die Priorität (C<prio>) des Ampelsignals und 
die Frequenz (C<freq>) in Hertz (Hz), mit welcher die Farbe der Ampel blinken soll festgelegt. Siehe auch B<ampel.pl>
Die Priorität beschreibt, die wichtigkeit eines Ampelsignals. Liegt auf der Ampel zum Beispiel das Signal 'leuchte gelb' mit der Priorität 1 
an und tritt Alarm auf, welcher 'blinke gelb' mit Priorität 2 definiert hat, so wird die Ampel gelb blinken. Das Signal 'leuchte gelb' wird 
hierbei aber nicht "vergessen", sondern bleibt im Hintergrund erhalten. Wird der Alarm mit der Priorität 2 beendet, so wird die Ampel wieder 
gelb leuchten. Genaueres Siehe C<FUNKTIONSWEISE>.

Unter 'C<audio>' werden zwei Befehle festgelegt. 'C<in>' für einkommende Alarme. 'C<quit>' für beendete Alarme. Der Befehl wird dann 
entsprechend dem Alarm ausgeführt. Der 'C<audio>' Abschnitt war ursprünglich dazu gedacht, eine Audiodatei abzuspielen, kann aber auch dazu 
verwendet werden, andere Scripte zu starten, die dann zum Beispiel eine E-Mail verschicken. Hierbei ist zu beachten, dass Befehle, die hinter 
'C<in>' oder 'C<out>' definiert werden nicht mit dem Alarm gestartet und beendet werden, sondern im Hintergrund gestartet und nicht beendet 
werden. Der 'C<in>' Befehl wird bei einem einkommenden Alarm gestartet, der 'C<out>' Befehl, wenn der Alarm vorbei ist. Die Befehle werden in 
dem selben Ordner ausgeführt, in dem sich der B<alarmd.pl> Server befindet.

=head2 Beispiel-Konfiguration

Ein Beispiel erklärt meistens mehr als jede Beschreibung.

	config:						# Die Basis-Konfiguration ist unter 'config:'
		port: 5061				# Der Port, auf welchem gelauscht wird
		pass: test				# Das Server-Passwort
		ampel: "./ampel.pl"			# Das Script zum ansteuern der Ampel. (Siehe auch 'ampel.pl')
		separator: "::"				# Die Werte, welche an den Server geschickt werden, werden durch diese Zeichenkette getrennt.
							# Siehe auch 'PROTOKOLL'
		verbose: 0				# Debug Informationen ausgeben. (1)
		start: 'mplayer start.mp3'		# Befehl, welcher beim erfolgreichen Start des alarmd.pl ausgeführt wird.
		error: 'mplayer error.mp3'		# Befehl, welcher bei einem Fehler ausgeführt wird.
		stop: 'mplayer end.mp3'			# Befehl, welcher beim erfolgreichen Beenden des alarmd.pl ausgeführt wird.

	alarms:						# Die einzelnen Alarme werden unter diesem Abschnitt definiert.
		nagios:					# Der Clientname
			warning:			# Der Alarm, welcher von dem Client 'nagios' gesendet wird
				ampel:			# Das Ampelsignal wird unter diesem Abschnitt definiert.
					color: gelb	# Die Farbe der Ampel, welche verwendet wird.
					prio: 1		# Die Priorität des Signals
					freq: 0		# Die Frequenz, mit welcher geblinkt werden soll. Auslassen für 0; 0 entspricht leuchten.
				audio:			# Die Befehle, welche 
					in: 		# beim eintreten des Alarms 
					quit:		# oder beim beenden des Alarms ausgeführt werden.

			unknown:
				ampel:
					color: gelb
					prio: 1
							# Der 'audio', sowie 'ampel' Abschnitt kann auch ausgelassen werden, falls nicht benötigt. 
			critical:
				ampel:
					color: rot
					prio: 1
			down:
				ampel:
					color: rot
					prio: 2
					freq: 1.2
			nagdown:
				ampel:
					color: rot
					prio: 3
					freq: 2.4
		ticket:
			neu:
				ampel:
					color: gelb
					prio: 2
					freq: '0.1/0.9'
				audio:
					in: 'mplayer new_ticket.mp3'	# Die Audio-Datei wird in dem Selben Ordner, wie dieses Script selbst, gesucht.
			ticketdown:
				ampel:
					color: gelb
					prio: 3
					freq: 2.4
		internet:
			weg:
				ampel:
					color: gruen
					prio: 3
					freq: 4.8
				audio:
					in: 'mplayer offline.mp3'
					quit: 'mplayer start.mp3'

=head2 FUNKTIONSWEISE

Zuerst wird überprüft, ob dieses Script als root ausgeführt wird. Die Ausführung als root ist notwendig, da da B<ampel.pl> root-Rechte 
benötigt, um die Ampel anzusteuern. Danach wird in das Verzeichnis gewechselt, in welchem sich dieses Script befindet, damit später ohne 
großen Aufwand in der Konfiguration Dateien spezifiziert werden können, welche sich in dem selben Verzeichnis befinden.

Die Funktion C<exittsk()> wird mit den Signalen I<INT>, I<TERM>, I<QUIT>, I<ABRT> und I<HUP> verlinkt. Das bewirkt, dass sich dieses 
Script nicht sofort beendet, sondern zuerst noch der konfigurierte 'C<stop>' Befehl ausgeführt werden kann.

Danach wird eine neue Warteschlange erstellt (C<$inqueue>), welche zur Kommunikation zwischen den einzelnen I<Verbindungs-Threads> 
(C<sub connhandler>) und dem I<Arbeiter-Thread> (C<sub worker>) genutzt wird. Daraufhin wird versucht, den konfigurierten Port zu öffnen. 
Sollte dies fehlschlagen, wird der konfigurierte 'C<error>' Befehl ausgeführt und das Programm beendet. Der 'C<error>' Befehl wird außerdem 
ausgeführt, sollte eine Fehlerhafte oder unbekannte Anfrage an den Server gestellt werden.

Sobald der Port geöffnet wurde, wird der I<Arbeiter-Thread> gestartet. Dieser schaltet die Ampel initial auf grün leuchten, da noch kein Alarm 
vorhanden ist. Danach wartet der I<Arbeiter-Thread> auf neue Aufträge, welche über die Warteschlange eintreffen.

In dem I<Hauptprozess> wird inzwischen der konfigurierte 'C<start>' Befehl im Hintergrund gestartet. Danach beginnt der I<Hauptprozess>, bei dem 
geöffneten Port auf neue Clients zu warten. Baut ein neuer Client eine Verbindung auf, so wird ein neuer I<Verbindungs-Thread> gestartet, und das 
Verbindungs-Handle an diesen übergeben. Danach wird im I<Hauptprozess> sofort weiter auf neue Clients gewartet. Dies ist notwendig, damit nicht 
ein Client alle eingehenden Verbindungen blockieren kann. Durch dieses Vorgehen "kümmert" sich um jeden Client ein eigener Thread.

In dem I<Verbindungs-Thread> wird jetzt auf eine (oder mehrere) Nachrichten des verbundenen Clients gewartet (Siehe auch C<PROTOKOLL>). Für jede 
Nachricht wird zunächst anhand dem Konfigurierten Trenner ('C<separator>') zerlegt (gesplittet). Danach wird das Passwort überprüft. Sollte 
das Passwort nicht mit dem konfigurierten Passwort ('C<pass>') übereinstimmen, wird sofort die Verbindung geschlossen und der Thread beendet. 
Stimmt das Passwort hingegen, wird die Nachricht zunächst auf ihre Vollständigkeit geprüft und dann darauf untersucht, ob der Alarm 
bekannt ist, den der Client melden will. Ist die Nachricht unvollständig, so wird der konfigurierte 'C<error>' Befehl ausgeführt und dem 
Client ein "err" gemeldet. Ist der Alarm unbekannt, wird dem Client ein "unknown" gemeldet und ebenfalls der 'C<error>' Befehl ausgeführt. Ist 
der Alarm bekannt, wird er der Warteschlange hinzugefügt und dem Client ein "ok" gemeldet.

Der I<Arbeiter-Thread> nimmt den Alarm an und prüft zunächst, ob etwas für diesen Alarm konfiguriert wurde ('C<ampel>', 'C<audio>'). Ist keines 
von beiden konfiguriert worden, wird nichts unternommen und auf den nächsten Alarm gewartet. Ist ein 'C<audio>' Befehl konfiguriert worden, so 
wird dieser im Hintergrund gestartet. Der 'C<in>' Befehl für neue Alarme, der 'C<quit>' Befehl für beendete Alarme. Wurde ein Ampelsignal definiert
und der Alarm als neu gemeldet, wird dieses in einen Hash (C<$signal>) eingetragen. Dieser Hash enthält alle aktuell auf der Ampel anliegenden 
Signale in folgender Reihenfolge sortiert: I<Farbe>, I<Priorität>, I<Eintrittszeitpunkt>. Wird der Alarm als beendet gemeldet, wird das Signal 
wieder aus dem Hash entfernt. Nachdem der Hash bearbeitet wurde, wird in dem Hash für jede Farbe nach der Frequenz für mit der höchsten Priorität 
gesucht und diese in einen weiteren Hash (C<$final>) der jeweiligen Farbe zugeordnet. Sollten mehrere Frequenzen mit gleicher Priorität vorliegen, 
wird die genommen, die als erstes in dem Hash steht, welche in der Regel dem ersten eingetroffenen Alarm dieser Priorität entspricht. Es wird nicht 
empfohlen, mehrere Signale auf einer Farbe mit der selben Priorität zu vergeben. Der Hash C<$final> enthält an dieser Stelle die neue Frequenz für 
jede Farbe. Jetzt wird jeder B<ampel.pl> Prozess beendet, welcher in dem Hash C<$procs> vorhanden ist. An dieser Stelle leuchtet keine Farbe der 
Ampel. Danach wird für jede Farbe in dem Hash C<$final> ein neuer B<ampel.pl> Prozess gestartet, welcher die jeweilige Farbe der Ampel mit der 
gegebenen Frequenz ansteuert. Wurde kein neuer B<ampel.pl> Prozess gestartet, so wird ein B<ampel.pl> Prozess mit der Farbe grün gestartet, damit 
die Ampel grün Leuchtet, wenn kein Fehler da ist. Dann wartet der I<Arbeiter-Thread> wieder auf neue Alarme.

=head1 PROTOKOLL

=head2 Client zu Server

Folgende Nachricht muss zum auslösen eines Alarms an den Server gesendet werden:

	Passwort::Clientname::Alarmname::1

Bei dem Passwort handelt es sich um das Serverpasswort ('C<pass>'). Der Clientname ist der Name, mit 
wechem sich der Client gegenüber dem Server meldet. Alarmname ist Name 
des Alarms, welcher ausgelöst oder aufgehoben werden soll. Die Eins markiert, dass der 
Alarm ausgelöst wird. Bei den doppelten Doppelpunkten (::) handelt es sich um den 
vordefinierten Trenner ('C<separator>'). Dieser kann je nach Konfiguration abweichen, muss aber immer beim 
Server und Client der gleiche sein.

Folgende Nachricht hebt den ausgelösten Alarm wieder auf:

	Passwort::Clientname::Alarmname::0

Die Null markiert das Aufheben des Alarms.

=head2 Server zu Client

Die Antwort des Servers beschränkt sich auf ein einfaches

	'ok'

falls der Alarm erfolgreich aufgenommen wurde,

	'err'

falls die Anfrage ungültig war oder

	'unknown'

falls der Alarm auf dem Server nicht definiert ist. Ein 'err' und ein 'unknown' starten den unter 
'C<error>' Konfigurierten Befehl, um über die Fehlkonfiguration zu benachrichtigen.

Ist das Passwort falsch, wird der Server sofort und ohne Quittierung die Verbindung beenden.

=head1 AUTHOR

B<alarmd.pl> - Geschrieben von Florian Schießl (florian@trans.net) im Rahmen des 
Projektes zur IHK Abschlussprüfung zum Fachinformatiker für Systemintegration Sommer 2013. 
Entwicklungsbeginn ist der 11.3.2013.

=head1 SIEHE AUCH

B<AlarmClient.pm> - Ein Perl Modul zur Kommunikation mit diesem Server.

B<ampel.pl> - Eine Farbe einer Cleware Ampel ansteuern.



