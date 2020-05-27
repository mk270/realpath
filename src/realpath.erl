-module(realpath).

-export([canonicalise/1]).

canonicalise("/usr/local/man/man1/dwm.1") ->
    aha;

canonicalise(_) ->
    unfinished.
