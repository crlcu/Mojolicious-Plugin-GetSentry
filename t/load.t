#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok('Mojolicious::Plugin::GetSentry');
}

diag(
    "Testing Mojolicious::Plugin::GetSentry $Mojolicious::Plugin::GetSentry::VERSION, Perl $], $^X"
);
