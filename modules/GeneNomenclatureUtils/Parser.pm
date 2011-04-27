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
    convert_case_by_mode
    parse_file_by_column_to_hash_with_validation
);
use GeneNomenclatureUtils::ColumnParser;

### Global
my $debug;


=head2 debug

=cut

sub debug {
    my ( $self, $flag ) = @_;
    
    if (defined($flag)) {
        $debug = $flag;
    }
    return $debug;
}

=head2 new

  my $parser = GeneNomenclatureUtils::Parser->new($dir, $file
    , ['mgi_id', 'mgi_symbol']);

=cut

sub new {
    my ( $class, $dir, $file, $attrib ) = @_;
    
    $dir = '' unless $dir;
    unless ($file) {
        confess "Must pass a file name";
    }
    unless ($attrib) {
        confess "Must pass an attrib to parse by";
    }
    
    ### Create the GeneNomenclatureUtils::Parser object    
    my $parser = {};
    bless $parser, $class;
    
    
    my $file_spec  = check_for_file($dir, $file);
    print "FILE SPEC  : $file_spec\n";
    my $parser_name = $dir . '_' . $file ;
    print "PARSER NAME: $parser_name\n";
    
    ### Check the requested attribute to parse by are valid
    my $attribs = GeneNomenclatureUtils::ColumnParser::get_attribute_names(
        $parser_name);
    $parser->attributes($attribs);
    $attrib = $parser->validate_attribute($attrib); #Does case conversion
    $parser->parsed_by($attrib);
    $parser->file_spec($file_spec);
    $parser->name($parser_name);
    $parser->_init_no_match_symbols();
    
    return $parser;
}

sub parse {
    my ( $self ) = @_;
    
    ### Parse by specified attribute
    my ($line_regex, $match_type)
        = GeneNomenclatureUtils::ColumnParser::get_line_pattern($self->name());
    print STDERR " - line_regex: $line_regex\n" if $debug;
    print STDERR " - match_type: $match_type\n" if $debug;
        
        
    my $attribute_name = $self->parsed_by() or confess "parsed_by not set";
    my $attribute      = $self->get_attribute($attribute_name);
    print STDERR "Attribute name: $attribute_name\n" if $debug;
    print STDERR "Attribute: ", Dumper($attribute), "\n" if $debug;
    
    ### Is ID validation specified
    my ($id_type, $id_regex);
    if ($id_type = $attribute->{id_type}) {
        $id_regex = can_validate_id_type($id_type);    
    }
        
    my $file_spec        = $self->file_spec() or confess "file_spec not set";
    my $allow_duplicates = $self->duplicates();
    
    my $filters    = $self->get_filters;
    print STDERR "Filters: ", Dumper($filters), "\n" if $debug;
        
    my ($parsed, $filtered, $duplicated)
        = parse_file_by_column_to_hash_with_validation(
              $file_spec
            , $attribute->{column}
            , $id_regex
            , $line_regex
            , $match_type
            , $attribute->{split_by}
            , $attribute_name
            , $allow_duplicates
            , $filters
            , $self->convert_case
    );

    $self->{_parsed}          = $parsed;
    $self->{_lines_filtered}  = $filtered;
    $self->{_keys_duplicated} = $duplicated;
    return $parsed;    
}

=head2 get_filtered

=cut

sub get_filtered {
    my ( $self ) = @_;
    
    $self->parsed();
    return $self->{_lines_filtered};
}

=head2 get_duplicated

=cut

sub get_duplicated {
    my ( $self ) = @_;
    
    $self->parsed();
    return $self->{_keys_duplicated};
}

=head2 lookup

=cut

