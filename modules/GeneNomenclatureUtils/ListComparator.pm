### dev

=pod

=head1 NAME - GeneNomenclatureUtils::ListComparator

=head1 DESCRIPTION

=head1 AUTHOR

webmaster@genes2cognition.org

=cut

package GeneNomenclatureUtils::ListComparator;

use strict;
use warnings;
use Carp;
use Config::IniFiles;
use Data::Dumper;
use Exporter;
use GeneNomenclatureUtils::TabFileParser qw(
    clean_array_elements_of_whitespace
    close_data_files
    open_data_file
    parse_tab_delimited_file_to_hash_keyed_by_column
    read_next_line_from_data_file
);
use YAML qw(
    LoadFile
);

use vars qw{ @ISA @EXPORT_OK };

@ISA = qw(Exporter);
@EXPORT_OK = qw(
    add_list_from_memory
    do_list_comparison
    dump_lists
    get_all_list_names
    get_list
    get_union_list
    load_list_ids_file
    parse_list_config
);

### Global
my $debug;

{
    my ($unionlist, $lists, $file_names_seen, $list_names_seen);

    sub do_list_comparison {
        my ( $comp_string, $quiet, $gene_title, $filter_by_list_name
            , $markup ) = @_;      
        unless ($comp_string and !ref($comp_string)) {
            confess "Must pass comparision string";
        }
        
        ### Verify list name to filter by is valid
        if ($filter_by_list_name) {
            unless ($lists->{$filter_by_list_name}) {
                confess "'$filter_by_list_name' not loaded";
            }
            print "\nFILTER BY: $filter_by_list_name" unless $quiet; 
        }
        
        ### Get the list names passed
        my @tokens = split(/\s+/, $comp_string);
        
        my @list_names;
        foreach my $list_name (@tokens) {
            if ($list_name eq 'WEB-USER') {
                unshift(@list_names, 'WEB-USER');
            } else {
                push (@list_names, $list_name);
            }
        }
        
        clean_array_elements_of_whitespace(\@list_names);
        unless (@list_names >= 2) {
            confess "Must specify at least 2 list_name with 'comparison: '";
        }
        
        my $table = [];
        
        $gene_title = 'Gene' unless $gene_title;
        my $title = [$gene_title];
        push (@$table, $title); 

        ### Verify we have all the required sets
        ### Build the title row
        
        foreach my $list_name (@list_names) {
            unless ($lists->{$list_name}) {
                confess "'$list_name' not loaded";
            }
            unless ($quiet) {
                print "  Comparison: $list_name ("
                    , scalar(keys(%{$lists->{$list_name}->{ids}})), ")\n";
            }
            
            unless ($list_name eq 'WEB-USER' and $filter_by_list_name eq 'WEB-USER') {
                if ($markup) {
                    push (@$title, '<center>' . $list_name . '</center>');
                } else {
                    push (@$title, $list_name);
                }
            }
        }
        
        unless ($quiet) {
            print "\nUNION OF ALL SETS: ", scalar(keys(%$unionlist)), "\n";
            print "\n";
        }
        
        my $yes = 'YES';
        my $no  = 'NO';
        if ($markup) {
            $yes = '<center>YES</center>';
            $no  = '<center>NO</center>';
        } 
        
        ### BUILD THE RESULTS
        ### LOOP OVER EACH ID IN THE UNION OF ALL IDS
        
        foreach my $master_id (keys(%$unionlist)) {
            my $row = [$master_id];
            
            my $detected;
            
            ### This ensures the list row will be output if we 
            ### Are not filtering by a given list
            
            my $filter_by_list_result;
            $filter_by_list_result++ unless $filter_by_list_name;
            
            ### Loop over the lists selected for comparison
            
            foreach my $list_name (@list_names) {
            
                ### Was the ID found in the present list
                if ($lists->{$list_name}->{ids}->{$master_id}) {

                    $detected++;
                    if ($filter_by_list_name
                        and $filter_by_list_name eq $list_name) {
                        $filter_by_list_result++;
                        
                        push (@$row, $yes) if $debug;
                    } else {
                        push (@$row, $yes);
                    }
                } else {
                    push (@$row, $no);
                }
            }
            
            if ($detected and $filter_by_list_result) {
                push (@$table, $row);
            }
        }
        
        return $table;
    }

    sub _init_shared {
        $unionlist       = {};
        $lists           = {};
        $file_names_seen = {};
        $list_names_seen = {};
    }

    sub get_unionlist {
        return $unionlist;
    }

    sub add_list_from_memory {
        my ( $hash, $name ) = @_;
        
        unless ($hash and ref($hash) =~ /HASH/) {
            confess "Must pass a hash reference";
        }
        unless ($name) {
            confess "Must pass a name for the list";
        }
        if ($list_names_seen->{$name}) {
            confess "List name '$name' already used";
        }
        $lists->{$name}->{ids} = $hash;

        foreach my $id (keys(%$hash)) {
            $unionlist->{$id}++;
        }
    }
    
    sub dump_lists {
        print Dumper($lists);
        print "\n";
        print Dumper($unionlist)
    }
    
    sub get_union_list {
        return $unionlist;
    }

    sub get_all_list_names {
        
        my $sets_string = join (" ", sort keys(%$lists));
        return $sets_string;
    }
    
    sub get_list {
        my ( $list ) = @_;
        
        unless ($list) {
            confess "Must pass a list name";
        }
        unless ($lists->{$list}) {
            confess "List '$list' name unrecognised";
        }
        
        return $lists->{$list};
    }

    sub parse_list_config {
        my ( $file, $quiet ) = @_;

        _init_shared() unless $unionlist;

        print "CONFIG FILE: $file\n" unless $quiet;
        my $cfg = LoadFile($file);

        
        ### ID Match regular expression
        my $id_match = $cfg->{id_match}
            or confess "'id_match: ' not set";
        print "ID match: $id_match\n" unless $quiet;

        ### Skip words
        my $skipwords = parse_skip_words($cfg, $quiet);
        
        ### ID files    
        my @list_names = keys(%{$cfg->{lists}});

        ### Check parameters for each file
        foreach my $name (@list_names) {

            if ($list_names_seen->{$name}) {
                confess "'$name' already parsed";
            }
            $list_names_seen->{$name}++;

            my $params = $cfg->{lists}->{$name}
                or confess "Error with '$name'";

            my ( $file, $column, $skip_title ) = (
                  $params->{file} 
                , $params->{column}
                , $params->{skip_title}
            );
            unless ($file and -e $file) {
                confess "Couldn't read $file";
            }
            if ($file_names_seen->{$file}) {
                confess "Duplicate file: $file";
            }
            unless (defined($column) and $column >= 1 ) {
                confess "column must set for '$name'";
            }
            unless (defined($skip_title)) {
                $skip_title = 0;
            }

            unless ($quiet) {
                print "Name        : $name\n";
                print "File        : $file\n";
                print "IDs column  : $column\n";
                print "Skip title  : $skip_title\n";
            }

            my $ids = load_list_ids_file($params, $name, $skipwords
                , $id_match, $unionlist, $quiet);
            $lists->{$name}->{ids}           = $ids;
            $lists->{$name}->{file}          = $file;
            $lists->{$name}->{column}        = $column;
            $lists->{$name}->{skip_title}    = $skip_title;
            $lists->{$name}->{table}         = $params->{table};
            $lists->{$name}->{pubmed}        = $params->{pubmed};
            $lists->{$name}->{species}       = $params->{species};
            $lists->{$name}->{year}          = $params->{year};
            $lists->{$name}->{description}   = $params->{description};
            $lists->{$name}->{count}         = scalar(keys(%$ids));
            
            unless ($lists->{$name}->{confidential}   = $params->{confidential}) {
                $lists->{$name}->{confidential} = 'unknown';
            }
        }
        
        return [keys(%$lists)];
    }
}

