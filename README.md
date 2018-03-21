# Mojolicious-Plugin-GetSentry
Sentry client for Mojolicious

# Intialization

```perl
$self->plugin('GetSentry', {
    sentry_dsn => '...',
    tags_context => sub {
        my ($raven, $c) = @_;

        $raven->merge_tags(
            account => '12345',
        );
    },
    user_context => {
        my ($raven, $c) = @_;

        $raven->add_context(
            $raven->user_context(
                id          => 1,
                ip_address  => '10.10.10.1',
            )
        );
    },
    request_context => {
        my ($raven, $c) = @_;

        $raven->add_context(
            $raven->request_context('https://custom.domain/profile', method => 'GET', headers => { ... });
        );
    },
});
```

# Defaults

`tags_context` - nothing is captured by default
`user_context` - this plugin is trying to capture the `user id` and the `ip address`
`request_context` - this plugin is trying to capture the `url`, `request method` and the `headers`
