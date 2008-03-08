#!/usr/bin/env perl

use strict;
use warnings;

die "Usage: perl retrieve.pl <paste_ID_or_URI>\n"
    unless @ARGV;

my $Paste = shift;

use lib '../lib';
use POE qw(Component::WWW::PastebinCa::Retrieve);

my $poco = POE::Component::WWW::PastebinCa::Retrieve->spawn;

POE::Session->create(
    package_states => [
        main => [ qw(_start retrieved) ],
    ],
);

$poe_kernel->run;

sub _start {
    $poco->retrieve({ id => $Paste, event => 'retrieved' });
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