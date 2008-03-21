use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'POE::Component::WWW::PastebinCa::Retrieve',
    license             => 'perl',
    dist_author         => 'Zoffix Znet <zoffix@cpan.org>',
    dist_version_from   => 'lib/POE/Component/WWW/PastebinCa/Retrieve.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'Carp'                      => 1.04,
        'WWW::Pastebin::PastebinCa::Retrieve' => 0.001,
        'POE'                       => 0.9999,
        'POE::Filter::Reference'    => 1.2220,
        'POE::Filter::Line'         => 1.2222,
        'POE::Wheel::Run'           => 1.2222,
    },
    add_to_cleanup      => [ 'POE-Component-WWW-PastebinCa-Retrieve-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
