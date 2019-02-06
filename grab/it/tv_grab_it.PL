# Generate tv_grab_it from tv_grab_it.in.  This is to set the path to
# the files in /usr/local/share/xmltv or wherever.
#
# The second argument is the share directory for the final
# installation.

# 15/07/2005
# we switch the pod in the file according to the locale.
# maybe we should ask the user if he wants to...
# code below is based on lib/XMLTV.pm.pl

use strict;

use File::Copy qw/copy/;

#here are the pods...
my $ENG_POD=<<END;
=pod

=head1 NAME

tv_grab_it - Grab TV listings for Italy.

=head1 SYNOPSIS

tv_grab_it --help

tv_grab_it [--config-file FILE] --configure

tv_grab_it [--config-file FILE] [--output FILE]
           [--days N] [--offset N] [--quiet]
           [--slow] [--verbose] [--errors-in-xml]
           [--backend SITE1[,SITE2[,SITE3]]]
	   [--cache-slow]

=head1 DESCRIPTION

Output TV listings for several channels available in Italy.
The grabber relies on parsing HTML so it might stop working at any time.
The data comes from different backends. This is to minimize blackouts
in case of site changes but also to extend the number of channels.
If the grabber canE<39>t find the data with the first backend it will
try the second one, and so on. You can specify your order of preference
using the --backend option.

Currently configured backends are (in default order):

=over

=item B<mediaset>  - grabs data from www.mediaset.it

=item B<skylife>  - grabs data from www.skylife.it

=item B<raiit>    - grabs data from www.rai.it

=item B<mediaset_guidatv>  - grabs data from www.mediaset.it/guidatv

=item B<mediasetpremium>  - grabs data from www.mediasetpremium.it

=item B<iris>     - grabs data from www.iris.it

=item B<boingtv>  - grabs data from www.boingtv.it

=item B<la7>    - grabs data from www.la7.it


=back

First run B<tv_grab_it --configure> to choose which channels you want
to download. Then running B<tv_grab_it> with no arguments will output
listings in XML format to standard output.

B<--configure> Prompt for which channels, and writes the configuration file.

B<--config-file FILE> Set the name of the configuration file, the
default is B<~/.xmltv/tv_grab_it.conf>.  This is the file written
by B<--configure> and read when grabbing.

B<--gui OPTION> Use this option to enable a graphical interface to be used.
OPTION may be 'Tk', or left blank for the best available choice.
Additional allowed values of OPTION are 'Term' for normal terminal output
(default) and 'TermNoProgressBar' to disable the use of XMLTV::ProgressBar.

B<--output FILE> write to FILE rather than standard output.

B<--days N> Grab N days.  The default is 7.

B<--offset N> Start N days in the future.  The default is to start
from today.

B<--quiet> Suppress the progress messages normally written to standard
error.

B<--slow> Downloads more details (descriptions, actors...). This means
downloading a new file for each programme, so itE<39>s off by default to
save time.

B<--cache-slow> If you use the --cache option to speed up thing when you
grab data several times a week, using this option you will cache only the
--slow data, so you shouldnE<39>t miss changes in schedules.

B<--verbose> Prints out verbose information useful for debugging.

B<--errors-in-xml> Outputs warnings as programmes in the xml file,
so that you can see errors in your favorite frontend in addition
to the default STDERR.

B<--backend> Set the backend (or backends) to use. See the examples.

B<--version> Show the version of the grabber.

B<--help> Print a help message and exit.

=head1 CAVEATS

If you use --quiet you should also use --errors-in-xml or you wonE<39>t
be warned about errors. Note also that, as opposed to previous versions,
this grabber doesnE<39>t die if it cannot find any data, but returns an
empty (or optionally containing just warnings) xml file instead.

The backendsE<39> data quality differs a lot. For example, mytv was very
basic, yet complete and uses the least amount of bandwidth. Skytv has a
lot of channels, but unless you use it with the --slow option the data
is not very good (and in this case i would be VERY slow). wfactory is a
good overall site if you donE<39>t need the whole sky package.

