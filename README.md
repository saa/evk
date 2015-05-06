evk
=====

Erlang library for vk.com (vkontakte)

Build
-----

    $ rebar3 compile

Features
--------

- secure.sendNotification

Example
-------

```erlang
1> application:set_env(evk, client_id, "123").
ok
2> application:set_env(evk, client_secret, "wekfUYbf").
ok
3) evk:send_notification(<<"12314">>, <<"Hello!">>).
ok
```
