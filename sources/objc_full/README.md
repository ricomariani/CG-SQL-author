<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

# OBJC Full Wrapper Example

These files serve to illustrate how you can interoperate with CQL generated code
in Objective C.


## The CQL to access

* `./Sample.sql`

This file has several test procedures.  The most important is a stored procedure
that creates a table, puts stuff in it, and then returns its contents.  This is
in some sense the core of the demo.  Everything else is scaffolding.

## The OBJC Generator

The CQL compiler is used to generated JSON to describe the exact contents of
`Sample.sql`. The python reads the generated JSON and creates first the Java
wrappers and then the necessary C code to support them.  It is invoked twice.

* `./cql_objc_full.py`

## Building Tools

Use `make.sh` to build and execute the JNI demo.  Use `clean.sh` to clean up the
build artifacts afterwards.

* `./make.sh`
* `./clean.sh`

Build notes:

Unfortunately there are some problems here:

* I can't run this code on Linux so I don't know if it work, this is kind of a problem
* The best I could do was ensure it compiles, it should work, it's just glue but those are famous last words
* I couldn't even build it with `-fobjc_arc` enabled because that doesn't work on "legacy framework"
* This means the ObjectiveC here is a bit old school

To make a long story short, this code should only be viewed as a starting off point for an inspired
person with access to a Mac so they can actually try this stuff..
