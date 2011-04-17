### dev

=pod

=head1 NAME - DPStore::Utils::Spreadsheet

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHOR

webmaster@genes2cognition.org

=cut

package DPStore::Utils::Spreadsheet;

use strict;
use warnings;
use Carp;
use Spreadsheet::WriteExcel;
use Exporter;
use vars qw{ @ISA @EXPORT_OK };

@ISA = ('Exporter');
@EXPORT_OK = qw(
    write_excel_from_table
);

=head2 write_excel_from_table

Given a file name and a reference to an array of arrays converts 
the 'table' into a binary Excel file.

Passing '-' as the file name causes the binary spreadsheet to be
written to STDOUT (useful for CGI scripts) 

=cut 

sub write_excel_from_table {
    my ( $file, $table ) = @_;
    
    unless ($file) {
        confess "Must pass a filename";
    }
    
    unless ($table and ref($table) =~ /ARRAY/) {
        confess "Must pass a reference to an array";
    }

    my $workbook = Spreadsheet::WriteExcel->new($file)
        or confess "$!";    
    my $worksheet = $workbook->add_worksheet()
        or confess "Error adding worksheet";

    my $row_count = scalar(@$table);
    my $rows_written = 0;
    
    for (my $row = 0; $row < $row_count; $row++) {
        
        my $column_count = scalar(@{$table->[$row]});
        
        for (my $column = 0; $column < $column_count; $column++) {
            
            my $value = $table->[$row]->[$column];
            $worksheet->write($row, $column, $value);
        }
        $rows_written++;
    }
    $workbook->close();

    return $rows_written;
}

1;
