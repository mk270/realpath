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

%% @doc
%% Return a canonicalised pathname, having resolved symlinks to their
%% destination. Modelled on realpath(3).
%%
%% The path may be a string or a binary, and the result has the same type.
%% A binary is raw bytes, which is how the operating system sees a file
%% name; a string is turned into bytes using the VM's file name encoding,
%% so it cannot name every file. A binary can.
%%
%% Failures are errors, never guesses: it returns `{error, loop}' if it
%% follows too many links, and `{error, Reason}', with a POSIX error atom
%% such as `eacces' or `enametoolong', if it cannot tell whether part of the
%% path is a link. A part of the path that does not exist is not an error,
%% since there is then nothing to resolve.
%%
%% For a string only, `{error, undecodable_link}' is returned for a link
%% whose target cannot be represented as a string (which happens when the
%% target is not valid in the VM's file name encoding). A binary has no
%% such problem.
%% @end

-spec canonicalise(Path) -> Result
              when Path   :: string(),
                   Result :: {'ok', string()} | {'error', atom()};
                  (Path) -> Result
              when Path   :: binary(),
                   Result :: {'ok', binary()} | {'error', atom()}.
canonicalise(Path) when is_list(Path) ->
    check_canonical(Path, 20, []);
canonicalise(Path) when is_binary(Path) ->
    check_canonical(Path, 20, <<>>).


% Empty is the empty path, of the same type as the one being checked.
check_canonical(S, TTL, Empty) ->
    Fragments = make_fragments(S),
    check_fragments(Fragments, Empty, TTL).

check_fragments(_, _, 0) ->
    {error, loop};
check_fragments([], AlreadyChecked, _) ->
    {ok, AlreadyChecked};
check_fragments([Head|Tail], AlreadyChecked, TTL) ->
    case is_symlink(AlreadyChecked, Head) of
        false -> check_fragments(Tail, filename:join(AlreadyChecked, Head),
                                 TTL);
        {true, Referent} ->
            TailJoined = join_non_null(Tail, Head),
            AllJoined = filename:join(Referent, TailJoined),
            check_canonical(AllJoined, TTL - 1, empty_like(Head));
        {error, _Reason} = Error ->
            Error
    end.

empty_like(S) when is_binary(S) -> <<>>;
empty_like(S) when is_list(S)   -> [].

% Is Basename, in Dirname, a symbolic link, and if so where does it point?
% Strings and binaries are both accepted (Dirname and Basename have the
% same type), and the target comes back in the same type.
%
% file:read_link_all/1 is used, not file:read_link/1. When the VM's file
% name encoding is UTF-8, read_link/1 answers {error, einval} for a link
% whose target is not valid UTF-8, which is also its answer for something
% that is not a link at all; such a link would go unnoticed, and be
% followed by the operating system after the path had been judged free of
% links. read_link_all/1 returns that target as a binary instead. That
% cannot be put into a string, so for a string the path is refused; for a
% binary it is just the bytes.
%
% Only what is certainly not a link (einval), or not there (enoent,
% enotdir), counts as "not a link"; any other error means we cannot tell,
% and is passed on.
-spec is_symlink(Dirname, Basename) -> Result
              when Dirname  :: string() | binary(),
                   Basename :: string() | binary(),
                   Result   :: false
                             | {true, string() | binary()}
                             | {error, atom()}.
is_symlink(Dirname, Basename) ->
    Path = filename:join(Dirname, Basename),
    case file:read_link_all(Path) of
        {ok, Name} ->
            link_target(Name, Dirname, is_binary(Basename));
        {error, Reason} when Reason =:= einval;
                             Reason =:= enoent;
                             Reason =:= enotdir ->
            false;
        {error, Reason} ->
            {error, Reason}
    end.

% Name is what read_link_all/1 gave: a string if the VM could decode it,
% else a binary. In binary mode a string is converted back to the exact
% bytes it came from.
link_target(Name, _Dirname, false) when is_binary(Name) ->
    {error, undecodable_link};
link_target(Name, Dirname, false) ->
    absolutise(Name, Dirname);
link_target(Name, Dirname, true) when is_binary(Name) ->
    absolutise(Name, Dirname);
link_target(Name, Dirname, true) ->
    Bytes = unicode:characters_to_binary(Name, unicode,
                                         file:native_name_encoding()),
    absolutise(Bytes, Dirname).

absolutise(Name = [$/|_], _Dirname)      -> {true, Name};   % absolute
absolutise(Name = <<$/, _/binary>>, _)   -> {true, Name};   % absolute
absolutise(Name, Dirname) ->                                % relative
    {true, filename:join(Dirname, Name)}.

join_non_null([], Like)  -> empty_like(Like);
join_non_null(SS, _Like) -> filename:join(SS).

%% @doc
%% Return a path where the use of ".." to indicate parent directory has
%% been resolved. Currently does not accept relative paths.
%%
%% The path may be a string or a binary, and the result has the same type.
%% @end
-spec normalise(Path) -> Result
              when Path   :: string(),
                   Result :: {'ok', string()} | {'error', atom()};
                  (Path) -> Result
              when Path   :: binary(),
                   Result :: {'ok', binary()} | {'error', atom()}.
normalise(S=[$/|_]) when is_list(S)->
    Parts = filename:split(S),
    {ok, filename:join(lists:reverse(normalise(Parts, [])))};
normalise(S = <<$/, _/binary>>) ->
    Parts = filename:split(S),
    {ok, filename:join(lists:reverse(normalise(Parts, [])))};
normalise(_S) when is_list(_S); is_binary(_S) ->
    {error, relative_path}.


normalise([], Path) -> Path;
normalise([".."|T], Path) ->
    {_H, Rest} = pop(Path),
    normalise(T, Rest);
normalise([<<"..">>|T], Path) ->
    {_H, Rest} = pop(Path),
    normalise(T, Rest);
normalise([H|T], Path) ->
    Rest = push(H, Path),
    normalise(T, Rest).

% The root, when there is nothing left to pop, has the type of the path.
pop([])                    -> {"/", []};
pop([R]) when R =:= "/"; R =:= <<"/">> -> {R, [R]};
pop([H|T])                 -> {H,T}.
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


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tests of canonicalise/1 and normalise/1 as they behave now.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% The fixture is a real directory tree with real symbolic links, under a
%% fresh temporary directory:
%%   Base/real/file  Base/real/deep/
%%   Base/rel -> real   Base/abs -> Base/real
%%   Base/chain1 -> chain2 -> real
%%   Base/tofile -> real/file   Base/dangling -> nothere
%%   Base/loop1 -> loop2 -> loop1
%%   Base/up -> ../<Base's own name>/real   (a link whose target has "..")
%%   Base/outside_<0xE9>/secret   (a directory name that is not valid UTF-8)
%%   Base/badlink -> Base/outside_<0xE9>/secret   (an undecodable target)
%%   Base/badrel -> outside_<0xE9>/secret   (the same, as a relative link)
%%   Base/locked   (mode 000: nothing inside can be reached)
canonicalise_test_() ->
    {setup, fun fixture_setup/0, fun fixture_teardown/1,
     fun canonicalise_tests/1}.

fixture_setup() ->
    Unique = integer_to_list(erlang:unique_integer([positive])),
    Base = filename:absname("realpath_test_" ++ Unique),
    ok = filelib:ensure_path(filename:join([Base, "real", "deep"])),
    ok = file:write_file(filename:join([Base, "real", "file"]), <<"data">>),
    Link = fun(Target, Name) ->
               ok = file:make_symlink(Target, filename:join(Base, Name))
           end,
    Link("real", "rel"),
    Link(filename:join(Base, "real"), "abs"),
    Link("chain2", "chain1"),
    Link("real", "chain2"),
    Link("real/file", "tofile"),
    Link("nothere", "dangling"),
    Link("loop2", "loop1"),
    Link("loop1", "loop2"),
    Link("../" ++ filename:basename(Base) ++ "/real", "up"),
    % names that are not valid UTF-8 can only be written as binaries
    BaseBin = list_to_binary(Base),
    Outside = <<BaseBin/binary, "/outside_", 233>>,
    ok = file:make_dir(Outside),
    ok = file:write_file(<<Outside/binary, "/secret">>, <<"SECRET">>),
    ok = file:make_symlink(<<Outside/binary, "/secret">>,
                           <<BaseBin/binary, "/badlink">>),
    ok = file:make_symlink(<<"outside_", 233, "/secret">>,
                           <<BaseBin/binary, "/badrel">>),
    Locked = filename:join(Base, "locked"),
    ok = file:make_dir(Locked),
    ok = file:change_mode(Locked, 8#000),
    Base.

fixture_teardown(Base) ->
    _ = file:change_mode(filename:join(Base, "locked"), 8#755),
    file:del_dir_r(Base).

undecodable_link_checked(Result) ->
    case file:native_name_encoding() of
        utf8   -> ?assertEqual({error, undecodable_link}, Result);
        latin1 -> ?assertMatch({ok, _}, Result)
    end.

canonicalise_tests(Base) ->
    BaseBin = list_to_binary(Base),
    % Base itself is canonicalised first, so the expectations don't depend
    % on whether the directory the tests run in is reached through links.
    {ok, Canon} = canonicalise(Base),
    In = fun(Rel) -> {ok, filename:join(Canon, Rel)} end,
    C = fun(Rel) -> canonicalise(Base ++ "/" ++ Rel) end,
    [% links are followed: relative, absolute, chains, to files
     ?_assertEqual(In("real/deep"), C("real/deep")),
     ?_assertEqual(In("real/deep"), C("rel/deep")),
     ?_assertEqual(In("real/deep"), C("abs/deep")),
     ?_assertEqual(In("real/deep"), C("chain1/deep")),
     ?_assertEqual(In("real/file"), C("tofile")),
     % the result always names the same file as the path it came from
     ?_test(begin
                [ begin
                      {ok, Resolved} = C(Link ++ "/file"),
                      ?assertEqual({ok, <<"data">>}, file:read_file(Resolved))
                  end || Link <- ["real", "rel", "abs", "chain1"] ],
                {ok, ToFile} = C("tofile"),
                ?assertEqual({ok, <<"data">>}, file:read_file(ToFile))
            end),
     % a loop of links is an error
     ?_assertEqual({error, loop}, C("loop1")),
     ?_assertEqual({error, loop}, C("loop1/x")),
     % what does not exist is not an error: a dangling link resolves to its
     % target's name, and missing parts stay as they are
     ?_assertEqual(In("nothere"), C("dangling")),
     ?_assertEqual(In("nothere/x"), C("dangling/x")),
     ?_assertEqual(In("nope/x"), C("nope/x")),
     % ".", repeated slashes and a trailing slash are tidied away
     ?_assertEqual(In("real/deep"), canonicalise(Base ++ "/real/./deep")),
     ?_assertEqual(In("real/deep"), canonicalise(Base ++ "/real//deep")),
     ?_assertEqual(In("real/deep"), canonicalise(Base ++ "/real/deep/")),
     % ".." is NOT resolved by canonicalise/1, whether it was in the path or
     % in a link's target: that is normalise/1's job
     ?_assertEqual({ok, Canon ++ "/real/../real/file"},
                   C("real/../real/file")),
     ?_assertEqual({ok, Canon ++ "/../" ++ filename:basename(Canon)
                    ++ "/real/deep"}, C("up/deep")),
     % something that is not a directory has nothing to resolve beneath it
     ?_assertEqual(In("real/file/x"), C("real/file/x")),
     % a link whose target is not valid UTF-8 is never skipped. The
     % operating system follows it ...
     ?_assertEqual({ok, <<"SECRET">>},
                   file:read_file(<<BaseBin/binary, "/badlink">>)),
     ?_assertEqual({ok, <<"SECRET">>},
                   file:read_file(<<BaseBin/binary, "/badrel">>)),
     % ... so a VM that cannot put the target in a string refuses the path
     % (UTF-8), and one that can resolves it (Latin-1), wherever in the
     % path the link is
     ?_test(undecodable_link_checked(C("badlink"))),
     ?_test(undecodable_link_checked(C("badrel"))),
     ?_test(undecodable_link_checked(C("badlink/more"))),
     % when we cannot tell whether a part of the path is a link, that is an
     % error, not "no"
     ?_assertEqual({error, enametoolong}, C(lists:duplicate(300, $a))),
     ?_test(case os:cmd("id -u") of
                "0\n" -> ok;   % root can search anything
                _ -> ?assertEqual({error, eacces}, C("locked/x"))
            end),
     % the edges
     ?_assertEqual({ok, "/"}, canonicalise("/")),
     ?_assertEqual({ok, ""}, canonicalise("")),
     % every case above, as a binary, agrees with the string form
     ?_test(binary_agrees(Base, Canon))].

%% Paths relative to the fixture, covering every kind of case the string
%% tests above do (the undecodable links have tests of their own).
agreement_cases() ->
    ["real/deep", "rel/deep", "abs/deep", "chain1/deep", "tofile",
     "loop1", "loop1/x", "dangling", "dangling/x", "nope/x",
     "real/./deep", "real//deep", "real/deep/", "real/../real/file",
     "up/deep", "real/file/x", lists:duplicate(300, $a), "locked/x", ""].

%% The binary result is the string result, as a binary; errors are equal.
binary_agrees(Base, Canon) ->
    [ begin
          Path = case Rel of "" -> Base; _ -> Base ++ "/" ++ Rel end,
          Str = canonicalise(Path),
          Bin = canonicalise(list_to_binary(Path)),
          ?assertEqual(as_binary(Str), Bin, Path)
      end || Rel <- agreement_cases() ],
    ?assertEqual({ok, list_to_binary(Canon)},
                 canonicalise(list_to_binary(Base))),
    ?assertEqual({ok, <<"/">>}, canonicalise(<<"/">>)),
    ?assertEqual({ok, <<>>}, canonicalise(<<>>)).

as_binary({ok, S})         -> {ok, list_to_binary(S)};
as_binary({error, _} = E)  -> E.

%% Names that are not valid UTF-8: a binary, unlike a string, can always
%% be followed, in either file name mode, and gives the exact bytes.
binary_undecodable_test_() ->
    {setup, fun fixture_setup/0, fun fixture_teardown/1,
     fun binary_undecodable_tests/1}.

binary_undecodable_tests(Base) ->
    {ok, Canon} = canonicalise(list_to_binary(Base)),
    Secret = <<Canon/binary, "/outside_", 233, "/secret">>,
    B = fun(Rel) -> canonicalise(<<Canon/binary, "/", Rel/binary>>) end,
    [?_assertEqual({ok, Secret}, B(<<"badlink">>)),
     ?_assertEqual({ok, Secret}, B(<<"badrel">>)),
     ?_assertEqual({ok, <<Secret/binary, "/more">>}, B(<<"badlink/more">>)),
     ?_assertEqual({ok, <<"SECRET">>}, begin
                       {ok, R} = B(<<"badrel">>), file:read_file(R)
                   end),
     % a path that itself holds such bytes is kept as it is
     ?_assertEqual({ok, <<Canon/binary, "/outside_", 233, "/x">>},
                   B(<<"outside_", 233, "/x">>)),
     % and the string form of the same path is not confused with it
     ?_test(undecodable_link_checked(canonicalise(Base ++ "/badlink")))].

normalise_test_() ->
    [?_assertEqual({ok, "/b"}, normalise("/a/../b")),
     ?_assertEqual({ok, "/"}, normalise("/..")),
     ?_assertEqual({ok, "/"}, normalise("/../..")),
     ?_assertEqual({ok, "/a/b"}, normalise("/a/./b")),
     ?_assertEqual({ok, "/a/b"}, normalise("//a//b")),
     ?_assertEqual({ok, "/a/b"}, normalise("/a/b/")),
     ?_assertEqual({ok, "/"}, normalise("/")),
     ?_assertEqual({error, relative_path}, normalise("a/b")),
     ?_assertEqual({error, relative_path}, normalise("../x")),
     ?_assertEqual({error, relative_path}, normalise("")),
     % the same, as binaries
     ?_assertEqual({ok, <<"/b">>}, normalise(<<"/a/../b">>)),
     ?_assertEqual({ok, <<"/">>}, normalise(<<"/..">>)),
     ?_assertEqual({ok, <<"/">>}, normalise(<<"/../..">>)),
     ?_assertEqual({ok, <<"/a/b">>}, normalise(<<"/a/./b">>)),
     ?_assertEqual({ok, <<"/a/b">>}, normalise(<<"//a//b">>)),
     ?_assertEqual({ok, <<"/a/b">>}, normalise(<<"/a/b/">>)),
     ?_assertEqual({ok, <<"/">>}, normalise(<<"/">>)),
     ?_assertEqual({error, relative_path}, normalise(<<"a/b">>)),
     ?_assertEqual({error, relative_path}, normalise(<<"../x">>)),
     ?_assertEqual({error, relative_path}, normalise(<<>>)),
     % bytes that are not valid UTF-8 pass through untouched
     ?_assertEqual({ok, <<"/b", 233, "/c">>},
                   normalise(<<"/a/../b", 233, "/./c">>))].
