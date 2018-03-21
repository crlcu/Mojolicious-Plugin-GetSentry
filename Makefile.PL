use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    NAME => 'Mojolicious::Plugin::GetSentry',
    AUTHOR => 'Adrian Crisan <adrian.crisan88@gmail.com>',
    LICENSE => 'artistic_2',
    ABSTRACT_FROM => 'lib/Mojolicious/Plugin/GetSentry.pm',
    VERSION_FROM => 'lib/Mojolicious/Plugin/GetSentry.pm',
    ABSTRACT => 'Sentry client for Mojolicious',
    EXE_FILES => [qw(  )],
    META_MERGE => {
        resources => {
            bugtracker => 'https://github.com/crlcu/Mojolicious-Plugin-GetSentry/issues',
            homepage => 'https://github.com/crlcu/Mojolicious-Plugin-GetSentry',
            repository => 'https://github.com/crlcu/Mojolicious-Plugin-GetSentry.git',
        },
    },
    BUILD_REQUIRES => {
        'Test::More' => '0',
        'File::Find' => '0',
    },
    PREREQ_PM    => {
        'Devel::StackTrace::Extract' => 0,
        'Mojo::IOLoop' => 0,
        'Sentry::Raven' => 0,
        'Mojolicious'   => 0,
    },
    test => {
        TESTS => "t/*.t"
    },
);
