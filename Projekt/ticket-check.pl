#!/usr/bin/perl -w
#
# ticket-check.pl by Florian Schießl <florian@trans.net>
#
# Dev-Start: 12.3.2013
#
use strict;
use WWW::Mechanize;
use YAML::Tiny;
use FindBin;
use lib $FindBin::Bin; # Für den AlarmClient
use AlarmClient;
##################
# Konfiguration
my $yaml = YAML::Tiny->read($FindBin::Bin.'/ticket-check.yml');
my $interval = $yaml->[0]->{config}->{interval}; # Interwall, zwischen dem erneuten check aller Instanzen
my $interval_betw_inst = $yaml->[0]->{config}->{interval_betw_inst}; # Wartezeit zwischen den Instanzen
my $maxretrys = $yaml->[0]->{config}->{maxretrys}; # Erneute Versuche, bevor als nicht erreichbar gemeldet.
my $alarmd = $yaml->[0]->{alarmd};
my $instances = $yaml->[0]->{instances};
my $verbose = $yaml->[0]->{config}->{verbose};

##########
# Start

my $ac = AlarmClient->new($alarmd->{host},$alarmd->{port},$alarmd->{client},$alarmd->{pass},$alarmd->{maxretrys},$alarmd->{after},$alarmd->{separator});

# Initialisierung
#&alert("ticketdown",0);
#&alert("neu",0);

