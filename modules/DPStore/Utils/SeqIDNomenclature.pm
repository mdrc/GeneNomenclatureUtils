### release

=pod

=head1 NAME - DPStore::Utils::SeqIDNomenclature

=head1 DESCRIPTION

=head1 AUTHOR - mike_croning@hotmail.com

=cut

package DPStore::Utils::SeqIDNomenclature;

use strict;
use warnings;
use Carp;
use Config::IniFiles;
use Data::Dumper;
use Exporter;
use File::stat;
use DPStore::Utils::TabFileParser qw(
    clean_array_elements_of_whitespace
    close_data_files
    open_data_file
    parse_tab_delimited_file_to_array
    parse_tab_delimited_file_to_hash_keyed_by_column
    read_next_line_from_data_file
);
use Time::localtime;
use vars qw{ @ISA @EXPORT_OK };

@ISA = qw(Exporter);
@EXPORT_OK = qw(
    check_for_file
    check_or_translate_ids_in_file
    get_swissprot_or_trembl_acc
    lookup_names_for_interpro_accs
    parse_hgnc_all_file
    parse_hgnc_all_file_entry
    parse_hgnc_core_file
    parse_hmd_human_sequence_file
    parse_hmd_human_sequence_file_entry
    parse_mgi_hmd_human_phenotype_file
    parse_mgi_interpro_domains_report_file
    parse_mgi_interpro_report_file
    parse_mgi_interpro_report_file_entry
    parse_mgi_list_2_file
    parse_mgi_mouse_human_orthology_file
    parse_mgi_mouse_human_orthology_file_entry
    parse_mgi_mouse_human_sequence_file
    parse_mgi_mouse_human_sequence_file_entry
    parse_mgi_phenogeno_mp_file
    parse_mgi_phenotypic_allele_file
    parse_mgi_swissprot_trembl
    parse_mgi_synonym_file
    parse_mim2gene
    parse_mp_vocabulary
    parse_omim_titles
    parse_synonyms_from_hgnc_all_file
    parse_rgd_rat_genes_file
);

=head1 check_or_translate_ids_in_file

Used to compare the IDs in the specified column of a file against the
passed hash of IDs. 

$reg_ex is used to perform basic validation of the alphanumeric form of
the id, in addition to check it in the hash of IDs passed by reference.

Example call (to check)

check_or_translate_ids_in_file($file, $valid_ids_hash, 'CHECK NAME', $reg_ex
        , $id_column, $output_column, $skip_title);

Example call (to translate)

check_or_translate_ids_in_file($file, $valid_ids_hash, 'CHECK NAME', $reg_ex
        , $id_column, $output_column, $skip_title, 'translate');

=cut

sub check_or_translate_ids_in_file {
    my ( $file, $valid_ids, $check_name, $validation_pattern
        , $column_to_check, $output_column, $skip_title, $translate ) = @_;

    my $entries = parse_tab_delimited_file_to_array($file, 'clean');
    if ($skip_title) {
        my $titles = shift(@$entries);
        
        splice (@$titles, $output_column - 1, 0, $check_name);
        print join("\t", @$titles), "\n";
    }

    ### Loop over the IDs
    
    my $found             = 0;
    my $not_found         = 0;
    my $nothing_to_lookup = 0;
    my $invalid           = 0;
    my $invalid_ids       = {};
    my $not_found_ids     = {};         
    
    foreach my $entry (@$entries) {
    
        my $output;
        my $successful_lookup;
        
        my $id = $entry->[$column_to_check - 1];
        unless ($id) {
            $output = 'NOTHING_TO_CHECK';
            $nothing_to_lookup++;
        } else {
            unless ($id =~ /$validation_pattern/) {
                $output = 'INVALID';
                $invalid_ids->{$id}++;
                $invalid++;
            }
        }
        
        unless ($output) {
            if ($valid_ids->{$id}) {
                if ($translate) {
                    $output = $valid_ids->{$id};
                } else {
                    $output = 'PASS';
                }
                $successful_lookup++;
                $found++;
            } else {
                $output = 'FAIL';
                $not_found_ids->{$id}++;
                $not_found++;
            }
        }
        
        ### 
        if ($translate and !$successful_lookup) {
            $output = 'NOT_FOUND';
        }
        
        splice (@$entry, $output_column - 1, 0, $output);
        print join("\t", @$entry), "\n";
    }
    
    print STDERR "\n";
    print STDERR "PASS            : $found\n";
    print STDERR "FAIL            : $not_found\n";
    print STDERR "INVALID         : $invalid\n";
    print STDERR "NOTHING TO CHECK: $nothing_to_lookup\n";
    
    if ($not_found) {
        print STDERR "\nFAILED IDs:\n";
        foreach my $id (keys(%$not_found_ids)) {
            print STDERR "  $id", ' ' x (20 - length($id))
                , $not_found_ids->{$id}, " occurrences\n";
        }
    }
    
    if ($invalid) {
        print STDERR "\nINVALID IDs: (not matching '$validation_pattern')\n";
        foreach my $id (keys(%$invalid_ids)) {
            print STDERR "  $id", ' ' x (20 - length($id))
                , $invalid_ids->{$id}, " occurrences\n";
        }
    }
    print STDERR "\n";
}

### parse_omim_titles
#
# Looks for a file in $ENV{OMIM_dir} called omim.txt
#
# my $parsed_by_omim_id = parse_omim_titles();
#
# print $parsed_by_omim_id->{256840};

