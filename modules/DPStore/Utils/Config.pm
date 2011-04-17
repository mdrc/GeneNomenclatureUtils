### release

=pod

=head1 NAME - DPStore::Utils::Config

=head1 SYNOPSIS

=head2 Constructor:

my $config = DPStore::Utils::Config->new($filename, $debug);

=head1 DESCRIPTION

Utility module to parse .ini configuration files and check
that mandatory and optional parameters are found. Requires a 
'configure_parameters' routine in the calling programme
to find what the expected parameters are, which returns two
references to hashes of arrays, representing the section and
value format of the .ini file(s). If these are not found in the 
parsed file, a fatal error occurs.

    sub configure_parameters {

        my $mandatory = {};
        my $optional  = {};

        $mandatory->{'flank_size'} = ['size'];

        $mandatory->{'five_prime_arm'} = ['min', 'max'];
        $mandatory->{'five_prime_arm'} = ['min', 'max'];

        $optional->{'three_prime_arm'} = ['min', 'max'];
        return ($mandatory, $optional);
    }

The corresponding .ini file would need to contain at least
the following first two sections []:

    [flank_size]
    size = 10000

    [five_prime_arm]

    min = 6500
    max = 15000

    [three_prime_arm]

    min = 3500
    max = 15000

Methods names will be the concatenated section_name_variable_name,
so in the example above: flank_size_size, five_prime_arm_min, etc
Thus they need to be valid Perl method names (they cannot contain
spaces, and must start with a letter. This is checked, and causes
a fatal error should they not be validated.

These could then be acessed as:

my $size = $config->flank_size_size();
$config->flank_size_size(1000);


Information that MUST be present in the .ini file:
--------------------------------------------------

[binary paths]

linux = /analysis/mdr/bin/linux
osf1  = /analysis/mdr/bin/osf1

(Or an entry for whatever $^O says the os_type is)
(Used by _set_path_by_os_type_from_config)


[tmp_dir]
loc = /tmp

(Used by _set_tmp_dir to set $ENV{TMPDIR})


Optional sections in the .ini file
----------------------------------

[http_proxy]
url = http://wwwcache.sanger.ac.uk:3128


Utilises the Config::IniFiles library for .ini file parsing.

=head1 AUTHOR

webmaster@genes2cognition.org

=cut

package DPStore::Utils::Config;

use strict;
use warnings;
# use Bio::EnsEMBL::DBSQL::DBAdaptor;
# use DPStore::DBSQL::DBAdaptor;
use Carp;
use Config::IniFiles;


=head2 new

Constructor for a DPStore::Utils::Config object. Additional
methods will be added to the information found in the
main::configure_parameters methods

my $config = DPStore::Utils::Config->new($filename, $debug);

Debugging is enabled when $debug is true.

=cut

sub new {
    my( $pkg, $file, $debug, $simple ) = @_;

    my $cfg = $pkg->_parse_config_file($file, $debug);    
    my ($mandatory, $optional) = main::configure_parameters();
    my ($parameters, $values) = $pkg->_parse_parameters($cfg
        , $mandatory, $optional, $debug);
    $pkg->_validate_method_names($parameters);            
    $pkg->_make_get_set_methods($parameters, $values);

    my $objref = {};
    bless $objref, $pkg;
    $objref->_set_values($parameters, $values, $debug);
    $objref->ConfigIniFiles($cfg);
    unless ($simple) {
        $objref->_set_path_by_os_type_from_config($cfg, $debug);
        $objref->_set_tmp_dir($cfg, $debug);
        $objref->_set_http_proxy($cfg, $debug);
    }
    return $objref;    
}

sub _multi_files_cfg {
    my ( $self, $conf_dir, $files, $debug ) = @_;
    
    my $master_cfg;
    foreach my $file (@$files) {
        
        unless ($master_cfg) {
            $master_cfg = Config::IniFiles->new(-file => $conf_dir . $file)
                or confess "Can't open / error parsing : $conf_dir" . $file;
            print STDERR "Parsed: ", $conf_dir . $file . "\n" if $debug;
            next;
        }
        
        my $temp_cfg = Config::IniFiles->new(-file   => $conf_dir . $file,
                                             -import => $master_cfg)
            or confess "Can't open / error parsing : $conf_dir" . $file;
        print STDERR "Parsed: ", $conf_dir . $file . "\n" if $debug;
        $master_cfg = $temp_cfg;
    }
    return $master_cfg;
}

=head2 ConfigIniFiles

Get/set method for the Config::IniFiles object created by the class.
Shouldnt normally be set from outside the new constructor of
DPStore::Utils::Config::new

=cut

sub ConfigIniFiles {
    my ( $self, $cfg ) = @_;
   
    if ($cfg) {
        $self->{_dpstore_utils_config} = $cfg;
        unless ($cfg->isa('Config::IniFiles')) {
            confess "Must pass a Config::Inifiles object";
        }
    }

    return $self->{_dpstore_utils_config};
}

=head2 make_DBAdaptor_from_config

Given an object of class Config::IniFiles, attempts to make a
connection to an Ensembl core database, returning a 
Bio::EnsEMBL::DBSQL::DBAdaptor object, and the text of the
connection details as an array reference

An optional parameter (if true) causes the connection details
to be output to STDOUT

=cut

sub make_DBAdaptor_from_config {
    my ( $self, $output ) = @_;
    
    my $cfg = $self->ConfigIniFiles;
    
    my $db_name = $cfg->val('ensembl_database', 'db') or
    confess "'db' not set in '[ensembl_database]' section of config file";

    my $host = $cfg->val('ensembl_database', 'host') or
    confess "'host' not set in '[ensembl_database]' section of config file";

    my $user = $cfg->val('ensembl_database', 'user') or
    confess "'user' not set in '[ensembl_database]' section of config file";
    
    my ($pass, $port) = ($cfg->val('ensembl_database', 'pass')
        , $cfg->val('ensembl_database', 'port'));

    my $dba = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host   => $host,
                                                 -user   => $user,
                                                 -dbname => $db_name,
                                                 -pass   => $pass,
                                                 -port   => $port);
    my @txt;
    push (@txt, "Connected to host: $host");
    push (@txt, " (port: $port)") if $port;
    push (@txt, ", as user: $user\n");
    push (@txt, "Database         : $db_name\n\n");
    
    print @txt if $output;
    return ($dba, \@txt);    
}

