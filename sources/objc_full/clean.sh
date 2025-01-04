#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

S=$(cd $(dirname "$0"); pwd)
rm -rf $S/out
rm -f Sample.c
rm -f Sample.h
rm -f Sample.json
rm -f Sample_objc.h
rm -f Sample_objc.m
rm -f Sample_objc.o
rm -f my_objc.o