sub parse_skip_words {
    my ( $cfg, $quiet ) = @_;
        
    my $stopword_string = $cfg->{skipwords};
    unless ($stopword_string) {
        confess "Must set 'skipwords: '";
    }
    my @skipwords = split(/\s+/, $stopword_string);
    clean_array_elements_of_whitespace(\@skipwords);
    my $skipwords = {};
    foreach my $word (@skipwords) {
        $skipwords->{$word}++;
    }
    unless ($quiet) {
        print "SKIPWORDS : ", join(' ', keys(%$skipwords)), "\n\n";
    }

    return $skipwords;
}

sub load_list_ids_file {
    my ( $params, $name, $skipwords, $id_match, $unionlist, $quiet ) = @_;
    
    my $ids = {};
    
    my $duplicate_count = 0;
    my $blank_count     = 0;
    my $skipword_count  = 0;
    my $invalid_count   = 0;
    
    open_data_file('DATA', $params->{file});
    if ($params->{skip_title}) {
        my $titles = read_next_line_from_data_file('DATA');
    } 
    while (defined(my $line = read_next_line_from_data_file('DATA'))) {
       
        chomp($line);
        my @fields = split("\t", $line);
        clean_array_elements_of_whitespace(\@fields);
       
        my $id = $fields[$params->{column} - 1];
        unless ($id) {
            $blank_count++;
            next;
        }
        if ($skipwords->{$id}) {
            $skipword_count++;
            next;
        }
        if ($ids->{$id}) {
            print STDERR "Duplicate: $id\n";
            $duplicate_count++;
        } else {
            if ($id =~ /$id_match/) {
                $ids->{$id}++;
                $unionlist->{$id}++;
            } else {
                print STDERR "Invalid: $id\n";
                $invalid_count++;
            }
        }
    }
    
    unless ($quiet) {
        print "Verified IDs: ", scalar(keys(%$ids)), "\n";
        print "Invalid IDs : $invalid_count\n"; 
        print "Duplicates  : $duplicate_count\n";
        print "Blanks      : $blank_count\n";
        print "Skipwords   : $skipword_count\n";
        print "\n";
    }
    
    close_data_files();

    return ($ids);
}

1;

