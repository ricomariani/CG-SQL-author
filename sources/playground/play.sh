#!/bin/bash

set -o errexit -o nounset -o pipefail

# Globals

readonly CLI_NAME=${0##*/}
readonly SCRIPT_DIR=$(dirname $(readlink -f "$0"))
readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
readonly CQL_ROOT_DIR=$SCRIPT_DIR_RELATIVE/..
readonly CQL=$CQL_ROOT_DIR/out/cql

tty -s <&1 && IS_TTY=true || IS_TTY=false
VERBOSITY_LEVEL=$([ "$IS_TTY" = "true" ] && echo 3 || echo 0)
SCRIPT_OUT_DIR=$SCRIPT_DIR_RELATIVE/out
DEFAULT_C_CLIENT=${DEFAULT_C_CLIENT:-$SCRIPT_DIR_RELATIVE/default_client.c}
DEFAULT_LUA_CLIENT=${DEFAULT_LUA_CLIENT:-$SCRIPT_DIR_RELATIVE/default_client.lua}
SQLITE_FILE_PATH_ABSOLUTE=${SQLITE_FILE_PATH_ABSOLUTE:-:memory:}
CLONE_SQLITE_DATABASE=false

# Commands

exit_with_help_message() {
    local exit_code=$1

    cat <<EOF | theme
CQL Playground

Sub-commands:
    help
        Show this help message
    hello
        Onboarding checklist — Get ready to use the playground
    build-cql-compiler
        Rebuild the CQL compiler

    build-everything
        Build all outputs for all CQL procedures examples
    build [<output_list>] <path_to_example_list> [--watch]
        Generate an output
    run [<output_list>] <path_to_example_list> [--rebuild] [--watch]
        Execute or print a generated output
    run-data-access-demo
        Run the data access demo
    clean
        Clean all generated files

Arguments:
    Outputs (<output_list>)
        c (includes binary) [DEFAULT] — The compilation of the default C client embedding the C standard compilation (.c and .h) of the sql file
        lua — The compilation of the default Lua client embedding the Lua compilation of the sql file (.lua)
        objc — The Objective-C wrappers
        java — The Java wrappers
        schema — The canonical schema
        schema_upgrade — A CQL schema upgrade script
        query_plan — The query plan for every DML statement
        stats — A simple .csv file with AST node count information per procedure
        ast — The internal AST
        ast_dot — The internal AST using dot format
        ast_dot_pdf — The internal AST using dot format as PDF file
        preprocessed — The preprocessed version of the sql file
        cql_json_schema — A JSON output for codegen tools
        cql_sql_schema — A normalized version of the cql_json_schema (.sql)
        cql_sqlite_schema — SQLite database of the cql_sql_schema.sql (.sqlite)
        table_diagram_dot — Table Diagram
        table_diagram_dot_pdf — Table Diagram as PDF file
        region_diagram_dot — Region Diagram
        region_diagram_dot_pdf — Region Diagram as PDF file
        erd_dot — Entity Relationship Diagram
        erd_dot_pdf — Entity Relationship Diagram as PDF file
        all_outputs — All outputs

    Examples (<path_to_example_list>)
        Any ".sql" file. See: $SCRIPT_DIR_RELATIVE/examples/*.sql

Options:
    --out-dir <path>
        The directory where the outputs will be generated (Default: "$SCRIPT_DIR_RELATIVE/out")
    --db-path <path>
        The sqlite database to use (Default: "$SQLITE_FILE_PATH_ABSOLUTE")
    --db-path-clone <path>
        The sqlite database is copied into the out directory and used as the database for the example
    --watch
        Watch for changes and rebuild/run accordingly
    --rebuild
        Unconditionally build all targets
    --help -h
        Show this help message
    -v, -vv, -vvv
        Control verbosity level

Sample Usage:
    ./play.sh run c examples/repl.sql
    ./play.sh run c examples/crud.sql
    ./play.sh run query_plan examples/crud.sql
    ./play.sh run lua examples/crud.sql
    ./play.sh run c examples/mandelbrot.sql
    ./play.sh run c lua query_plan examples/mandelbrot.sql
EOF

    exit $exit_code;
}

hello() {
    local cql_compiler_ready=$(is_dependency_satisfied cql_compiler && echo true || echo false)
    local java_ready=$(is_dependency_satisfied java && echo true || echo false)
    local jq_ready=$(is_dependency_satisfied jq && echo true || echo false)
    local lua_ready=$(is_dependency_satisfied lua && echo true || echo false)
    local lsqlite_ready=$(is_dependency_satisfied lsqlite && echo true || echo false)
    local dot_ready=$(is_dependency_satisfied dot && echo true || echo false)
    local python3_ready=$(is_dependency_satisfied python3 && echo true || echo false)
    local gcovr_ready=$(is_dependency_satisfied gcovr && echo true || echo false)

    cat <<EOF | theme
CQL Playground — Onboarding checklist

Required Dependencies
    The CQL compiler
        $($cql_compiler_ready && \
            echo "SUCCESS: The CQL compiler is ready ($CQL)" || \
            echo "ERROR: The CQL compiler was not found. Build it with: $CLI_NAME build-cql-compiler"
        )

Optional Dependencies
    Python3
        $($python3_ready && \
            echo "SUCCESS: Python3 is ready" || \
            echo "WARNING: Python3 was not found.
        Install it with: \`brew install python\` (MacOS) or go to https://www.python.org/downloads/".
        )
        Python is used to build different outputs derived from the json output
            - Java Wrappers
            - Table Diagrams
            - Region Diagrams
            - Entity Relationship Diagrams (ERD)
            - A .sql file for a database with the schema info
    Lua
        $($lua_ready && \
            echo "SUCCESS: Lua is ready" || \
            echo "WARNING: Lua was not found.
        Install it with: \`brew install lua\` (MacOS) or \`sudo apt-get install lua\` (Linux)".
        )
        Lua is used to run the Lua apps compiled by the CQL compiler.
        Only Useful to build and run Lua apps.
    LSQLite
        $($lsqlite_ready && \
            echo "SUCCESS: LSQLite is ready" || \
            echo "WARNING: LSQLite was not found.
        Install it with: \`brew install luarocks\` (MacOS) or \`sudo apt-get install luarocks\` (Linux).
        Finally, run \`luarocks install lsqlite3\`"
        )
        LSQLite is used to run Lua apps (using "\lsqlite3\") compiled by the CQL compiler.
        Only Useful to build and run Lua apps.
    Dot
        $($dot_ready && \
            echo "SUCCESS: Dot is ready" || \
            echo "WARNING: Dot was not found.
        Install it with: \`brew install graphviz\` (MacOS) or \`sudo apt-get install graphviz\` (Linux)"
        )
        Dot is used to generate PDF output from the AST Dot output. Only useful for debugging the AST.
    Java
        $($java_ready && \
            echo "SUCCESS: Java is ready (JAVA_HOME: ${JAVA_HOME:-Undefined})" || \
            echo "WARNING: \$JAVA_HOME must be set to your JDK dir"
        )
        Java is used to generate and execute the Java wrappers for CQL procedures.
    Gcovr
        $($gcovr_ready && \
            echo "SUCCESS: gcovr is ready" || \
            echo "WARNING: gcovr was not found.
        Install it with: \`brew install gcovr\` (MacOS) or \`sudo apt-get install gcovr\` (Linux)".
        )
        Gcovr is used to assemble code coverage reports for the CQL compiler.
        Gcovr provides a utility for managing the use of the GNU gcov utility and generating summarized code coverage results.

Recommended Dependencies
    JQ
        $($jq_ready && \
            echo "SUCCESS: JQ is ready" || \
            echo "NOTE: JQ was not found.
        Install it with: \`brew install jq\` (MacOS) or \`sudo apt-get install jq\` (Linux)".
        )
        JQ allows you to succinctly manipulate the JSON output.
EOF

    exit 0;
}

build_cql_compiler() {
    local current_dir=$(pwd);
    echo_vv "CQL Playground — Build CQL Compiler\n" | theme

    cd "$SCRIPT_DIR_RELATIVE/.." || { echo "Failed to change directory!"; return 1; }

    echo_vv "Cleaning up previous builds..."
    make clean || { echo "Make clean failed!"; cd "$current_dir"; return 1; }

    echo_vv "Building..."
    make || { echo "Build failed!"; cd "$current_dir"; return 1; }

    cd "$current_dir" || { echo "Failed to return to the original directory!"; return 1; }

    echo_vv ""
    echo_vv "SUCCESS: The CQL compiler is ready: $CQL" | theme
}

build_everything() {
    build "all_outputs" "$(echo $SCRIPT_DIR_RELATIVE/examples/*.sql)"

    echo_vv ""
    echo_vv "SUCCESS: All outputs are ready" | theme
}

build() {
    local targets=$1
    local sources=$2

    for source in $sources; do
        local example_name=$(resolve_example_name_from_source $source);

        do_build $example_name "$source" "$targets"
    done

    if [[ $VERBOSITY_LEVEL -ge 3 ]]; then
        execute "Listing all output folders" "ls -d $SCRIPT_OUT_DIR/*/"
    fi
}

do_build() {
    local example_name=$1
    local source=$2
    local targets=$3

    local resolved_sqlite_file_path_absolute="$SQLITE_FILE_PATH_ABSOLUTE"

    mkdir -p "$SCRIPT_OUT_DIR/$example_name"
    echo_vv -e "Building \`$example_name\` outputs ($source)\n" | theme

    if [[ $force_rebuild == true ]]; then
        MAKE_FLAGS="--always-make"
    else
        MAKE_FLAGS=""
    fi

    if [[ -z $targets ]]; then
        targets="c"
    fi

    if [[ $CLONE_SQLITE_DATABASE == true ]]; then
        resolved_sqlite_file_path_absolute="$SCRIPT_OUT_DIR/$example_name/$(basename $SQLITE_FILE_PATH_ABSOLUTE)"

        cp "$SQLITE_FILE_PATH_ABSOLUTE" "$resolved_sqlite_file_path_absolute"

        echo_vvv -e "INFO: The SQLite database was cloned into the output directory and used as the database for the example\n" | theme
    else
        # Cleanup previously generated database file to avoid confusion
        rm -f "$SCRIPT_OUT_DIR/$example_name/$(basename $SQLITE_FILE_PATH_ABSOLUTE)"
    fi

    if [[ $SQLITE_FILE_PATH_ABSOLUTE != ":memory:" ]]; then
        echo_vv -e "NOTE: SQLITE Database Path: $resolved_sqlite_file_path_absolute\n" | theme
    fi

    # The file is static: `'EOF'` disables variable expansion
    # `.RECIPEPREFIX = > ` Emulated with sed for unsupported on macos's old make
    # It avoids mixing indentation strategies and improves default output indentation
    <<'EOF' cat | sed -E 's/(^> )/\t/g' | tee ./out/Makefile | make \
    $MAKE_FLAGS \
    --makefile - \
    SQLITE_FILE_PATH_ABSOLUTE="$resolved_sqlite_file_path_absolute" \
    CQL_ROOT_DIR="$CQL_ROOT_DIR" \
    CQL="$CQL" \
    SCRIPT_DIR_RELATIVE="$SCRIPT_DIR_RELATIVE" \
    DEFAULT_C_CLIENT="$DEFAULT_C_CLIENT" \
    dot_is_ready="$(is_dependency_satisfied dot && echo true || echo false)" \
    is_example_implemented_in_c=$(is_example_implemented_in c "$source" && echo true || echo false) \
    is_example_implemented_in_lua=$(is_example_implemented_in lua "$source" && echo true || echo false) \
    source="$source" \
    example_name="$example_name" \
    OUT="$SCRIPT_OUT_DIR/$example_name" \
    $targets gitignore
O=$(OUT)

TO_PASCAL_CASE = $(shell echo $(1) | awk 'BEGIN {FS="[^a-zA-Z0-9]+"; OFS="";} {for (i=1; i<=NF; i++) $$i=toupper(substr($$i, 1, 1)) tolower(substr($$i, 2));} {print}')

.PHONY:      gitignore preprocessed c c_binary lua query_plan objc java schema_upgrade cql_json_schema schema stats ast ast_dot cql_sql_schema cql_sqlite_schema table_diagram_dot region_diagram_dot erd_dot ast_dot_pdf table_diagram_dot_pdf region_diagram_dot_pdf erd_dot_pdf
all_outputs: gitignore preprocessed c c_binary lua query_plan objc java schema_upgrade cql_json_schema schema stats ast ast_dot cql_sql_schema cql_sqlite_schema table_diagram_dot region_diagram_dot erd_dot ast_dot_pdf table_diagram_dot_pdf region_diagram_dot_pdf erd_dot_pdf

gitignore: $O/.gitignore
$O/.gitignore:
> @echo '*' > $O/.gitignore

preprocessed: $O/$(example_name).pre.sql
$O/$(example_name).pre.sql: $(source)
> cc -I$O -I$(SCRIPT_DIR_RELATIVE) --preprocess --language=c $(source) > $O/$(example_name).pre.sql

$O/$(example_name).c: $O/$(example_name).pre.sql
> $(CQL) --nolines --in $O/$(example_name).pre.sql --cg $O/$(example_name).h $O/$(example_name).c $O/$(example_name)_imports.sql --generate_exports --cqlrt $(CQL_ROOT_DIR)/cqlrt.h

c: $O/$(example_name)
$O/$(example_name): $O/$(example_name).c
ifeq ($(is_example_implemented_in_c),true)
> if grep -q "entrypoint(void)" $O/$(example_name).h; then \
    FLAGS="-DNO_DB_CONNECTION_REQUIRED_FOR_ENTRYPOINT"; \
fi; \
cc $$FLAGS --debug -DSQLITE_FILE_PATH_ABSOLUTE="\"$(SQLITE_FILE_PATH_ABSOLUTE)\"" -DCQL_TRACING_ENABLED -Wno-macro-redefined -DHEADER_FILE_FOR_SPECIFIC_EXAMPLE='"$(example_name).h"' -I$O -I$(SCRIPT_DIR_RELATIVE) -I$(CQL_ROOT_DIR) $O/$(example_name).c $(DEFAULT_C_CLIENT) $(CQL_ROOT_DIR)/cqlrt.c --output $O/$(example_name) -lsqlite3 && rm -rf "$O/$(example_name).dSYM"
else
> echo "$(example_name) ($(source)) is not implemented in C yet"
endif

objc: $O/$(example_name).pre.sql
> mkdir -p $O/objc
> $(CQL) --nolines --in $O/$(example_name).pre.sql --cg $O/objc/$(example_name).h $O/objc/$(example_name).c --cqlrt $(CQL_ROOT_DIR)/cqlrt_cf/cqlrt_cf.h
> $(CQL) --dev --test --in $O/$(example_name).pre.sql --rt objc_mit --cg $O/objc/$(example_name)_objc.h --objc_c_include_path $O/objc/$(example_name).h
> if grep -q "entrypoint(void)" $O/objc/$(example_name).h; then \
    FLAGS="-DNO_DB_CONNECTION_REQUIRED_FOR_ENTRYPOINT"; \
fi; \
cc $$FLAGS -x objective-c --debug -DSQLITE_FILE_PATH_ABSOLUTE="\"$(SQLITE_FILE_PATH_ABSOLUTE)\"" -DCQL_TRACING_ENABLED -Wno-macro-redefined -DHEADER_FILE_FOR_SPECIFIC_EXAMPLE='"$(example_name).h"' -I$O/objc -I$(CQL_ROOT_DIR)/cqlrt_cf -I$(CQL_ROOT_DIR) -I$(SCRIPT_DIR_RELATIVE) $O/objc/$(example_name).c $(SCRIPT_DIR_RELATIVE)/default_client.c $(CQL_ROOT_DIR)/cqlrt_cf/cqlrt_cf.c $(CQL_ROOT_DIR)/cqlrt_cf/cqlholder.m --output $O/objc/$(example_name) -lsqlite3 -framework Foundation -fobjc-arc

query_plan: $O/$(example_name).pre.sql c
> $(CQL) --nolines --in $O/$(example_name).pre.sql --rt query_plan --cg $O/query_plan.sql;
> $(CQL) --nolines --dev --in $O/query_plan.sql --cg $O/query_plan.h $O/query_plan.c;
> cc --compile -I$O -I$(SCRIPT_DIR_RELATIVE) -I$(CQL_ROOT_DIR) $O/query_plan.c -o $O/query_plan.o;
> cc --compile -I$O -I$(SCRIPT_DIR_RELATIVE) -I$(CQL_ROOT_DIR) $(CQL_ROOT_DIR)/query_plan_test.c -o $O/query_plan_test.o;
> cc --debug --optimize -I$O -I$(SCRIPT_DIR_RELATIVE) -I$(CQL_ROOT_DIR) $O/query_plan.o $O/query_plan_test.o $(CQL_ROOT_DIR)/cqlrt.c --output $O/query_plan -lsqlite3 && rm -rf "$O/query_plan.dSYM";

$O/cqlrt.lua:
> cp $(CQL_ROOT_DIR)/cqlrt.lua $O/cqlrt.lua

lua: $O/$(example_name).lua
$O/$(example_name).lua: $O/$(example_name).pre.sql $O/cqlrt.lua
ifeq ($(is_example_implemented_in_lua),true)
> $(CQL) --in $O/$(example_name).pre.sql --rt lua --cg $O/$(example_name).lua && cat $(SCRIPT_DIR_RELATIVE)/default_client.lua >> $O/$(example_name).lua
else
> echo "$(example_name) ($(source)) is not implemented in Lua yet"
endif

schema_upgrade: $O/schema_upgrade.sql
$O/schema_upgrade.sql: $O/$(example_name).pre.sql
> $(CQL) --in $O/$(example_name).pre.sql --rt schema_upgrade --cg $O/schema_upgrade.sql --global_proc entrypoint

cql_json_schema: $O/cql_json_schema.json
$O/cql_json_schema.json: $O/$(example_name).pre.sql
> $(CQL) --in $O/$(example_name).pre.sql --rt json_schema --cg $O/cql_json_schema.json

schema: $O/schema.sql
$O/schema.sql: $O/$(example_name).pre.sql
> $(CQL) --in $O/$(example_name).pre.sql --rt schema --cg $O/schema.sql

stats: $O/stats.csv
$O/stats.csv: $O/$(example_name).pre.sql
> $(CQL) --in $O/$(example_name).pre.sql --rt stats --cg $O/stats.csv

ast: $O/ast.txt
$O/ast.txt: $O/$(example_name).pre.sql
> $(CQL) --in $O/$(example_name).pre.sql --sem --ast --hide_builtins > $O/ast.txt # remove builtin spam

ast_dot: $O/ast.dot
$O/ast.dot: $O/$(example_name).pre.sql
> $(CQL) --in $O/$(example_name).pre.sql --dot --hide_builtins > $O/ast.dot # remove builtin spam

cql_sql_schema: $O/cql_sql_schema.sql
$O/cql_sql_schema.sql: $O/cql_json_schema.json
> $(CQL_ROOT_DIR)/cqljson/cqljson.py --sql $O/cql_json_schema.json > $O/cql_sql_schema.sql

cql_sqlite_schema: $O/cql_sqlite_schema.sqlite
$O/cql_sqlite_schema.sqlite: $O/cql_sql_schema.sql
> rm -f $O/cql_sqlite_schema.sqlite && cat $O/cql_sql_schema.sql | sqlite3 $O/cql_sqlite_schema.sqlite

table_diagram_dot: $O/table_diagram.dot
$O/table_diagram.dot: $O/cql_json_schema.json
> $(CQL_ROOT_DIR)/cqljson/cqljson.py --table_diagram $O/cql_json_schema.json > $O/table_diagram.dot

region_diagram_dot: $O/region_diagram.dot
$O/region_diagram.dot: $O/cql_json_schema.json
> $(CQL_ROOT_DIR)/cqljson/cqljson.py --region_diagram $O/cql_json_schema.json > $O/region_diagram.dot

erd_dot: $O/erd.dot
$O/erd.dot: $O/cql_json_schema.json
> $(CQL_ROOT_DIR)/cqljson/cqljson.py --erd $O/cql_json_schema.json > $O/erd.dot

java: $O/$(example_name).java
$O/$(example_name).java: $O/cql_json_schema.json
> $(CQL_ROOT_DIR)/java_demo/cqljava.py $O/cql_json_schema.json --package $(example_name) --class $(call TO_PASCAL_CASE, $(example_name)) > $O/$(example_name).java

ifeq ($(dot_is_ready),true)
ast_dot_pdf: $O/ast.dot.pdf
$O/ast.dot.pdf: $O/ast.dot
> dot $O/ast.dot -Tpdf -o $O/ast.dot.pdf

table_diagram_dot_pdf: $O/table_diagram.dot.pdf
$O/table_diagram.dot.pdf: $O/table_diagram.dot
> dot $O/table_diagram.dot -Tpdf -o $O/table_diagram.dot.pdf

region_diagram_dot_pdf: $O/region_diagram.dot.pdf
$O/region_diagram.dot.pdf: $O/region_diagram.dot
> dot $O/region_diagram.dot -Tpdf -o $O/region_diagram.dot.pdf

erd_dot_pdf: $O/erd.dot.pdf
$O/erd.dot.pdf: $O/erd.dot
> dot $O/erd.dot -Tpdf -o $O/erd.dot.pdf
else
ast_dot_pdf: $O/ast.dot.pdf
$O/ast.dot.pdf: $O/ast.dot
> @echo "You need to install dot to generate $O/ast.dot.pdf"

table_diagram_dot_pdf: $O/table_diagram.dot.pdf
$O/table_diagram.dot.pdf: $O/table_diagram.dot
> @echo "You need to install dot to generate $O/table_diagram.dot.pdf"

region_diagram_dot_pdf: $O/region_diagram.dot.pdf
$O/region_diagram.dot.pdf: $O/region_diagram.dot
> @echo "You need to install dot to generate $O/region_diagram.dot.pdf"

erd_dot_pdf: $O/erd.dot.pdf
$O/erd.dot.pdf: $O/erd.dot
> @echo "You need to install dot to generate $O/erd.dot.pdf"
endif
EOF

    if [[ $VERBOSITY_LEVEL -ge 3 ]]; then
        execute "Listing the output files for '$example_name'" "ls $SCRIPT_OUT_DIR/$example_name/*"
    fi
}

run() {
    local targets="$1";
    local sources="$2";

    build "$targets" "$sources"

    for source in $sources; do
        local example_name=$(resolve_example_name_from_source $source);

        echo_vv -e "Running \`$example_name\` outputs ($source)\n" | theme

        if [[ $targets == "all_outputs" ]]; then
            targets="c lua objc java schema_upgrade cql_json_schema schema stats ast ast_dot cql_sql_schema cql_sqlite_schema table_diagram_dot region_diagram_dot erd_dot ast_dot_pdf table_diagram_dot_pdf region_diagram_dot_pdf erd_dot_pdf"
        fi

        for out_type in $targets; do
            do_run $example_name $out_type
        done
    done
}

do_run() {
    local example_name=$1
    local target=$2

    local example_output_dir_relative="$SCRIPT_OUT_DIR/$example_name"

    case "$target" in
        c|lua)
            if ! is_example_implemented_in "$target" "$source"; then
                echo "WARNING: Example $example_name is not implemented in $target" | theme
                exit 0 
            fi
            ;;
    esac

    case "$target" in
        preprocessed)            execute "The 'preprocessed' output"            "cat $example_output_dir_relative/$example_name.sql.pre" ;;
        c)                       execute "The 'c' output"                       "$example_output_dir_relative/$example_name" ;;
        objc)                    execute "The 'objc' output"                    "$example_output_dir_relative/objc/$example_name" ;;
        java)                    execute "The 'java' output"                    "cat $example_output_dir_relative/$example_name.java" ;;
        lua)                     execute "The 'lua' output"                     "(cd $example_output_dir_relative/ ; lua $example_name.lua)" ;;
        query_plan)              execute "The 'query_plan' output"              "$example_output_dir_relative/query_plan" ;;
        schema_upgrade)          execute "The 'schema_upgrade' output"          "cat $example_output_dir_relative/schema_upgrade.sql" ;;
        cql_json_schema)         execute "The 'cql_json_schema' output"         "cat $example_output_dir_relative/cql_json_schema.json" ;;
        cql_sql_schema)          execute "The 'cql_sql_schema' output"          "cat $example_output_dir_relative/cql_sql_schema.sql" ;;
        cql_sqlite_schema)       execute "The 'cql_sqlite_schema' output"       "ls $example_output_dir_relative/cql_sqlite_schema.sqlite" ;;
        table_diagram_dot)       execute "The 'table_diagram_dot' output"       "cat $example_output_dir_relative/table_diagram.dot" ;;
        table_diagram_dot_pdf)   execute "The 'table_diagram_dot_pdf' output"   "echo \"$ open $example_output_dir_relative/table_diagram.dot.pdf\"" ;;
        region_diagram_dot)      execute "The 'region_diagram_dot' output"      "cat $example_output_dir_relative/region_diagram.dot" ;;
        region_diagram_dot_pdf)  execute "The 'region_diagram_dot_pdf' output"  "echo \"$ open $example_output_dir_relative/region_diagram.dot.pdf\"" ;;
        erd_dot)                 execute "The 'erd_dot' output"                 "cat $example_output_dir_relative/erd.dot" ;;
        erd_dot_pdf)             execute "The 'erd_dot_pdf' output"             "echo \"$ open $example_output_dir_relative/erd.dot.pdf\"" ;;
        schema)                  execute "The 'schema' output"                  "cat $example_output_dir_relative/schema.sql" ;;
        stats)                   execute "The 'stats' output"                   "cat $example_output_dir_relative/stats.csv" ;;
        ast)                     execute "The 'ast' output"                     "cat $example_output_dir_relative/ast.txt" ;;
        ast_dot)                 execute "The 'ast_dot' output"                 "cat $example_output_dir_relative/ast.dot" ;;
        ast_dot_pdf)             execute "The 'ast_dot_pdf' output"             "echo \"$ open $example_output_dir_relative/ast.dot.pdf\"" ;;
        *)
            echo "ERROR: Unknown target: $target" | theme
            exit 1
            ;;
    esac
}

