DECLARE PROC printf NO CHECK;

CREATE PROC entrypoint ()
BEGIN
    declare x text not null;

    SET x := 'hello';
    SET x := (SELECT "hello world" as x);
    CALL printf("%s", x);
END;
