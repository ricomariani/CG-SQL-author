@ifdef foo
  let foo_defined := 1;
  @ifdef foo
    let nested_foo_defined := 1;
  @else
    let error_foo_not_defined = 1;
  @endif
@else
  let not_foo_defined := 1;
@endif

@ifndef goo
  let not_goo_defined := 1;
@else
  let goo_defined := 1;
@endif

@ifdef foo
  let foo_defined_no_else := 1;
@endif

@ifdef goo
  let goo_defined_no_else := 1;
@endif

@ifndef foo
  let foo_not_defined_no_else := 1;
@endif

@ifndef goo
  let goo_not_defined_no_else := 1;
@endif

@ifndef foo
  let str := "@ELSE";
@else
  let foo_else := 1;
@endif
  
@ifndef foo
  let foo_endif := "@ENDIF";
@endif

@ifdef goo
  -- @ELSE
@else
  goo_not_defined := 1;
@endif

@ifdef goo
  /* @ELSE doesn't work here */
  /* @ENDIF doesn't work either */
  let q := "@ELSE doesn't work";
  let r := '@ELSE doesn''t work';
  let `@ELSE does not work`;
@else
  goo_not_defined_after_c_comment := 1;
@endif

@ifdef goo
  let this_does_not_appear := 1;

  @ifdef foo
    set this_does_not_appear := 2;
  @else
    set this_does_not_appear := 3;
  @endif

  @ifdef foo
    set this_does_not_appear := 4;
  @endif

  set this_does_not_appear := 5;
@endif