run_data_access_demo() {
    local source="$SCRIPT_DIR_RELATIVE/examples/crud.sql"
    local example_name="crud_data_access_demo"

    DEFAULT_C_CLIENT="$SCRIPT_DIR_RELATIVE/adhoc_client_crud_data_access.c"

    echo_vv -e "CQL Playground — Data Access Demonstration

Build Step
" | theme

    do_build $example_name $source c

    echo_vv -e "
Related Files

    The c file performing the data access
        $DEFAULT_C_CLIENT

    The sql file being used
        $source

    The compiled binary
        $SCRIPT_OUT_DIR/$example_name/$example_name

Executing the demonstration
" | theme

    do_run $example_name c
}

watch() {
    local sources="$1";
    local rest="$2"
    rest="${rest/--watch/}" # avoids infinite loops

    if ! type "entr" > /dev/null 2>&1; then
        echo -e "WARNING: You must install entr to use the --watch option" | theme
        echo -e "NOTE: Falling back to standard execution" | theme
        echo

        $SCRIPT_DIR_RELATIVE/play.sh $rest

        exit $?
    fi

    echo_vvv -e "WARNING: Make the output less noisy with the \`-v\` option\n" | theme
    echo_vv -e "Watching file(s): $sql_files\n"

    ls -d $sources | SHELL="/bin/bash" entr -s "./play.sh $rest --rebuild"
}

