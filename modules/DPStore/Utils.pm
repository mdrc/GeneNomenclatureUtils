### nomenclature 

=pod

=head1 NAME - DPStore::Utils

=head1 DESCRIPTION

Utility subroutines

=head1 AUTHOR - mike_croning@hotmail.com

=cut 

package DPStore::Utils;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use Exporter;
use DPStore::Utils::Config;
use Term::ReadKey;
use Time::Local;
use vars qw{ @ISA @EXPORT_OK };

#Global
my $debug;

@ISA = ('Exporter');
@EXPORT_OK = qw(
    show_perldoc
);    


=head2 show_perldoc

Outputs the passed txt to STDERR, followed by the POD of the program,
afer a two second delay, then confesses.

=cut

sub show_perldoc {
    my ( $text ) = shift(@_);
    
    $text = "HELP:" unless $text;
    chomp($text);
    print STDERR "\n$text\n\n";
    sleep 2;

    my @perldoc = `perldoc -T $0`;
    foreach my $line (@perldoc) {
        print STDERR $line;
    }
    unless ($text eq 'HELP:') {
        confess "\n" , $text;
    } else {
        die 'Exiting';
    }
}

=head2 get_basedir

=cut

sub get_basedir {
    
    my $base_dir = $ENV{'DPStoreBaseDir'}
        or show_perldoc("Must set \$DPStoreBaseDir\n");
    show_perldoc("Can't read directory '$base_dir'\n") unless -d $base_dir;
    show_perldoc('Error finding scripts with $DPStoreBaseDir')
        unless -f "$base_dir/scripts/db/create_db_tables";
    
    return $base_dir;
}
