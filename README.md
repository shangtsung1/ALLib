A Client/Library written in D for Adventure.land

install dub package manager

install ldc2 compiler

create .env file with username and password seperated by new line.
like so.
```
username=eg@eg.com
password=somepass
```

to run app.d
```
dub run
```

to compile as library

```
dub build --config=cwrapper
```
