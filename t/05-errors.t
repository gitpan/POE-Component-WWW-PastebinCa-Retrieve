#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;
my $ID = 'rwrwv453255b252545';

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
    diag "Got error ($in->{error}) should be 404";
    ok( (defined $in->{error} and length $in->{error}),  '{error}');
    is( $in->{id}, $ID, '{id} must have id on error');
    is( $in->{_user}, 'foos', '{_user} must have user argument');
    is( scalar keys %$in, 3, '$_[ARG0] must have only three keys');
    
    $poco->shutdown;
}