sub parse_omim_titles {
    my ( $output ) = @_;
    
    my $dir  = 'OMIM_dir';
    my $file = 'omim.txt';
    my $file_spec = check_for_file($dir, $file);
    
    my $parsed_by_omim_id = {};
    my $count = 0;
    
    open_data_file('omim', $file_spec);
    while (my $line = read_next_line_from_data_file('omim')) {
        
        chomp($line);
        if ($line eq '*FIELD* TI') {
            $count++;
        
            my $line2 = read_next_line_from_data_file('omim');
            unless ($line2 =~ /^\d/) {
                $line2 =~ s/^.//g;
            }
            
            unless ($line2 and $line2 =~ /^\d/) {
                confess "Error '$line' '$line2'";
            }
            chomp $line2;
            my @fields = split(/\s/, $line2, 2);
            
            $parsed_by_omim_id->{$fields[0]} = $fields[1];
            
        }
    }
    close_data_files();
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed    : $file_spec\n";
    print STDERR "File Date : $file_modified\n";
    print STDERR "Total     : ", scalar(keys(%$parsed_by_omim_id)), "\n";
     
    return ($parsed_by_omim_id);    
}


### parse_mgi_phenogeno_mp_file
#
# Looks for a file in $ENV{MGI_dir} called MGI_PhenoGenoMP.rpt
#
# my ($parsed_by_mgi_id, $unique_parsed_by_mgi_id)
#     = parse_mgi_phenogeno_mp_file();
#
# print Dumper($unique_parsed_by_mgi_id->{'MGI:95819'})
#
# Returns references to two hashes, keyed by mgi_id, each value
# itself being a hash reference, the first one being a full 
# parse of the file, the second being made unique to MP ID.

sub parse_mgi_phenogeno_mp_file {
    
    my $file = 'MGI_PhenoGenoMP.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);

    my $parsed_by_mgi_id        = {};
    my $unique_parsed_by_mgi_id = {};

    open_data_file('mgi', $file_spec);
    
    my $multiple_allele_count = 0;
    my $lines_parsed          = 0;
    
    while (my $line = read_next_line_from_data_file('mgi')) {
     
        $lines_parsed++;
        chomp($line);
        my @fields = split("\t", $line);
        clean_array_elements_of_whitespace(\@fields);
        
        my $allelic_comp  = $fields[0];
        my $genetic_bgrnd = $fields[1];
        my $mp_id         = $fields[2];
        my $pubmed_id     = $fields[3];
        my $mgi_ids       = $fields[4];
        
        if (index($mgi_ids, ',') > 0) {
            $multiple_allele_count++;
            next;
        }
        my $mgi_id = $mgi_ids;
        unless ($mgi_id and $mgi_id =~ /^MGI:\d+$/) {
            confess "Bad MGI ID on '$mgi_id' on '$line'";
        }
        
        unless ($mp_id and $mp_id =~ /MP:\d+$/) {
            confess "Bad MP ID on '$line'";
        }
        
        my $entry = {};
        $entry->{'allelic_comp'}  = $allelic_comp;
        $entry->{'genetic_bgrnd'} = $genetic_bgrnd;
        $entry->{'mp_id'}         = $mp_id;
        $entry->{'pubmed_id'}     = $pubmed_id;
        $entry->{'mgi_id'}        = $mgi_id;
        
        $parsed_by_mgi_id->{$mgi_id}        ||= [];
        $unique_parsed_by_mgi_id->{$mgi_id} ||= {};
        
        push(@{$parsed_by_mgi_id->{$mgi_id}}, $entry);
        $unique_parsed_by_mgi_id->{$mgi_id}->{$mp_id}++;
    }
    close_data_files();

    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Warning                 : Only single allele knockouts are parsed\n";
    print STDERR "Parsed                  : $file_spec\n";
    print STDERR "File Date               : $file_modified\n";
    print STDERR "MGI IDs                 : ", scalar(keys(%$parsed_by_mgi_id)), "\n";
    print STDERR "Multiple alleles skipped: $multiple_allele_count\n";
    print STDERR "Lines parsed            : $lines_parsed\n";
    return ($parsed_by_mgi_id, $unique_parsed_by_mgi_id);
}


### parse_mp_vocabulary 
#
# Looks for a file in $ENV{MGI_dir} called VOC_MammalianPhenotype.rpt
#
# my $parsed_by_mp_id  = parse_mp_vocabulary();
# print $parsed_by_mp_id->{'MP:0001393'}'
#
# ataxia

sub parse_mp_vocabulary {

    my $file      = 'VOC_MammalianPhenotype.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);

    my $parsed_by_mp_id = {};

    open_data_file('mgi', $file_spec);

    my $lines_parsed          = 0;
    my $mp_id_duplicate_count = 0;
    my $no_description_count  = 0;
    
    while (my $line = read_next_line_from_data_file('mgi')) {

        $lines_parsed++;
        chomp($line);
        my @fields = split("\t", $line);
        clean_array_elements_of_whitespace(\@fields);
        
        my $mp_id       = $fields[0];
        my $name        = $fields[1]
            or confess "No name on '$line'";
        my $description = $fields[2];
        unless ($description) {
            $no_description_count++;
        }
        
        unless ($mp_id and $mp_id =~ /MP:\d+$/) {
            confess "Bad MP ID on '$line'";
        }
        
        my $entry = {};
        $entry->{'accession'}   = $mp_id;
        $entry->{'name'}        = $name;
        $entry->{'description'} = $description;
        
        if ($parsed_by_mp_id->{$mp_id}) {
            $mp_id_duplicate_count++;
        }
        $parsed_by_mp_id->{$mp_id} = $entry;           
        
    }
    close_data_files();


    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed                   : $file_spec\n";
    print STDERR "File Date                : $file_modified\n";
    print STDERR "MP IDs                   : ", scalar(keys(%$parsed_by_mp_id)), "\n";
    print STDERR "Terms without description: $no_description_count\n";
    print STDERR "Lines parsed             : $lines_parsed\n"; 
    
    return ($parsed_by_mp_id);
}


