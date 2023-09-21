@echo c, "#include <utils/timer.c>\n"; 

declare function create_timer() object<timer> not null;
declare function start_object_timer(timer object<timer> not null) object<timer> not null;
declare function stop_object_timer(timer object<timer> not null) object<timer> not null;
declare function print_object_timer(timer object<timer> not null) object<timer> not null;