sub lookup {
    my ( $self, $requested ) = @_;
    
    unless ($requested) {
        confess "Nothing passed";
    }
    
    my $output_attrib = $self->output_attribute
        or confess "Output attribute not set";
    print STDERR "OUTPUT ATTRIB: $output_attrib\n" if $debug;
    
    my $parsed = $self->parsed(); # Check the parser was run.
    my $entry  = $parsed->{$requested};
    return unless $entry;
    
    my $parsed_entry = 
        GeneNomenclatureUtils::ColumnParser::parse_row_to_named_attributes(
            $self->name, $entry);
            
    my $result = $parsed_entry->{$output_attrib};
    if ($result) {
        if (ref($result) and ref($result) eq 'ARRAY' and @$result <= 1) {
            $result = $result->[0];
        }
    
        if (ref($result)) {
            if (my $mode = $self->output_allow_lists) {
                my @final;
                foreach my $id (@$result) {
                    push (@final, convert_case_by_mode($id, $self->output_convert_case));
                }
                if ($mode eq 'array') {
                    return \@final;
                } elsif ($mode eq 'tostring'){
                    return join($self->join_lists_by(), @final);
                } elsif ($mode eq 'ambiguous') {
                    return $self->no_match_symbol('ambiguous');
                }
            } else {
                confess "List output not permitted on lookup of '$requested'"
                    . " gave ", scalar(@$result), " results for '$output_attrib'. Call \$parser->output_allow_lists";
            }
        } else {
            return convert_case_by_mode($result, $self->output_convert_case);
        }
    } else {
        return;
    }
}

sub _init_no_match_symbols {
    my ( $self ) = @_;

    $self->{_no_match_symbols} = {
        'notfound'          => 'NOT_FOUND',
        'ambiguous'         => 'AMBIGUOUS',
        'invalid'           => 'INVALID',
        'nothingtocheck'    => 'NOTHING_TO_CHECK',
        'pass'              => 'PASS',
        'fail'              => 'FAIL'
    };
}

=head2 get_no_match_symbols

=cut 

sub get_no_match_symbols {
    my ( $self ) = @_;
    
    return $self->{_no_match_symbols};    
}

=head2 no_match_symbol

=cut

sub no_match_symbol {
    my ( $self, $symbol, $value ) = @_;
    
    unless ($symbol) {
        confess "Must pass a symbol name";
    }
    unless (exists($self->{_no_match_symbols}->{$symbol})) {
        confess "Invalid no_match_symbol '$symbol'";
    }
    if ($value) {
        $self->{_no_match_symbols}->{$symbol} = $value;
    }
    return $self->{_no_match_symbols}->{$symbol};
}

=head2 get_parsed_entry

=cut 

sub get_parsed_entry {
    my ( $self, $requested ) = @_;
    
    unless ($requested) {
        confess "Nothing passed";
    }

    my $parsed = $self->parsed(); # Check the parser was run.
    my $entry  = $parsed->{$requested};
    return $entry;
}

=head2 add_filter

=cut

sub add_filter {
    my ( $self, $attribute_name, $match_type, $regex ) = @_;

    if ($self->_is_parsed) {
        confess "Must add filters before parse";
    }

    unless ($attribute_name) {
        confess "Must pass an attribute name";
    }
    $attribute_name = $self->validate_attribute($attribute_name);
    my $attribute   = $self->get_attribute($attribute_name);
    unless ($match_type and $match_type =~ /^match$|^nomatch$/) {
        confess "match_type must be 'match' or 'nomatch'";
    }
    unless ($regex) {
        confess "Must pass a regex";
    }
    
    $self->{_filters} ||= {};
    if ($self->{_filters}->{$attribute_name}) {
        confess "Filter already defined for '$attribute_name'";
    }
    
    my $filter = {
        column     => $attribute->{column},
        match_type => $match_type,
        regex      => $regex
    };
    $self->{_filters}->{$attribute_name} = $filter;
}

=head2 get_filters

=cut 

sub get_filters {
    my ( $self ) = @_;
    
    $self->{_filters} ||= {};
    return $self->{_filters};
}

=head2 duplicates

Specifies how to handle duplicate IDs/keys when parsing, as by default
this these throw a fatal error. 

To prevent this:

  $parser->duplicates('allow');
    
 or 
  
  $parser->duplicates('delete');  
    
'allow' will cause original parsed entries to be overwritten by those
subsequently occurring in the parsed file.

'delete' will remove duplicated keys (and their entries) from the parse.

In either case, the number of duplicated keys will be reported by the
parser, and they can be obtained from the parser object with:

  my $duplicated = $parser->get_duplicated();

=cut

sub duplicates {
    my ( $self, $attrib ) = @_;
    
    if (defined($attrib)) {
        if ($self->_is_parsed) {
            confess "Must set duplicates before parse";
        }
        if ($attrib and $attrib !~ /^allow$|^delete$/) {
            confess "Must be one of 'allow' or 'delete'";
        }
        $self->{_duplicates} = $attrib;
    }
    return $self->{_duplicates};
}

