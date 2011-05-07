### nomenclature

=pod

=head1 NAME - GeneNomenclatureUtils::Parser

=head1 DESCRIPTION

Class for parsing tab-delimited files.

=head1 AUTHOR - mike_croning@hotmail.com

=cut


package GeneNomenclatureUtils::Parser;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use GeneNomenclatureUtils::ColumnParser;
use GeneNomenclatureUtils::SeqIDNomenclature qw(
    can_validate_id_type
    check_for_file
    check_or_translate_ids_in_file
);
use GeneNomenclatureUtils::TabFileParser qw(
    convert_case_by_mode
    parse_file_by_column_to_hash_with_validation
);

### Global
my $debug;

=head2 debug

Get/set method for debugging in the parser

  $parser->debug('yes');

=cut

sub debug {
    my ( $self, $flag ) = @_;
    
    if (defined($flag)) {
        $debug = $flag;
    }
    return $debug;
}

=head2 new

Constructor for the GeneNomenclatureUtils::Parser class. Pass an environment
variable name, which is used as the path to the specified file. 

The third parameter specifies the column name/attribute to parse by.
 
  my $parser = GeneNomenclatureUtils::Parser->new($env_var_name, $file, 'mgi_symbol');

=cut

sub new {
    my ( $class, $dir, $file, $parsing_attrib ) = @_;
    
    $dir = '' unless $dir;
    unless ($file) {
        confess "Must pass a file name";
    }
    unless ($parsing_attrib) {
        confess "Must pass an attrib to parse by";
    }
    
    ### Create the GeneNomenclatureUtils::Parser object    
    my $parser = {};
    bless $parser, $class;
    
    
    my $file_spec  = check_for_file($dir, $file);
    print STDERR "FILE SPEC  : $file_spec\n";
    my $parser_name = $dir . '_' . $file ;
    print STDERR "PARSER NAME: $parser_name\n";
    
    ### Check the requested attribute to parse by are valid
    my $parsing_attribs = GeneNomenclatureUtils::ColumnParser::get_attributes(
        $parser_name);
    $parser->attributes($parsing_attribs);
    $parsing_attrib = $parser->validate_attribute_name($parsing_attrib); #Does case conversion
    $parser->parsed_by($parsing_attrib);
    my $attribute = $parser->get_attribute($parsing_attrib);
    $parser->file_process_id_type($attribute->{id_type});
    $parser->file_spec($file_spec);
    $parser->name($parser_name);
    $parser->_init_no_match_symbols();
    
    return $parser;
}

=head2 parse

Perform the parse of the file, as specified in the constructor, and subsequent
modifiers such as $parser->add_filer, $parser->convert_case.

  $parser->parse();

Does not take any parameters

=cut

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
        print STDERR "  -  Checking id_type: '$id_type' with '$id_regex'\n";
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
            , $attribute->{split}
            , $attribute_name
            , $allow_duplicates
            , $filters
            , $self->convert_case
            , $self->prepend_key
            , $self->postpend_key
    );

    $self->{_parsed}          = $parsed;
    $self->{_lines_filtered}  = $filtered;
    $self->{_keys_duplicated} = $duplicated;
    return $parsed;    
}

=head2 get_filtered

Returns a reference to an array of arrays of the lines parsed from the
tab-delimited file, that were filtered as a consequence of columns
specified with $parser->add_filter($column_num, $regex) matching the 
regex. 

  my $filtered = $parser->get_filtered();
  
=cut

sub get_filtered {
    my ( $self ) = @_;
    
    $self->parsed();
    return $self->{_lines_filtered};
}

=head2 get_duplicated

Returns a reference to a hash, keyed by the IDs of the duplicated IDs/values
as observed during $parser->parse, the values of which are the number of
times the ID was observed.

  my $duplicaed = $parser->get_duplicated();

=cut

sub get_duplicated {
    my ( $self ) = @_;
    
    $self->parsed();
    return $self->{_keys_duplicated};
}

=head2 process_file

Used to check or translate (determined by $parser->file_process_mode) the
specifed file. When mode is 'check' output will be of the format pass/fail,
while when mode is 'translate' look-up will be done by the column name/attribute
specified by $parser->output_attribute.

Input_column specifes the column to check with the parser, and output_column
that which to splice output. 


  $parser->process_file($file, $input_column, $output_column, $skip_title
    , $output_title);

The optional parameters skip_title and output_title cause the first line of the
processed file to be skipped (no lookup being done), and output_title
overrides $parser->output_attribute in that written to STDOUT.

=cut 

