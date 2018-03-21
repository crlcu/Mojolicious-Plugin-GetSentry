# Mojolicious-Plugin-GetSentry
Sentry client for Mojolicious

# Intialization

```perl
$self->plugin('GetSentry', {
    sentry_dsn => '...',
    tags_context => sub {
        my ($raven, $c) = @_;

        ...
    },
    user_context => {
        my ($raven, $c) = @_;

        ...
    },
    request_context => {
        my ($raven, $c) = @_;

        ...
    },
});
```