clean() {
    if [[ "$SCRIPT_OUT_DIR" == "$SCRIPT_DIR_RELATIVE/out" ]]; then
        execute "Cleaning all generated files" "rm -rf \"$SCRIPT_DIR_RELATIVE/out\""
        echo -e "Playground: Done"
        exit 0
    fi

    # Below is a safety net to avoid deleting the wrong directory

    echo "ERROR: Clean yourself" | theme
    echo "Double-check and run the following command:"
    echo "COMMAND: rm -rf \"$SCRIPT_OUT_DIR/*\"" | theme

    exit 1
}

# Utils
function theme() {
    ! $IS_TTY && cat || awk '
{ gsub(/<output_list>/, "\033[36m&\033[37m") }
{ gsub(/<path_to_example_list>/, "\033[32m&\033[37m") }

/^([[:space:]]*)SUCCESS:/   { sub("SUCCESS:", "✅ \033[1;32m&"); print; printf "\033[0m"; next }
/^([[:space:]]*)INFO:/      { sub("INFO:", "💡 \033[1;34m&"); print; printf "\033[0m"; next }
/^([[:space:]]*)WARNING:/   { sub("WARNING:", "⚠️  \033[1;33m&"); print; printf "\033[0m"; next }
/^([[:space:]]*)ERROR:/     { sub("ERROR:", "❌ \033[1;31m&"); print; printf "\033[0m"; next }
/^([[:space:]]*)NOTE:/      { sub("NOTE:", "📢 \033[1;37m&"); print; printf "\033[0m"; next }
/^([[:space:]]*)#/          { sub("#", "\033[0;30m&"); print; printf "\033[0m"; next }
/^([[:space:]]*)COMMAND:/   { sub("COMMAND:", "\033[0m$\033[1;37m"); print; in_command_block = 1; next }
in_command_block && /^$/ { printf "\033[0m\n"; in_command_block = 0; next; }
in_command_block { print; next; }

/^CQL Playground/  { print "\033[1;4m" $0 "\033[0m"; next }

/^        / { print; next }
/^    /     { print "\033[1m" $0 "\033[0m"; next }
/^./        { print "\033[4m" $0 "\033[0m"; next }
            { print }

END { printf "\033[0;0m" }'
}