sub process_file {
    my ( $self, $file, $input_column, $output_column, $skip_title
        , $output_title ) = @_;
    
    my $mode = $self->file_process_mode;
    undef $mode if $mode eq 'check';
    
    unless ($output_title) {
        $output_title = $self->output_attribute;
    }
    
    check_or_translate_ids_in_file($file, $self, $output_title
        , $self->file_process_id_type, $input_column, $output_column
        , $skip_title, $mode, $self->get_no_match_symbols
    );
}

=head2  file_process_mode

Set to one of 'check' or 'translate' before calling
$parser->process_file; 

=cut 

sub file_process_mode {
    my ( $self, $mode ) = @_;
    
    if ($mode) {
        unless ($mode =~ /^check$|^translate$/) {
            confess "Must set to one of check|translate"; 
        }
        $self->{_file_process_mode} = $mode;
    }
    unless ($self->{_file_process_mode}) {
        confess "Must set explicitly";
    }
    return $self->{_file_process_mode};
}

=head2  file_process_id_type

Used to request validation on the IDs processed by a call
to parser->process_file();

  $parser->file_process_id_type('mgi_id');

=cut 

sub file_process_id_type {
    my ( $self, $id_type ) = @_;
    
    if ($id_type) {
        unless (can_validate_id_type($id_type)) {
            confess "Don't know how to check id_type '$id_type'"; 
        }
        $self->{_file_process_id_type} = $id_type;
    }
    return $self->{_file_process_id_type};
}


=head2 lookup

Looks-up the passed value in the parser. If successful, returns the
column/atrribute specified by $parser->output_attribute. 

  my $results = $parser->lookup('grin1');

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
        if (ref($result) and ref($result) eq 'ARRAY') {
            if  (@$result == 1) {
                $result = $result->[0];
            } elsif (@$result == 0) {
                $result = undef;
            }
        }
    
        #Do we have a list, with more than one element?
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

Returns a hash by reference of the symbols that $parser->process_file
should include in output, when lookups fail, are ambiguous, etc.

Hash keys (and default values) are:

    notfound                NOT_FOUND
    ambiguous               AMBIGUOUS
    invalid                 INVALID
    nothingtocheck          NOTHING_TO_CHECK
    pass                    PASS
    fail                    FAIL

These default values can be overriden with calls to $parser->no_match_symbol

=cut 

sub get_no_match_symbols {
    my ( $self ) = @_;
    
    return $self->{_no_match_symbols};    
}

=head2 no_match_symbol

Used to get/set the value of the 'no match symbols' employed by the parser
as written to output by $parser->process_file();

See get_no_match_symbols for a list of their names and defaults.

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

=head2 get_unparsed_entry

Returns a reference to an array of the line from the file
split on delimit tab-chars.  

  my $unparsed = $parser->get_unparsed_entry('my_val');
  
Generally it is preferable to use $parser->lookup, which does
result validation, handles multiple values specified in a column,
case conversion, etc.

=cut 

sub get_unparsed_entry {
    my ( $self, $requested ) = @_;
    
    unless ($requested) {
        confess "Nothing passed";
    }

    my $parsed_by_id = $self->parsed(); # Check the parser was run.
    my $entry  = $parsed_by_id->{$requested};
    return $entry;
}

=head2 add_filter

Add a filter on a column (specified by name) to the parser object. 
These will be used during $parser->parse, as the first step in the
parsing process.

  $parser->add_filter('gene_type', 'match', 'pseudo');

The set of filtered lines can be recovered with:

  my $filtered = $parser->get_filtered();

The second parameter must be 'match' or 'nomatch'
  
=cut

