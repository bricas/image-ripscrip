package Image::RIPscrip;

use Moose;
use Carp 'croak';

our $VERSION = '0.01';

has 'commands' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } ) ;

my %arg_map = (
    '=' => '(..)(....)(..)',
    '@' => { format => '^(..)(..)(.*)', count => 2 },
    'T' => { format => '^(.*)', count => 0 },
    "1\x1b" => { format => '^(.)(...)(.*)', count => 2 },
);

sub read {
    my ( $self, $fh ) = @_;

    $fh = _get_fh( $fh );

    while ( my $line = <$fh> ) {
        last if $line =~ m{\x1a};

        while ( $line =~ m{\\\s*$} ) {    # parse any continuations
            $line =~ s{\\\s*$}{};
            $line .= <$fh>;
        }
        $line =~ s{[\r\n]+$}{};
        $line =~ s{^(\!\|)}{};
        next unless $1 && $1 eq '!|';

        for my $command_line ( split( /\|/, $line ) ) {
            my ( $command, $args ) = $command_line =~ m{^(\d*\D)(.*)}s;

            last if $command eq '#';
            # use Data::Dump 'dump'; warn dump( $command, $args );
            next unless $command;

            my @args = _parse_args( $args, $arg_map{ $command } );

            push @{ $self->commands }, { command => $command, args => \@args };
        }
    }

    close( $fh );
}

sub _parse_args {
    my $args = shift;
    my $format = shift || '(..)';
    my $count  = 2048;
    
    if( ref $format ) {
        $count  = $format->{ count };
        $format = $format->{ format };
    }

    return
        map { $count-- > 0 ? ( Math::Base36::decode_base36( $_ ) . '' ) : $_ } $args =~ m{$format}g;
}

sub _get_fh {
    my ( $file ) = @_;

    my $fh = $file;
    if ( !ref $fh ) {
        undef $fh;
        open $fh, '<', $file    ## no critic (InputOutput::RequireBriefOpen)
            or croak "Unable to open '$file': $!";
    }

    binmode( $fh );
    return $fh;
}

no Moose;

__PACKAGE__->meta->make_immutable;

1;
