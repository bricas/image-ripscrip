package Image::RIPscrip;

use Moose;

use Math::Base36 ();
use Graphics::Color::RGB;
use Graphics::Primitive::Brush;
use Graphics::Primitive::Canvas;
use Graphics::Primitive::Driver::Cairo;
use Graphics::Primitive::Operation::Fill;
use Graphics::Primitive::Operation::Stroke;
use Graphics::Primitive::Paint::Solid;
use Geometry::Primitive::Arc;
use Geometry::Primitive::Bezier;
use Geometry::Primitive::Circle;
use Geometry::Primitive::Ellipse;
use Geometry::Primitive::Point;
use Geometry::Primitive::Polygon;

our $VERSION = '0.01';

my @fullpal = map {
    my @d = split( //, sprintf( '%06b', $_ ) );
    {   red   => oct( "0b$d[ 3 ]$d[ 0 ]" ) / 3,
        green => oct( "0b$d[ 4 ]$d[ 1 ]" ) / 3,
        blue  => oct( "0b$d[ 5 ]$d[ 2 ]" ) / 3,
    }
} 0 .. 63;

my @defaultpal
    = map { $fullpal[ $_ ] } qw( 0 1 2 3 4 5 20 7 56 57 58 59 60 61 62 63 );
my @dash_patterns = ( undef, [ 2, 2 ], [ 3, 4, 3, 6 ], [ 3, 5, 3, 6 ], );
my $pi = atan2( 1, 1 ) * 4;

my %command_map = ( '=' => 'eq' );

has 'colors' => (
    isa     => 'ArrayRef',
    is      => 'ro',
    default => sub {
        [ map { Graphics::Color::RGB->new( %$_ ) } @defaultpal ];
    }
);

has 'fill_color' => ( isa => 'Int', is => 'rw', default => 0 );

has 'draw_color' => ( isa => 'Int', is => 'rw', default => 0 );

has 'draw_thickness' => ( isa => 'Int', is => 'rw', default => 1 );

has 'dash_pattern' => (
    isa     => 'Maybe[ArrayRef]',
    is      => 'rw',
    default => sub { $dash_patterns[ 0 ] }
);

has 'canvas' => (
    isa     => 'Object',
    is      => 'ro',
    default => sub {
        Graphics::Primitive::Canvas->new(
            width            => 640,
            height           => 350,
            background_color => shift->colors->[ 0 ]
        );
    },
    lazy => 1
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
        chomp( $line );

        for my $command_line ( split( /\|/, $line ) ) {
            my ( $command, $args ) = $command_line =~ m{^(\d*\D)(.*)}s;

            last if $command eq '#';
            next unless $command;

            my $method = $command_map{ $command } || $command;
            my $code = $self->can( "_command_${method}" );
            next unless $code;

            my @args = _parse_args( $args,
                ( $command =~ m{=} ) ? '(..)(....)(..)' : undef );
            $code->( $self, @args );
        }

    }

    close( $fh );
}

sub _command_p {    # filled polygon
    my ( $self, @args ) = @_;
    my $arg_cnt = shift @args;

    my $poly = Geometry::Primitive::Polygon->new;

    while ( @args ) {
        my $x = shift( @args );
        my $y = shift( @args );
        $poly->add_point(
            Geometry::Primitive::Point->new( 'x' => $x, 'y' => $y ) );
    }

    $self->canvas->path->add_primitive( $poly );

    $self->_fill();
    $self->_stroke();
}

sub _command_a {    # set palette entry
    my ( $self, @args ) = @_;
    my $old = $self->colors->[ $args[ 0 ] ];
    my $new = $fullpal[ $args[ 1 ] ];
    $old->red( $new->{ red } );
    $old->green( $new->{ green } );
    $old->blue( $new->{ blue } );
}

sub _command_S {    # set fill color
    my ( $self, @args ) = @_;
    $self->fill_color( $args[ 1 ] );
}

