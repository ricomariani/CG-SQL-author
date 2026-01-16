---
title: "Chapter 1: Introduction"
weight: 1
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

CQL is a compiler for the SQLite runtime system. SQLite lacks
stored procedures but has a rich C runtime interface that allows you to create
any kind of control flow mixed with any SQL operations that you might need.
However, SQLite's programming interface is both verbose and error-prone in that
small changes in SQL statements can require significant swizzling of the C code
that calls them. Additionally, many of the SQLite runtime functions have error
codes which must be strictly checked to ensure correct behavior. In practice,
it's easy to get some or all of this wrong.

CQL simplifies this situation by providing a high-level SQL language not unlike
the stored procedure forms that are available in client/server SQL solutions and
lowering that language to "The C you could have written to do that job using the
normal SQLite interfaces."

As a result, the generated C is generally approachable while the source
language avoids brittleness due to query or table changes, and CQL
always generates correct column indices, nullability checks, error checks, and
the other miscellany needed to use SQLite correctly.

CQL is also strongly typed, whereas SQLite is very forgiving with regard to what
operations are allowed on which data. Strict type checking is much more
reasonable given CQL's compiled programming model.

> NOTE: CQL was created to help solve problems in the building of Meta
> Platforms' Messenger application, but this content is free from references to
> Messenger. The CQL code generation here is done in the simplest mode with the
> fewest runtime dependencies allowed for illustration.

### Audience and Scope

This guide is for developers who want to write robust, maintainable SQL and
compile it to predictable C that uses SQLite correctly. It focuses on core
language features, composition patterns, and runtime basics.

### Getting Started

Before starting, build the `cql` executable as described in
[Getting Started](../quick_start/getting-started.md).

The "Hello World" program rendered in CQL looks like this:

```sql
-- needed to allow vararg calls to C functions
declare procedure printf no check;

create proc hello()
begin
  call printf("Hello, world\n");
end;
```

This nearly works as written, but we need a little glue to wire it up.

