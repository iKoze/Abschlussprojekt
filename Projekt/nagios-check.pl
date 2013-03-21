#!/usr/bin/perl -w
# 
# nagios-check.pl by Florian Schießl <florian@trans.net>
# 
# Dev-Start 11.3.2013
#
use strict;
use WWW::Mechanize; # LWP::UserAgent schneidet manchmal den output ab
use YAML::Tiny;
use FindBin;
use lib $FindBin::Bin; # Für den AlarmClient
use AlarmClient;
##################
# Konfiguration
my $yaml = YAML::Tiny->read($FindBin::Bin.'/nagios-check.yml');
my $interval = $yaml->[0]->{config}->{interval}; # Interwall, in welchem alle Nagios Instanzen überprüft werden sollen
my $interval_betw_inst = $yaml->[0]->{config}->{interval_betw_inst}; # Wartezeit zwischen den Instanzen
my $maxretrys = $yaml->[0]->{config}->{maxretrys}; # Erneute Versuche, bevor ein Nagios Server als nicht erreichbar gemeldet wird
my $alarmd = $yaml->[0]->{alarmd};
my $instances = $yaml->[0]->{instances};
my $verbose = $yaml->[0]->{config}->{verbose};

##########
# Start

my $ac = AlarmClient->new($alarmd->{host},$alarmd->{port},$alarmd->{client},$alarmd->{pass},$alarmd->{maxretrys},$alarmd->{after},$alarmd->{separator});

# Initialisierung
#&alert("warning",0);
#&alert("unknown",0);
#&alert("critical",0);
#&alert("down",0);
#&alert("nagdown",0);

# Enthält die Zusammenfassung des aktuellen Checks aller Instanzen
my $current = {
	warning => 0,
	unknown => 0,
	critical => 0,
	down => 0
};

# Enthält die letzte Zusammenfassung
my $last = {
	warning => 0,
	unknown => 0,
	critical => 0,
	down => 0
};

