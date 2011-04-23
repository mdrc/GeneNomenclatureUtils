### nomenclature

=pod

=head1 NAME - GeneNomenclatureUtils::ColumnParser

=head1 DESCRIPTION

This module 'knows' how to parse lines from nomenclature files to
named attributes, validating particular columns (by regular
expression) as necessary.

It's purpose is to make it easy to set-up more such parsers, without
having to spread the information throughout SeqIDNomenclature.pm
which it subserves.

The module does not export any routines to MAIN, but the subroutines
can be accessed by a fully-specified package names for instance:

GeneNomenclatureUtils::ColumnParser::configure();

- Which is how one initialises the parsers hardcoded into the module.

Debugging can be enabled with:
  $GeneNomenclatureUtils::Parsers::debug = 1;

See: GeneNomenclatureUtils/scripts/add_rat_attribute_by_rgd_id for an
example of script that employs it.

=head1 AUTHOR - mike_croning@hotmail.com

=cut 

package GeneNomenclatureUtils::ColumnParser;

use strict;
use warnings;
use Carp;
use Data::Dumper;


our $debug;

{
    my $parsers;

    ### These column numbers are 1 based (like the script params)
    
    sub configure {
        
        ### GENES_RAT.txt
        #
        # All columns (23/04/11)
        #
        # Mandatory validated columns are: 1,2,3
        
        $parsers->{'GENES_RAT.txt'} = {
            1   => ['gene_rgd_id', '^\d+$'],
            2   => ['symbol', '^\S+$'],
            3   => ['name', '.'],
            4   => ['gene_desc'],
            5   => ['chromosome_celera'],
            6   => ['chromosome_old_ref'],
            7   => ['chromosome_new_ref'],
            8   => ['fish_band'],
            9   => ['start_pos_celera'],
            10  => ['stop_pos_celera'],
            11  => ['strand_celera'],
            12  => ['start_pos_old_ref'],
            13  => ['stop_pos_old_ref'],
            14  => ['strand_old_ref'],
            15  => ['start_pos_new_ref'],
            16  => ['stop_pos_new_ref'],
            17  => ['strand_new_ref'],
            18  => ['curated_ref_rgd_id', undef, ';'],
            19  => ['curated_ref_pubmed_id', undef, ';'],
            20  => ['uncurated_pubmed_id', undef, ';'],
            21  => ['entrez_gene'],
            22  => ['uniprot_id', undef, ';'],
            23  => ['uncurated_ref_medline_id'],
            24  => ['genbank_nucleotide', undef, ';'],
            25  => ['tigr_id', undef, ';'],
            26  => ['genbank_protein', undef, ';'],
            27  => ['unigene_id', undef, ';'],
            28  => ['sslp_rgd_id', undef, ';'],
            29  => ['sslp_symbol', undef, ';'],
            30  => ['old_symbol', undef, ';'],
            31  => ['old_name', undef, ';'],
            32  => ['qtl_rgd_id', undef, ';'],
            33  => ['qtl_symbol'],
            34  => ['nomenclature_status'],
            35  => ['splice_rgd_id', undef, ';'],
            36  => ['splice_symbol'],
            37  => ['gene_type'],
            38  => ['ensembl_id']
        };
        
        ### Do some simple validation on the parsers, check
        ### attribute names are not duplicated
        
        foreach my $parser (keys(%$parsers)) {
            
            my $attributes = get_attribute_names($parser);
        }
    }
    
    ### _get_parser
    #
    # Internal routine to get a parser by name, will not return
    # if no such parser is available
    
    sub _get_parser {
        my ( $parser ) = @_;
        
        unless ($parser) {
            confess "Must pass a parser name";
        }
        unless ($parsers->{$parser}) {
            confess "No parser for '$parser'";
        } else {
            if ($parsers->{$parser}->{0}) {
                confess "Invalid parser '$parser' has a column 0 specified";
            }
            return $parsers->{$parser};
        }
    }

=head2 parse_row_to_named_attributes

Given the name of the file (for which a parser must be defined in this module)
and a 'row' parsed by parse_tab_delimited_file_to_array, converts the row to
a hash of named attributes, with their values. 

Additionally checks values of mandatory attributes by regular exporession, and
converts columns that hold multiple values separated by a delimiter into
anonymous arrays for subsequent use.
 
  my $parsed = GeneNomenclatureUtils::ColumnParser::parse_row_to_named_attributes(
        'GENES_RAT.txt', $entry);

=cut

    sub parse_row_to_named_attributes {
        my ( $file_name, $row, $warn_on_validation_error ) = @_;
        
        unless ($file_name) {
            confess "Must pass a file_name";
        }
        unless ($row and ref($row) =~ /ARRAY/) {
            confess "Must pass a row from the file as an ARRAY reference";
        }
        
        my $parser = _get_parser($file_name);
        
        my $parsed = {};
        foreach my $column (keys(%$parser)) {
        
            my ($attrib, $reg_ex, $split) = @{$parser->{$column}};
            
            my $adjusted_column = $column - 1;
            confess "Error in parser '$file_name'" if $adjusted_column < 0;
            my $value = $row->[$adjusted_column];
            
            ### Do we need to validate the column contents?
            if ($reg_ex) {
                unless ($value and $value =~ /$reg_ex/) {
                    print STDERR "Validation error for '$value' (col: $column) with '$reg_ex'\n";
                    print STDERR Dumper($row), "\n";
                    unless ($warn_on_validation_error) {
                        confess "Fatal - exiting";
                    }
                        
                } else {
                    print STDERR "Validated '$value' with '$reg_ex'\n" if $debug; 
                }
            }
            
            ### Do we need to split the column into a list of values
            if ($value and $split) {
                my @values = split(/$split/, $value);
                $parsed->{$attrib} = \@values;
                print STDERR "We split '$attrib' to ", Dumper(\@values), "\n" if $debug; 
            } else {
                $parsed->{$attrib} = $value;
            }
        }
        return $parsed;
    }

=head2 get_attribute_names

Given a file/parser name return a hash of the attributes available from
it on parsing a row with parse_row_to_named_attributes

  my $attributes = GeneNomenclatureUtils::ColumnParser::get_attribute_names(
     'GENES_RAT.txt');

Checks for duplications in atrribute names in the parser specifications. This
is performed automatically as part of the initial call to:
GeneNomenclatureUtils::ColumnParser::configure

=cut

    sub get_attribute_names {
        my ( $file_name ) = @_;
        
        my $parser = _get_parser($file_name);
                
        my $attributes   = {};
        foreach my $column (keys(%$parser)) {
            my $name = $parser->{$column}->[0];
        
            if ($attributes->{$name}) {
                confess "Duplicate attribute name in parser: '$name' on col: $column\n";
            }
            $attributes->{$name} = $column;
        }
        return $attributes;
    }    
}

1;