{
    my ($mgi_swiss, $mgi_trembl);

    sub parse_mgi_swissprot_trembl {

        my $swiss_file  = 'MRK_SwissProt.rpt';
        my $trembl_file = 'MRK_SwissProt_TrEMBL.rpt';

        my $swiss_file_spec   = check_for_file('MGI_dir', $swiss_file);
        my $trembl_file_spec  = check_for_file('MGI_dir', $trembl_file);

        $mgi_swiss  = parse_tab_delimited_file_to_hash_keyed_by_column($swiss_file_spec, 1);
        $mgi_trembl = parse_tab_delimited_file_to_hash_keyed_by_column($trembl_file_spec, 1);

        my $swiss_file_modified = ctime(stat($swiss_file_spec)->mtime);
        print STDERR "Parsed (SWISS) : $swiss_file_spec\n";
        print STDERR "File Date      : $swiss_file_modified\n";
        print STDERR "MGI IDs        : ", scalar(keys(%$mgi_swiss)), "\n\n";

        my $trembl_file_modified = ctime(stat($trembl_file_spec)->mtime);
        print STDERR "Parsed (TREMBL): $trembl_file_spec\n";
        print STDERR "File Date      : $trembl_file_modified\n";
        print STDERR "MGI IDs        : ", scalar(keys(%$mgi_trembl)), "\n\n";

        return ($mgi_swiss, $mgi_trembl);
    }

    sub get_swissprot_or_trembl_acc {
        my ( $mgi_id ) = @_;
        
        unless ($mgi_swiss and $mgi_trembl) {
            confess "Must call: parse_mgi_swissprot_trembl first";
        }

        unless ($mgi_id) {
            confess "Must pass a Swiss/Trembl/UniProt accession";
        }        

        my $uniprot_acc;
        my $mode;
        my $mgi_entry = $mgi_swiss->{$mgi_id};
        if ($mgi_entry and $mgi_entry->[6]) {
            $uniprot_acc = $mgi_entry->[6];
            $mode = 'swiss';
            if (index($uniprot_acc, " ") >= 0) {
                $uniprot_acc =~ s/\s.*$//;
                $mode .= ' multiple';
            }
        }
        unless ($uniprot_acc) {
            my $mgi_entry = $mgi_trembl->{$mgi_id};
            if ($mgi_entry and $mgi_entry->[6]) {
                $uniprot_acc = $mgi_entry->[6];
                $mode = 'trembl';
                if (index($uniprot_acc, " ") >= 0) {
                    $uniprot_acc =~ s/\s.*$//;
                    $mode .= ' multiple';
                }
            }
        }
        
        return ($uniprot_acc, $mode);
    }
}


### parse_mgi_mouse_human_sequence_file_entry

sub parse_mgi_mouse_human_sequence_file_entry {
    my ( $mgi ) = @_;
    
    unless ($mgi) {
        confess "Must pass a line from MGI_MouseHumanSequence.rpt "
            . "parsed into an array by reference";
    } 

    my $entry = {};
    
    $entry->{mgi_id}               = $mgi->[0] or confess "No MGI ID";   
    $entry->{mouse_gene_symbol}    = $mgi->[1] or confess "No MGI symbol";
    $entry->{mouse_name}           = $mgi->[2] or confess "No mouse name";
    $entry->{cm_pos}               = $mgi->[3];
    $entry->{mouse_entrez_gene_id} = $mgi->[4];
    $entry->{ncbi_gene_chr}        = $mgi->[5];
    $entry->{ncbi_gene_start}      = $mgi->[6];
    $entry->{ncbi_gene_end}        = $mgi->[7];
    $entry->{ncbi_gene_strand}     = $mgi->[8];
    $entry->{ensembl_gene_id}      = $mgi->[9];
    $entry->{ensembl_gene_chr}     = $mgi->[10];
    $entry->{ensembl_gene_start}   = $mgi->[11];
    $entry->{ensembl_gene_end}     = $mgi->[12];
    $entry->{ensembl_gene_strand}  = $mgi->[13];
    $entry->{vega_gene_id}         = $mgi->[14];
    $entry->{vega_gene_chr}        = $mgi->[15];
    $entry->{vega_gene_start}      = $mgi->[16];
    $entry->{vega_gene_end}        = $mgi->[17];
    $entry->{vega_gene_strand}     = $mgi->[18];
    $entry->{mouse_genbank_ids}    = $mgi->[19];
    $entry->{mouse_unigene_ids}    = $mgi->[20];
    $entry->{mouse_refseq_ids}     = $mgi->[21];
    $entry->{mouse_swissprot_ids}  = $mgi->[22];
    $entry->{mouse_interpro_ids}   = $mgi->[23];
    $entry->{mouse_synonyms}       = $mgi->[24];
    $entry->{human_entrez_gene_id} = $mgi->[25];
    $entry->{human_gene_symbol}    = $mgi->[26];
    $entry->{human_name}           = $mgi->[27];
    $entry->{human_chr}            = $mgi->[28];
    $entry->{human_refseq_ids}     = $mgi->[29];
    $entry->{human_synonyms}       = $mgi->[30];

    return $entry;
}

### parse_mgi_mouse_human_orthology_file_entry

sub parse_mgi_mouse_human_orthology_file_entry {
    my ( $mgi ) = @_;
    
    unless ($mgi) {
        confess "Must pass a line from HMD_HGNC_Accession.rpt "
            . "parsed into an array by reference";
    } 

    my $entry = {};
    
    $entry->{mgi_id}               = $mgi->[0] or confess "No MGI ID";   
    $entry->{mouse_gene_symbol}    = $mgi->[1] or confess "No MGI symbol";
    $entry->{mouse_name}           = $mgi->[2] or confess "No Mouse name";
    $entry->{mouse_entrez_gene_id} = $mgi->[3];
    $entry->{human_hgnc_id}        = $mgi->[4];
    $entry->{human_gene_symbol}    = $mgi->[5];
    $entry->{human_entrez_gene_id} = $mgi->[6];
    
    return $entry;
}

