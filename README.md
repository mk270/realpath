realpath
========

An Erlang library application which returns the real path of a file,
resolving symlinks

Usage
-----

     > realpath:canonicalise("/usr/local/man/man1/dwm.1").
     {ok, "/usr/local/share/man/man1/dwm.1"}
     > realpath:canonicalise("/tmp/deliberate-loop").
     {error, loop}
     > realpath:normalise("/var/lib/../log").
     {ok, "/var/log"}
     > realpath:normalise("../etc/passwd").
     {error, relative_path}

