#!/usr/bin/perl -w
#
# internet-check.pl by Florian Schießl <florian@trans.net>
#
# Dev-Start: 12.3.2013
#
use strict;
use Net::Ping;
use YAML::Tiny;
use FindBin;
use lib $FindBin::Bin; # Für den AlarmClient
use AlarmClient;
##################
# Konfiguration
my $yaml = YAML::Tiny->read($FindBin::Bin.'/internet-check.yml');
my $pinghosts = $yaml->[0]->{pinghosts};
my $alarmd = $yaml->[0]->{alarmd};
my $timeout = $yaml->[0]->{config}->{timeout}; # Sekunden Timeout (ping)
my $interval = $yaml->[0]->{config}->{interval};
my $verbose = $yaml->[0]->{config}->{verbose};

##########
# Start

# Root-Check
die "This script must be run as root" if $> != 0;

#print "$_\n" for keys %{ $yaml->[0] };

my $ac = AlarmClient->new($alarmd->{host},$alarmd->{port},$alarmd->{client},$alarmd->{pass},$alarmd->{maxretrys},$alarmd->{after},$alarmd->{separator});
my $p = Net::Ping->new("icmp");

# Initialisierung
#&alert("weg",0);

my $lastdown = 0;
while(1)
{
	
	my $down = 1;
	foreach my $host (keys $pinghosts)
	{
		my $result = $p->ping($pinghosts->{$host},$timeout);
		if(defined($result) && $result == 1)
		{
			&debug($host." alive\n");
			$down = 0;
		}
		else
		{
			&debug($host." down\n");
		}
	}
	&alert("weg",1) if $down == 1 && $lastdown == 0;
	&alert("weg",0) if $down == 0 && $lastdown == 1;
	$lastdown = $down;

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

B<internet-check.pl> - Mehrere Hosts anpingen und Alarm auslösen, wenn alle nicht erreichbar sind.

=head1 KONFIGURATION

Die Konfiguration erfolgt über die Konfigurationsdatei 'C<internet-check.yml>', welche in dem selben Ordner wie das Script 
selbst erwartet wird. Die Konfigurationsdatei ist im YAML Format.

Bei dem YAML Format können mehrere Werte "zusammengefasst" werden. Hierbei ist die Anzahl der Leerzeichen 
oder Tabulatoren für einen Abschnitt immer gleich zu halten.

Kommentare beginnen in YAML mit einer Raute (#).

=head2 Beispiel-Konfiguration

	config:				# Die Basis-Konfiguration ist unter 'config:'
		timeout: 2		# Das Timeout eines Pings (Sekunden)
		interval: 1		# Die Zeit, die Vergeht, bevor alle Hosts erneut gepingt werden (Sekunden)
		verbose: 0		# Debug Informationen ausgeben. (1)

	alarmd:				# Konfiguration für den AlarmClient genaueres siehe Dokumentation zu AlarmClient.pm.
		host: '127.0.0.1'
		port: 5061
		client: internet
		pass: test
		maxretrys: 5
		after: 5
		separator: '::'

	pinghosts:			# Die Hosts, welche angepingt werden sollen.
		googlens: '8.8.8.8'	# Der Name davor dient nur zur identifizierung.
		heise: 'heise.de'

=head1 GESENDETE ALARME

Sobald kein Host mehr erreichbar ist, ein Alarm an den Server gesendet. Hierfür wird das Perl-Modul B<AlarmClient.pm> benutzt. 
Das macht selbstverständlich nur Sinn, wenn sich der B<alarmd.pl> Server im selben Netzwerk, oder idealerweise sogar auf dem 
selben Host befindet. Der Alarm wird aufgehoben, sobald ein Host aus der Liste wieder erreichbar ist.

=over

=item * C<weg>

Kein Host mehr erreichbar.

=back

=head1 FUNKTIONSWEISE

Zuerst wird überprüft, ob das Script als root gestartet wurde. Dies ist notwendig, da 
das C<Net::Ping> Perl Modul root Rechte benötigt, um Pings zu senden.

Ist die Überprüfung erfolgreich, so wird eine Endlosschleife gestartet, in welcher der Reihe nach alle definierten Pinghosts 
angepingt werden. Wann ein Alarm ausgegeben wird, steht in dem Abschnitt C<GESENDETE ALARME>.

=head1 AUTOR

B<internet-check.pl> - Geschrieben von Florian Schießl (florian@trans.net) im Rahmen des 
Projektes zur IHK Abschlussprüfung zum Fachinformatiker für Systemintegration Sommer 2013. 
Entwicklungsbeginn ist der 12.3.2013.

=head1 SIEHE AUCH

B<AlarmClient.pm> - Das verwendete Perl Modul zur Kommunikation mit dem B<alarmd.pl> Server.

B<alarmd.pl> - Der Alarm-Server.



