package POE::Component::WWW::PastebinCa::Retrieve;

use warnings;
use strict;

our $VERSION = '0.004';

use Carp;
use WWW::Pastebin::PastebinCa::Retrieve;
use POE qw( Filter::Reference  Filter::Line  Wheel::Run );

sub spawn {
    my $package = shift;
    croak "$package requires an even number of arguments"
        if @_ & 1;

    my %params = @_;
    
    $params{ lc $_ } = delete $params{ $_ } for keys %params;

    delete $params{options}
        unless ref $params{options} eq 'HASH';
    
    $params{obj_args} = {
        timeout => delete( $params{timeout} ),
        ua      => delete( $params{ua}      ),
    };

    my $self = bless \%params, $package;

    $self->{session_id} = POE::Session->create(
        object_states => [
            $self => {
                retrieve => '_retrieve',
                shutdown => '_shutdown',
            },
            $self => [
                qw(
                    _child_error
                    _child_closed
                    _child_stdout
                    _child_stderr
                    _sig_child
                    _start
                )
            ]
        ],
        ( defined $params{options} ? ( options => $params{options} ) : () ),
    )->ID();

    return $self;
}


sub _start {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $self->{session_id} = $_[SESSION]->ID();

    if ( $self->{alias} ) {
        $kernel->alias_set( $self->{alias} );
    }
    else {
        $kernel->refcount_increment( $self->{session_id} => __PACKAGE__ );
    }

    $self->{wheel} = POE::Wheel::Run->new(
        Program    => sub{ _wheel( $self->{obj_args} ); },
        ErrorEvent => '_child_error',
        CloseEvent => '_child_close',
        StdoutEvent => '_child_stdout',
        StderrEvent => '_child_stderr',
        StdioFilter => POE::Filter::Reference->new,
        StderrFilter => POE::Filter::Line->new,
        ( $^O eq 'MSWin32' ? ( CloseOnCall => 0 ) : ( CloseOnCall => 1 ) )
    );

    $kernel->yield('shutdown')
        unless $self->{wheel};

    $kernel->sig_child( $self->{wheel}->PID(), '_sig_child' );

    undef;
}

sub _sig_child {
    $poe_kernel->sig_handled;
}

sub session_id {
    return $_[0]->{session_id};
}

sub retrieve {
    my $self = shift;
    $poe_kernel->post( $self->{session_id} => 'retrieve' => @_ );
}