### parse_mgi_mouse_human_orthology_file
#
# Looks for a file in $ENV{MGI_dir} called  HMD_HGNC_Accession.rpt

sub parse_mgi_mouse_human_orthology_file {
    my ( $allow_dups ) = @_;
    
    my $file = 'HMD_HGNC_Accession.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);
    
    my $parsed_by_mgi_id
        = parse_tab_delimited_file_to_hash_keyed_by_column($file_spec, 1, $allow_dups);
        
    my $parsed_by_hgnc_symbol
        = parse_tab_delimited_file_to_hash_keyed_by_column(
            $file_spec, 6, $allow_dups, 'skip_blank_keys'
    );

    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed      : $file_spec\n";
    print STDERR "File Date   : $file_modified\n";
    print STDERR "MGI IDs     : ", scalar(keys(%$parsed_by_mgi_id)), "\n";
    print STDERR "HGNC symbols: ", scalar(keys(%$parsed_by_hgnc_symbol)), "\n\n";
    return ($parsed_by_mgi_id, $parsed_by_hgnc_symbol);
}

sub parse_mgi_interpro_report_file {
    
    my $file = 'MRK_InterPro.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);
    
    open_data_file('mgi', $file_spec);
    
    my $parsed_by_mgi_id = {};
    while (my $line = read_next_line_from_data_file('mgi')) {

        chomp($line);
        my @fields = split(/\t/, $line);
        confess "Error" unless @fields == 3;
        
        my $mgi_id = $fields[0];
        
        if ($parsed_by_mgi_id->{$mgi_id}) {
            confess "Duplicate for '$mgi_id'";
        }
        $parsed_by_mgi_id->{$mgi_id} = $fields[2];
    }
    close_data_files();
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed      : $file_spec\n";
    print STDERR "File Date   : $file_modified\n";
    print STDERR "MGI IDs     : ", scalar(keys(%$parsed_by_mgi_id)), "\n";
    return ($parsed_by_mgi_id);
}

sub parse_mgi_interpro_domains_report_file {
    
    my $file = 'MGI_InterProDomains.sql.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);
    
    open_data_file('mgi', $file_spec);
    
    my $parsed_by_ipr_acc = {};
    while (my $line = read_next_line_from_data_file('mgi')) {

        $line =~ s/^\s+//g;
        $line =~ s/\s+$//g;
        
        next unless $line =~ /^IPR/;
        
        chomp($line);
        my @fields = split(/\s+/, $line, 2);
        confess "Error" unless @fields == 2;
        
        my $ipr_acc = $fields[0];
        unless ($ipr_acc =~ /^IPR\d+/) {
            confess "Error with '$ipr_acc'";
        }
        if ($parsed_by_ipr_acc->{$ipr_acc}) {
            confess "Duplicate for '$ipr_acc'";
        }
        $parsed_by_ipr_acc->{$ipr_acc} = $fields[1];
    }
    close_data_files();
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed       : $file_spec\n";
    print STDERR "File Date    : $file_modified\n";
    print STDERR "InterPro ACCs: ", scalar(keys(%$parsed_by_ipr_acc)), "\n";
    return ($parsed_by_ipr_acc);
}

sub parse_mgi_interpro_report_file_entry {
    my ( $entry ) = @_;
    
    unless ($entry) {
        return [];
    }
    
    my @interpro_accs = split(/\s/, $entry);
    
    my $interpro_accs = [];
    foreach my $acc (@interpro_accs) {
        unless ($acc =~ /^IPR\d+$/) {
            confess "Error";
        }
        push (@$interpro_accs, $acc); 
    }
    return $interpro_accs;
}

sub lookup_names_for_interpro_accs {
    my ( $interpro_accs, $lookup ) = @_;
    
    unless ($interpro_accs) {
        return {};
    }
    unless (ref($interpro_accs) =~ /ARRAY/) {
        confess "Must pass interpro accs as an ARRAY reference";
    }
    unless ($lookup and ref($lookup) =~ /HASH/) {
        confess "Must pass InterPro name lookup as an HASH reference"; 
    }
    
    my $interpro_names_by_acc = {};
    foreach my $acc (@$interpro_accs) {
        
        my $name = $lookup->{$acc}
            or confess "Could not lookup: '$acc'";
        
        $interpro_names_by_acc->{$acc} = $name;
    }
    return $interpro_names_by_acc;
}



### parse_mim2gene
#
# Looks for a file in $ENV{ENTREZ_dir} called mim2gene

sub parse_mim2gene {

    my $dir  = 'ENTREZ_dir';
    my $file = 'mim2gene';
    my $file_spec = check_for_file($dir, $file);
    
    my $parsed_gene_omim      = {};
    my $parsed_phenotype_omim = {};

    open_data_file('mim', $file_spec);
    my $phenotype_duplicates = 0;
    my $gene_duplicates      = 0;
    while (my $line = read_next_line_from_data_file('mim')) {
        
        chomp($line);
        next unless $line =~ /^\d/;
        
        my @fields = split(/\t/, $line);
        confess "Error" unless @fields == 3;
        
        my $omim   = $fields[0]
            or confess "No OMIM on '$line'";
        my $entrez = $fields[1]
            or confess "No ENTREZ ID on '$line'";    
        my $type   = $fields[2]
            or confess "No gene|phenotype on '$line'";
        
        if ($type eq 'phenotype') {
            if ($parsed_phenotype_omim->{$entrez}) {
                $phenotype_duplicates++;
            }
            $parsed_phenotype_omim->{$entrez} ||= [];
            push (@{$parsed_phenotype_omim->{$entrez}}, $omim);
        } elsif ($type eq 'gene') {
            if ($parsed_gene_omim->{$entrez}) {
                $gene_duplicates++;
            }
            $parsed_gene_omim->{$entrez} ||= [];
            push(@{$parsed_gene_omim->{$entrez}}, $omim);
        } else {
            confess "Error with gene|phenotype on '$line'";
        }
    }
    close_data_files();
    
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed              : $file_spec\n";
    print STDERR "File Date           : $file_modified\n";
    print STDERR "OMIM phenotype      : ", scalar(keys(%$parsed_phenotype_omim)), "\n";
    print STDERR "OMIM gene           : ", scalar(keys(%$parsed_gene_omim)), "\n";
    print STDERR "Phenotype multiples : $phenotype_duplicates\n";
    print STDERR "Gene duplicates     : $gene_duplicates\n\n";
    
    return ($parsed_gene_omim, $parsed_phenotype_omim);
}

