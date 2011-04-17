### release

=pod

=head1 NAME - DPStore::Utils::TabFileParser

=head1 DESCRIPTION

=head1 AUTHOR

webmaster@genes2cognition.org

=cut

package DPStore::Utils::TabFileParser;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use Exporter;
use IO::File;
use vars qw{ @ISA @EXPORT_OK };


@ISA = ('Exporter');
@EXPORT_OK = qw(
    clean_array_elements_of_whitespace
    clean_line_of_trailing_whitespace
    clean_tab_delimited_file
    close_data_files
    close_output_files
    confirm_keys_are_present
    get_tab_file_geometry
    open_data_file
    open_output_file
    output_array_of_arrays
    output_hash_of_arrays
    output_tab_delimited_txt_from_hash_of_arrays
    parse_columns_from_parameter
    parse_tab_delimited_file_to_array
    parse_tab_delimited_file_to_hash_keyed_by_column
    read_next_line_from_data_file 
    set_tabfileparser_clobber
    set_tabfile_parser_path_root
    write_line_to_output_file
    write_lines_to_output_file
    find_keys_in_two_hashes
    find_keys_not_in_second_hash
    verify_cell
);

sub parse_columns_from_parameter {
    my ( $param, $geometry ) = @_;

    $param =~ s/^\s+//g;
    $param =~ s/\s+$//g;

    unless ($param) {
        confess "Nothing to parse";
    }
    
    my @columns = split(',', $param);
    
    foreach my $column (@columns) {
        unless ($column >= 1) {
            confess "Invalid column spec (must be >= 1) in '$param'";
        }
        if ($column > $geometry->{columns}) {
            confess "Column is out of range '$column' \n";
        }
    }
    
    return \@columns;
}


=pod get_tab_file_geometry

my $geometry = get_tab_file_geometry($file, $has_title);

Returns a hashref with the following keys

  titles                    - if $has_title is true
  columns                   - column count
  column_widths             - insepct if not rectangular
  rectangular               - true if the file is rectangular
  rows                      - row count

=cut 
 
sub get_tab_file_geometry {
    my ( $file, $skip_title) = @_;
    
    my $geometry = {};

    my $data = parse_tab_delimited_file_to_array($file, 'clean');
    if ($skip_title) {
        my $titles = shift(@$data);

        my $column = 1;
        my $titles_by_column = {};
        
        foreach my $title (@$titles) {
            $titles_by_column->{$column} = $title;
            $column++;
        }
        $geometry->{titles} = $titles_by_column;
    }
    my $column_widths = {};
    my $row_count     = 0;

    foreach my $entry (@$data) {
    
        $row_count++;

        my $width = $#$entry + 1;
        $column_widths->{$width}++;
    }
    
    $geometry->{rows}          = $row_count;
    $geometry->{column_widths} = $column_widths;
    
    if (scalar(keys(%$column_widths)) == 1) {
    
        my ($columns) = keys(%$column_widths);
        $geometry->{rectangular}++;
        $geometry->{columns} = $columns;
    } else {
        $geometry->{rectangular} = 0;
    }
    return $geometry;
}

=head2 verify_cell

TODO: Needs to be written

=cut

sub verify_cell {
    my ( $parsed, $col, $row, $expected ) = @_;
    
    unless ($parsed and ref($parsed) eq 'ARRAY') {
        confess "Expected an ARRAY reference";
    }
    unless (defined($expected)) {
        confess "Error with expected";
    }
    unless (defined($col) and $col >= 0) {
        confess "Error with col";
    }
    unless (defined($row) and $row >= 0) {
        confess "Error with row";
    }
    
    my $value     = $parsed->[$col]->[$row];
    if ($value eq $expected) {
        return 1;
    } else {
        print STDERR "Expected: '$expected' got: " . Dumper($value);
    }
}


=head2 find_keys_in_two_hashes

Given two hash references, finds the keys common to
both hashes, returning an array reference to them
or undef should none be common

A third optional parameter, if true, causes a report
to be output to STDOUT

  my $common_ids = find_keys_in_two_hashes($hash1, $hash2);

=cut