sub _retrieve {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    my $sender = $_[SENDER]->ID;
    
    return
        if $self->{shutdown};
        
    my $args;
    if ( ref $_[ARG0] eq 'HASH' ) {
        $args = { %{ $_[ARG0] } };
    }
    else {
        carp "First parameter must be a hashref, trying to adjust...";
        $args = { @_[ARG0 .. $#_] };
    }
    
    $args->{ lc $_ } = delete $args->{ $_ }
        for grep { !/^_/ } keys %$args;

    unless ( $args->{event} ) {
        carp "Missing 'event' parameter to retrieve";
        return;
    }
    unless ( $args->{id} ) {
        carp "Missing 'id' parameter to retrieve";
        return;
    }

    if ( $args->{session} ) {
        if ( my $ref = $kernel->alias_resolve( $args->{session} ) ) {
            $args->{sender} = $ref->ID;
        }
        else {
            carp "Could not resolve 'session' parameter to a valid"
                    . " POE session";
            return;
        }
    }
    else {
        $args->{sender} = $sender;
    }
    
    $kernel->refcount_increment( $args->{sender} => __PACKAGE__ );
    $self->{wheel}->put( $args );
    
    undef;
}

sub shutdown {
    my $self = shift;
    $poe_kernel->call( $self->{session_id} => 'shutdown' => @_ );
}

sub _shutdown {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $kernel->alarm_remove_all;
    $kernel->alias_remove( $_ ) for $kernel->alias_list;
    $kernel->refcount_decrement( $self->{session_id} => __PACKAGE__ )
        unless $self->{alias};

    $self->{shutdown} = 1;
    
    $self->{wheel}->shutdown_stdin
        if $self->{wheel};
}

sub _child_closed {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    
    carp "_child_closed called (@_[ARG0..$#_])\n"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_error {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    carp "_child_error called (@_[ARG0..$#_])\n"
        if $self->{debug};

    delete $self->{wheel};
    $kernel->yield('shutdown')
        unless $self->{shutdown};

    undef;
}

sub _child_stderr {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    carp "_child_stderr: $_[ARG0]\n"
        if $self->{debug};

    undef;
}

sub _child_stdout {
    my ( $kernel, $self, $input ) = @_[ KERNEL, OBJECT, ARG0 ];
    
    my $session = delete $input->{sender};
    my $event   = delete $input->{event};

    $kernel->post( $session, $event, $input );
    $kernel->refcount_decrement( $session => __PACKAGE__ );
    
    undef;
}

sub _wheel {
    my $obj_args = shift;

    if ( $^O eq 'MSWin32' ) {
        binmode STDIN;
        binmode STDOUT;
    }
    
    my $raw;
    my $size = 4096;
    my $filter = POE::Filter::Reference->new;

    my $paster = WWW::Pastebin::PastebinCa::Retrieve->new( %$obj_args );

    while ( sysread STDIN, $raw, $size ) {
        my $requests = $filter->get( [ $raw ] );
        foreach my $req_ref ( @$requests ) {

            _process_request( $paster, $req_ref ); # changes $req_ref

            my $response = $filter->put( [ $req_ref ] );
            print STDOUT @$response;
        }
    }
}

sub _process_request {
    my ( $paster, $req_ref ) = @_;
    my $response_ref = $paster->retrieve( $req_ref->{id} );

    if ( defined $response_ref ) {
        %$req_ref = ( %$response_ref, %$req_ref );
        @$req_ref{ qw(uri id) } = ( $paster->uri, $paster->id );
    }
    else {
        $req_ref->{error} = $paster->error;
    }

    undef;
}


1;
__END__


=head1 NAME

POE::Component::WWW::PastebinCa::Retrieve - non-blocking wrapper around WWW::Pastebin::PastebinCa::Retrieve

=head1 SYNOPSIS

    use strict;
    use warnings;

    use POE qw(Component::WWW::PastebinCa::Retrieve);

    my $poco = POE::Component::WWW::PastebinCa::Retrieve->spawn;

    POE::Session->create(
        package_states => [ main => [qw(_start retrieved )] ],
    );

    $poe_kernel->run;

    sub _start {
        $poco->retrieve( {
                id    => 'http://pastebin.ca/931145',
                event => 'retrieved',
            }
        );
    }

    sub retrieved {
        my $in = $_[ARG0];

        if ( $in->{error} ) {
            print "Error: $in->{error}\n";
        }
        else {
            printf "The paste number %d was created on %s (%s ago) by %s"
                    . ". It appears to be %s, you can check it out on %s\n\n%s\n",
                    @$in{ qw(id post_date age name language uri content) };
        }

        $poco->shutdown;
    }

Using event based interface is also possible of course.

=head2 DESCRIPTION

The module is a non-blocking wrapper around L<WWW::PastebinCa::Retrieve>
which provides interface to retrieve pastes from L<http://pastebin.ca>

=head1 CONSTRUCTOR

=head2 spawn

    my $poco = POE::Component::WWW::PastebinCa::Retrieve->spawn;

    POE::Component::WWW::PastebinCa::Retrieve->spawn(
        alias => 'paster',
        timeout => 10,
        # or:  ua => LWP::UserAgent->new( timeout => 10, agent => 'blah'),
        options => {
            debug => 1,
            trace => 1,
            # POE::Session arguments for the component
        },
        debug => 1, # output some debug info
    );

The C<spawn> method returns a
POE::Component::WWW::PastebinCa::Retrieve object. It takes a few arguments,
I<all of which are optional>. The possible arguments are as follows:

=head3 alias

    POE::Component::WWW::PastebinCa::Retrieve->spawn(
        alias => 'paster'
    );

B<Optional>. Specifies a POE Kernel alias for the component.

=head3 timeout

    ->spawn( timeout => 10 );

B<Optional>. Specifies the timeout argument of L<LWP::UserAgent>'s
constructor, which is used for pasting. B<Defaults to>: C<30> seconds.

=head3 ua

    ->spawn( ua => LWP::UserAgent->new( agent => 'Foos!' ) );

B<Optional>. If the C<timeout> argument is not enough for your needs of
mutilating the L<LWP::UserAgent> object used for retrieving the pastes, feel
free to specify the C<ua> argument which takes an L<LWP::UserAgent> object
as a value. B<Note:> the C<timeout> argument to the constructor will not do
anything if you specify the C<ua> argument as well. B<Defaults to:> plain
boring default L<LWP::UserAgent> object with C<timeout> argument set to
whatever POE::Component::WWW::PastebinCa::Retrieve's C<timeout> argument is
set to as well as C<agent> argument is set to mimic Firefox.

=head3 options

    my $poco = POE::Component::WWW::PastebinCa::Retrieve->spawn(
        options => {
            trace => 1,
            default => 1,
        },
    );

B<Optional>.
A hashref of POE Session options to pass to the component's session.

=head3 debug

    my $poco = POE::Component::WWW::PastebinCa::Retrieve->spawn(
        debug => 1
    );

When set to a true value turns on output of debug messages. B<Defaults to:>
C<0>.

=head1 METHODS

=head2 retrieve

    $poco->retrieve( {
            event => 'event_for_output',
            id    => 'http://pastebin.ca/931145',
            # or just '931145',
            _blah => 'pooh!',
            session => 'other',
        }
    );

Takes a hashref as an argument, does not return a sensible return value.
See C<retrieve> event's description for more information.

=head2 session_id

    my $poco_id = $poco->session_id;

Takes no arguments. Returns component's session ID.

=head2 shutdown

    $poco->shutdown;

Takes no arguments. Shuts down the component.

=head1 ACCEPTED EVENTS

=head2 retrieve

    $poe_kernel->post( paster => retrieve => {
            event => 'event_for_output',
            id    => 'http://pastebin.ca/931145',
            # or just '931145',
            _blah => 'pooh!',
            session => 'other',
        }
    );

Instructs the component to retrieve the paste. Takes a hashref as an
argument, the possible keys/value of that hashref are as follows:

=head3 event

    { event => 'results_event', }

B<Mandatory>. Specifies the name of the event to emit when results are
ready. See OUTPUT section for more information.

=head3 id

    { id => 'http://pastebin.ca/931145' }

    { id => '931145' }

B<Mandatory>. As a value takes a full URI to the paste you want to retrieve
or just its ID.

=head3 session

    { session => 'other' }

    { session => $other_session_reference }

    { session => $other_session_ID }

B<Optional>. Takes either an alias, reference or an ID of an alternative
session to send output to.

=head3 user defined

    {
        _user    => 'random',
        _another => 'more',
    }

B<Optional>. Any keys starting with C<_> (underscore) will not affect the
component and will be passed back in the result intact.

=head2 shutdown

    $poe_kernel->post( paster => 'shutdown' );

Takes no arguments. Tells the component to shut itself down.

=head1 OUTPUT

    $VAR1 = {
        'language' => 'Perl Source',
        'content' => 'blah blah',
        'name' => 'Zoffix',
        'age' => '11 hrs 33 mins',
        'uri' => bless( do{\(my $o = 'http://pastebin.ca/931145')}, 'URI::http' ),
        'post_date' => 'Thursday, March 6th, 2008 at 4:57:44pm MST',
        'id' => '931145',
        '_blah' => 'foos'
    };

The event handler set up to handle the event which you've specified in
the C<event> argument to C<retrieve()> method/event will recieve input
in the C<$_[ARG0]> in a form of a hashref. The possible keys/value of
that hashref are as follows:

=head2 content

    { 'content' => 'blah blah' }

The C<content> key will contain the content of the paste as its value.

=head2 error

    { 'error' => 'Failed to retrieve the paste: 404 File Not Found' }

If there was some problem while retrieving your paste the C<error> key will
be present and will contain a human parseable description of the error.

=head2 id

    { 'id' => '931145' }

If an error occured, the C<id> key will contain whatever you've specified
as an C<id> argument to C<retrieve()> event/method. Otherwise it will
contain the ID number of the retrieved paste.

=head2 uri

    { 'uri' => bless( do{\(my $o = 'http://pastebin.ca/931145')}, 'URI::http' ) }

The C<uri> key will contain the L<URI> object pointing to the page
of the paste you've retrieved.

=head2 language

    { 'language' => 'Perl Source' }

The C<language> key will contain the (computer) language the paste
is written in.

=head2 post_date

    { 'post_date' => 'Thursday, March 6th, 2008 at 4:57:44pm MST' }

The C<post_date> key will contain the date and time when the paste was
created.

=head2 name

    { 'name' => 'Zoffix' }

The C<name> key will contain name of the poster or title of the paste.

=head2 age

    { 'age' => '11 hrs 33 mins' }

The C<age> key will contain the age of the paste (how long ago it was
created)

=head2 user defined

    { '_blah' => 'foos' }

Any arguments beginning with C<_> (underscore) passed into the C<retrieve()>
event/method will be present intact in the result.

=head1 SEE ALSO

L<POE>, L<LWP::UserAgent>, L<WWW::PastebinCa::Retrieve>

=head1 AUTHOR

Zoffix Znet, C<< <zoffix at cpan.org> >>
(L<http://zoffix.com>, L<http://haslayout.net>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-poe-component-www-pastebinca-retrieve at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=POE-Component-WWW-PastebinCa-Retrieve>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc POE::Component::WWW::PastebinCa::Retrieve

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-WWW-PastebinCa-Retrieve>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/POE-Component-WWW-PastebinCa-Retrieve>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/POE-Component-WWW-PastebinCa-Retrieve>

=item * Search CPAN

L<http://search.cpan.org/dist/POE-Component-WWW-PastebinCa-Retrieve>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 Zoffix Znet, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