### parse_mgi_hmd_human_phenotype_file
#
# Looks for a file in $ENV{MGI_dir} called HMD_HumanPhenotype.rpt

sub parse_mgi_hmd_human_phenotype_file {

    my $dir  = 'MGI_dir';
    my $file = 'HMD_HumanPhenotype.rpt';
    my $file_spec = check_for_file($dir, $file);
    
    my $parsed_by_mgi_id         = {};
    my $parsed_by_mgi_id_nervous = {};

    open_data_file('mgi', $file_spec);
    my $phenotype_duplicates = 0;
    my $gene_duplicates      = 0;
    while (my $line = read_next_line_from_data_file('mgi')) {
        
        chomp($line);
        
        my @fields = split(/\t+/, $line);
        next unless @fields == 5;
        clean_array_elements_of_whitespace(\@fields);
        
        my $mgi_id = $fields[3];
        unless ($mgi_id and $mgi_id =~ /^MGI:/) {
            confess "Error with MGI ID on '$mgi_id'";
        }
        
        my @phenotype_ids = split(/\s+/, $fields[4]);
        
        my $nervous;
        my $phenotypes = [];
        foreach my $phenotype_id (@phenotype_ids) {
        
            $nervous++ if $phenotype_id eq 'MP:0003631';
            push (@$phenotypes, $phenotype_id);
        }
        
        $parsed_by_mgi_id->{$mgi_id} = $phenotypes;
        if ($nervous) {
            $parsed_by_mgi_id_nervous->{$mgi_id} = $phenotypes; 
        }
    }
    close_data_files();
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed                 : $file_spec\n";
    print STDERR "File Date              : $file_modified\n";
    print STDERR "MGI IDs with phenotypes         : ";
    print STDERR scalar(keys(%$parsed_by_mgi_id)), "\n";
    print STDERR "MGI IDs with nervous phenotypes : ";
    print STDERR scalar(keys(%$parsed_by_mgi_id_nervous)), "\n\n";

    return ($parsed_by_mgi_id, $parsed_by_mgi_id_nervous);
}

### parse_mgi_synonym_file
#
# Looks for a file in $ENV{MGI_dir} MRK_Synonym.sql.rpt

sub parse_mgi_synonym_file {
    
    my $file = 'MRK_Synonym.sql.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);
    
    open_data_file('mgi', $file_spec);
    
    my $parsed_by_mgi_id = {};
    while (my $line = read_next_line_from_data_file('mgi')) {

        chomp($line);       
        next unless $line =~ /^ MGI:/;
                
        my @fields = (substr($line, 1, 30)
            , substr($line, 32, 8)
            , substr($line, 41, 11)
            , substr($line, 53, 50)
            , substr($line, 104, 90)
            );
        clean_array_elements_of_whitespace(\@fields);
        my ($mgi_id, $chr, $position, $marker_symbol
            , $synonym) = @fields;
        
        unless ($mgi_id and $mgi_id =~ /^MGI:\d+/) {
            confess "Error";

        }
        unless ($synonym) {
            confess "Error with $mgi_id";
        }        

        $parsed_by_mgi_id->{$mgi_id} ||= [];
        push (@{$parsed_by_mgi_id->{$mgi_id}}, $synonym);
    }
    close_data_files();
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed     : $file_spec\n";
    print STDERR "File Date  : $file_modified\n";
    print STDERR "MGI symbols: ", scalar(keys(%$parsed_by_mgi_id)), "\n\n";
    
    return ($parsed_by_mgi_id);
}

### parse_synonyms_from_hgnc_all_file
#
# Looks for a file in $ENV:HGNC_dir} called hgnc_all_data.txt

sub parse_synonyms_from_hgnc_all_file {

    my $file = 'hgnc_all_data.txt';
    my $file_spec = check_for_file('HGNC_dir', $file);

    open_data_file('hgnc_symbol', $file_spec);

    my $parsed_by_hgnc_id = {};
    while (my $line = read_next_line_from_data_file('hgnc_symbol')) {
    
        chomp($line);
        my @fields = split(/\t/, $line);
    
        my ($hgnc_id, $approved_symbol, $approved_name, $status
            , $prev_symbols, $prev_names, $aliases) = ($fields[0]
            , $fields[1], $fields[2], $fields[3], $fields[5]
            , $fields[6], $fields[7]);
        next unless $status eq 'Approved';
        
        if ($hgnc_id) {
            $hgnc_id = 'HGNC:' . $hgnc_id;
        } else {
            confess "No HGNC ID on '$line'";
        }
        
        $parsed_by_hgnc_id->{$hgnc_id} ||= [];
        push (@{$parsed_by_hgnc_id->{$hgnc_id}}, $approved_symbol);

        if (length($prev_symbols)) {

            my @prev_symbols = split(/, /, $prev_symbols);
            foreach my $prev_symbol (@prev_symbols) {
                push (@{$parsed_by_hgnc_id->{$hgnc_id}}, $prev_symbol);
            }
        }

        if (length($aliases)) {
            my @aliases = split(/, /, $aliases);
            foreach my $alias (@aliases) {
                push (@{$parsed_by_hgnc_id->{$hgnc_id}}, $alias);
            }
        }
    }        
    close_data_files();

    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed   : $file_spec\n";
    print STDERR "File Date: $file_modified\n";
    print STDERR "HGNC IDs : ", scalar(keys(%$parsed_by_hgnc_id)), "\n\n";
    
    return ($parsed_by_hgnc_id);
}

