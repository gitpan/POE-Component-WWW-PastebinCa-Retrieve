#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;
my $ID = '931145';
my $PASTE_DUMP = {
          'language' => 'Perl Source',
          'content' => "{\r\n\ttrue => sub { 1 },\r\n\tfalse => sub { 0 },\r\n\ttime  => scalar localtime(),\r\n}",
          'post_date' => 'Thursday, March 6th, 2008 at 4:57:44pm MST',
          'name' => 'Zoffix',
          '_user' => 'foos',
          'id' => $ID,
          'uri' => URI->new( "http://pastebin.ca/$ID" ),
};

use POE qw(Component::WWW::PastebinCa::Retrieve);

my $poco = POE::Component::WWW::PastebinCa::Retrieve->spawn(debug=>1);

POE::Session->create(
    package_states => [ main => [qw(_start ret) ] ]
);

$poe_kernel->run;

sub _start {
    $poco->retrieve({ id => $ID, event => 'ret', _user => 'foos' });
}

sub ret {
    my $in = $_[ARG0];
    is(
        ref $in,
        'HASH',
        '$_[ARG0] must contain a hashref',
    );
    SKIP: {
        if ( $in->{error} ) {
            diag "Got error $in->{error}";
            ok( (defined $in->{error} and length $in->{error}),  '{error}');
            is( $in->{id}, $ID, '{id} must have id on error');
            is( $in->{_user}, 'foos', '{_user} must have user argument');
            is( scalar keys %$in, 3, '$_[ARG0] must have only three keys');
        }
        else {
            ok( (exists $in->{age} and length $in->{age}), '{age} must be present');
            delete $in->{age};
            is_deeply( $in, $PASTE_DUMP, 'matching to Dumper');
            skip "No errors, skipping ERROR tests", 2;
        }
    } # SKIP{}
    $poco->shutdown;
}