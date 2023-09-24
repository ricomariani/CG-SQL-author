#include <stdio.h>
#include <time.h> 

typedef struct {
  struct timespec start;
  struct timespec end;
} Timer;

void timer_start(Timer *_Nonnull timer) {
  clock_gettime(CLOCK_MONOTONIC, &(timer->start));
}

void timer_stop(Timer *_Nonnull timer) {
  clock_gettime(CLOCK_MONOTONIC, &(timer->end));
}

void timer_print(Timer *_Nonnull timer) {
  long sec_delta = timer->end.tv_sec - timer->start.tv_sec;
  long nsec_delta = timer->end.tv_nsec - timer->start.tv_nsec;

  if (nsec_delta < 0) {
    sec_delta -= 1;
    nsec_delta += 1000000000;
  }

  printf("%15.3f seconds\n",      sec_delta * 1          + (double)nsec_delta / 1000000000);
  printf("%15.3f milliseconds\n", sec_delta * 1000       + (double)nsec_delta / 1000000);
  printf("%15.3f microseconds\n", sec_delta * 1000000    + (double)nsec_delta / 1000);
  printf("%15ld nanoseconds\n",   sec_delta * 1000000000 +   (long)nsec_delta / 1);
}

static void timer_finalize(void *_Nonnull data) {
  Timer *_Nonnull self = data;
  free(self);
}

cql_object_ref _Nonnull create_timer() {
  Timer *_Nonnull self = calloc(1, sizeof(Timer));

  return _cql_generic_object_create(self, timer_finalize);
}

cql_object_ref _Nonnull start_object_timer(cql_object_ref _Nonnull object_reference) {
  Timer *_Nonnull self = _cql_generic_object_get_data(object_reference);

  timer_start(self);

  return object_reference;
}

cql_object_ref _Nonnull stop_object_timer(cql_object_ref _Nonnull object_reference) {
  Timer *_Nonnull self = _cql_generic_object_get_data(object_reference);

  timer_stop(self);

  return object_reference;
}

cql_object_ref _Nonnull print_object_timer(cql_object_ref _Nonnull object_reference) {
  Timer *_Nonnull self = _cql_generic_object_get_data(object_reference);

  timer_print(self);

  return object_reference;
}