sub parse_hgnc_all_file {

    my $file = 'hgnc_all_data.txt';
    my $file_spec = check_for_file('HGNC_dir', $file);

    open_data_file('hgnc_symbol', $file_spec);

    my $parsed_by_hgnc_id        = {};
    my $parsed_by_entrez_gene_id = {};
    while (my $line = read_next_line_from_data_file('hgnc_symbol')) {
    
        chomp($line);
        my @fields = split(/\t/, $line);
        unless ($fields[0]) {
            confess "Error";
        }
        next if $fields[0] eq 'HGNC ID';
        
        $fields[0] = 'HGNC:' . $fields[0];
        if ($parsed_by_hgnc_id->{$fields[0]}) {
            confess "Duplicate for '$fields[0]'";
        }
        
        my $ref = \@fields;
        $parsed_by_hgnc_id->{$fields[0]} = $ref;
        
        if ($fields[14]) {
            if ($parsed_by_entrez_gene_id->{$fields[14]}) {
                confess "Error - duplication by EntrezGene ID '$fields[14]'";
            }
            $parsed_by_entrez_gene_id->{$fields[14]} = $ref;
        }
    }
        
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed   : $file_spec\n";
    print STDERR "File Date: $file_modified\n";
    print STDERR "HGNC IDs : ", scalar(keys(%$parsed_by_hgnc_id)), "\n\n";
    
    return ($parsed_by_hgnc_id, $parsed_by_entrez_gene_id);
} 

sub parse_hgnc_all_file_entry {
    my ( $hgnc ) = @_;
    
    unless ($hgnc) {
        confess "Must pass a line parsed from 'hgnc_all_data.txt'";
    }

    my $entry = {};
    $entry->{hgnc_id}                   = $hgnc->[ 0];
    $entry->{approved_symbol}           = $hgnc->[ 1];
    $entry->{approved_name}             = $hgnc->[ 2];
    $entry->{status}                    = $hgnc->[ 3];
    $entry->{locus_type}                = $hgnc->[ 4];
    $entry->{previous_symbols}          = $hgnc->[ 5];
    $entry->{previous_names}            = $hgnc->[ 6];
    $entry->{aliases}                   = $hgnc->[ 7];
    $entry->{chromosome}                = $hgnc->[ 8];
    $entry->{date_approved}             = $hgnc->[ 9];
    $entry->{date_modified}             = $hgnc->[10];
    $entry->{date_name_changed}         = $hgnc->[11];
    $entry->{accession_numbers}         = $hgnc->[12];
    $entry->{enzyme_ids}                = $hgnc->[13];
    $entry->{entrez_gene_id}            = $hgnc->[14];
    $entry->{mgi_id}                    = $hgnc->[15];
    $entry->{specialist_database_links} = $hgnc->[16];
    $entry->{pubmed_ids}                = $hgnc->[17];
    $entry->{refeq_ids}                 = $hgnc->[18];
    $entry->{gene_family_name}          = $hgnc->[19];
    $entry->{gdb_id}                    = $hgnc->[20];
    $entry->{entrez_gene_id_2}          = $hgnc->[21];
    $entry->{omim_id}                   = $hgnc->[22];
    $entry->{refseq_id}                 = $hgnc->[23];
    $entry->{uniprot_id}                = $hgnc->[24];
    
    return $entry;
}
=head2 parse_rgd_genes_file 

Looks for a file in $ENV{RGD_dir} called 'GENES_RAT.txt'

my ($parsed_by_rgd_symbol, $parsed_by_rgd_id, $approved_name_by_rgdd_id)
    = parse_rgd_genes_file();

An optional parameter allows the case of the gene symbols parsed to be
modified, pass 'lc' or 'uc' to convert all the parsed symbols used as
keys returned in $parsed_by_rgd_symbol, to upper or lower case.

=cut

sub parse_rgd_rat_genes_file {
    my ( $case ) = @_;
    
    return(
       _parse_symbols_ids_names_type_file( 'GENES_RAT.txt', 'RGD_dir', $case,
        '^\d+\s', 2, 1, 3,  'WITHDRAWN', 'eq', 34)
    );
}        

### _parse_symbols_ids_names_type_file
#
# Internal subroutine used to parse symbols, IDs and names from a
# tab-delimited nomenclature file 