resolve_example_name_from_source() {
    local source=$1

    echo $source | sed 's|.*/\(.*\)\.sql$|\1|'
}

execute() {
    local description="$1"
    local command="$2"

    shift

    if [[ -n "$description" ]]; then
        echo_vvv -e "\n# $description" | theme >&2
        echo_vv -e "COMMAND: $command" | theme >&2
    fi

    eval "$command"

    if [[ $? -ne 0 ]]; then
        echo -e "ERROR: The command failed" | theme >&2
        echo -e "NOTE: If there is \"No such file or directory\", try with --rebuild" | theme

        if [[ $VERBOSITY_LEVEL -lt 2 ]]; then
            echo -e "COMMAND: $command" | theme >&2
        fi

        exit 1
    fi
}

is_dependency_satisfied() {
    local dependency=$1

    case $dependency in
        java)
            type java >/dev/null 2>&1 \
            && test -n "${JAVA_HOME}" \
            && return 0 || return 1
            ;;
        lsqlite)
            type luarocks >/dev/null 2>&1 \
            && luarocks show lsqlite3 --porcelain >/dev/null 2>&1 \
            && return 0 || return 1
            ;;

        cql_compiler) type "$CQL"  >/dev/null 2>&1 && return 0 || return 1 ;;
        jq)           type jq      >/dev/null 2>&1 && return 0 || return 1 ;;
        lua)          type lua     >/dev/null 2>&1 && return 0 || return 1 ;;
        dot)          type dot     >/dev/null 2>&1 && return 0 || return 1 ;;
        python3)      type python3 >/dev/null 2>&1 && return 0 || return 1 ;;
        gcovr)        type gcovr >/dev/null 2>&1 && return 0 || return 1 ;;

        *)
            echo "Unknown dependency: $1";
            exit 1
            ;;
    esac
}

