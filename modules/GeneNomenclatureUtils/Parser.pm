### nomenclature

=pod

=head1 NAME - GeneNomenclatureUtils::Parser

=head1 DESCRIPTION

To be written

=head1 AUTHOR - mike_croning@hotmail.com

=cut


package GeneNomenclatureUtils::Parser;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use DPStore::Utils::SeqIDNomenclature qw(
    can_validate_id_type
    check_for_file
);
use DPStore::Utils::TabFileParser qw(
    parse_file_by_column_to_hash_with_validation
);
use GeneNomenclatureUtils::ColumnParser;

=head2 new

  my $parser = GeneNomenclatureUtils::Parser->new($dir, $file
    , ['mgi_id', 'mgi_symbol']);

=cut

sub new {
    my ( $self, $dir, $file, $attrib, $allow_duplicates ) = @_;

    unless ($dir) {
        confess "Must pass a directory";
    }
    unless ($file) {
        confess "Must pass a file name";
    }
    unless ($attrib) {
        confess "Must pass an attrib to parse by";
    }
    
    my $file_spec  = check_for_file($dir, $file);
    my $parser_name = $dir . '_' . $file ;
    
    ### Check the requested attributes to parse by are valid
    my $valid_attribs = GeneNomenclatureUtils::ColumnParser::get_attribute_names(
        $parser_name);
    unless ($valid_attribs->{$attrib}) {
        confess "Attribute: '$attrib' not specifed in parser '$parser_name'";
    }
    
    ### Create the GeneNomenclatureUtils::Parser object    
    my $parser = {};
    bless $parser, $self;
    $parser->{_valid_attribs}  = $valid_attribs;
    $parser->{_file_spec}      = $file_spec;
    $parser->{_parser_name}    = $parser_name;
   
    ### Parse by specified attribute
    my ($line_regex, $match_type)
        = GeneNomenclatureUtils::ColumnParser::get_line_pattern($parser_name);

    my ($id_type, $id_reg_ex);
    if ($id_type = $valid_attribs->{$attrib}->{id_type}) {
        $id_reg_ex = can_validate_id_type($id_type);
    }

    my $parsed_by = parse_file_by_column_to_hash_with_validation(
          $file_spec
        , $valid_attribs->{$attrib}->{column}
        , $id_reg_ex
        , $line_regex
        , $match_type
        , $valid_attribs->{$attrib}->{split_by}
        , $attrib
        , $allow_duplicates
    );

    $parser->{_parsed_by} = $parsed_by;
    return $parser;
}

=head2 get_attributes

Returns a hash (by reference) the keys of which are the attribute
names, the values themselves are hashes, with the keys:

  column
  id_type
  mandatory
  split_by 

  my $attributes = $parser->get_attributes();

=cut 

sub get_attributes {
    my ( $self ) = @_;
    
    return $self->{'_valid_attribs'};
}

sub validate_attribute {
    my ( $self, $attribute ) = @_;
    
    unless ($attribute) {
        confess "Must pass an atrribute to check";
    }
    
    my $attributes = $self->{'_valid_attribs'};
    unless ($attributes->{$attribute}) {
        confess "Invalid attribute: '$attribute' choose one of: "
            . join(", ", sort {$a cmp $b} keys(%$attributes)). "\n";
    }
    return $attributes->{$attribute};
}

=head2 get_parsed

  my $parsed = $parser->get_parsed();

=cut

sub get_parsed {
    my ( $self ) = @_;
    
    return $self->{_parsed_by};
}

sub name {
    my ( $self ) = @_;
    
    return $self->{_parser_name};
}

1;