=head2 make_analysis_DBAdaptor_from_config

Given an object of class Config::IniFiles, attempts to make a
connection to a DPStore analysis database, returning a 
DPStore::DBSQL::DBAdaptor object, and the text of the 
connection details as an array reference

An optional parameter (if true) causes the connection details
to be output to STDOUT

The environment variable 'g2c_db_name' can be use to
override the specified explicitly in the config file

=cut

sub make_analysis_DBAdaptor_from_config {
    my ( $self, $output ) = @_;
    return $self->make_g2c_dba_from_named_config('analysis_database', $output);
}

=head2 make_g2c_dba_from_named_config

Given an object of class Config::IniFiles, attempts to make a
connection to a G2C database, returning a 
DPStore::DBSQL::DBAdaptor object, and the text of the 
connection details as an array reference

param - name that identifies the connection details in the supplied config file.
param - optional - boolean that causes details to be output to STDOUT.

i.e. to get a typical g2c database adaptor,

    my $verbose_output = 1;
    my $g2c_dba = $cfg->make_g2c_dba_from_named_config(
            'analysis_database', 
            $verbose_output
    );

=cut

sub make_g2c_dba_from_named_config {
    my ( $self, $name, $output ) = @_;
    
    my $cfg = $self->ConfigIniFiles;
    
    my $db_name = $cfg->val($name, 'db') or
    confess "'db' not set in '[". $name . "]' section of config file";
    
    my $host = $cfg->val($name, 'host') or
    confess "'host' not set in '[". $name . "]' section of config file";

    my $user = $cfg->val($name, 'user') or
    confess "'user' not set in '[". $name . "]' section of config file";
    
    my ($pass, $port) = ($cfg->val($name, 'pass'), $cfg->val($name, 'port'));

    my $dba = DPStore::DBSQL::DBAdaptor->new;
    $dba->host($host);
    $dba->db($db_name);
    $dba->user($user);
    $dba->pass($pass);
    $dba->port($port);
    $dba->dbh;

    my @txt;
    push (@txt, "Connected to host: $host");
    push (@txt, " (port: $port)") if $port;
    push (@txt, ", as user: $user\n");
    push (@txt, "Database       : $db_name\n\n");
    
    print @txt if ($output);
    return ($dba, \@txt);    
}

