#!/usr/bin/perl -w
#
# startup.pl by Florian Schießl <florian@trans.net>
#
# Dev-Start: 13.3.2013
#
use strict;
use Proc::Background;
use FindBin;

# Root-Check
die "This script must be run as root" if $> != 0;

# In das Verzeichnis wechseln, in welchem sich dieses Script befindet.
chdir $FindBin::Bin;

my @procs;
push(@procs,Proc::Background->new("./alarmd.pl"));
push(@procs,Proc::Background->new("./internet-check.pl"));
push(@procs,Proc::Background->new("./ticket-check.pl"));
push(@procs,Proc::Background->new("./nagios-check.pl"));

# Exit Signale abfangen
$SIG{INT} = \&exittsk;
$SIG{TERM} = \&exittsk;
$SIG{QUIT} = \&exittsk;
$SIG{ABRT} = \&exittsk;
$SIG{HUP} = \&exittsk;

# Am leben bleiben
while(1)
{
	sleep 100;
}

sub exittsk
{
	# Alle Prozesse beenden
	foreach my $proc (@procs)
	{
		$proc->die;
	}
	exit 0;
}

__END__

# Das nachfolgende ist eine Plain old Documentation (POD) dieses Scripts. Um sie besser betrachten zu 
# können, schaue sie über pod2text, pod2html oder einen anderen POD-Renderer an.

=head1 NAME

B<startup.pl> - Dieses Script startet das Überwachungs-System.

=head1 BESCHREIBUNG

Dieses Script startet zuerst das B<alarmd.pl> Script und danach die anderen Scripte, welche 
die einzelnen Dienste überwachen. Wird es beendet, so beendet es auch die anderen Scripte.

=head2 Start-Reihenfolge

=over

=item C<alarmd.pl>

Script, welches die Ampel ansteuert.

=item C<internet-check.pl>

Script, welches das Internet überwacht.

=item C<ticket-check.pl>

Script, welches benachrichtigt, sobald neue Tickets da sind.

=item C<nagios-check.pl>

Script, welches den Nagios-Status überwacht.

=back

=head1 FUNKTIONSWEISE

Zuerst wird überprüft, ob das Script als root gestartet wurde. Dies ist notwendig, da 
für das B<alarmd.pl> und das B<internet-check.pl> Script root-Rechet benötigt werden.

Danach wird in das Verzeichnis gewechselt, in welchem sich dieses Script befindet. Dort 
erwartet es die anderen Scripte.

Die anderen Scripte werden daraufhin gestartet und einem Array hinzugefügt, damit sie 
beendet werden können, sobald dieses Script beendet wird.

Die Funktion C<exittsk()> wird mit den Signalen I<INT>, I<TERM>, I<QUIT>, I<ABRT> und I<HUP> 
verlinkt. Das bewirkt, dass sich dieses Script nicht sofort beendet, sondern zuerst noch 
die anderen beenden kann, welches innerhalb der Funktion C<exittsk()> erfolgt.

Damit dieses Script nicht nachdem alles andere gestartet wurde beendet wird, und es somit 
auch zum beenden der anderen Scripte benutzt werden kann, wird am Schluss eine 
Endlosschleife ausgefuehrt, in welcher für jeweils 100 Sekunden gewartet wird.

=head1 AUTHOR

B<startup.pl> - Geschrieben von Florian Schießl (florian@trans.net) im Rahmen des 
Projektes zur IHK Abschlussprüfung zum Fachinformatiker für Systemintegration Sommer 2013. 
Entwicklungsbeginn ist der 13.3.2013.

