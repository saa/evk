-module(evk).

-include("evk.hrl").

%% API exports
-export([send_notification/2]).
-export([groups_is_member/2]).

-type error_result() :: {error, non_neg_integer(), binary()}.
-type result() :: ok | error_result().

%%====================================================================
%% API functions
%%====================================================================

send_notification(UserId, Message) when is_binary(UserId) ->
    send_notification([UserId], Message);
send_notification(UserIds, Message) when is_list(UserIds),
                                         length(UserIds) =< 100,
                                         is_binary(Message),
                                         size(Message) =< 254 ->
    request(send_notification, UserIds, Message).

groups_is_member(GroupId, UserId) when is_binary(GroupId), is_integer(UserId) ->
    case request(?EVK_GROUPS_IS_MEMBER, [GroupId, UserId]) of
        {ok, #{<<"member">> := 1}} ->
            true;
        {ok, #{<<"member">> := 0}} ->
            false;
        Error ->
            Error
    end.

%%====================================================================
%% Internal functions
%%====================================================================

request(Method, Params) ->
    URL = get_method_url(Method, Params),
    {ok, Response} = request(URL),
    case maps:is_key(<<"error">>, Response) of
        true ->
            get_error(maps:get(<<"error">>, Response));
        false ->
            {ok, maps:get(<<"response">>, Response)}
    end.

-spec request(atom(), [binary()], binary()) -> result().
request(Action, UserIds, Message) ->
    case get_access_token() of
        {ok, AccessToken} ->
            request(Action, AccessToken, UserIds, Message);
        {error, _Reason} = Error ->
            Error
    end.

-spec request(atom(), binary(), [binary()], binary()) -> result().
request(send_notification, AccessToken, UserIds, Message) ->
    URL = gen_send_notification_url(AccessToken, UserIds, Message),
    {ok, Response} = request(URL),
    case lists:keyfind(<<"error">>, 1, Response) of
        false ->
            ok;
        {<<"error">>, Error} ->
            get_error(Error)
    end.

-spec get_error(map()) -> error_result().
get_error(Error) ->
    {error, maps:get(<<"error_code">>, Error), maps:get(<<"error_msg">>, Error)}.

-spec join([binary() | string()], [binary() | string()]) -> binary().
join([], Acc) ->
    iolist_to_binary(lists:reverse(Acc));
join([I | R], Acc) when R /= [] ->
    join(R, [[I, ","] | Acc]);
join([I | R], Acc) when R == [] ->
    join(R, [I | Acc]).

-spec get_client_secret() -> undefined | string().
get_client_secret() ->
    application:get_env(?MODULE, client_secret, undefined).

-spec get_client_id() -> undefined | string().
get_client_id() ->
    application:get_env(?MODULE, client_id, undefined).

-spec get_access_token() -> {ok, binary()} | error_result().
get_access_token() ->
    get_access_token(get_client_id(), get_client_secret()).

-spec get_access_token(undefined | string(), undefined | string()) -> {ok, binary()} | error_result().
get_access_token(ClientId, ClientSecret) when is_list(ClientId),
                                              is_list(ClientSecret) ->
    URL = gen_access_token_url(ClientId, ClientSecret),
    case request(URL) of
        {ok, Response} ->
            {<<"access_token">>, AccessToken} = lists:keyfind(<<"access_token">>, 1, Response),
            {ok, AccessToken};
        {error, _Reason} = Error ->
            Error
    end;
get_access_token(_, _) ->
    {error, creds_not_set}.

-spec request(binary() | string()) -> {ok, [{binary(), any()}]} | error_result().
request(URL) ->
    case hackney:post(URL) of
        {ok, 200, _Hdrs, Ref} ->
            {ok, JSON} = hackney:body(Ref),
            {ok, jsx:decode(JSON, [return_maps])};
        {ok, Status, _Hdrs, Ref} ->
            {ok, Error} = hackney:body(Ref),
            {error, {Status, Error}}
    end.

-spec gen_access_token_url(string(), string()) -> binary().
gen_access_token_url(ClientId, ClientSecret) ->
    iolist_to_binary(["https://oauth.vk.com/access_token",
                      "?client_id=", ClientId,
                      "&client_secret=", ClientSecret,
                      "&v=", ?EVK_API_VERSION,
                      "&grant_type=client_credentials"]).

-spec gen_send_notification_url(binary(), [binary()], binary()) -> binary().
gen_send_notification_url(AccessToken, UserIds, Message) ->
    UserIdsBin = join(UserIds, []),
    iolist_to_binary([?EVK_API_URL, ?EVK_SECURE_SEND_NOTIFICATION,
                      "?user_ids=", UserIdsBin,
                      "&v=", ?EVK_API_VERSION,
                      "&message=", hackney_url:urlencode(Message),
                      "&access_token=", AccessToken,
                      "&client_secret=", get_client_secret()]).

get_method_url(?EVK_GROUPS_IS_MEMBER = Method, [GroupId, UserId]) when is_integer(UserId) ->
    UserIdBin = integer_to_binary(UserId),
    iolist_to_binary([?EVK_API_URL, Method,
                      "?group_id=", GroupId,
                      "&user_id=", UserIdBin,
                      "&extended=1"]).
