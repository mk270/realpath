realpath
========

An Erlang library application which returns the real path of a file,
resolving symlinks

Usage
-----

```erlang
     > realpath:canonicalise("/usr/local/man/man1/dwm.1").
     {ok, "/usr/local/share/man/man1/dwm.1"}
     > realpath:canonicalise("/tmp/deliberate-loop").
     {error, loop}
     > realpath:normalise("/var/lib/../log").
     {ok, "/var/log"}
     > realpath:normalise("../etc/passwd").
     {error, relative_path}
```

Strings and binaries
--------------------

Both functions take a path as a string or as a binary, and the result is
the same type as the argument:

```erlang
     > realpath:normalise(<<"/var/lib/../log">>).
     {ok, <<"/var/log">>}
     > realpath:canonicalise(<<"/usr/local/man/man1/dwm.1">>).
     {ok, <<"/usr/local/share/man/man1/dwm.1">>}
```

A binary is the raw bytes of the name, which is what the operating system
sees. A string is turned into bytes using the VM's file name encoding (UTF-8
or Latin-1, depending on the locale), so it cannot always name the same
file in every VM. Prefer binaries for names that are not plain ASCII.

One difference: a symbolic link whose target is not valid in the VM's file
name encoding cannot be put in a string, so for a string the call returns
`{error, undecodable_link}`. A binary has no such problem, and the link is
simply followed.

Notes
-----

`canonicalise/1` leaves ".." alone (use `normalise/1` for that), and a
relative path given to it is treated as if it were absolute. Failures are
errors, not guesses: `{error, loop}` after too many links, or a POSIX error
such as `eacces` when it cannot tell whether part of the path is a link.
A part of the path that does not exist is not an error.

Documentation
-------------

Online at [realpath documentation](https://hexdocs.pm/realpath).
