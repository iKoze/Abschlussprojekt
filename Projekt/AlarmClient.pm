########################################################
# AlarmClient by Florian Schießl <florian@trans.net>
#
# Dev-Start 12.3.2013
#
package AlarmClient;
use strict;
use IO::Socket;

sub new
{
	my $class = shift;
	our $conn = {
		host => shift,
		port => shift,
		client => shift,
		pass => shift,
		maxretrys => shift,
		after => shift,
		separator => shift,
	};
	bless $conn, $class;
}

sub alert
{
	my $conn = shift;
	my $message = shift;
	my $active = shift;
	my $retry = 0;
	my $sep = $conn->{separator};
	my $tosend = $conn->{pass}.$sep.$conn->{client}.$sep.$message.$sep.$active."\n";
	while ($retry++ <= $conn->{maxretrys})
	{
		sleep $conn->{after} if $retry > 1;
		my $socket = new IO::Socket::INET (
			PeerAddr => $conn->{host},
			PeerPort => $conn->{port},
			Type => SOCK_STREAM,
		);
		next unless defined $socket;
		
		print $socket $tosend;
		my $answer = <$socket>;
		chomp($answer);
		return 0 if $answer eq 'ok';
		return 1 if $answer eq 'err' || $answer eq 'unknown';
	}
	return 1;
}
1;

__END__

# Das nachfolgende ist eine Plain old Documentation (POD) dieses Moduls. Um sie besser betrachten zu 
# können, schaue sie über pod2text, pod2html oder einen anderen POD-Renderer an.

=head1 NAME

B<AlarmClient.pm> - Perl Modul, um mit einem B<alarmd.pl> über Netzwerk zu kommunizieren.

=head1 GEBRAUCH

	use AlarmClient;
	
	my $ac = AlarmClient->new(
		'alerthost.example.com',
		5061,
		'Testclient',
		'Serverpasswort',
		5,
		15,
		'::',
	);
	
	$ac->alert('EinAlarm', 1); # Alarm tritt auf
	
	$ac->alert('EinAlarm', 0); # Alarm vorbei

=head1 OPTIONEN

Alle Optionen werden im Konstruktor in nachfolgender Reihenfolge übergeben:

=over

=item C<Host>

Der Hostname oder die IP-Adresse des B<alarmd.pl> Servers.

=item C<Port>

Der Port, auf welchem der Server lauscht.

=item C<Clientname>

Der Name, mit dem Sich die Instanz des B<AlarmClient> gegenüber dem Server meldet.

=item C<Passwort>

Das Password des B<alarmd.pl> Servers.

=item C<Erneute Versuche>

Die maximale Anzahl der erneuten Versuche, bis aufgegeben wird, den Server zu kontakten.

=item C<Warten>

Wie viele Sekunden nach einem erfolglosem Verbindungsversuch gewartet werden soll.

=item C<Trenner>

Die Werte, welche an den Server geschickt werden, werden durch diese Zeichenkette getrennt.

=back

=head1 FUNKTIONEN

=head2 alert($name, $neu)

B<Übergabeparameter:>

=over

=item C<name>

Der Name des Alarms.

=item C<neu>

Ob der Alarm neu ist (1) oder vorbei ist (0).

=back

B<Rückgabewerte:>

0 = Erfolg; 1 = Fehler


=head1 FUNKTIONSWEISE

Tritt in dem verwendenden Script ein Alarm auf, so wird von diesem die Funktion C<alert()> 
aufgerufen und der Name des Alarms, sowie eine Eins (1) übergeben. Die Eins markiert, dass 
ein Alarm auftritt. Eine Null (0) hingegen markiert, dass ein Alarm vorbei ist.

Die Funktion C<alert()> baut zunächst aus den übergebenen Werten die Nachricht für den 
Server auf. Genaueres Siehe Abschnitt PROTOKOLL. Daraufhin wird eine Verbindung zum Server 
aufgebaut und die Nachricht übermittelt. Sollte ein Verbindungsaufbau nicht möglich sein, 
oder die Antwort vom Server nicht "ok", "err" oder "unknown" lauten, so wird es nach der 
vordefinierten Wartezeit erneut versucht. Sind alle erneuten Versuche auch fehlgeschlagen,
so wird eine Eins an den Aufrufer zurückgegeben. Wurde die Nachricht erfolgreich 
übermittelt, so wird eine Null zurückgegeben.

=head1 PROTOKOLL

=head2 Client zu Server

Folgende Nachricht wird zum auslösen eines Alarms an den Server gesendet:

	Passwort::Clientname::Alarmname::1

Bei dem Passwort handelt es sich um das Serverpasswort. Der Clientname ist der Name, mit 
wechem sich die Instanz dieses Modules gegenüber dem Server meldet. Alarmname ist Name 
des Alarms, welcher ausgelöst oder aufgehoben werden soll. Die Eins markiert, dass der 
Alarm ausgelöst wird. Bei den doppelten Doppelpunkten handelt es sich um den 
vordefinierten Trenner. Dieser kann je nach Konfiguration abweichen, muss aber immer beim 
Server und Client der gleiche sein.

Folgende Nachricht hebt den ausgelösten Alarm wieder auf:

	Passwort::Clientname::Alarmname::0

Die Null markiert das Aufheben des Alarms.

=head2 Server zu Client

Die Antwort des Servers beschränkt sich auf ein einfaches

	'ok'

falls der Alarm erfolgreich aufgenommen wurde,

	'err'

falls die Anfrage ungültig war (sollte mit diesem Modul nicht auftreten) oder

	'unknown'

falls der Alarm auf dem Server nicht definiert ist. Ein 'err' und ein 'unknown' lösen 
ein akustisches Signal auf dem Server aus, um über die Fehlkonfiguration zu benachrichtigen.

Ist das Passwort falsch, wird der Server sofort und ohne Quittierung die Verbindung beenden.

=head1 AUTHOR

B<AlarmClient.pm> - Geschrieben von Florian Schießl (florian@trans.net) im Rahmen des 
Projektes zur IHK Abschlussprüfung zum Fachinformatiker für Systemintegration Sommer 2013. 
Entwicklungsbeginn ist der 12.3.2013.

=head1 SIEHE AUCH

B<alarmd.pl> - Der Alarm-Server.