=head2 _set_http_proxy 

Internal method called by the new method to set the http_proxy
environment variable should it be specified in the parsed .ini
file

=cut 

sub _set_http_proxy {
    my ( $self, $cfg, $debug ) = @_;
    
    my $url;
    if ($url = $cfg->val('http_proxy', 'url')) {
        $ENV{http_proxy} = $url;
        print STDERR 'Set $ENV{http_proxy} to ', "$url\n" if $debug;
    } else {
        print STDERR "'url' not set in '[http_proxy]' section of config file\n"
            if $debug;
    }
    
}

=head2 _set_path_by_os_type_from_config

Internal method called by new. Given an object of class Config::IniFiles
prepends a directory to $ENV{PATH} based on operating system type

Expects to find something like this in the previously-parsed .ini file:

[binary paths]
linux = /bin/linux
osf1  = /team71/analysis/mdr/bin/osf1

Confesses if the information is not found in the .ini file, or is
not a valid directory

=cut

sub _set_path_by_os_type_from_config {
    my ( $self, $cfg, $debug ) = @_;

    my $os_type = $^O;
    print STDERR "os_type: $os_type\n" if $debug;
    my $bin_path;
    unless ($bin_path = $cfg->val('binary_paths', $os_type)) {
        confess "'$os_type' not set in '[binary paths]' section of config file";
    }
    
    unless (-d $bin_path) {
        confess "Invalid binaries path for $os_type"
            ." '[binary paths]' section of config file\n";
    }  
    
    print STDERR "Prepending: $bin_path to " . '$PATH', "\n" if $debug;
    $ENV{PATH} = $bin_path . ':' . $ENV{PATH};
}

=head2 _set_tmp_dir

Internal method called by new. Sets the environment variable TMPDIR to
value of the parameter loc in the [tmp_dir] section of the parsed
.ini file.;

Confess if the parameter is not set, or points to an invalid directory.

=cut

sub _set_tmp_dir {
    my ( $self, $cfg, $debug ) = @_;
    
    my $tmp_dir;
    unless ($tmp_dir = $cfg->val('tmp_dir', 'loc')) {
        confess "'loc' not set in 'tmp_dir' section of config file";
    }
    unless (-d $tmp_dir)  {
        confess "Set 'loc' not set in '[tmp_dir]' " 
            . "section to a writable directory";
    }
    $ENV{TMPDIR} = $tmp_dir;
    print STDERR 'Set $ENV{TMPDIR} to ', "$tmp_dir\n" if $debug;
}

=head2 _set_values

Internal routine called by the new method, to initialise the
values of the objects newly created attribute to those parsed
from the .ini file.

=cut 

sub _set_values {
    my ( $self, $parameters, $values, $debug) = @_;
    
    for (my $i = 0; $i <= $#$parameters; $i++) {
        my $method = $parameters->[$i];
        my $value  = $values->[$i];
        $self->$method($value);

        if ($debug) {
            print STDERR 'Set $config->', $parameters->[$i];
            if (defined($values->[$i])) {
                print STDERR "($values->[$i])";
            } else {
                print STDERR "(undef)";
            }
            print STDERR "\n";
        }
    }
    print STDERR "\n" if $debug;
}

=head2 _parse_config_file

Given a file name looks for it in the directory pointed to by
the environment variable $DPStoreConfDir

Confesses upon error.

=cut