is_example_implemented_in() {
    local runtime=$1
    local source=$2
    
    # You would typically do this using the json output. We're avoiding extra dependencies and complexity

    case "$runtime" in
        c)   grep -q '^\s*@attribute(playground:not_implemented_in_c)\s*$'   "$source" && return 1 || return 0 ;;
        lua) grep -q '^\s*@attribute(playground:not_implemented_in_lua)\s*$' "$source" && return 1 || return 0 ;;
    esac

    return 1
}

ensure_source_files_are_provided() {
    local source=$1

    if [[ -z $sql_files ]]; then
        echo -e "ERROR: Provide at least one sql file to run" | theme
        execute "See all examples available" "ls $SCRIPT_DIR_RELATIVE/examples/*.sql"
        exit 1
    fi
}

echo_v()   { [[ $VERBOSITY_LEVEL -ge 1 ]] && echo "$@" || echo -n ""; }
echo_vv()  { [[ $VERBOSITY_LEVEL -ge 2 ]] && echo "$@" || echo -n ""; }
echo_vvv() { [[ $VERBOSITY_LEVEL -ge 3 ]] && echo "$@" || echo -n ""; }

initial_parameters="$@"
sub_command="exit_with_help_message"
force_rebuild=false
watch=false
sql_files=""
targets=""
rest=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        help|-h|--help) exit_with_help_message 0 ;;

        hello)                sub_command="hello" ;;
        build-cql-compiler)   sub_command="build_cql_compiler" ;;

        build)                sub_command="build" ;;
        run)                  sub_command="run" ;;
        clean)                sub_command="clean" ;;
        build-everything)     sub_command="build_everything" ;;
        run-data-access-demo) sub_command="run_data_access_demo" ;;

        preprocessed|c|lua|objc|java|schema|schema_upgrade|query_plan|stats|ast|ast_dot| \
        cql_json_schema|cql_sql_schema|cql_sqlite_schema|table_diagram_dot|table_diagram_dot_pdf| \
        region_diagram_dot|region_diagram_dot_pdf|erd_dot|erd_dot_pdf)
            if [[ $targets != "all_outputs" ]] && [[ ! $targets =~ (^|[[:space:]])$1($|[[:space:]]) ]]; then
                targets="$targets $1"
            fi
            ;;

        all_outputs|all) targets="all_outputs" ;;
        *.sql) sql_files="$sql_files $1" ;;

        --rebuild) force_rebuild=true ;;
        --watch) watch=true ;;

        --db-path|--db-path-clone)
            if [[ -z "${2-}" ]]; then
                echo -e "ERROR: You must provide a path to a database for --db-path[-clone]" | theme
                exit 1
            fi

            case $2 in
                /*) SQLITE_FILE_PATH_ABSOLUTE="$2" ;;
                *)  SQLITE_FILE_PATH_ABSOLUTE="$SCRIPT_DIR/$2" ;;
            esac

            if [[ ! -f "$SQLITE_FILE_PATH_ABSOLUTE" ]]; then
                echo -e "ERROR: The path provided for --db-path[-clone] is not a file" | theme
                exit 1
            fi

            if [[ $1 == "--db-path-clone" ]]; then
                CLONE_SQLITE_DATABASE=true
            fi

            shift
            ;;

        --out-dir)
            if [[ -z "${2-}" ]]; then
                echo -e "ERROR: You must provide a path for --out-dir" | theme
                exit 1
            fi

            SCRIPT_OUT_DIR="$2"

            if [[ ! -d "$SCRIPT_OUT_DIR" ]]; then
                mkdir -p "$SCRIPT_OUT_DIR"
            fi

            shift
            ;;

        -vvv)       VERBOSITY_LEVEL=3 ;;
        -vv)        VERBOSITY_LEVEL=2 ;;
        -v)         VERBOSITY_LEVEL=1 ;;
        --quiet|-q) VERBOSITY_LEVEL=0 ;;

        *) rest="$rest $1" ;;
    esac
    shift
done

if [[ $rest != "" ]]; then
    echo -e "ERROR: Unknown arguments: $rest" | theme
    exit 1
fi

if [[ $sub_command != "build_cql_compiler" ]] && ! is_dependency_satisfied cql_compiler; then
    hello
    exit 1
fi

case "$sub_command" in
    run)
        ensure_source_files_are_provided $sql_files

        if "$watch"; then
            echo_vv -e "CQL Playground — Run (Watching)\n" | theme
            watch "$sql_files" "$initial_parameters"
        else
            echo_vv -e "CQL Playground — Run\n" | theme
            run "$targets" "$sql_files"

            echo -e "\nPlayground: Done"
        fi
        ;;

    build)
        ensure_source_files_are_provided $sql_files

        if "$watch"; then
            echo_vv -e "CQL Playground — Build (Watching)\n" | theme
            watch "$sql_files" "$initial_parameters"
        else
            echo_vv -e "CQL Playground — Build\n" | theme
            build "$targets" "$sql_files"

            echo -e "\nPlayground: Done"
        fi
        ;;

    exit_with_help_message) exit_with_help_message 1 ;;

    hello|clean|run_data_access_demo|build_cql_compiler|build_everything) $sub_command ;;

    *) echo -e "ERROR: Unknown sub-command: $sub_command" | theme; exit 1;
esac
