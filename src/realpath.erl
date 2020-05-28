%% realpath, an Erlang realpath() implementation, by Martin Keegan
%%
%% To the extent (if any) permissible by law, Copyright (C) 2020  Martin Keegan
%%
%% This programme is free software; you may redistribute and/or modify it under
%% the terms of the Apache Software Licence v2.0.

-module(realpath).
-include_lib("eunit/include/eunit.hrl").
-export([canonicalise/1]).
-export([normalise/1]).

% This should start with a TTL counter of, say, 20, which should be
% decremented each time a symlink is found, failing if it gets to zero.

% For any path, the string should be broken up into fragments by
% slashes, and each potential initial subset of consecutive fragments
% should be tested to see if its final member is a symlink, i.e.,
%
%   for the path /usr/local/man/man1/dwm.1, we should test
%     /usr
%     /usr/local
%     /usr/local/man
%     [etc]
%
% If a symlink is encountered, the TTL should be decremented by one and the
% process of substring testing should restart with against the target of
% symlink.

-spec canonicalise(list()) -> {'ok', string()} | {'error', atom()}.
canonicalise(Path) when is_list(Path) ->
    check_canonical(Path, 20);
canonicalise(_Path) when is_binary(_Path) ->
    {error, string_required}.


check_canonical(S, TTL) ->
    Fragments = make_fragments(S),
    check_fragments(Fragments, [], TTL).

check_fragments(_, _, 0) ->
    {error, loop};
check_fragments([], AlreadyChecked, _) ->
    {ok, AlreadyChecked};
check_fragments([Head|Tail], AlreadyChecked, TTL) ->
    case is_symlink(AlreadyChecked, Head) of
        false -> check_fragments(Tail, filename:join(AlreadyChecked, Head),
                                 TTL);
        {true, Referent} ->
            TailJoined = join_non_null(Tail),
            AllJoined = filename:join(Referent, TailJoined),
            check_canonical(AllJoined, TTL - 1)
    end.

is_symlink(Dirname, Basename) ->
    Path = filename:join(Dirname, Basename),
    case file:read_link(Path) of
        {ok, Name} ->
            case Name of
                % absolute link
                [$/|_] -> {true, Name};

                % relative link
                _ ->
                    {true, filename:join(Dirname, Name)}
            end;
        _ -> false
    end.

join_non_null([]) -> "";
join_non_null(SS) -> filename:join(SS).

-spec normalise(list()) -> {'ok', string()} | {'error', atom()}.
normalise(S=[$/|_]) when is_list(S)->
    Parts = filename:split(S),
    {ok, filename:join(lists:reverse(normalise(Parts, [])))};
normalise(_S) when is_list(_S) ->
    {error, relative_path};
normalise(_) ->
    {error, string_required}.


normalise([], Path) -> Path;
normalise([".."|T], Path) ->
    {_H, Rest} = pop(Path),
    normalise(T, Rest);
normalise([H|T], Path) ->
    Rest = push(H, Path),
    normalise(T, Rest).

pop([])    -> {"/", []};
pop(["/"]) -> {"/", ["/"]};
pop([H|T]) -> {H,T}.
push(H,T)  -> [H|T].


make_fragments(S) ->
    filename:split(S).

make_fragments_test_data() ->
    [{"/usr/local/bin", ["/", "usr", "local", "bin"]},
     {"usr/local/bin/bash", ["usr", "local", "bin", "bash"]},
     {"/usr/local/bin/", ["/", "usr", "local", "bin"]}].

make_fragments_test_() ->
    [ ?_assertEqual(Expected, make_fragments(Observed))
      || {Observed, Expected} <- make_fragments_test_data() ].
