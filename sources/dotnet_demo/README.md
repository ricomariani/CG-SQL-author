<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

# Interop Example

These files serve to illustrate how you can interoperate with CQL generated code in C#.

## The C# entry point

This is the main program. It calls some stored procedures using the generated
Interop wrappers. The point of `make.sh` (below) is to generate all the Interop needed
to use the CQL in `Sample.sql`. There are standard Interop helpers to create the
runtime environment, but those aer not specific to any given set of procedures.
See below.

* `./MyCode.cs`

## Database access

This is the Interop class that opens the database for us and gives us a handle.  You
should replace this as needed or use an alternative. In the C# world the
`sqlite3 *` that is the database is just a `long` so it's easy to project it
from whatever database source you might have.

* `./CQLDb.c`
* `./CQLDb.cs`

## Result set access

This is the Interop class that captures a result set with the generic interface to
access any of the defined columns dynamically.  Note that the metadata of the
CQL result set is verified against the calls so this is still type-safe.

* `./CQLResultSet.c`
* `./CQLResultSet.cs`

## View Model Abstract class

This class provides the basic shape for all of the generated ViewModel classes.
The python generates subtypes of this class.

* `./CQLViewModel.cs`

More specifically, `CQLResultSet` uses standard Interop methods to read the
primitive types out of any result set.  The compiler produce a subclass of
`CQLViewModel` that uses `CQLResultSet` to do its job.  The Interop C file
`CQLResultSet.c` has the necessary calls to the CQL and C# runtime to do that reading.
Each of the functions is just a few lines of code.
`CQLDb` creates a simple memory database, you can replace it with whatever you need.

## Encoded Types

A very simple very bad string encoder for the CQL encoded string type is provided.
You can investigate the "vault" options to learn more.  This one is only useful
as a test tool.

* `./CQLEncodedString.cs`

## The CQL to access

* `./Sample.sql`

This file has several test procedures.  The most important is a stored procedure
that creates a table, puts stuff in it, and then returns its contents.  This is
in some sense the core of the demo.  Everything else is scaffolding.

## The Interop Generator

The CQL compiler is used to generated JSON to describe the exact contents of
`Sample.sql`. The python reads the generated JSON and creates first the C#
wrappers and then the necessary C code to support them.  It is invoked twice.
You can make as many or as few units of Interop as you like since the JSON bundles
could be created from amalgamations of `.sql` files.  Alternatively,
`./cqlcs.py` would be trivially extended to take more than one input and
create a unitary output for all the input files.

* `./cqlcs.py`

## Building Tools

Use `make.sh` to build and execute the Interop demo.  Use `clean.sh` to clean up the
build artifacts afterwards.

* `./make.sh`
* `./clean.sh`

Build notes:

* set `SQLITE_PATH` to the location of your SQLite installation if you want to
  use an amalgam build of SQLITE rather than just use `-lsqlite3`

`make.sh` is itself pretty straightforward though it is longish. It's not done
with "better" build technology just so that it can showcase exactly what needs
to happen with a minimum of clutter.  The build steps are all very simple
and can be readily turned into `cmake` or whatever.