sub _parse_symbols_ids_names_type_file {
    my ( $file, $dir, $case, $regex_for_line, $symbol_column
        , $id_column, $name_column, $skip_status, $skip_type, $skip_column ) = @_;
    
    if ($case and $case !~ /^[l|u]c$/) {
        confess "Case must be 'lc' or 'uc'";
    }

    my $file_spec = check_for_file($dir, $file);

    my $parsed_by_symbol    = {};
    my $parsed_by_id        = {};
    my $approved_name_by_id = {};
    my $skipped             = 0;

    open_data_file('file', $file_spec);
    while (my $line = read_next_line_from_data_file('file')) {
        
        chomp($line);
        
        $line =~ s/^\s+//;
        $line =~ s/\s$//;
        next unless $line =~ /$regex_for_line/;

        my @fields = split(/\t/, $line);
        clean_array_elements_of_whitespace(\@fields);
        
        my $symbol = $fields[$symbol_column - 1];
        my $id     = $fields[$id_column - 1];
        my $name   = $fields[$name_column -1];
        
        if ($skip_status) {
            if ($skip_type eq 'eq') {
                if ($fields[$skip_column - 1] eq $skip_status) {
                    $skipped++;
                    next;
                }
            } elsif ($skip_type eq 'ne') {
                if ($fields[$skip_column - 1] ne $skip_status) {
                    $skipped++;
                    next;
                }
            } else {
                confess "Error with skip_type '$skip_type'";
            }
        }
        
        ### Do we need to do case conversion on the symbols?
        my $mod_case_symbol = $symbol;
        if ($case) {
            if ($case eq 'lc') {
                $mod_case_symbol = lc($mod_case_symbol);
            } else {
                $mod_case_symbol = uc($mod_case_symbol);
            }
        }
        
        $parsed_by_symbol->{$mod_case_symbol} = $id;
        $parsed_by_id->{$id}                  = $symbol;
        $approved_name_by_id->{$id}           = $name;
    }
    close_data_files();
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed         : $file_spec\n";
    print STDERR "File Date      : $file_modified\n";
    print STDERR "Parsed symbols : ", scalar(keys(%$parsed_by_symbol)), "\n";
    if ($skip_status) {
        print STDERR "Skipped symbols: $skipped (by $skip_type '$skip_status'";
        print STDERR " in Col:$skip_column)\n";
    }
    print STDERR "\n";
    
    return ($parsed_by_symbol, $parsed_by_id, $approved_name_by_id);
}        


=head2 parse_mgi_list_2_file

Looks for a file in $ENV{MGI_dir} called MRK_List2.rpt

my ($parsed_by_mgi_symbol, $parsed_by_mgi_id, $approved_name_by_mgi_id)
    = parse_mgi_list_2_file();

An optional parameter allows the case of the gene symbols parsed to be
modified, pass 'lc' or 'uc' to convert all the parsed symbols used as
keys returned in $parsed_by_mgi_symbol, to upper or lower case.

=cut

sub parse_mgi_list_2_file {
    my ( $case ) = @_;

    return(
       _parse_symbols_ids_names_type_file( 'MRK_List2.rpt', 'MGI_dir', $case,
        '^MGI:\d+', 4, 1, 6, 'Gene', 'ne', 7 )
    );
}


### parse_mgi_mouse_human_sequence_file
#
# Looks for a file in $ENV{MGI_dir} called MGI_MouseHumanSequence.rpt

sub parse_mgi_mouse_human_sequence_file {
    my ( $allow_dups ) = @_;
    
    my $file = 'MGI_MouseHumanSequence.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);
    
    my $parsed_by_mgi_id  = parse_tab_delimited_file_to_hash_keyed_by_column(
        $file_spec, 1, $allow_dups);
    my $parsed_by_mgi_sym = parse_tab_delimited_file_to_hash_keyed_by_column(
        $file_spec, 2, $allow_dups);
    
    my $parsed_by_hgnc_symbol
                          = parse_tab_delimited_file_to_hash_keyed_by_column(
        $file_spec, 27, $allow_dups, 'skip_missing_keys');
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed      : $file_spec\n";
    print STDERR "File Date   : $file_modified\n";
    print STDERR "MGI IDs     : ", scalar(keys(%$parsed_by_mgi_id)), "\n";
    print STDERR "MGI symbols : ", scalar(keys(%$parsed_by_mgi_sym)), "\n";
    print STDERR "HGNC symbols: ", scalar(keys(%$parsed_by_hgnc_symbol)), "\n\n";
    return ($parsed_by_mgi_id, $parsed_by_mgi_sym, $parsed_by_hgnc_symbol);
}

### parse_mgi_phenotypic_allele_file
#
# Looks for a file in $ENV{MGI_dir} called MGI_PhenotypicAllele.rpt

sub parse_mgi_phenotypic_allele_file {
    my ( $avoid_gene_traps ) = @_;
    
    my $file = 'MGI_PhenotypicAllele.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);

    my $parsed_by_mgi_id = {};

    open_data_file('mgi', $file_spec);
    
    my $no_mgi_id = 0;
    my $skipped_gene_traps = 0;
    while (my $line = read_next_line_from_data_file('mgi')) {
        
        chomp($line);
        next unless $line =~ /^MGI:/;
        
        my @fields = split(/\t/, $line);
        
        my $mgi_id = $fields[5];
        unless ($mgi_id) {
            $no_mgi_id++;
            next;
        }
        if ($fields[3] eq 'Gene trapped'and $avoid_gene_traps) {
            $skipped_gene_traps++;
            next;
        }
        
        $parsed_by_mgi_id->{$mgi_id} ||= [];
        push(@{$parsed_by_mgi_id->{$mgi_id}}, [@fields]);
    }
    close_data_files();

    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed                : $file_spec\n";
    print STDERR "File Date             : $file_modified\n";
    print STDERR "MGI IDs               : ", scalar(keys(%$parsed_by_mgi_id)), "\n";
    print STDERR "Gene traps excluded   : $skipped_gene_traps\n" if $skipped_gene_traps;
    print STDERR "Alleles without MGI ID: $no_mgi_id\n\n";
    return ($parsed_by_mgi_id);
}

### parse_hgnc_core_file
#
# Looks for a file in $ENV{HGNC_data} called hgnc_core_data.txt