=head1 EXAMPLES

=over

=item tv_grab_it --backend skylife --configure

configures tv_grab_it using only the backend skylife

=item tv_grab_it --backend skylife,wfactory --days 1

grabs one day of data overriding the default order (could also be --backend skylife --backend wfactory)

=item tv_grab_it --cache --slow --days 3

grabs the full data for the next three days using the default backend order and using a disk cache.

=back

=head1 RECOMMENDED USAGE

=over

=item tv_grab_it --cache --slow --cache-slow --errors-in-xml

=back

=head1 SEE ALSO

L<xmltv>.

=head1 AUTHOR

This grabber is currently unmantained.

=cut

END

my $ITA_POD=<<END;
=pod

=head1 NOME

tv_grab_it - Recupera informazioni sui programmi TV italiani.

=head1 SINTASSI

tv_grab_it --help

tv_grab_it [--config-file FILE] --configure

tv_grab_it [--config-file FILE] [--output FILE]
           [--days N] [--offset N] [--quiet]
           [--slow] [--verbose] [--errors-in-xml]
           [--backend SITE1[,SITE2[,SITE3]]]
	   [--cache-slow]

=head1 DESCRIZIONE

Crea un file con i programmi TV di vari canali italiani.
Il grabber eE<39> basato sullE<39>analisi del sorgente HTML dei siti,
quindi potrebbe smettere di funzionare in qualsiasi momento.
I dati vengono presi da piuE<39> fonti per poter ridurre i periodi di
blackout dovuti a cambiamenti nei siti, ma anche per aumentare
il numero di canali disponibili.
Se il grabber non riesce ad ottenere dati dalla prima fonte passeraE<39>
alla seconda, e cosE<39> via. Puoi specificare il tuo ordine usando
lE<39>opzione --backend.

Le fonti configurate al momento sono: (in ordine di utilizzo):

=over

=item B<skylife>  - prende i dati da www.skylife.it

=item B<boingtv>  - prende i dati da www.boingtv.it

=item B<sitcom1>  - prende i dati da www.sitcom1.it

=item B<raisat>   - prende i dati da www.risat.it

=item B<raiit>    - prende i dati da www.rai.it

=item B<iris>     - prende i dati da www.iris.it

=item B<mediasetpremium>  - prende i dati da www.mediasetpremium.it

=back

Per prima cosa esegui B<tv_grab_it --configure> per scegliere quali
canali vuoi scaricare. In seguito lE<39>esecuzione di B<tv_grab_it>
senza opzioni manderE<39> sullo standard output i dati in formato XML.

B<--configure> Chiede quali canali scaricare e scrive il file di configurazione.

B<--config-file FILE> Imposta il nome del file di configurazione, di
default eE<39> B<~/.xmltv/tv_grab_it.conf>. Questo file viene scritto
usando B<--configure> e letto durante il grabbing.

B<--gui OPTION> Usa questa opzione per abilitare una interfaccia grafica.
OPTION puE<39> essere 'Tk', oppure lasciato in bianco per la scelta migliore.
Altri valori possibili per OPTION sono: 'Term' per un terminale normale
(default) e 'TermNoProgressBar' per disabilitare lE<39>uso di XMLTV::ProgressBar.

B<--output FILE> scrive in questo file invece che sullo standard output.

B<--days N> prende dati per N giorni. Di default eE<39> 7.

B<--offset N> parte da N giorni in poi. Normalmente parte da oggi.

B<--quiet> non usa i messaggi di avanzamento che normalmente vengono scritti su standard error.

B<--slow> scarica piuE<39> dettagli (trame, attori...). Questo vuol dire scaricare un nuovo file per ogni programma, quindi di default eE<39> disabilitato per risparmiare tempo.

B<--cache-slow> Se usi lE<39>opzione --cache per accelerare le cose se usi il programma piuE<39> volte alla settimana, con questa opzione verranno messe in cache solo le informazioni --slow, cosiE<39> non dovresti perdere cambiamenti nei palinsesti.

