### nomenclature

=pod

=head1 NAME - MedlineCacheDB

=head1 DESCRIPTION

Class for accessign the MEDLINE cache database of GeneNomenclatureUtils

=head1 AUTHOR - mike_croning@hotmail.com

=cut


package MedlineCacheDB;

use strict;
use warnings;
use Carp;
use Config::IniFiles;
use DBI;

sub new {
    my ( $self, $config_file ) = @_;

    unless ($ENV{GeneNomenclatureUtilsConf}) {
        show_perldoc('Must set $ENV{GeneNomenclatureUtilsConf}');
    }
    
    my $cfg = new Config::IniFiles(
        -file => $ENV{GeneNomenclatureUtilsConf} . '/' .$config_file
    );

    my $db   = $cfg->val('MEDLINE DB', 'db')
        or confess 'db not set'; 
    my $host = $cfg->val('MEDLINE DB', 'host')
        or confess 'host not set';
    my $port = $cfg->val('MEDLINE DB', 'port');
    $port = 3306 unless $port;
    my $user = $cfg->val('MEDLINE DB', 'user')
        or confess "user not set";
    my $pass = $cfg->val('MEDLINE DB', 'pass')
        or confess "pass not set";

    my $socket = '/tmp/mysql.sock';

    my $dsn = "dbi:mysql:$db:$host:$port";
    my $dbh;
    
    eval {
        $dbh  =  DBI->connect($dsn, $user, $pass, {RaiseError => 1});
    };
    confess "No connection" unless $dbh;

    my $adaptor = {};
    bless $adaptor, $self;
    $adaptor->{'medlinecache_dbh'} = $dbh;
    
    return $adaptor;
}

sub dbh {
    my ( $self ) = @_;
    
    return $self->{'medlinecache_dbh'};
}

sub store_request {
    my ( $self, $pubmed_id ) = @_;

    my $dbh = $self->dbh or confess "dbh not set";
    
    unless ($pubmed_id and $pubmed_id =~ /^\d+$/) {
        confess "Must pass a pubmed_id";
    }
   
    my $sth = $dbh->prepare(qq{
        INSERT into request (
              request_id
            , pubmed_id
            , status
        ) values (
              NULL
            , ?
            , ?
        )
    });

    $sth->execute($pubmed_id, 'requested');

    my $row_count = $sth->rows;
    unless ($row_count and ($row_count == 1)) {
        confess "Failed to update request with pubmed_id '$pubmed_id'";
    }
    return $row_count;
}


sub check_for_pubmed_id {
    my ( $self, $pubmed_id ) = @_;
    
    my $dbh = $self->dbh or confess "dbh not set";
    
    unless ($pubmed_id and $pubmed_id =~ /^\d+$/) {
        confess "Must pass a pubmed_id";
    }
   
    my $sth = $dbh->prepare(qq{
        SELECT request_id
            , status
        FROM request
        WHERE pubmed_id = ?
    });

    $sth->execute($pubmed_id);
    
    my ( $request_id, $status ) = $sth->fetchrow;
    if ( $request_id ) {
        return $request_id, $status;
    } else {
        return;
    }
}

sub fetch {
    my ( $self, $pubmed_id ) = @_;

    my $dbh = $self->dbh or confess "dbh not set";
    
    unless ($pubmed_id and $pubmed_id =~ /^\d+$/) {
        confess "Must pass a pubmed_id";
    }
    
    my $sth = $dbh->prepare(qq{
        SELECT medline_id
            , pubmed_id
            , record
        FROM medline
        WHERE pubmed_id = ?
    });
    
    $sth->execute($pubmed_id);
    
    my ( $fetched_id, $fetched_pubmed_id, $record ) = $sth->fetchrow;
    
    return ($fetched_id, $fetched_pubmed_id, $record )
}

sub get_requested_pubmed_ids {
    my ( $self ) = @_;
    
    my $dbh = $self->dbh or confess "dbh not set";
    
    my $sth = $dbh->prepare(qq{
        SELECT pubmed_id
        FROM request
        WHERE status = 'requested'
    });

    $sth->execute();
    
    my $requests = [];
    while (my @rows = $sth->fetchrow) {
        push(@$requests, @rows);
    }
    
    return $requests;
}

sub update_request {
    my ( $self, $pubmed_id, $status ) = @_;
    
    my $dbh = $self->dbh or confess "dbh not set";
    
    unless ($pubmed_id and $pubmed_id =~ /^\d+$/) {
        confess "Must pass a pubmed_id";
    }
    unless ($status and $status =~ /^requested$|^available$|^error$/) {
        confess "Must pass status as one of 'requested', 'available', 'error'";
    }

    my $sth = $dbh->prepare(qq{
        UPDATE request
        SET status      = ?
        WHERE pubmed_id = ?
    });

    $sth->execute($status, $pubmed_id);

    my $row_count = $sth->rows;
    unless ($row_count and ($row_count == 1)) {
        confess "Failed to update request with pubmed_id '$pubmed_id'";
    }
    return $row_count;
}

sub store_medline {
    my ( $self, $pubmed_id, $text ) = @_;
    
    my $dbh = $self->dbh or confess "dbh not set";
    
    unless ($pubmed_id and $pubmed_id =~ /^\d+$/) {
        confess "Must pass a pubmed_id";
    }

    unless ($text) {
        confess "Must pass MEDLINE text";
    }
    
    my $sth = $dbh->prepare(qq{
        INSERT into medline (
              medline_id
            , pubmed_id
            , record
        ) values (
              NULL
            , ?
            , ?
        ) 
    });
    
    $sth->execute($pubmed_id, $text);
    my $row_count = $sth->rows;
    unless ($row_count and ($row_count == 1)) {
        confess "Failed to insert row with pubmed_id '$pubmed_id'";
    }
    return $row_count;
}

sub get_pubmed_ids_by_status {
    my ( $self, $status ) = @_;

    my $dbh = $self->dbh or confess "dbh not set";
    
    unless ($status and $status =~ /^requested$|^available$|^error$/) {
        confess "Must pass status as one of 'requested', 'available', 'error'";
    }
   
    my $sth = $dbh->prepare(qq{
        SELECT pubmed_id
        FROM request
        WHERE status = ?
    });

    $sth->execute($status);
    
    my $requests = [];
    while (my @rows = $sth->fetchrow) {
        push(@$requests, @rows);
    }
    
    return $requests;
}




1;

