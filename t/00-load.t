#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 9;

BEGIN {
    use_ok('Carp');
    use_ok('WWW::Pastebin::PastebinCa::Retrieve');
    use_ok('POE');
    use_ok('POE::Filter::Reference');
    use_ok('POE::Filter::Line');
    use_ok('POE::Wheel::Run');
	use_ok('POE::Component::WWW::PastebinCa::Retrieve');
}

diag( "Testing POE::Component::WWW::PastebinCa::Retrieve $POE::Component::WWW::PastebinCa::Retrieve::VERSION, Perl $], $^X" );

use POE qw(Component::WWW::PastebinCa::Retrieve);

my $poco = POE::Component::WWW::PastebinCa::Retrieve->spawn(debug=>1);
isa_ok($poco, 'POE::Component::WWW::PastebinCa::Retrieve');
can_ok($poco, qw(spawn shutdown retrieve session_id _start _sig_child
                    _retrieve _shutdown _child_closed _child_error
                    _child_stderr _child_stdout _wheel _process_request));

POE::Session->create(
    inline_states => { _start => sub { $poco->shutdown; }, },
);

$poe_kernel->run;