=head2 file_spec

=cut 

sub file_spec {
    my ( $self, $attrib ) = @_;
    
    if ($attrib) {
        $self->{_file_spec} = $attrib;
    }
    return $self->{_file_spec};
}

=head2 parsed_by

=cut

sub parsed_by {
    my ( $self, $attrib ) = @_;
    
    if ($attrib) {
        $attrib = $self->validate_attribute($attrib);
        $self->{_parsed_by} = $attrib;
    }
    return $self->{_parsed_by};
}

=head2 output_attribute

=cut

sub output_attribute {
    my ( $self, $attrib ) = @_;
    
    if ($attrib) {
        $attrib = $self->validate_attribute($attrib);
        $self->{_output_attribute} = $attrib;
    }
    return $self->{_output_attribute};
}

=head2 output_allow_lists

=cut

sub output_allow_lists {
    my ( $self, $mode ) = @_;
    
    if (defined($mode)) {
        if ($mode and $mode !~ /array|tostring|ambiguous/) {
            confess "Must set to one of 'array', 'tostring', 'ambiguous'"
        }
        $self->{_output_allow_lists} = $mode;
    }
    return $self->{_output_allow_lists};
}

=head2 join_lists_by

=cut

sub join_lists_by {
    my ( $self, $string ) = @_;
    
    if ($string) {
        $self->{_join_lists_by} = $string;
    }
    unless ($self->{_join_lists_by}) {
        $self->{_join_lists_by} = ', ';
    }
    return $self->{_join_lists_by};
}

=head2 attributes

Returns a hash (by reference) the keys of which are the attribute
names, the values themselves are hashes, with the keys:

  column
  id_type
  mandatory
  split_by 

  my $attributes = $parser->attributes();

=cut 

sub attributes {
    my ( $self, $attributes ) = @_;
    
    if ($attributes) {
        unless (ref($attributes) and ref($attributes) eq 'HASH') {
            confess "Must pass attributes as a hash ref";
        }
        $self->{_valid_attribs} = $attributes;
    }
    return $self->{_valid_attribs};
}

=head2 get_attribute

=cut

sub get_attribute {
    my ( $self, $attribute ) = @_;

    unless ($attribute) {
        confess "Must pass an attribute";
    }
    $attribute = $self->validate_attribute($attribute);
    
    return $self->{_valid_attribs}->{$attribute};  
}

=head2 validate_attribute

=cut

sub validate_attribute {
    my ( $self, $attribute ) = @_;
    
    unless ($attribute) {
        confess "Must pass an attribute to check";
    }
    $attribute = lc($attribute);
    
    my $attributes = $self->{_valid_attribs};
    unless ($attributes->{$attribute}) {
        confess "Invalid attribute: '$attribute' choose one of: "
            . join(", ", sort {$a cmp $b} keys(%$attributes)). "\n";
    }
    return $attribute;
}

=head2 name

=cut

sub name {
    my ( $self, $name ) = @_;
    
    if ($name) {
        $self->{_parser_name} = $name;
    }
    return $self->{_parser_name};
}

=head2 parsed

=cut

sub parsed {
    my ( $self ) = @_;

    unless ($self->{_parsed}) {
        confess "Must call \$parser->parse first";
    }
    return $self->{_parsed};    
}

sub _is_parsed {
    my ( $self ) = @_;
    
    if (exists($self->{_parsed})) {
        return 1;
    }
}

=head2 convert_case

=cut

sub convert_case {
    my ( $self, $case ) = @_;
    
    if ($case) { 
        if ($self->_is_parsed) {
            confess "Must set convert_case before parse";
        }
        $case = $self->_validate_case($case);
        $self->{_convert_case} = $case;
    }
    return $self->{_convert_case};
}

=head2 output_convert_case

=cut

sub output_convert_case {
    my ( $self, $case ) = @_;
    
    if ($case) { 
        $case = $self->_validate_case($case);
        $self->{_output_convert_case} = $case;
    }
    return $self->{_output_convert_case};
}

sub _validate_case {
    my ( $self, $case ) = @_;
    
    unless ($case) {
        confess "Nothing passed";
    }
    $case = lc($case);
    unless ($case =~ /^upper$|^lower$|^capital$/) {
        confess "case parameter must be one of 'upper', 'lower', 'capital'";
    }
    return $case;
}

1;
