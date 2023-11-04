---
title: "Chapter 18: Macros"
weight: 18
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Introduction

Macros are a recent introduction to the CQL language, previously
any macro-type functionality was provided by running the C Pre-Processor
over the input file before processing.  Indeed this practice is still in
many examples.   However it is less than idea.

 * It's not possible to create automatic code formatting with text based replacement
 * Macros are easily abused creating statement fragments in weird places that are hard to understand
 * The usual problems with text replacement and order of operations means that macro arguments frequently have to be wrapped to avoid errors
 * Debugging problems in the macros is very difficult with line information being unhelpful and pre-processed output being nearly unreadable

To address these problems CQL introduces the notion of structured macros.
That is, a macro the describes the sort of thing it intends to produce
and the kinds of things it consumes.  This allows for reasonable
syntax and type checking and much better error reporting.

### Types of Macros