First, assuming you have [built](../quick_start/getting-started.md#building) `cql`, do:

```bash
$ cql --in hello.sql --cg hello.h hello.c
```

This will produce the C output files `hello.c` and `hello.h` which can be readily compiled.

However, `hello.c` will not have a `main`; rather it will have a function like this:

```c
...
void hello(void);
...
```

The declaration of this function can be found in `hello.h`.

> **NOTE:** `hello.h` attempts to include `cqlrt.h`. To avoid configuring
> include paths for the compiler, you might keep `cqlrt.h` in the same directory
> as the examples and avoid that complication. Otherwise, you must make
> arrangements for the compiler to locate `cqlrt.h`, either by adding it to an
> `INCLUDE` path or by incorporating some `-I` options to aid the compiler in
> finding the source.

That `hello` function is not quite adequate to get a running program, which
brings us to the next step in getting things running. Typically, you have some
kind of client program that will execute the procedures you create in CQL. Let's
create a simple one in a file we'll creatively name `main.c`.

A very simple CQL main might look like this:

```c
#include <stdlib.h>
#include "hello.h"
int main(int argc, char **argv)
{
   hello();
   return 0;
}
```

Now compile and run:

```bash
$ cc -o hello main.c hello.c
$ ./hello
Hello, world
```

Congratulations—you've printed `"Hello, world"` with CG/SQL!

### Why did this work?

A few noteworthy details in this simple program:

* the procedure `hello` had no arguments, and did not use the database
  * therefore its type signature when compiled will be `void hello(void);` so we know how to call it
  * see the declaration by examining `hello.c` or `hello.h`
* since nobody used a database, we didn't need to initialize one
* since there are no actual uses of SQLite, we didn't need to provide that library
* for the same reason, we didn't need to include a reference to the CQL runtime
* the function `printf` was declared "no check", so calling it creates a regular C call using whatever arguments are provided, in this case a string
* the `printf` function is declared in `stdio.h` which is pulled in by `cqlrt.h`, which appears in `hello.c`, so it will be available to call in the generated C code
* CQL allows string literals with double quotes, and those literals may have most C escape sequences in them, so the "\n" bit works
  * Normal SQL string literals (also supported) use single quotes and do not allow, or need escape characters other than `''` to mean one single quote

All of these facts put together mean that the normal, simple linkage rules
result in an executable that prints the string "Hello, world" and then a
newline.

### Variables and Arithmetic

Borrowing from examples in "The C Programming Language",
it's possible to do significant control flow in CQL without referencing
databases. The following program illustrates a variety of concepts:

```sql
-- needed to allow vararg calls to C functions
declare procedure printf no check;

-- print a conversion table  for temperatures from 0 to 300
create proc conversions()
begin
  -- not null can be abbreviated with '!'
  declare fahr, celsius int!;

  -- variable type can be implied
  -- these are all int not null  (or int!)
  let lower := 0;   /* lower limit of range */
  let upper := 300; /* upper limit of range */
  let step := 20;   /* step size */

  -- this is the canonical SQL assignment syntax
  -- but there are shorthand versions available in CQL
  set fahr := lower;
  while fahr <= upper
  begin
    -- top level assignment without 'set' is ok
    celsius := 5 * (fahr - 32) / 9;
    call printf("%d\t%d\n", fahr, celsius);

    -- the usual assignment ops are supported
    fahr += step;
  end;
end;
```

Both SQL-style `--` line comments and C-style `/* */` block comments are acceptable.

Like C, in CQL all variables must be declared before they are used.  They remain in scope until the end of the
procedure in which they are declared, or they are global scoped if they are declared outside of any procedure.  The
declarations announce the names and types of the local variables.   Importantly, variables stay in scope for the whole
procedure even if they are declared within a nested `begin` and `end` block.

The most basic types are the scalar or "unitary" types (as they are referred to in the compiler)

|type        |aliases      | notes                              |
|------------|-------------|------------------------------------|
|`integer`   |int          | a 32 bit integer                   |
|`long`      |long integer | a 64 bit integer                   |
|`bool`      |boolean      | an 8 bit integer, normalized to 0/1|
|`real`      |n/a          | a C double                         |
|`text`      |n/a          | an immutable string reference      |
|`blob`      |n/a          | an immutable blob reference        |
|`object`    |n/a          | an object reference                |
|`X not null`|x!           | `!` means `not null` in types      |

> NOTE: SQLite makes no distinction between integer storage and long integer
> storage, but the declarations tell CQL whether it should use the SQLite
> methods for binding and reading 64-bit or 32-bit quantities when using the
> variable or column so declared.

There will be more notes on these types later, but importantly, all keywords and
names in CQL are case insensitive just like in the underlying SQL language.
Additionally, all of the above may be combined with `not null` to indicate that a
`null` value may not be stored in that variable (as in the example).  When
generating the C code, the case used in the declaration becomes the canonical
case of the variable and all other cases are converted to that in the emitted
code.  As a result, the C remains case sensitively correct.

Reference type sizes are machine dependent (pointer-sized). Non-reference types
use machine-independent declarations like `int32_t` to get desired sizes.

All variables of a reference type are set to `NULL` when they are declared,
including those that are declared `NOT NULL`. For this reason, all nonnull
reference variables must be initialized (i.e., assigned a value) before anything
is allowed to read from them. This is not the case for nonnull variables of a
non-reference type, however: They are automatically assigned an initial value of
0, and thus may be read from at any point.

The program's execution begins with three assignments:

```sql
let lower := 0;
let upper := 300;
let step := 20;
```

This initializes the variables just like in the isomorphic C code. Statements
are separated by semicolons, as in C. In the above, the variable type was
inferred because `let` was used.

The table is then printed using a `while` loop.

```sql
while fahr <= upper
begin
  ...
end;
```

This repeats the `begin`/`end` block until the condition becomes false.

The body of a `begin`/`end` block can contain one or more statements.

The typical computation of Celsius temperature ensues with this code:

```sql
celsius := 5 * (fahr - 32) / 9;
call printf("%d\t%d\n", fahr, celsius);
fahr += step;
```

This computes the Celsius temperature and prints it, then moves to the next
entry. Note the shorthand: `SET` can be omitted; `+=` assignment operators are
supported. Top-level procedure calls can be made without `call`.

The CQL compiler uses the SQLite order of operations, which is not the same as
C. As a result, the compiler may add parentheses in the C output to preserve the
correct order, or remove ones that are unnecessary in C.

The `printf` call operates as before, with the `fahr` and `celsius` variables
being passed on to the C runtime library for formatting, unchanged.

> NOTE: When calling "unchecked" native functions like `printf`, string literals
> are simply passed  through unchanged as C string literals. No CQL string
> object is created.

### Basic Conversion Rules

As a rule, CQL does not perform its own conversions, leaving that instead to the C compiler.  An exception
to this is that boolean expressions are normalized to a 0 or 1 result before they are stored.

However, even with no explicit conversions, there are compatibility checks to ensure that letting the C compiler
do the conversions will result in something sensible.  The following list summarizes the essential facts/rules as
they might be applied when performing a `+` operation.

* the numeric types are bool, int, long, real
* non-numeric types cannot be combined with numerics, e.g. 1 + 'x' always yields an error
* any numeric type combined with itself yields the same type
* bool combined with int yields int
* bool or int combined with long yields long
* bool, int, or long combined with real yields real

### Preprocessing Features

CQL includes its own pre-processor (see [Chapter 18](./18_pre_processing/)).
Using the C pre-processor in front of CQL is deprecated. Supported features:

  * macros (`@macro`)
  * including files (`@include`)
  * conditional compilation (`@ifdef`, `@ifndef`)
  * token pasting (`@text` and `@id`)
