/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@echo c, "#include <utils/timer.c>\n";

declare function create_timer() create object<timer> not null;
declare function start_object_timer(timer object<timer> not null) object<timer> not null;
declare function stop_object_timer(timer object<timer> not null) object<timer> not null;
declare function print_object_timer(timer object<timer> not null) object<timer> not null;

@op object<timer> : call start as start_object_timer;
@op object<timer> : call stop as stop_object_timer;
@op object<timer> : call print as print_object_timer;
