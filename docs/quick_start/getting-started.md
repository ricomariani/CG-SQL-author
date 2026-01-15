---
title: Getting Started with CG/SQL
description: Getting Started with CG/SQL
weight: 1
---

## Building
caution: Please make sure you meet the [requirements](#requirements).

Set your current directory to the CG/SQL `sources` directory, wherever that may be, then:

```
make clean
make
```

This compiles CQL and puts the result at `out/cql`. Now you can run it to show available command options (also
[documented here](./user_guide/appendices/01_command_lines_options.md):

```bash
$ out/cql
```

You might want to alias the location of `out/cql`. For example, by using the `alias` command in Linux or MacOS.

## Next Steps

- Go to the [first chapter of the CQL Guide](./user_guide/01_introduction.md#getting-started) to write your first CQL program!
The [second chapter](./user_guide/02_using_data.md#a-sample-program) has a less trivial program that walks through how to query a SQLite database with CQL.
- [CQL Language Cheatsheet](./user_guide/appendices/06_cql_in_20_minutes.md)
- [CQL Playground](playground.md)

## Requirements

### MacOS Users
The default bison and flex on Mac are quite old.  You'll need to replace them. The Build
produces an error if this is happening.  You can get a more recent versions like this:

```
  brew install bison
  brew link bison --force
  brew install flex
  brew link flex --force
```

### Linux Users
The default SQLite on Ubuntu systems is also fairly old.  Some of the tests (particularly
the query plan tests) use features not available in this version.  You'll want to link
against a newer sqlite to pass all the tests.

From a bare Ubuntu installation, you might need to add these components:

```bash
sudo apt update
sudo apt install make
sudo apt install gcc
sudo apt install clang
sudo apt install flex
sudo apt install bison
sudo apt install sqlite3
sudo apt install libsqlite3-dev
```

After which you can do the normal builds.

For the coverage build you need:

```bash
sudo apt install gcovr
```

The instructions are helpful for getting gcov

```bash
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt-get update
sudo apt-get install -y gcc-10 g++-10
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 1
```

And if you want to do the AST visualizations in PDF form you need:

```bash
sudo apt install graphviz
```

For Lua:

```bash
sudo apt install lua5.4
sudo apt install liblua5.4-dev
```

Then Luarocks

```bash
wget https://luarocks.org/releases/luarocks-3.11.0.tar.gz
tar zxpf luarocks-3.11.0.tar.gz
cd luarocks-3.11.0
./configure && make && sudo make install
sudo luarocks install lsqlite3
```

## Options

* If you add `CGSQL_GCC` to your environment the `Makefile` will add `CFLAGS += -std=c99`
to try to be more interoperable with gcc.

* If you add `SQLITE_PATH` to your environment the `Makefile` will try to compile `sqlite3-all.c` from that path
and it will link that in instead of using `-lsqlite3`.

## Amalgam Build

The amalgam is created by `./make_amalgam.sh` and the result is in `out/cql_amalgam.c`

You can create and test the amalgam in one step (preferred) using

```
./test.sh --use_amalgam
```

This will cause the amalgam to be created and compiled.  Then the test suite will run against that binary.