sub find_keys_in_two_hashes {
    my ( $hash1, $hash2, $noisy ) = @_;
    
    my @ids;
    my $found_count = 0;
    foreach my $key (keys(%{$hash1})) {
        if ($hash2->{$key}) {
            push (@ids, $key);
            $found_count++;
            print "$key\n" if $noisy;
        }
    }
    if ($noisy) {
        print "\nFound a total of: $found_count ids from ", scalar(keys(%{$hash1}));
        print " in ", scalar(keys(%{$hash2})), "\n";
    }
    if (@ids) {
        return \@ids;
    } else {
        return;
    }
}

=head2 find_keys_not_in_second_hash

Given two hash references, finds the keys not in
the second hash, returning an array reference to them
or undef if thee is none.

A third optional parameter, if true, causes a report
to be output to STDOUT

  my $not_found_ids
    = find_keys_not_in_second_hash($hash1, $hash2);

=cut

sub find_keys_not_in_second_hash {
    my ( $hash1, $hash2, $noisy ) = @_;
    
    my @ids;
    my $missed_count = 0;
    foreach my $key (keys(%{$hash1})) {
        unless ($hash2->{$key}) {
            push (@ids, $key);
            $missed_count++;
            print "$key\n" if $noisy;
        }
    }
    if ($noisy) {
        print "\nFound a total of: $missed_count ids from ", scalar(keys(%{$hash1}));
        print " not in second hash of ", scalar(keys(%{$hash2})), "\n";
    }
    if (@ids) {
        return \@ids;
    } else {
        return;
    }
}

=head2 output_hash_of_arrays

Given a reference to a hash of arrays prints them to
STDOUT joining the array elements with tab chars.

Confesses if you dont pass a valid HASH reference.

=cut

sub output_hash_of_arrays {
    my ( $hash ) = @_;
    
    unless ($hash and ref($hash) =~ /HASH/) {
        confess "Must pass a hash reference";
    }
    
    my $array = [];
    foreach my $key (keys(%{$hash})) {
        push (@$array, $hash->{$key});
    }    
    output_array_of_arrays($array);
}

=head2 output_array_of_arrays

Given a reference to an array prints the elements
on a line joined by tab chars.

A second optional parameter allows the output to
be passed to a file handle

=cut

sub output_array_of_arrays {
    my ( $array, $fh ) = @_;
    
    my $error;
    unless ($array and ref($array) =~ /ARRAY/) {
        confess "Must pass an array reference";
    }
    $fh = \*STDOUT unless $fh;
    
    foreach my $array_ref (@$array) {
        my $line = join "\t", @$array_ref;
        print $fh "$line\n" or $error++;
    }
    
    if ($error) {
        return;
    } else {
        return 1;
    }
}


=head2 confirm_keys_are_present

Given a hash reference, an array reference (to an array of arrays)
and a column number (indexed from 1), treats each array as if it
was a row parsed from a spreadsheet, then checks the value/key found
in the specified columm, is present as a key in the hash.

Returns an error count, the number of arrays (rows) checked and a
reference to an array of the error msg(s) generated.

=cut 

sub confirm_keys_are_present {
    my ( $hash, $arrays, $column ) = @_;
    
    unless ($hash and ref($hash) =~ /HASH/) {
        confess "First parameter must be a hash reference";
    }
    unless ($arrays and ref($arrays) =~ /ARRAY/) {
        confess "Second parameter must be an array reference";
    }
    unless ($column and $column >= 1) {
        confess "Third parameter must be a column number >= 1"; 
    }
    
    my $err_count = 0;
    my $rows = 0;
    my @error_msgs;
    foreach my $array (@$arrays) {

        $rows++;
        unless (scalar(@$array) >= $column) {
            push (@error_msgs, "Line only has " . scalar(@$array) . " columns: '"
                . join ("\t", @$array) . "'\n");
            $err_count++;
            next;
        }
        
        my $key = $array->[$column - 1];
        unless ($key) {
            push (@error_msgs, "No key present in column: $column for line '"
                . join ("\t", @$array) . "'\n");
            $err_count++;
            next;
        }
        
        unless ($hash->{$key}) {
            push (@error_msgs, "Key '$key' not found in hash for line '"
                . join ("\t", @$array) . "'\n");
            $err_count++;
        }
    }
    
    my $errors;
    $errors = \@error_msgs if $err_count;
    
    return ($err_count, $rows, $errors);
}


