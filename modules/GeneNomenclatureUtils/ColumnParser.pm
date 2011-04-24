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
use DPStore::Utils::SeqIDNomenclature qw(
    can_validate_id_type
    validate_id_type
);


our $debug;

{
    my $parsers;

    ### These column numbers are 1 based (like the script params)
    
    sub _configure {
        
        ### GENES_RAT.txt
        #
        # All columns (23/04/11)
        #
        # Mandatory validated columns are: 1,2,3
        
        ### format [attribute_name, mandatory, id_type, split_on]
         
        $parsers->{'RGD_dir_GENES_RAT.txt'} = {
            line_pattern => ['^#|^GENE_RGD_ID', '!'],
            
            1   => ['gene_rgd_id'                   , 'mandatory', 'rgd_id'],
            2   => ['symbol'                        , 'mandatory', 'rgd_symbol'],
            3   => ['name'                          , 'mandatory', 'anything'],
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
            18  => ['curated_ref_rgd_id'            , undef, undef           , ';'],
            19  => ['curated_ref_pubmed_id'         , undef, undef           , ';'],
            20  => ['uncurated_pubmed_id'           , undef, undef           , ';'],
            21  => ['entrez_gene'                   , undef,'entrez_gene_id'],
            22  => ['uniprot_id'                    , undef, undef           , ';'],
            23  => ['uncurated_ref_medline_id'],
            24  => ['genbank_nucleotide'            , undef, undef           , ';'],
            25  => ['tigr_id'                       , undef, undef           , ';'],
            26  => ['genbank_protein'               , undef, undef           , ';'],
            27  => ['unigene_id'                    , undef, undef           , ';'],
            28  => ['sslp_rgd_id'                   , undef, undef           , ';'],
            29  => ['sslp_symbol'                   , undef, undef           , ';'],
            30  => ['old_symbol'                    , undef, undef           , ';'],
            31  => ['old_name'                      , undef, undef           , ';'],
            32  => ['qtl_rgd_id'                    , undef, undef           , ';'],
            33  => ['qtl_symbol'],
            34  => ['nomenclature_status'],
            35  => ['splice_rgd_id'                 , undef, undef, ';'],
            36  => ['splice_symbol'],
            37  => ['gene_type'],
            38  => ['ensembl_id'                    , undef, 'ensembl_rat_gene_id', ';']
        };

        $parsers->{'RGD_dir_RGD_ORTHOLOGS'} = {
            line_pattern => ['^#|^RAT_GENE_SYMBOL', '!'],

            1   => ['rat_gene_symbol'              ,'rgd_symbol'],
            2   => ['rat_gene_rgd_id'              ,'rgd_id'],
            3   => ['rat_gene_entrez_gene_id'      , undef       , 'entrez_gene_id'],
            4   => ['human_ortholog_symbol'        , undef       , undef            , '\|'],
            5   => ['human_ortholog_rgd_id'        , undef       , 'rgd_id'],
            6   => ['human_ortholog_entrez_gene_id', undef       , 'entrez_gene_id'],
            7   => ['human_ortholog_source'],
            8   => ['mouse_ortholog_symbol'        , undef       , undef            , '\|'],
            9   => ['mouse_ortholog_rgd_id        ', undef       , 'rgd_id'],
            10  => ['mouse_ortholog_entrez_gene_id', undef       , 'entrez_gene_id'],
            11  => ['mouse_ortholog_mgi_id'        , undef       , 'mgi_id'],
            12  => ['mouse_ortholog_source']
        };        

        $parsers->{'MGI_dir_MRK_List2.rpt'} = {
            line_pattern => ['^MGI\sAccession', '!'],

            1   => ['mgi_id'        , 'mandatory', 'mgi_id'],
            2   => ['chr'],
            3   => ['cm_position'],   
            4   => ['symbol'        , 'mandatory'],
            5   => ['status'],
            6   => ['name'],
            7   => ['type'],
        };        

        $parsers->{'MGI_dir_HMD_HGNC_Accession.rpt'} = {
            line_pattern => ['.', '~'],

            1   => ['mgi_id'                    , 'mandatory'   , 'mgi_id'],
            2   => ['mouse_marker_symbol'       , 'mandatory'],
            3   => ['mouse_marker_name'],
            4   => ['mouse_entrez_gene_id'      , undef         , 'entrez_gene_id'],
            5   => ['hgnc_id'                   , undef         , 'hgnc_id'],
            6   => ['hgnc_human_marker_symbol'],
            7   => ['human_entrez_gene_id'      , undef         , 'entrez_gene_id']
        };        
        
        ### Do some simple validation on the parsers, check
        ### attribute names are not duplicated
        
        foreach my $parser_name (keys(%$parsers)) {
            
            my $attributes = get_attribute_names($parser_name);
            get_line_pattern($parser_name);
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
        _configure() unless $parsers;
        
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
        my ( $file_name, $row, $warn ) = @_;
        
        unless ($file_name) {
            confess "Must pass a file_name";
        }
        unless ($row and ref($row) =~ /ARRAY/) {
            confess "Must pass a row from the file as an ARRAY reference";
        }
        
        my $parser = _get_parser($file_name);
        
        my $parsed = {};
        foreach my $column (keys(%$parser)) {
            next if $column eq 'line_pattern';
        
            my ($attrib, $mandatory, $id_type, $split) = @{$parser->{$column}};
            
            my $adjusted_column = $column - 1;
            confess "Error in parser '$file_name'" if $adjusted_column < 0;
            my $value = $row->[$adjusted_column];
            
            ### Is the value of the column mandatory
            if ($mandatory) {
                unless ($value) {
                    if ($warn) {
                        print STDERR "No '$attrib' parsed from col: $column on\n";
                        print STDERR Dumper($row), "\n";
                    } else {
                        confess "No '$attrib' parsed from col: $column on\n"
                            . Dumper($row);
                    }
                    next;
                }
            }
            
            ### Do we need to validate the column contents?
            if ($id_type) {
                unless (validate_id_type($id_type, $value, $warn)) {
                
                    print STDERR "Validation error for '$value' (col: $column) as '$id_type'\n";
                    print STDERR Dumper($row), "\n";
                       
                } else {
                    print STDERR "Validated '$value' as '$id_type'\n" if $debug; 
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
            next if $column eq 'line_pattern';
        
            my $name      = $parser->{$column}->[0];
            my $mandatory = $parser->{$column}->[1];
            my $id_type   = $parser->{$column}->[2];
            my $split_by  = $parser->{$column}->[3];
            
            if ($id_type) {
                unless (can_validate_id_type($id_type)) {
                    confess "Don't know how to check '$id_type' in '$parser'";
                }
            }
            if ($attributes->{$name}) {
                confess "Duplicate attribute name in parser: '$name' on col: $column\n";
            }
            
            my $attribute = {};
            $attribute->{column}    = $column;
            $attribute->{id_type}   = $id_type;
            $attribute->{mandatory} = $mandatory;
            $attribute->{split_by}  = $split_by;
            
            $attributes->{$name}    = $attribute;
        }
        return $attributes;
    }
    
    sub get_line_pattern {
        my ( $file_name ) = @_;
        
        my $parser = _get_parser($file_name);
        my $line_pattern = $parser->{line_pattern};
        
        unless ( $line_pattern and ref($line_pattern) eq 'ARRAY' and @$line_pattern == 2) {
            confess "Invalid line_pattern for parser '$file_name'";
        }
        return @$line_pattern;
    }    
}

sub validate_output_attrib {
    my ( $valid, $attrib, $msg ) = @_;

    my $valid_string = join(", ", sort {$a cmp $b} keys(%$valid));
    $msg = '' unless $msg;
    
    if ($attrib) {
        $attrib = lc($attrib);
        unless ($valid->{$attrib}) {
            confess "Invalid '$attrib', $msg \n$valid_string\n\n";
        } else {
            return $attrib;
        }
    } else {
        confess "$msg\n$valid_string\n\n";
    }
}


1;
