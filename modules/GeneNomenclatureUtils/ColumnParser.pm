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
    check_for_file
    validate_id_type
);
use YAML qw(
    LoadFile
);

our $debug;

{
    my $parsers;

    sub _configure {
        my $config_file = check_for_file('DPStoreConfDir', 'parser_definitions.yml');
        $parsers        = LoadFile($config_file);
        
        unless ($parsers->{files} and ref($parsers->{files}) eq 'HASH') {
            confess "No 'files:' specified in '$config_file'";
        }
 
        my @parser_names = keys(%{$parsers->{files}});
        foreach my $parser_name (@parser_names) {
        
            my $parser_def = $parsers->{files}->{$parser_name};
            _validate_parser_definition($parser_name, $parser_def);
            
            $parser_def->{attributes_by_name}
                = _make_attributes_by_name($parser_def);
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
        
        my $parser_def;
        unless ($parser_def = $parsers->{files}->{$parser}) {
            confess "No parser for '$parser'";
        }
        return $parser_def;
    }
}

### _validate_parser_definition

sub _validate_parser_definition {
    my ( $parser_name, $parser_def ) = @_;
    
    ### line_pattern specification
    unless ($parser_def->{line_pattern}) {
        confess "Must set 'line_pattern:' in $parser_name";
    }
    unless ($parser_def->{line_pattern_match_type}
        and $parser_def->{line_pattern_match_type} =~ /^match$|^nomatch$/) {
    
        confess "Must set 'line_pattern_match_type:' in $parser_name" 
            . " to 'match' or 'nomatch'";
    }
    
    ### columns
    unless ($parser_def->{columns} and ref($parser_def->{columns}) eq 'HASH') {
        confess "No 'columns:' specified in '$parser_name'";
    }
    
    my $column_names_seen = {};
    
    my @column_numbers = keys(%{$parser_def->{columns}});
    foreach my $column_number (@column_numbers) {
        unless ($column_number =~ /^\d+/) {
            confess "Invalid column_number '$column_number' in '$parser_name'";
        }
        if ($column_number == 0) {
            confess "Invalid column number '0' in '$parser_name'"
                . " columns are numbered from 1";
        }
        
        my $column = $parser_def->{columns}->{$column_number};
        unless ($column and ref($column) eq 'HASH') {
            confess "Invalid column '$column_number' specification in '$parser_name'";
        }
        my $name = $column->{name}
            or confess "'name:' not set in column '$column_number' in '$parser_name'";
    
        if ($column_names_seen->{$name}) {
            confess "Duplicated column name '$name' in '$parser_name'";
        }
        $column_names_seen->{$name}++;
        
        ### check for the mandatory property
        my $mandatory = $column->{mandatory};
        if ($mandatory) {
            unless ($mandatory =~ /^yes$|^no$/) {
                confess "Invalid '$mandatory' for mandatory (must be 'yes' "
                    . "or 'no') in column '$column_number' of '$parser_name'";
            }
        }
        
        ### check for validate property
        my $validate = $column->{validate};
        if ($validate) {
            unless (can_validate_id_type($validate)) {
                confess "Don't understand id_type '$validate' in column "
                    . " '$column_number' of '$parser_name'";
            }
        }
        
        ### check for superfluous 
        foreach my $property (keys(%$column)) {
            unless ($property =~ /^name$|^mandatory$|^validate$|^split$/) {
                confess "Invalid property '$property' in column '$column_number'"
                    . " of '$parser_name'";
            }
        } 
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
    my ( $name, $row, $warn ) = @_;

    unless ($name) {
        confess "Must pass a parser name";
    }
    unless ($row and ref($row) =~ /ARRAY/) {
        confess "Must pass a row from the file as an ARRAY reference";
    }

    my $parser_def = _get_parser($name);
    my $attributes = get_attributes($name) or confess "";
  
    my $parsed = {};

    foreach my $attrib_name (keys(%$attributes)) {

        my $attribute       = $attributes->{$attrib_name}
            or confess "Couldnt get attribute '$attrib_name'";
        my $column_num      = $attribute->{column} or confess "No column";
        my $mandatory       = $attribute->{mandatory};
        my $id_type         = $attribute->{id_type};
        my $split           = $attribute->{split};

        my $value           = $row->[$column_num - 1];        

        ### Is the value of the column mandatory
        if ($mandatory and $mandatory eq 'yes') {
            unless ($value) {
                if ($warn) {
                    print STDERR "No '$attrib_name' parsed from col: $column_num on\n";
                    print STDERR Dumper($row), "\n";
                } else {
                    confess "No 'attrib_name' parsed from col: $column_num on\n"
                        . Dumper($row);
                }
                next;
            }
        }

        ### Do we need to split the column into a list of values
        if ($value) {
            if ($split) {
                my @values = split(/$split/, $value);
                $parsed->{$attrib_name} = \@values;
                print STDERR "We split '$attrib_name' to ", Dumper(\@values), "\n" if $debug;

                if ($id_type) {
                    foreach my $id (@{$parsed->{$attrib_name}}) {
                        unless (validate_id_type($id_type, $id, $warn)) {

                            print STDERR "Validation error for '$id' (col: $column_num) as '$id_type'\n";
                            print STDERR Dumper($row), "\n";
                        } else {
                            print STDERR "Validated '$id' as '$id_type'\n" if $debug;
                        } 
                    }
                }
            } else {
                $parsed->{$attrib_name} = $value;
                if ($id_type) {
                    unless (validate_id_type($id_type, $value, $warn)) {
                        print STDERR "Validation error for '$value' (col: $column_num) as '$id_type'\n";
                        print STDERR Dumper($row), "\n";
                    } else {
                        print STDERR "Validated '$value' as '$id_type'\n" if $debug;
                    } 
                }
            }
        }
    }
    return $parsed;
}

=head2 get_attributes

Given a parser name returns a hash of the attributes available from
it on parsing a row with parse_row_to_named_attributes

  my $attributes = GeneNomenclatureUtils::ColumnParser::get_attributes(
     'RGD_dir_GENES_RAT.txt');

=cut

sub get_attributes {
    my ( $parser_name ) = @_;

    my $parser_def = _get_parser($parser_name);
    return $parser_def->{attributes_by_name};
}

### _make_attributes_by_name

sub _make_attributes_by_name {
    my ( $parser_def ) = @_;
    
    my $attributes   = {};
    
    my @column_numbers = keys(%{$parser_def->{columns}});
    foreach my $column_num (@column_numbers) {

        my $column = $parser_def->{columns}->{$column_num};
        
        my $attribute = {
            column    => $column_num,
            id_type   => $column->{validate},
            mandatory => $column->{mandatory},
            split     => $column->{split}
        };
        $attributes->{$column->{name}} = $attribute;    
    }
    return $attributes;
}

=head2 get_line_pattern

    my ($regex, $match_type) = get_line_pattern('RGD_dir_GENES_RAT.txt');
    
=cut
    
sub get_line_pattern {
    my ( $name ) = @_;

    my $parser_def = _get_parser($name);
    my $line_pattern = [$parser_def->{line_pattern}
                      , $parser_def->{line_pattern_match_type}];

    return @$line_pattern;
}

1;