{
    my ($parser_temp_name, $count);   
    sub _get_temp_name {

        unless ($parser_temp_name) {
            $parser_temp_name = $0 . '_' . $$ . '_';
        }
        $count++;
        
        return $parser_temp_name . $count;
    }
}

=head2 parse_tab_delimited_file_to_array {
    
Given a file name, parses the file to an array of
anonymous arrays, the latter being populated by
splitting each line of the file on tab chars (after
removing trailing whitespace)

Returns an array reference, or undef should no
lines have been successfully parsed.

Passing a second (optional) parameter of 'clean'
forces the parser to clean each element of whitespace 
    
=cut


sub parse_tab_delimited_file_to_array {
    my ( $file, $clean ) = @_;

    confess "Must pass a file_name" unless $file;

    my $input_name  = _get_temp_name();

    my @file;
    open_data_file($input_name, $file);
    while (defined(my $line = read_next_line_from_data_file($input_name))) {

        chomp($line);
        #$line = clean_line_of_trailing_whitespace($line);
        my @fields = split(/\t/, $line);
        unless (@fields >= 1) {
            carp "Parsed no columns from line '$line'"
                unless $DPStore::Utils::TabFileParser::quiet;
            next;
        }
        if ($clean) {
            clean_array_elements_of_whitespace(\@fields);
        }

        push (@file, \@fields);
    }

    if (@file) {
        return \@file;
    } else {
        return;
    }
}

=head2 parse_tab_delimited_file_to_hash_keyed_by_column

Given a file name and a column number (leftmost column is numbered 1)
from which to use as the source of the keys for the hash, parses each
line of the file to an array by splitting on tab chars, checking that
the column keys are not duplicated

The values of the hash will be a reference to an anonymous array of the
fields that were separated by tabs 

A third optional parameter (if true) allows keys to be duplicated, with
only the last parsed line (with the key) being returned.

=cut 

sub parse_tab_delimited_file_to_hash_keyed_by_column {
    my ( $file, $column, $allow_duplicates, $skip_missing_keys ) = @_;

    confess "Must pass a file_name" unless $file;
    confess "Must pass a column number" unless $column and $column >= 1;

    my $input_name  = _get_temp_name();

    my %tab_file_hash;
    open_data_file($input_name, $file);
    while (defined(my $line = read_next_line_from_data_file($input_name))) {

        my $key;
        $line = clean_line_of_trailing_whitespace($line);
        my @fields = split(/\t/, $line);
        unless (@fields >= 1) {
            carp "Parsed no columns from line '$line'"
                unless $DPStore::Utils::TabFileParser::quiet;
            next;
        }

        if (@fields < $column) {
            unless ($skip_missing_keys) {
                confess "Cant parse a key on column $column for '$line'";
            } else {
                print STDERR "Can't parse a key on column $column for '$line'\n";
                next;
            }
        } else {
            $key = $fields[$column - 1];
        }

        if ($tab_file_hash{$key}) {
            if ($allow_duplicates) {
                print STDERR "[WARN] Duplicate key for: '$key'\n"
                    unless $DPStore::Utils::TabFileParser::quiet;
            } else {
                confess "Duplicate key for: '$key'";
            }
        }
        clean_array_elements_of_whitespace(\@fields);
        
        $tab_file_hash{$key} = \@fields;
    }
    if (keys(%tab_file_hash)) {
        return \%tab_file_hash;
    } else {
        return;
    }
}

=head2  clean_line_of_trailing_whitespace

Given a line cleans it of leading and trailing whitespace,
returning it. Warns if a null line is passed.

Doesn't remove tab chars

=cut 

sub clean_line_of_trailing_whitespace {
    my ( $line ) = @_;

    if ($line) {
        chomp($line);
        $line =~ s/\n+$//; #Remove LF at EOL
        $line =~ s/\r+$//; #Remove CR at EOL
        $line =~ s/ +$//;
        $line =~ s/^\n+//; #Remove LF at SOL
        $line =~ s/^\r+//; #Remove CR at SOL
        $line =~ s/^ +//; #Remove CR at SOL       
        return $line;
    } else {
        carp "Caution you passed a null line"
            unless $DPStore::Utils::TabFileParser::quiet;
    }
}

=head2 clean_tab_delimited_file

Given an input file name and an output file name, reads
each line of the input file, trims leading and trailing
whitespace, splits the line on the tabs, removes any
whitespace from each element, and joins the line back
together with tabs, and outputs it to the file specified.

=cut

sub clean_tab_delimited_file {
    my ( $input_file, $output_file ) = @_;
    
    confess "Must pass an input file name"  unless $input_file;
    confess "Must pass an output file name" unless $output_file;
    
    my $input_name  = $input_file  . '_' . $0 . '_' . $$ . '_input';
    my $output_name = $output_file . '_' . $0 . '_' . $$ . '_output';

    open_data_file($input_name, $input_file);
    open_output_file($output_name, $output_file);
    while (defined(my $line = read_next_line_from_data_file($input_name))) {
        $line = clean_line_of_trailing_whitespace($line);

        my @fields = split(/\t/, $line);
        clean_array_elements_of_whitespace(\@fields);
        
        my $concat_string = join '', @fields;
        if ($concat_string) {
            my $line = join "\t", @fields;
            write_line_to_output_file($output_name, "$line\n");
        }
    }
}

=head2 clean_array_elements_of_whitespace

Given an array reference, iterates over the elements of the 
array removing leading and trailing whitespace (\s)

=cut
 
sub clean_array_elements_of_whitespace {
    my ( $array ) = @_;                                                                                                                                               

    
    for (my $i = 0; $i <= $#$array; $i++) {
        if ($array->[$i]) {
            $array->[$i] =~ s/^\s+//;
            $array->[$i] =~ s/\s+$//;
        }
    }
}

=head2 output_tab_delimited_txt_from_hash_of_arrays

Given a reference to a hash of arrays iterates over
the arrays (alphabetically sorted by the hash keys)
outputting each array as a line joined by tab chars

Confesses if a valid hash reference is not passed.

=cut 

sub output_tab_delimited_txt_from_hash_of_arrays {
    my ( $hash ) = @_; 

    unless ($hash and ref($hash) =~ /HASH/) {
        confess "Must pass a hash reference";
    }
        
    foreach my $key (sort (keys(%{$hash}))) {
        my $line = join "\t", @{$hash->{$key}};
        print "'$key' -> '$line'\n";
    }
}

# File I/O routines to manage input and output to multiple
# files being keyed by a short_name given to them

{
    my (%input_handles, %output_handles, $clobber, $path_root);

=head2 set_tabfile_parser_path_root

Used to get/set a path used as an optional root by the
open_data_file and open_output_file routines.

=cut

    sub set_tabfile_parser_path_root {
        my ( $path ) = @_;
        
        if (defined($path)) {
    
            unless ($path =~ /\/$/) {
                $path_root .= '/';
            }
            $path_root = $path;
        }
        return $path_root;
    }

=head2 set_tabfileparser_clobber

Used to set whether file ing is allowed i.e.
overwriting of a previously existing file.

Set to any true value to allow clobbering.

=cut
    
    sub set_tabfileparser_clobber {
        my ( $state ) = @_;
        
        if (defined($state)) {
    
            $clobber = $state;
        }
        return $clobber;
    }

=head2 open_data_file

Given a short name and a file name, opens the file for reading.
Confesses if the short name is already in use, or the file
cannot be opened.

Uses the path specified by set_tabfile_parser_path_root if it has been set.

    open_data_file('test', 'substrates_1.txt');

    my $line_count = 0;
    while (defined(my $line = read_next_line_from_data_file('test'))) {
        $line_count++;
    }
    print "Total lines read: $line_count\n";    

=cut

    sub open_data_file {
        my ( $short_name, $file ) = @_;
        
        confess "Must pass a short_name for file" unless $short_name;
        confess "Must pass a file_name" unless $file;

        if ($path_root) {
            $file = $path_root . $file;
        }
                
        unless (-f $file and -s $file) {
            confess "Cannot read file '$file': $!";
        }
        if ($input_handles{$short_name}) {
            confess "A file with that short_name has already been opened"
                . $input_handles{$short_name}->[1];
        }
        
        my $fh_in = new IO::File;
        $fh_in->open("<$file")
            or confess "Could not open for reading '$file': $!";
        $input_handles{$short_name} = [$fh_in, $file];
        return 1;
    }

=head2 read_next_line_from_data_file

Given a short name for the previously opened file reads a line from 
it, returning it exactly as read, or undef.

    my $line = read_next_line_from_data_file('test');
    
=cut 

    sub read_next_line_from_data_file  {
        my ( $short_name ) = @_;
        
        confess "Must pass a short_name" unless $short_name;
        unless ($input_handles{$short_name}) {
            confess "No such short_name '$short_name' for input file";
        }
        
        my $fh_in = $input_handles{$short_name}->[0];
        my $line = <$fh_in>;
        return $line;
    }

=head2 close_data_files

Closes all open data (input) files, carping if there are
any errors from the close calls to IO:File

    close_data_files();

=cut
    
    sub close_data_files {
        
        foreach my $short_name (keys(%input_handles)) {

            my $fh_in = $input_handles{$short_name}->[0];
            unless ($fh_in->close) {
                confess "Could not close input file $!";
            }
            delete($input_handles{$short_name});
        }
        return 1;
    }

=head2 open_output_file

Given a short name and a file name, opens the file for writing.
Confesses if the short name is already in use, or the file already
exists (unless set_tabfileparser_clobber has been set to true).

Uses the path specified by set_tabfile_parser_path_root if it has been set.

=cut 


    sub open_output_file {
        my ( $short_name, $file ) = @_;
        
        confess "Must pass a short_name for output file" unless $short_name;
        confess "Must pass a file_name for output file" unless $file;
        
        if ($output_handles{$short_name}) {
            confess "A file with that short_name has already been opened"
                . $output_handles{$short_name}->[1];
        }

        if ($path_root) {
            $file = $path_root . $file;
        }
        
        if (-e $file and !$clobber) {
            confess "Output file '$file' already exists";
        }
        
        my $fh_out = new IO::File;
        $fh_out->open(">$file") or confess "Could not open for writing '$file': $!";
        $output_handles{$short_name} = [$fh_out, $file];
        return 1;
    }

=head2 write_lines_to_output_file

Given a short name and a reference to an array of lines, writes them to the output file
previously opened and assigned to the short name.

Confesses unless an array reference is passed, or an error occurs on writing.

=cut

    sub write_lines_to_output_file  {
        my ( $short_name, $lines ) = @_;
        
        confess "Must pass a short_name" unless $short_name;
        unless ($lines and ref($lines) =~ /ARRAY/) {
            confess "Must pass an ARRAY reference line to write to '$short_name'";
        }
        
        unless ($output_handles{$short_name}) {
            confess "No such short_name '$short_name' for output file";
        }
        
        my $fh_out = $output_handles{$short_name}->[0];
        foreach my $line (@$lines) {
            print $fh_out $line
                or confess "Could not write line: $!";
        }
        return 1;
    }

=head2 write_line_to_output_file

Given a short name and a line (scalar) writes it to the output file
previously opened and assigned to the short name.

Confesses if a null line is passed, or an error occurs on writing.

=cut

    sub write_line_to_output_file  {
        my ( $short_name, $line ) = @_;
        
        confess "Must pass a short_name" unless $short_name;
        confess "Must pass a line to write to '$short_name'" unless $line;
        
        unless ($output_handles{$short_name}) {
            confess "No such short_name '$short_name' for output file";
        }
        
        my $fh_out = $output_handles{$short_name}->[0];
        print $fh_out $line
            or confess "Could not write line: $!";
        return 1;
    }


=head2 close_output_files

Close all files previously opened with call(s) to
open_output_file. Carps if an error is raised attempting
to close a file.

=cut    
    sub close_output_files {

        my $return_code = 1;
        foreach my $short_name (keys(%output_handles)) {
            
            my $fh_out = $output_handles{$short_name}->[0];
            unless ($fh_out->close) {
                confess "Could not close output file $!";
                $return_code = '';
            }
	    delete $output_handles{$short_name};
        }
        return $return_code;
    }
}


our $quiet;

1;
