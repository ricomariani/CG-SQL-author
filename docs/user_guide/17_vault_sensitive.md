---
title: "Chapter 17: Vault Sensitive — Encoding for Privacy - Deleted"
weight: 17
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Introduction

This feature was removed from the compiler on 2024/12/28

The general idea of "vaulted" values was that some fields in your
database might contain sensitive data and you might not want to make
this data visible to all the code in your whole project.  The data could
be sensitive for a number of reasons, maybe it's PII, or maybe it's
confidential for some other reason.  The idea here was that you can't
very well limit access to this data in a lower layer like CQL can provide
because it's likely that the functions accessing the data at this layer
are in the business of processing this data.  However, you can make it
so that an additional step is needed "decode" the data so that it's apparent
where such data is being used and with some kind of "key" you could make it
so that code that has no access to the keys cannot possibly display sensitive
data.  This isn't foolproof but it is a good line of defense for privacy.

However, nobody was actually using this feature and indeed if you want to do
this the best way is not to rely on the CQL code generation directly but
rather to wrap results just like we do for say JNI access.  Indeed the python
used to do JNI wrappers could easily be modified to encode sensitive fields
directly in that API.  This is true for any access API, even the native one.
Doing it with the CQL JSON and your own python gives you flexibility to do
your encoding your way.  It's best left out of the hands of the lowest level
codegen.  Again just like the JNI choice, or the dotnet choice.

So, we deleted a ton of code in favor of a hopefully much smaller amount
of python for those who want this feature (which seems to be nobody at the
moment).

>Note: We may add an example python vaulter in the future.