sub parse_hgnc_core_file {
    my ( $case ) = @_;
    
    if ($case and $case !~ /^[l|u]c$/) {
        confess "Case must be 'lc' or 'uc'";
    }
   
    my $file = 'hgnc_core_data.txt';
    my $file_spec = check_for_file('HGNC_dir', $file);

    my $parsed_by_symbol         = {};
    my $parsed_by_hgnc_id        = {};
    my $approved_name_by_hgnc_id = {};
    
    open_data_file('hgnc', $file_spec);
    while (my $line = read_next_line_from_data_file('hgnc')) {
        chomp($line);
        next if $line =~ /^HGNC ID/;
        
        my @fields = split(/\t/, $line);
        
        my $hgnc_id       = $fields[0] or confess "No HGNC ID on '$line'";
        my $symbol        = $fields[1] or confess "No approved symbol on '$line'";
        my $approved_name = $fields[2] or confess "No approved name on '$line'";
        my $status        = $fields[3] or confess "No status on '$line'";
        next unless $status eq 'Approved';
        
        $hgnc_id = 'HGNC:' . $hgnc_id;
     
        ### Do we need to do case conversion on the HGNC Symbols?
        my $mod_case_symbol = $symbol;
        if ($case) {
            if ($case eq 'lc') {
                $mod_case_symbol = lc($symbol);
            } else {
                $mod_case_symbol = uc($symbol);
            }
        }
          
        if ($parsed_by_symbol->{$symbol}) {
            confess "Ambiguous HGNC symbol: '$symbol'";
        }
        $parsed_by_symbol->{$mod_case_symbol} = $hgnc_id;
        
        if ($parsed_by_hgnc_id->{$hgnc_id}) {
            confess "Ambiguous HGNC ID: '$hgnc_id";
        }
        $parsed_by_hgnc_id->{$hgnc_id} = $symbol;
        
        $approved_name_by_hgnc_id->{$hgnc_id} = $approved_name; 
    }
    close_data_files();

    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed                : $file_spec\n";
    print STDERR "File Date             : $file_modified\n";
    print STDERR "Parsed by HGNC symbol : ", scalar(keys(%$parsed_by_symbol)), "\n";
    print STDERR "Parsed by HGNC ID     : ", scalar(keys(%$parsed_by_hgnc_id)), "\n";
    
    return ($parsed_by_symbol, $parsed_by_hgnc_id, $approved_name_by_hgnc_id);
}

### check_for_file
#
# Expects a env_dir and file name, checks if the file exists and has non-zero
# Size in the directory pointed to by $ENV{MGI_dir}

sub check_for_file {
    my ( $env_dir, $file ) = @_;
    
    unless ($env_dir) {
        confess "Must pass a env_dir to check";
    }
    unless ($ENV{$env_dir}) {
        confess "Set environment variable '$env_dir'";
    }

    my $path = $ENV{$env_dir};
    unless (-d $path) {
        confess "Can't read directory '$path'";
    }
    
    $path .= '/' unless $path =~ /\/$/;
    my $file_spec = $path . $file;
    
    unless (-e $file_spec and -s $file_spec) {
        confess "Can't read: '$file_spec'";
    }
    return $file_spec;
}

### parse_hmd_human_sequence_file
#
# To be written

sub parse_hmd_human_sequence_file {
    
    my $file = 'HMD_HumanSequence.rpt';
    my $file_spec = check_for_file('MGI_dir', $file);

    open_data_file('mgi', $file_spec);

    my $duplicate_count = 0;

    my $parsed_by_mgi_id = {};
    while (my $line = read_next_line_from_data_file('mgi')) {

        chomp($line);
        my @fields = split(/\t/, $line);
        
        my $mgi_id = $fields[1];
        
        if ($parsed_by_mgi_id->{$mgi_id}) {
            warn "Duplicate for '$mgi_id'";
            $duplicate_count++;
            next;
        }
        $parsed_by_mgi_id->{$mgi_id} = \@fields;
    }        
    close_data_files();
    
    my $file_modified = ctime(stat($file_spec)->mtime);
    print STDERR "Parsed            : $file_spec\n";
    print STDERR "File Date         : $file_modified\n";
    print STDERR "MGI IDs           : ", scalar(keys(%$parsed_by_mgi_id)), "\n";
    print STDERR "MGI ID dudplicates: $duplicate_count\n";
    return ($parsed_by_mgi_id);
}

### parse_hmd_human_sequence_file_entry
#
# To be written

sub parse_hmd_human_sequence_file_entry {
    my ( $entry ) = @_;
    
    unless ($entry) {
        confess "Must pass a line parsed from 'HMD_HumanSequence.rpt'";
    }
    
    my $parsed = {};
    $parsed->{mouse_marker_symbol}           = $entry->[0];
    $parsed->{mgi_marker_accession_id}       = $entry->[1];
    $parsed->{mouse_entrez_gene_id}          = $entry->[2];
    $parsed->{human_marker_symbol}           = $entry->[3];
    $parsed->{human_entrez_gene_id}          = $entry->[4];
    $parsed->{mouse_nucleotide_refseq_ids}   = comma_to_list($entry->[5]);  # comma-delimited
    $parsed->{human_nucleotide_refseq_ids}   = comma_to_list($entry->[6]);  # comma-delimited
    $parsed->{mouse_protein_refseq_ids}      = comma_to_list($entry->[7]);  # comma-delimited
    $parsed->{human_protein_refseq_ids}      = comma_to_list($entry->[8]);  # comma-delimited
    $parsed->{mouse_swissprot_ids}           = comma_to_list($entry->[9]);  # comma-delimited
    $parsed->{human_swissprot_ids}           = comma_to_list($entry->[10]); # comma-delimited
    $parsed->{mouse_genbank_accession_ids}   = comma_to_list($entry->[11]); # comma-delimited
    $parsed->{evidences}                     = comma_to_list($entry->[12]); # comma-delimited
    $parsed->{j_numbers}                     = comma_to_list($entry->[13]); # comma-delimited     
    $parsed->{pubmed_ids}                    = comma_to_list($entry->[14]); # comma-delimited

    return $parsed;    
}

sub comma_to_list {
    my ( $string ) = @_;
    
    my $parsed = [];
    if ($string) {
        push(@$parsed, split(",", $string));
    }
    return $parsed;
}


1;