my $tickets = {};
foreach my $host (keys $instances)
{
	$tickets->{$host} = {};
}
my $retrys = {};
my $last_down = 0;
while(1)
{
	my $new_ticket = 0;
	my $ticket_removed = 0;
	# Aktuellen Status aller Instanzen holen
	foreach my $host (keys $instances)
	{
		my $current_tickets = {};
		my $ua = WWW::Mechanize->new(
			ssl_opts => { verify_hostname => 0},
			onerror => sub {}
		);
		
		my $response = $ua->post(
			$instances->{$host}->{url}, {
				username => $instances->{$host}->{user},
				password => $instances->{$host}->{pass},
			}
		);
		if($response->is_success)
		{
			$retrys->{$host} = 0;
			my @content = split("\n",$response->decoded_content);
			foreach(@content)
			{
				if($_ =~ m/_self"\>#[0-9]*\<\/a\>/)
				{
					my $ticket_id = $&; # '_self">#47615</a>'
					$ticket_id =~ s/_self"\>//; # '#47615</a>'
					$ticket_id =~ s/\<\/a\>//; # '#47615'
					&debug($ticket_id."\n");
					$current_tickets->{$ticket_id} = 1;
				}
			}
			
			# Neue Tickets finden
			foreach my $ticket_id (keys $current_tickets)
			{
				$new_ticket = 1 unless defined($tickets->{$host}->{$ticket_id});
				$tickets->{$host}->{$ticket_id} = 1;
			}
			
			# genommene Tickets entfernen
			foreach my $ticket_id (keys $tickets->{$host})
			{
				if(!defined($current_tickets->{$ticket_id}))
				{
					delete $tickets->{$host}->{$ticket_id};
					$ticket_removed = 1;
				}
			}
		}
		else
		{
			++$retrys->{$host};
		}
		sleep $interval_betw_inst;
	}

	# Status der Ticketsystem Instanzen überprüfen
	my $ticketdown = 0;
	foreach my $host (keys $retrys)
	{
		$ticketdown = 1 if $retrys->{$host} > $maxretrys;
	}
	
	&alert('ticketdown', 1) if $ticketdown == 1 && $last_down == 0;
	&alert('ticketdown', 0) if $ticketdown == 0 && $last_down == 1;
	$last_down = $ticketdown;
	
	&alert("neu",1) if $new_ticket == 1;
	
	if ($new_ticket == 0)
	{
		# schauen, ob alle neuen Tickets weg sind
		foreach my $host (keys $instances)
		{
			my $sub = $tickets->{$host};
			$new_ticket = 1 if keys($sub);
		}
	}
	
	&alert("neu",0) if $new_ticket == 0 && $ticket_removed == 1;

	sleep $interval;
}

#########
# Subs

sub debug
{
	print shift if $verbose == 1;
}

sub alert
{
	my $message = shift;
	my $alert = shift;

	&debug($message." ".$alert."\n");
	$ac->alert($message,$alert);
}

__END__

# Das nachfolgende ist eine Plain old Documentation (POD) dieses Scripts. Um sie besser betrachten zu 
# können, schaue sie über pod2text, pod2html oder einen anderen POD-Renderer an.

=head1 NAME

B<ticket-check.pl> - Ein treE Ticketsystem auf neue Tickets überprüfen.

=head1 BESCHREIBUNG

Dieses Script überprüft ein oder mehrere treE Ticketsystem(e) auf das Vorhandensein neuer Tickets. Dies erfolgt durch das 
anmelden beim Ticketsystem als User und Überprüfung der Seite für neue Tickets. 

=head1 KONFIGURATION

Die Konfiguration erfolgt über die Konfigurationsdatei 'C<ticket-check.yml>', welche in dem selben Ordner wie das Script 
selbst erwartet wird. Die Konfigurationsdatei ist im YAML Format.

Bei dem YAML Format können mehrere Werte "zusammengefasst" werden. Hierbei ist die Anzahl der Leerzeichen 
oder Tabulatoren für einen Abschnitt immer gleich zu halten.

Kommentare beginnen in YAML mit einer Raute (#).

=head2 Beispiel-Konfiguration

	config:				# Die Basis-Konfiguration ist unter 'config:'
		interval: 3		# Wie lange nach dem Check aller Ticketsysteme gewartet werden soll, bis diese
					# erneut gecheckt werden. (Sekunden)
		interval_betw_inst: 0	# Wie viel Zeit zwischen einzelnen Ticketsytemen vergehen soll. (Sekunden)
		maxretrys: 2		# Maximale Anzahl der erneuten versuche, bis ein 'ticketdown' gesendet werden soll.
		verbose: 0		# Debug Informationen ausgeben. (1)

	alarmd:				# Konfiguration für den AlarmClient genaueres siehe Dokumentation zu AlarmClient.pm.
		host: '127.0.0.1'
		port: 5061
		client: ticket
		pass: test
		maxretrys: 5
		after: 5
		separator: '::'

	instances:			# Unter diesem Punkt werden die einzelnen Ticketsysteme definiert.
		example:		# Name der Instanz
			url: 'https://ticket.example.com/index/status/1/' 	# URL zur 'Neue Tickets' Seite.
			user: 'checkuser'					# Benutzername
			pass: 'Pa$$w0rD.'					# und Passwort für das Ticketsystem.

		ticket2:		# Beispiel für ein zweites Ticketsystem
			url: 'https://ticket2.example.net/index/status/1/'
			user: 'checkuser'
			pass: 'pwTest'

=head1 GESENDETE ALARME

B<Folgende Alarme werden an den B<alarmd.pl> Server übertragen:>

=over

=item * C<neu>

Falls eine Instanz einen neues Ticket enthält.

Erst wenn keine neuen Tickets mehr da sind, also kein Ticket mehr in keinem der Ticketsysteme unter der Kategorie 'neu' ist,
wird der Alarm aufgehoben.

=item * C<ticketdown>

Falls eine Instanz nach vordefinierter Anzahl erneuter versuche nicht erreichbar ist.

=back

=head1 FUNKTIONSWEISE

In dem Script wird eine Endlosschleife gestartet, in welcher für jedes Ticketsystem die jeweilige Seite für neue Tickets
aufgerufen wird. In dieser Seite wird nach Ticket-ID's gesucht. Ticket-ID's fangen immer mit einer Raute (#) an und haben 
dahinter eine fortlaufende Zahl. (Beispiel: #47615). Alle gefundenen Tickets werden in einem Hash zu dem jeweiligen 
Ticketsystem gespeichert. Ist ein Ticket dabei, welches bei der letzten Überprüfung nicht dabei war (neues Ticket) so wird
ein 'neu' Alarm an den B<alarmd.pl> Server gesendet. Hierfür wird das Perl-Modul B<AlarmClient.pm> benutzt.

Kann ein Ticketsystem nicht erreicht werden, so wird dessen Retry-Counter (C<$retrys>) für um eins erhöht. 
Überschreitet ein Retry-Counter das vordefinierte Limit ('maxretrys'), so wird ein 'ticketdown' Alarm an den Server 
übermittelt.

=head1 AUTHOR

B<ticket-check.pl> - Geschrieben von Florian Schießl (florian@trans.net) im Rahmen des 
Projektes zur IHK Abschlussprüfung zum Fachinformatiker für Systemintegration Sommer 2013. 
Entwicklungsbeginn ist der 12.3.2013.

=head1 SIEHE AUCH

B<AlarmClient.pm> - Das verwendete Perl Modul zur Kommunikation mit dem B<alarmd.pl> Server.

B<alarmd.pl> - Der Alarm-Server.

http://www.deam.org/tree/ - Das treE Ticketsystem.