sub _command_c {    # set draw color
    my ( $self, @args ) = @_;
    $self->draw_color( $args[ 0 ] );
}

sub _command_Q {    # new palette
    my ( $self, @args ) = @_;
    for ( 0 .. 15 ) {
        my $new = $fullpal[ $args[ $_ ] ];
        my $old = $self->colors->[ $_ ];
        $old->red( $new->{ red } );
        $old->green( $new->{ green } );
        $old->blue( $new->{ blue } );
    }
}

sub _command_eq {
    my ( $self, @args ) = @_;
    if ( $args[ 0 ] != 4 ) {
        $self->dash_pattern( @dash_patterns[ $args[ 0 ] ] );
    }
    else {    # custom dash pattern
    }

    $self->draw_thickness( $args[ 2 ] );
}

sub _command_P {    # polygon
    my ( $self, @args ) = @_;
    my $arg_cnt = shift @args;
    my $poly    = Geometry::Primitive::Polygon->new;

    while ( @args ) {
        my $x = shift( @args );
        my $y = shift( @args );
        $poly->add_point(
            Geometry::Primitive::Point->new( 'x' => $x, 'y' => $y ) );
    }
    $self->canvas->path->add_primitive( $poly );

    $self->_stroke();
}

sub _command_l {    # polyline
    my ( $self, @args ) = @_;
    my $arg_cnt = shift @args;

    my $canvas = $self->canvas;
    $canvas->move_to( shift @args, shift @args );

    while ( @args ) {
        my $x = shift( @args );
        my $y = shift( @args );
        $canvas->line_to( $x, $y );
    }

    $self->_stroke();
}

sub _command_X {    # put pixel
    my ( $self, @args ) = @_;
    my $canvas = $self->canvas;
    $canvas->move_to( @args );
    $canvas->rectangle( 1, 1 );
    $self->_stroke();
}

sub _command_R {    # rectangle
    my ( $self, @args ) = @_;
    my $canvas = $self->canvas;
    $canvas->move_to( @args[ 0, 1 ] );
    $canvas->rectangle( $args[ 2 ] - $args[ 0 ], $args[ 3 ] - $args[ 1 ] );
    $self->_stroke();
}

sub _command_B {    # filled rectangle
    my ( $self, @args ) = @_;
    my $canvas = $self->canvas;
    $canvas->move_to( @args[ 0, 1 ] );
    $canvas->rectangle( $args[ 2 ] - $args[ 0 ], $args[ 3 ] - $args[ 1 ] );
    $self->_fill();
}

sub _command_L {    # line
    my ( $self, @args ) = @_;
    my $canvas = $self->canvas;
    $canvas->move_to( @args[ 0, 1 ] );
    $canvas->line_to( @args[ 2, 3 ] );
    $self->_stroke();
}

sub _command_o {    # filled ellipse
    my ( $self, @args ) = @_;
    my $ellipse = Geometry::Primitive::Ellipse->new(
        origin => [ @args[ 0, 1 ] ],
        width  => $args[ 2 ],
        height => $args[ 3 ]
    );
    $self->canvas->path->add_primitive( $ellipse );
    $self->_stroke( dash_pattern => undef );
    $self->_fill();
}

sub _command_C {    # circle
    my ( $self, @args ) = @_;
    my $circle = Geometry::Primitive::Circle->new(
        origin => [ @args[ 0, 1 ] ],
        radius => $args[ 2 ]
    );
    $self->canvas->path->add_primitive( $circle );
    $self->_stroke();
}

sub _command_Z {    # beizer curve
    my ( $self, @args ) = @_;

    # $args[ 8 ] is the number of segments
    my $bezier = Geometry::Primitive::Bezier->new(
        start    => [ @args[ 0, 1 ] ],
        control1 => [ @args[ 2, 3 ] ],
        control2 => [ @args[ 4, 5 ] ],
        end      => [ @args[ 6, 7 ] ],
    );
    $self->canvas->path->add_primitive( $bezier );
    $self->_stroke();
}

