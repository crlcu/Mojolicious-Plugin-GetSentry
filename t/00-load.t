#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Mojolicious::Plugin::GetSentry' ) || print "Bail out!\n";
}

diag( "Testing Mojolicious::Plugin::GetSentry $Mojolicious::Plugin::GetSentry::VERSION, Perl $], $^X" );