sub _parse_config_file {
    my ( $self, $file, $debug ) = @_;
    
    my $conf_dir = $ENV{DPStoreConfDir};
    unless ($conf_dir) {
        confess "Set ", '$DPStoreConfDir', " environment variable";
    }
    unless (-d $conf_dir) {
        confess "Set ", '$DPStoreConfDir', " to a valid directory";
    }
    unless ($conf_dir =~ /\/$/) {
        $conf_dir .= '/';
    }
    
    #print STDERR "** $conf_dir\n";
    #die;

    #Make the default config file name based on $0
    my $prog_name = $0;
    if (rindex($prog_name, '/') > -1) {
        $prog_name = substr($prog_name, rindex($prog_name, '/') + 1);    
    }
    $prog_name .= '_defaults.ini';
    
    my $cfg;

    if ($file) { #Is $file ARRAY ref or a single file ?
        if (ref($file) =~ /ARRAY/) {
            $cfg = $self->_multi_files_cfg($conf_dir, $file, $debug);
        } else {
            $cfg = Config::IniFiles->new(-file => $conf_dir . $file)
                or confess "Can't open / error parsing : $conf_dir" . $file;
        }
        print STDERR "Parsed: ", $conf_dir . $file . "\n" if $debug;
        
    } else {
        confess "Must pass a config file name or reference to an array"
            . " of config file names"; 
    }
    return $cfg;
}

=head2 _parse_parameters

Internal method called by new. Uses the passed Config::IniFiles object,
together with mandatory and optional parameters (passed as hash refs)
to validate the .ini configuration file.

=cut

{
    my (@parameters, @values);
    sub _parse_parameters {
        my ( $self, $cfg, $mandatory, $optional, $debug ) = @_;

        print STDERR "\nParsing parameters\n" if $debug;
        print STDERR "------------------\n\n" if $debug;

        @parameters = (); @values = ();
        if (keys(%{$mandatory})) {
            print STDERR "Looking for mandatory:\n\n" if $debug;
            foreach my $section (keys(%{$mandatory})) {

                foreach my $var (@{$mandatory->{$section}}) {

                    my $value = $cfg->val($section, $var);
                    unless (defined($value)) {
                        confess "'[$section]' '$var' not set";
                    }               
                    _push_parameter_and_value($section, $var, $value, $debug);
                }
            }
            print STDERR "\n" if $debug;
        }

        if (keys(%{$optional})) {
            print STDERR "Looking for optional:\n\n" if $debug;
            foreach my $section (keys(%{$optional})) {

                foreach my $var (@{$optional->{$section}}) {

                    my $value = $cfg->val($section, $var);
                    _push_parameter_and_value($section, $var, $value
                        , $debug);
                }
            }
            print STDERR "\n" if $debug;
        }
        return (\@parameters, \@values);
    }

    sub _push_parameter_and_value {
        my ( $section, $var, $value, $debug ) = @_;

        my $parameter = $section . '_' . $var; 
        push(@parameters, $parameter);
        push(@values, $value);

        if ($debug) {
            my $parameter_combo = "  ('[$section]', '$var')";
            print STDERR $parameter_combo, ' ' x (40
                - length($parameter_combo));
            if (defined($value)) {
                print STDERR " : Value : $value\n";
            } else {
                print STDERR " : Value : undefined\n";
            }
        }
    }    
}

=head2 _validate_method_names

Internal method called by new. Checks that the names passed by
array reference do not contain any spaces, and start a with
a letter. 


=cut 

sub _validate_method_names {
    my ( $self, $method_ref ) = @_;
    
    foreach my $method_name (@$method_ref) {
        
        $method_name =~ s/\s+$//;
        if ($method_name =~ /\s/) {
            confess "Whitespace in method name: '$method_name'";
        }
        unless ($method_name =~ /^\w/ and ($method_name =~ /^\D/)) {
            confess "Method name must start with a letter: '$method_name'";
        } 
    }
    return;
}


=head2 _make_get_set_methods

Internal method called by the new method, creating the get/set methods
for the object.

=cut

sub _make_get_set_methods {
    my ( $pkg, $parameters, $values ) = @_;

    # Make a get-set method for each parameter
    foreach my $param (@$parameters) {
        no strict 'refs';
        
        my $get_set_sub = "${pkg}::$param";
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
            
            if (defined $arg) {
                $self->{$field} = $arg;
            }
            return $self->{$field};
        };
    }
}

1;