my $retrys; # Enthält den Retry-Zähler für jede Instanz
my $lastnagalert = 0;
while (1)
{
	# Aktuelle Zusammenfassung leeren
	$current = {
		warning => 0,
		unknown => 0,
		critical => 0,
		down => 0
	};

	# Aktuellen Status aller Instanzen holen
	foreach my $host (keys $instances)
	{
		my $netloc = $instances->{$host}->{host} . ":" . $instances->{$host}->{port};
		my $user = $instances->{$host}->{user};
		my $pass = $instances->{$host}->{pass};
		my $realm = $instances->{$host}->{realm};
		my $statuscgi = $instances->{$host}->{statuscgi};

		my $ua = WWW::Mechanize->new(
			ssl_opts => { verify_hostname => 0},
			onerror => sub {}
		);
		#$ua->show_progress(1);
		$ua->credentials($netloc, $realm, $user, $pass);

		my $response = $ua->get($statuscgi);
	
		if($response->is_success)
		{
			$retrys->{$host} = 0;
			my @lines = split("\n",$response->decoded_content);
			my $warning = 0;
			my $unknown = 0;
			my $critical = 0;
			my $down = 0;
			
			my $nextline = 0;
			foreach(@lines)
			{
				++$nextline;
				++$warning if m/statusWARNING/ && $lines[$nextline] !~m/statusBGWARNINGACK/;
				++$unknown if m/statusUNKNOWN/ && $lines[$nextline] !~m/statusBGUNKNOWNACK/;
				++$critical if m/statusCRITICAL/ && $lines[$nextline] !~ m/statusBGCRITICALACK/;
				++$down if m/statusHOSTDOWN/ && !m/statusHOSTDOWNACK/;
				++$down if m/statusHOSTUNREACHABLE/ && !m/statusHOSTUNREACHABLEACK/;
			}
			$down = $down / 2;
			&debug("Found ".$down." down hosts, ".$critical." critical, ".$unknown." unknown services and ".$warning." warning on ".$host."\n");
			$current->{warning} += $warning;
			$current->{unknown} += $unknown;
			$current->{critical} += $critical;
			$current->{down} += $down;
		}
		else
		{
			++$retrys->{$host};
			$current = $last; # Letzte Meldungen nicht verlieren!
			&debug($response->status_line."\n");
			
		}
		sleep $interval_betw_inst;
	}
	
	# Status der Nagios Instanzen überprüfen
	my $nagalert = 0;
	foreach my $host (keys $retrys)
	{
		$nagalert = 1 if $retrys->{$host} > $maxretrys;
	}
	
	&alert('nagdown', 1) if $nagalert == 1 && $lastnagalert == 0;
	&alert('nagdown', 0) if $nagalert == 0 && $lastnagalert == 1;
	$lastnagalert = $nagalert;
	
	# Status mit letztem Status vergleichen
	foreach my $key (keys $last)
	{
		&alert($key, 1)
		if $last->{$key} < $current->{$key};
		
		&alert($key, 0)
		if $last->{$key} > 0 && $current->{$key} == 0;
		
		$last->{$key} = $current->{$key};
	}
	
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

B<nagios-check.pl> - Eine oder mehrere Nagios-Instanzen überprüfen, und den Status zusammenfassen.

=head1 BESCHREIBUNG

Dieses Script meldet sich auf der Weboberfläche der Nagios Instanzen an und untersucht diese auf das Vorhandensein von Services mit dem 
Status I<CRITICAL>, I<UNKNOWN>, I<WARNING> und Hosts mit dem Status I<DOWN> oder I<UNREACHABLE>. Ist auf einer aller definierten Instanzen 
ein Host oder ein Service mit einem erkannten Status, so wird das gemeldet.

B<HINWEIS:> Dieses Script wurde mit einem Nagios 3.0.6 entwickelt und getestet. Die Funktion kann für andere Versionen nicht garantiert werden!

=head1 KONFIGURATION

Die Konfiguration erfolgt über die Konfigurationsdatei 'C<nagios-check.yml>', welche in dem selben Ordner wie das Script 
selbst erwartet wird. Die Konfigurationsdatei ist im YAML Format.

Bei dem YAML Format können mehrere Werte "zusammengefasst" werden. Hierbei ist die Anzahl der Leerzeichen 
oder Tabulatoren für einen Abschnitt immer gleich zu halten.

Kommentare beginnen in YAML mit einer Raute (#).

=head2 Beispiel-Konfiguration

	config:				# Die Basis-Konfiguration ist unter 'config:'
		interval: 5		# Wie lange nach dem Check aller Instanzen gewartet werden soll, bis 
					# sie erneut gecheckt werden. (Sekunden)
		interval_betw_inst: 0	# Wie viel Zeit zwischen den Instanzen vergehen soll (Sekunden)
		maxretrys: 2		# Maximale Anzahl der erneuten versuche, bis ein 'nagdown' gesendet werden soll.
		verbose: 0		# Debug Informationen ausgeben. (1)

	alarmd:				# Konfiguration für den AlarmClient genaueres siehe Dokumentation zu AlarmClient.pm.
		host: '127.0.0.1'
		port: 5061
		client: nagios
		pass: test
		maxretrys: 5
		after: 5
		separator: '::'

	instances:			# Unter diesem Punkt werden die einzelnen Nagios Instanzen definiert.
		transnet:		# Name der Instanz
			statuscgi: 'https://nagios.example.com/cgi-bin/nagios3/status.cgi' 	# URL der Service Details Seite.
			host: 'nagios.example.com'	# Hostname der Instanz (wird für die Authentifikation gebraucht)
			port: 443			# Port des Webinterfaces (80 = http; 443 = https)
			realm: 'Nagios Access'		# Wo sich authentifiziert werden soll.
			user: 'nagioscheck'		# Benutzername
			pass: 'Pa$$w0rD.'		# und Passwort für die Weboberfläche
	
		nagios2:		# Beispiel für 2. Instanz
			statuscgi: 'http://nagios2.example.net/cgi-bin/nagios3/status.cgi' 
			host: 'nagios.example.net'
			port: 80
			realm: 'Nagios Access'
			user: 'checker'
			pass: 'pwTest'

=head1 GESENDETE ALARME

Jeder Alarm außer 'C<nagdown>' wird erneut übertragen, sobald ein Service mehr den entsprechenden Status hat als davor.
Ein Alarm wird erst aufgehoben, wenn auf keinem der Instanzen mehr ein entsprechender Status vorliegt.
B<Folgende Alarme werden an den B<alarmd.pl> Server übertragen:>

=over

=item * C<warning>

Falls eine Instanz eine I<WARNING> enthält.

=item * C<unknown>

Falls eine Instanz ein I<UNKNOWN> enthält.

=item * C<critical>

Falls eine Instanz ein I<CRITICAL> enthält.

=item * C<down>

Falls eine Instanz ein I<DOWN> enthält.

=item * C<nagdown>

Falls eine Instanz nach vordefinierter Anzahl erneuter versuche nicht erreichbar ist.

=back

=head1 FUNKTIONSWEISE

In dem Script wird eine Endlosschleife gestartet, in welcher für die jeweilige Nagios Instanz die Service Details Seite aufgerufen wird.
Diese wird auf das vorkommen von eines erkannten Status überprüft und gegebenenfalls ein Alarm an den B<alarmd.pl> Server gesendet. 
Hierfür wird das Perl-Modul B<AlarmClient.pm> benutzt. Zwischen dem Status I<DOWN> und I<UNREACHABLE> wird nicht unterschieden.

Kann eine Nagios Instanz nicht erreicht werden, so wird deren Retry-Counter (C<$retrys>) für eins erhöht. 
Überschreitet ein Retry-Counter das vordefinierte Limit ('maxretrys'), so wird ein 'nagdown' Alarm an den Server 
übermittelt.

=head1 AUTOR

B<nagios-check.pl> - Geschrieben von Florian Schießl (florian@trans.net) im Rahmen des 
Projektes zur IHK Abschlussprüfung zum Fachinformatiker für Systemintegration Sommer 2013. 
Entwicklungsbeginn ist der 11.3.2013.

=head1 SIEHE AUCH

B<AlarmClient.pm> - Das verwendete Perl Modul zur Kommunikation mit dem B<alarmd.pl> Server.

B<alarmd.pl> - Der Alarm-Server.

