package Mojolicious::Plugin::GetSentry;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '1.0';

use Devel::StackTrace::Extract;
use Mojo::IOLoop;
use Sentry::Raven;

has [qw(
    sentry_dsn timeout
)];

has 'log_levels' => sub { ['error', 'fatal'] };

has 'pending' => sub { {} };
has 'processors' => sub { [] };

has 'raven' => sub {
    my $self = shift;

    return Sentry::Raven->new(
        sentry_dsn  => $self->sentry_dsn,
        timeout     => $self->timeout,
        processors  => $self->processors,
    );
};

sub register {
    my ($self, $app, $config) = (@_);
    
    $config ||= {};
    $self->{$_} = $config->{$_} for keys %$config;
    
    $self->_hook_after_dispatch($app);
    $self->_hook_on_message($app);
}

sub _hook_after_dispatch {
    my $self = shift;
    my $app = shift;

    $app->hook(after_dispatch => sub {
        my $c = shift;

        if (my $ex = $c->stash('exception')) {
            # Mark this exception as handled. We don't delete it from $pending
            # because if the same exception is logged several times within a
            # 2-second period, we want the logger to ignore it.
            $self->pending->{$ex} = 0 if defined $self->pending->{$ex};

            $self->capture_request($ex, $c);
        }
    });
}

sub _hook_on_message {
    my $self = shift;
    my $app = shift;

    $app->log->on(message => sub {
        my ($log, $level, $ex) = @_;

        if( grep { $level eq $_ } @{ $self->log_levels } ) {
            $ex = Mojo::Exception->new($ex) unless ref $ex;

            # This exception is already pending
            return if defined $self->pending->{$ex};
       
            $self->pending->{$ex} = 1;

            # Wait 2 seconds before we handle it; if the exception happened in
            # a request we want the after_dispatch-hook to handle it instead.
            Mojo::IOLoop->timer(2 => sub {
                $self->capture_message($ex);
            });
        }
    });
}

sub capture_request {
    my ($self, $ex, $c) = @_;

    $self->add_stacktrace_context($ex);
    $self->add_exception_context($ex);
    $self->add_user_context($c);

    $self->handle_custom('tags_context', $c) if ($self->defined_custom('tags_context'));
    
    my $request_context = $self->add_request_context($c);

    my $event_id = $self->raven->capture_request($c->url_for->to_abs, %$request_context, $self->raven->get_context);

    if (!defined($event_id)) {
        die "failed to submit event to sentry service:\n"
            . CORE::dump($self->raven->_construct_message_event($ex->message, $self->raven->get_context));
    }

    return $event_id;
}

sub capture_message {
    my ($self, $ex) = @_;

    $self->add_exception_context($ex);

    my $event_id = $self->raven->capture_message($ex->message, $self->raven->get_context);

    if (!defined($event_id)) {
        die "failed to submit event to sentry service:\n"
            . CORE::dump($self->raven->_construct_message_event($ex->message, $self->raven->get_context));
    }

    return $event_id;
}

sub add_stacktrace_context {
    my ($self, $exception) = @_;

    my $stacktrace = Devel::StackTrace::Extract::extract_stack_trace($exception);

    $self->raven->add_context(
        $self->raven->stacktrace_context($self->raven->_get_frames_from_devel_stacktrace($stacktrace))
    );
}

sub add_exception_context {
    my ($self, $exception) = @_;

    $self->raven->add_context(
        $self->raven->exception_context($exception->message, type => ref($exception))
    );
}

sub add_user_context {
    my ($self, $c) = @_;

    return $self->handle_custom('user_context', $c) if ($self->defined_custom('user_context'));

    $self->raven->add_context(
        $self->raven->user_context(
            id          => $c->user->id,
            ip_address  => $c->tx->remote_address,
        )
    );
}

sub add_request_context {
    my ($self, $c) = @_;

    return $self->handle_custom('request_context', $c) if ($self->defined_custom('request_context'));

    my $request_context = {
        method  => $c->req->method,
        headers => $c->req->headers->to_hash,
    };

    $self->raven->add_context(
        $self->raven->request_context($c->url_for->to_abs, %$request_context)
    );

    return $request_context;
}

sub defined_custom {
    my ($self, $method, $param) = @_;

    my $sub = $self->{ $method };

    if (ref($sub) eq 'CODE') {
        return 1;
    }

    return 0;
}

sub handle_custom {
    my ($self, $method, $param) = @_;

    my $sub = $self->{ $method };

    if (ref($sub) eq 'CODE') {
        return $sub->($self->raven, $param);
    }
}

1;

__END__

=pod

=head1 NAME

Mojolicious::Plugin::GetSentry - Sentry client for Mojolicious

=head1 VERSION

version 1.0

=head1 SYNOPSIS
    
    # Mojolicious with config
    #
    $self->plugin('sentry' => {
        sentry_dsn  => 'DSN',
        timeout     => 3,
        logger      => 'root',
        platform    => 'perl',
    });

    # Mojolicious::Lite
    #
    plugin 'sentry' => {
        sentry_dsn  => 'DSN',
        timeout     => 3,
        logger      => 'root',
        platform    => 'perl',
    };

=head1 DESCRIPTION

Mojolicious::Plugin::GetSentry is a plugin for the Mojolicious web framework which allow you use Sentry L<https://getsentry.com>.
See also L<Sentry::Raven|https://metacpan.org/pod/Sentry::Raven>

=head1 ATTRIBUTES

L<Mojolicious::Plugin::GetSentry> implements the following attributes.

=head2 sentry_dsn

Sentry DSN url

=head2 timeout

Timeout specified in seconds

=head2 log_levels

Which log levels needs to be sent to Sentry
e.g.: ['error', 'fatal']

=head2 processors

A list of processors to filter down Sentry event
See also L<Sentry::Raven->processors|https://metacpan.org/pod/Sentry::Raven#$raven-%3Eadd_processors(-%5B-Sentry::Raven::Processor::RemoveStackVariables,-...-%5D-)>

=head1 METHODS

L<Mojolicious::Plugin::GetSentry> inherits all methods from L<Mojolicious::Plugin> and implements the
following new ones.

=head2 user_context

    $app->sentry->user_context($raven, $controller)
    
    Build the user context from current controller.
    See also L<Sentry::Raven->user_context|https://metacpan.org/pod/Sentry::Raven#Sentry::Raven-%3Euser_context(-%25user_context-)>

=head2 request_context

    $app->sentry->request_context($raven, $controller)

    Build the request context from current controller.
    See also L<Sentry::Raven->request_context|https://metacpan.org/pod/Sentry::Raven#Sentry::Raven-%3Erequest_context(-$url,-%25request_context-)>

=head2 tags_context
    
    $app->sentry->tags_context($raven, $controller)

    Add some tags to the context.
    See also L<Sentry::Raven->3Emerge_tags|https://metacpan.org/pod/Sentry::Raven#$raven-%3Emerge_tags(-%25tags-)>

=head1 SOURCE REPOSITORY

L<https://github.com/crlcu/Mojolicious-Plugin-GetSentry>

=head1 AUTHOR

Adrian Crisan, E<lt>adrian.crisan88@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2016 by Adrian Crisan.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