sub add_filter {
    my ( $self, $attribute_name, $match_type, $regex ) = @_;

    if ($self->_is_parsed) {
        confess "Must add filters before parse";
    }

    unless ($attribute_name) {
        confess "Must pass an attribute name";
    }
    $attribute_name = $self->validate_attribute_name($attribute_name);
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

Returns a reference to a hash of hashes of the filter conditions
passed to the parser object. Hash keys are the column/attribute
names, the individual hashes are of the form 

    {
        column     => 1    
        match_type => match|nomatch
        regex      => regex
    }

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

Get/set method for the full path to the file to be parsed.
Automatically set the constructor call to new.

=cut 

sub file_spec {
    my ( $self, $attrib ) = @_;
    
    if ($attrib) {
        $self->{_file_spec} = $attrib;
    }
    return $self->{_file_spec};
}

=head2 prepend_key

Get/set method for the string to prepend to a key
during parse

  $parser->prepend_key('HGNC:');

=cut

sub prepend_key {
    my ( $self, $string ) = @_;
    
    if ($string) {
        $self->{_prepend_key} = $string;
    }
    return $self->{_prepend_key};
}

=head2 postpend_key

Get/set method for the string to postpend to a key
during parse

  $parser->postpend_key('_NEW');

=cut

sub postpend_key {
    my ( $self, $string ) = @_;
    
    if ($string) {
        $self->{_postpend_key} = $string;
    }
    return $self->{_postpend_key};
}


=head2 parsed_by

Get/set method for the name of the column/attribute to be
indexed during the file parse.

Automatically set the constructor call to new.

=cut

sub parsed_by {
    my ( $self, $attrib ) = @_;
    
    if ($attrib) {
        $attrib = $self->validate_attribute_name($attrib);
        $self->{_parsed_by} = $attrib;
    }
    return $self->{_parsed_by};
}

=head2 output_attribute

Get/set method for the column name (attribute) to be returned by 
$parser->lookup(), and used to produce the output produced by
$parser->process_file().

Can be set (and reset) if more then one type of lookup result is
required. 

 $parser->output_attribute('ensembl_id');

Note there is no default, this must be set explicitly before a call
to $parer->lookup, or file_convert.

=cut

sub output_attribute {
    my ( $self, $attrib ) = @_;
    
    if ($attrib) {
        $attrib = $self->validate_attribute_name($attrib);
        $self->{_output_attribute} = $attrib;
    }
    return $self->{_output_attribute};
}

=head2 output_allow_lists

By default if output column is parsed to a list of identifiers (as specified by
'split: ' in the YAML configuration file, then the lookup will throw an error
unless $parser->output_attribute has been set.

The permissible options are 'array', 'tostring', 'ambiguous'. array returns
an array reference from ($parser->lookup), tostring converts the list to a string
(joining by that specifed with $parser->join_lists_by), and ambiguous substitutes
the symbol/message returned by $parser->no_match_symbol('abiguous').


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

String by which to join multiple IDs/values parsed from a column. Defaults
to ', ' producing strings like 'identifier1, identifier2, identifier3'

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
names (as specified in the YAML parser config file 'parser_definitions.yml'.

The values themselves are hashes, with the keys:

  column
  id_type
  mandatory
  split 

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

Return a specific attribute by name, or throw an error if the name is invalid.

The attribute is a reference to a hash, see $parser->attributes. 

  my $attribute = $parser->get_attribute('sybmol');

=cut

sub get_attribute {
    my ( $self, $attribute ) = @_;

    unless ($attribute) {
        confess "Must pass an attribute";
    }
    $attribute = $self->validate_attribute_name($attribute);
    
    return $self->{_valid_attribs}->{$attribute};  
}

=head2 prepend_attribute

=cut 

sub prepend_attribute {
    my ( $self, $attribute_name, $string ) = @_;
    
    $attribute_name = $self->validate_attribute_name($attribute_name);
    my $attribute   = $self->get_attribute($attribute_name);
    if ($string) {
        $attribute->{prepend} = $string;
    }
    return $attribute->{prepend};
}

=head2 postpend_attribute

=cut 

sub postpend_attribute {
    my ( $self, $attribute_name, $string ) = @_;
    
    $attribute_name = $self->validate_attribute_name($attribute_name);
    my $attribute   = $self->get_attribute($attribute_name);
    if ($string) {
        $attribute->{postpend} = $string;
    }
    return $attribute->{postpend};
}

=head2 validate_attribute_name

Validates the passed attribute name, throwing a fatal error if was not
specified in the file parser, found in: parser_definitions.yml

  $parser->validate_attribute_name('symbol');

Returns the name of the passed attribute (lower-cased) if successful, 

=cut

sub validate_attribute_name {
    my ( $self, $attribute ) = @_;
    
    unless ($attribute) {
        confess "Must pass an attribute name to check";
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

Get/set method for the name of the parser, which is set automatically
by the constructor, by concatenating the passed dir and file name with
an underscore.

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

Instructs $parser->parse to convert the case of the IDs/keys parsed
from the file. Does this after the column validation.

Permissable values are 'upper', 'lower' and 'capital'

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

Instructs $parser->lookup to convert the case of its output 
(after the validation etc)

Permissable values are 'upper', 'lower' and 'capital'

=cut

sub output_convert_case {
    my ( $self, $case ) = @_;
    
    if ($case) { 
        $case = $self->_validate_case($case);
        $self->{_output_convert_case} = $case;
    }
    return $self->{_output_convert_case};
}

### _validate_case

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
