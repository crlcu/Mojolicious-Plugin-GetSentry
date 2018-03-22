package Mojolicious::Plugin::GetSentry;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '1.1';

use Data::Dump 'dump';
use Devel::StackTrace::Extract;
use Mojo::IOLoop;
use Sentry::Raven;

has [qw(
    sentry_dsn timeout
)];

has 'log_levels' => sub { ['error', 'fatal'] };
has 'processors' => sub { [] };

has 'raven' => sub {
    my $self = shift;

    return Sentry::Raven->new(
        sentry_dsn  => $self->sentry_dsn,
        timeout     => $self->timeout,
        processors  => $self->processors,
    );
};

has 'handlers' => sub {
    my $self = shift;

    return {
        capture_request     => sub { $self->capture_request(@_) },
        capture_message     => sub { $self->capture_message(@_) },
        stacktrace_context  => sub { $self->stacktrace_context(@_) },
        exception_context   => sub { $self->exception_context(@_) },
        user_context        => sub { $self->user_context(@_) },
        request_context     => sub { $self->request_context(@_) },
        tags_context        => sub { $self->tags_context(@_) },
        on_error            => sub { $self->on_error(@_) },
    };
};

has 'custom_handlers' => sub { {} };
has 'pending' => sub { {} };

sub register {
    my ($self, $app, $config) = (@_);
    
    my $handlers = {};

    foreach my $name (keys(%{ $self->handlers })) {
        $handlers->{ $name } = delete($config->{ $name });
    }

    # Set custom handlers
    $self->custom_handlers($handlers);

    $config ||= {};
    $self->{ $_ } = $config->{ $_ } for keys %$config;
    
    $self->hook_after_dispatch($app);
    $self->hook_on_message($app);
}

sub hook_after_dispatch {
    my $self = shift;
    my $app = shift;

    $app->hook(after_dispatch => sub {
        my $controller = shift;

        if (my $exception = $controller->stash('exception')) {
            # Mark this exception as handled. We don't delete it from $pending
            # because if the same exception is logged several times within a
            # 2-second period, we want the logger to ignore it.
            $self->pending->{ $exception } = 0 if defined $self->pending->{ $exception };
            
            $self->handle('capture_request', $exception, $controller);
        }
    });
}

sub hook_on_message {
    my $self = shift;
    my $app = shift;

    $app->log->on(message => sub {
        my ($log, $level, $exception) = @_;

        if( grep { $level eq $_ } @{ $self->log_levels } ) {
            $exception = Mojo::Exception->new($exception) unless ref $exception;

            # This exception is already pending
            return if defined $self->pending->{ $exception };
       
            $self->pending->{ $exception } = 1;

            # Wait 2 seconds before we handle it; if the exception happened in
            # a request we want the after_dispatch-hook to handle it instead.
            Mojo::IOLoop->timer(2 => sub {
                $self->handle('capture_message', $exception);
            });
        }
    });
}

sub handle {
    my ($self, $method) = (shift, shift);

    return $self->custom_handlers->{ $method }->($self, @_)
        if (defined($self->custom_handlers->{ $method }));
    
    return $self->handlers->{ $method }->(@_);
}

sub capture_request {
    my ($self, $exception, $controller) = @_;

    $self->handle('stacktrace_context', $exception);
    $self->handle('exception_context', $exception);
    $self->handle('user_context', $controller);
    $self->handle('tags_context', $controller);
    
    my $request_context = $self->handle('request_context', $controller);

    my $event_id = $self->raven->capture_request($controller->url_for->to_abs, %$request_context, $self->raven->get_context);

    if (!defined($event_id)) {
        $self->handle('on_error', $exception->message, $self->raven->get_context);
    }

    return $event_id;
}

sub capture_message {
    my ($self, $exception) = @_;

    $self->handle('exception_context', $exception);

    my $event_id = $self->raven->capture_message($exception->message, $self->raven->get_context);

    if (!defined($event_id)) {
        $self->handle('on_error', $exception->message, $self->raven->get_context);
    }

    return $event_id;
}

sub stacktrace_context {
    my ($self, $exception) = @_;

    my $stacktrace = Devel::StackTrace::Extract::extract_stack_trace($exception);

    $self->raven->add_context(
        $self->raven->stacktrace_context($self->raven->_get_frames_from_devel_stacktrace($stacktrace))
    );
}

sub exception_context {
    my ($self, $exception) = @_;

    $self->raven->add_context(
        $self->raven->exception_context($exception->message, type => ref($exception))
    );
}

sub user_context {
    my ($self, $controller) = @_;

    if (defined($controller->user)) {
        $self->raven->add_context(
            $self->raven->user_context(
                id          => $controller->user->id,
                ip_address  => $controller->tx && $controller->tx->remote_address,
            )
        );
    }
}

sub request_context {
    my ($self, $controller) = @_;

    if (defined($controller->req)) {
        my $request_context = {
            method  => $controller->req->method,
            headers => $controller->req->headers->to_hash,
        };

        $self->raven->add_context(
            $self->raven->request_context($controller->url_for->to_abs, %$request_context)
        );

        return $request_context;
    }

    return {};
}

sub tags_context {
    my ($self, $c) = @_;

    $self->raven->merge_tags(
        getsentry => $VERSION,
    );
}

sub on_error {
    my ($self, $message) = (shift, shift);

    die "failed to submit event to sentry service:\n" . dump($self->raven->_construct_message_event($message, @_));
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

=head2 raven

    Sentry::Raven instance

    See also L<Sentry::Raven|https://metacpan.org/pod/Sentry::Raven>

=head1 METHODS

L<Mojolicious::Plugin::GetSentry> inherits all methods from L<Mojolicious::Plugin> and implements the
following new ones.

=head2 stacktrace_context
    
    $app->sentry->stacktrace_context($exception)
    
    Build the stacktrace context from current exception.
    See also L<Sentry::Raven->stacktrace_context|https://metacpan.org/pod/Sentry::Raven#Sentry::Raven-%3Estacktrace_context(-$frames-)>

=head2 exception_context
    
    $app->sentry->exception_context($exception)
    
    Build the exception context from current exception.
    See also L<Sentry::Raven->exception_context|https://metacpan.org/pod/Sentry::Raven#Sentry::Raven-%3Eexception_context(-$value,-%25exception_context-)>

=head2 user_context

    $app->sentry->user_context($controller)
    
    Build the user context from current controller.
    See also L<Sentry::Raven->user_context|https://metacpan.org/pod/Sentry::Raven#Sentry::Raven-%3Euser_context(-%25user_context-)>

=head2 request_context

    $app->sentry->request_context($controller)

    Build the request context from current controller.
    See also L<Sentry::Raven->request_context|https://metacpan.org/pod/Sentry::Raven#Sentry::Raven-%3Erequest_context(-$url,-%25request_context-)>

=head2 tags_context
    
    $app->sentry->tags_context($controller)

    Add some tags to the context.
    See also L<Sentry::Raven->3Emerge_tags|https://metacpan.org/pod/Sentry::Raven#$raven-%3Emerge_tags(-%25tags-)>

head2 on_error
    
    $app->sentry->on_error($message, %context)

    Handle reporting to Sentry error.

=head1 SOURCE REPOSITORY

L<https://github.com/crlcu/Mojolicious-Plugin-GetSentry>

=head1 AUTHOR

Adrian Crisan, E<lt>adrian.crisan88@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2016 by Adrian Crisan.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