B<--verbose> scrive piuE<39> informazioni su quello che sta facendo il programma, utile per il debugging.

B<--errors-in-xml> scrive gli errori sotto forma di programmi nel file XML, cosiE<39> possono essere visti nel tuo frontend preferito oltre che in STDERR.

B<--backend> imposta la sorgente da utilizzare. Vedi gli esempi.

=head1 ATTENZIONE

Se usi --quiet dovresti usare anche --errors-in-xml, o non avrai nessun
avvertimento per eventuali errori. A differenza delle versioni precedenti,
inoltre, se il grabber non riesce a scaricare nessun dato ritorna un
file XML vuoto (o opzionalmente con solo i warning).

La qualitaE<39> dei dati delle varie sorgenti cambia molto. Per esempio, mytv
era molto semplice, ma completa e usava la minor banda possibile. Skytv ha molti
canali, ma i dati non sono molto buoni a meno che non si usi lE<39>opzione --slow,
(ed in quel caso serve MOLTO tempo). wfactory eE<39> tutto sommato un buon sito se
non hai bisogno di tutto il pacchetto sky.

=head1 ESEMPI

=over

=item tv_grab_it --backend skylife --configure

configura tv_grab_it usando solo la sorgente skylife

=item tv_grab_it --backend skylife,wfactory --days 1

prende solo un giorno di dati e utilizza un ordine diverso da quello di default (si sarebbe potuto scrivere anche cosiE<39>: --backend skylife --backend wfactory)

=item tv_grab_it --cache --slow --days 3

prende tutti i dati per i prossimi tre giorni ed usa una cache su disco (sempre raccomandabile).

=back

=head1 UTILIZZO CONSIGLIATO

=over

=item tv_grab_it --cache --slow --cache-slow --errors-in-xml

=back

=head1 VEDERE ANCHE

L<xmltv>.

=head1 AUTORE

Questo grabber non è più sviluppato.

=cut

END

# and here it's the code itself
# warn "Setting tv_grab_it pod...";
my $LANG = 'eng';
my $LANG_STR;

if ($^O eq 'MSWin32') {
    eval {
        require Win32::Locale;
    };
    if ($@) {
        warn "Win32::Locale not installed\n";
    }
    else {
        $LANG_STR = Win32::Locale::get_language();
    }
}
else {
    $LANG_STR = $ENV{LANG};
}
#warn ' $ENV{LANG} is '.$LANG_STR."\n";

$LANG = 'ita' if (defined $LANG_STR and $LANG_STR=~/^it[-_]/i);
#warn ' LANG is '.$LANG."\n";
my $out = 'grab/it/tv_grab_it.in2';
my $in  = 'grab/it/tv_grab_it.in';

#warn "lang e' $LANG deflang e' $LANG_STR\n";

open(IN_FH, $in) or die "cannot read $in: $!";
open(OUT_FH, ">$out") or die "cannot write to $out: $!";

while (<IN_FH>) {
    if (/^my \$POD_GOES_HERE;$/) {
        if ($LANG eq 'ita') {
            print OUT_FH $ITA_POD;
        }
        else {
            print OUT_FH $ENG_POD;
        }
    }
    elsif (/^my \$DEF_LANG = 'eng';\E$/) {
        print OUT_FH 'my $DEF_LANG = \''.$LANG.'\';';
    }

    else {
        print OUT_FH $_;
    }
}
close OUT_FH or die "cannot close $out: $!";
close IN_FH or die "cannot close $in: $!";


# stuff for setting share dir
die "usage: $_ output_file share_dir" if @ARGV != 2;

require './lib/set_share_dir.pl';

#warn "faccio $ARGV[0] $ARGV[1]\n";
#set_share_dir('grab/it/tv_grab_it.in2', $ARGV[0], $ARGV[1]);
copy( 'grab/it/tv_grab_it.in2', $ARGV[0] );
