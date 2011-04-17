### release

=pod

=head1 NAME - DPStore::Utils::Counts

=head1 SYNOPSIS

=head2 Constructor:

my $counts = DPStore::Utils::Counts->new(@counts);

=head1 DESCRIPTION

Object used to hold a number of custom named counts, specified by name
at runtime. Each count gets its own method calls. These are auto-generated
by _make_count_get_set_methods(). $Count->name is a get/set, and an
increment method is named $Count->increment_name.

=head1 AUTHOR 

webmaster@genes2cognition.org

=cut

package DPStore::Utils::Counts;

use strict;
use warnings;
use Carp;

use vars '@ISA';

=head2 new

Constructor for objects of type DPStore::Utils::Counts

my $counts = DPStore::Utils::Counts->new('ESTs', 'Clones', 'errors');

=cut

sub new {
    my( $pkg, @counts ) = @_;
    
    confess "No counts specified" unless @counts;
    $pkg->_make_count_get_set_methods(@counts);

    my $objref = {};
    bless $objref, $pkg;
    $objref->_count_list(@counts);

    return $objref;   
}

sub _count_list {
    my $self = shift;
    
    if (@_) {
        $self->{'_count_list'} = [@_];
    } else {
        my $l = $self->{'_count_list'} || [];
        return @$l;
    }
}

sub _longest_count_name {
    my ( $self) = @_;
    
    my @counts = $self->_count_list();
    my $longest_count = 0;
    foreach my $count (@counts) {
        if (length($count) > $longest_count) {
            $longest_count = length($count);
        }
    }
    return $longest_count;    

}

=head2 display_counts

Outputs all the counts as sorted formatted text, by default to
STDOUT else to the filehandle passed by reference to the 
typeglobbed filehandle;

    $counts->display_counts(\*STDERR);

=cut

sub display_counts {
    my ( $self, $fh ) = @_;

    unless ($fh) {
        $fh = \*STDOUT;
    }    
    
    my @counts = $self->_count_list();
    my $longest_name =  $self->_longest_count_name();
    print $fh "\n";
    foreach my $count (sort @counts) {
        print $fh $count . ' ' x ($longest_name - length($count)) . ' : ';
        my $val;
        if (defined($val = $self->$count))  {
            print $fh $val;
        } else {
            print 'Undefined';
        }
        print $fh "\n";
    }
    print $fh "\n";
}

=head2 stderr

Outputs all the counts as sorted formatted text to STDERR

    $counts->stderr($counts);

=cut

sub stderr {
    my ( $self ) = @_;
    
    $self->display_counts(\*STDERR);
}

=head2 undefined_ok

Get/set method for the undefined_ok property. Unless this
is set to true, then the count methods will automatically
return 0 rather than undefined, if it has not been set
explicitly.

=cut

sub undefined_ok {
    my ( $self, $value ) = @_;
    
    if (defined($value)) {
        $self->{_dpstore_utils_counts} = $value;
    }
    return $self->{_dpstore_utils_counts};
}

=head2 _make_count_get_set_methods

Magic routine to create the get/set methods for the object.

=cut

sub _make_count_get_set_methods {
    my( $pkg, @parameters ) = @_;

    # Make a get-set method for each parameter
    foreach my $param (@parameters) {
        no strict 'refs';
        
        my $get_set_sub = "${pkg}::$param";
        my $incr_sub    = "${pkg}::increment_$param";
        my $field = "_$param";
        
        # Check that this method doesn't already exist
        if (defined(&$get_set_sub)) {
            confess "Method '$get_set_sub' is already defined!";
        }

        # Insert a subroutine ref into the symbol
        # table under this name.  (This is the bit
        # that need strict refs turned off.)
        *$get_set_sub = sub {
            my( $self, $arg ) = @_;
            
            if (defined($arg)) {
                $self->{$field} = $arg;
            } else {
                unless (defined($self->{$field})) {
                    $self->{$field} = 0 unless $self->undefined_ok;
                }
            }
            return $self->{$field};
        };

        *$incr_sub = sub {
            my( $self ) = @_;
            
            $self->{$field}++;
        };
    }
}

1;