sub _command_A {    # circular arc
    my ( $self, @args ) = @_;
    my $arc = Geometry::Primitive::Arc->new(
        origin      => [ @args[ 0, 1 ] ],
        angle_start => deg2rad( $args[ 2 ] ),
        angle_end   => deg2rad( $args[ 3 ] ),
        radius      => $args[ 4 ]
    );
    $self->canvas->path->add_primitive( $arc );
    $self->_stroke( dash_pattern => undef );
}

sub _command_O {    # elliptical arc
    my ( $self, @args ) = @_;

    # $args[ 4 ] is x-radius
    # $args[ 5 ] is y-radius
    my $arc = Geometry::Primitive::Arc->new(
        origin      => [ @args[ 0, 1 ] ],
        angle_start => deg2rad( $args[ 2 ] ),
        angle_end   => def2rad( $args[ 3 ] ),
        radius      => $args[ 4 ]
    );
    $self->canvas->path->add_primitive( $arc );
    $self->_stroke( dash_pattern => undef );
}

# i don't see how this is any different than "O", so we'll re-use it.
*_command_V = \&_command_O;    # elliptical arc

sub _command_F {               # flood fill
    my ( $self, @args ) = @_;

    #    $i->fillToBorder( @args, $fill );
}

sub _command_1C {              # copy to clipboard
    my ( $self, @args ) = @_;

    #    my $w = $args[ 2 ] - $args[ 0 ];
    #    my $h = $args[ 3 ] - $args[ 1 ];

    #    next if $w < 0 or $h < 0;

    #    $clip = GD::Image->new( $w, $h );
    #    $clip->copy( $i, 0, 0, @args[ 0..1 ], $w, $h );
}

sub _comand_1P {               # paste from clipboard
    my ( $self, @args ) = @_;

    #    $i->copy( $clip, @args[ 0..1 ], 0, 0, $clip->getBounds );
}

sub _parse_args {
    my $args = shift;
    my $format = shift || '(..)';
    return
        map { Math::Base36::decode_base36( $_ ) . '' } $args =~ m{$format}gs;
}

sub _deg2rad {
    my $deg = shift;
    return ( $deg * $pi / 180 );
}

sub _fill {
    my $self    = shift;
    my $fill_op = Graphics::Primitive::Operation::Fill->new(
        paint => Graphics::Primitive::Paint::Solid->new(
            color => $self->colors->[ $self->fill_color ]
        )
    );
    $self->canvas->do( $fill_op );
}

sub _stroke {
    my $self    = shift;
    my %options = @_;
    my $dash
        = exists $options{ dash_pattern }
        ? $options{ dash_pattern }
        : $self->dash_pattern;
    my $stroke_op = Graphics::Primitive::Operation::Stroke->new(
        brush => Graphics::Primitive::Brush->new(
            width => $self->draw_thickness,
            color => $self->colors->[ $self->draw_color ],
            ( $dash ? ( dash_pattern => $dash ) : () )
        )
    );
    $self->canvas->do( $stroke_op );
}

sub _get_fh {
    my ( $file ) = @_;

    my $fh = $file;
    if ( !ref $fh ) {
        undef $fh;
        open $fh, $file;
    }

    binmode( $fh );
    return $fh;
}

sub render {
    my $self    = shift;
    my $file    = shift;
    my $options = shift || {};

    $options->{ format } ||= 'png';

    my $canvas = $self->canvas;
    my $driver = Graphics::Primitive::Driver::Cairo->new(
        format => $options->{ format } );

    $driver->prepare( $canvas );
    $driver->finalize( $canvas );
    $driver->draw( $canvas );

    $driver->write( $file );
}

no Moose;

__PACKAGE__->meta->make_immutable;

1;
