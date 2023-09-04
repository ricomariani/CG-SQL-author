#!/bin/bash

# Globals

readonly CLI_NAME=${0##*/}
readonly SCRIPT_DIR=$(dirname $(readlink -f "$0"))
readonly SCRIPT_DIR_RELATIVE=$(dirname "$0")
SCRIPT_OUT_DIR_RELATIVE=$SCRIPT_DIR_RELATIVE/out
readonly CQL_ROOT_DIR=$SCRIPT_DIR_RELATIVE/..
readonly CQL=$CQL_ROOT_DIR/out/cql

tty -s <&1 && IS_TTY=true || IS_TTY=false
VERBOSITY_LEVEL=$([ "$IS_TTY" = "true" ] && echo 3 || echo 0)
DEFAULT_C_CLIENT=${DEFAULT_C_CLIENT:-$SCRIPT_DIR_RELATIVE/default_client.c}
DEFAULT_LUA_CLIENT=${DEFAULT_LUA_CLIENT:-$SCRIPT_DIR_RELATIVE/default_client.lua}

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
        ast — The internal AST
        ast_dot — The internal AST using dot format
        objc — The Objective-C wrappers
        java — The Java wrappers
        json_schema — A JSON output for codegen tools
        schema — The canonical schema
        schema_upgrade — A CQL schema upgrade script
        query_plan — The query plan for every DML statement
        stats — A simple .csv file with AST node count information per procedure
        all_outputs — All outputs

    Examples (<path_to_example_list>)
        Any ".sql" file. See: $SCRIPT_DIR_RELATIVE/examples/*.sql

Options:
    --out-dir <path>
        The directory where the outputs will be generated (Default: $SCRIPT_DIR_RELATIVE/out)
    --watch
        Watch for changes and rebuild/run accordingly
    --rebuild
        Rebuild before running
    --help -h
        Show this help message
    -v, -vv, -vvv
        Control verbosity level
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

    cat <<EOF | theme
CQL Playground — Onboarding checklist

Required Dependencies
    The CQL compiler
        $($cql_compiler_ready && \
            echo "SUCCESS: The CQL compiler is ready ($CQL)" || \
            echo "ERROR: The CQL compiler was not found. Build it with: $CLI_NAME build-cql-compiler"
        )

Optional Dependencies
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
        Dot is used to generate png output from the AST Dot output. Only useful for debugging the AST.
    Java
        $($java_ready && \
            echo "SUCCESS: Java is ready (JAVA_HOME: ${JAVA_HOME:-Undefined})" || \
            echo "WARNING: \$JAVA_HOME must be set to your JDK dir"
        )
        Java is used to generate and execute the Java wrappers for CQL procedures.

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
    echo -e "CQL Playground — Build CQL Compiler\n" | theme

    cd "$SCRIPT_DIR_RELATIVE/.." || { echo "Failed to change directory!"; return 1; }

    echo "Cleaning up previous builds..."
    make clean || { echo "Make clean failed!"; cd "$current_dir"; return 1; }

    echo "Building..."
    make || { echo "Build failed!"; cd "$current_dir"; return 1; }

    cd "$current_dir" || { echo "Failed to return to the original directory!"; return 1; }

    echo -e "\nSUCCESS: The CQL compiler is ready: $CQL" | theme
}

build_everything() {
    build "$all_output_list" "$(echo $SCRIPT_DIR_RELATIVE/examples/*.sql)"

    if [[ $VERBOSITY_LEVEL -ge 2 ]]; then
        echo ""
        execute "Listing the output files" "ls $SCRIPT_OUT_DIR_RELATIVE/"
    else 
        echo -e "SUCCESS: All outputs are ready" | theme
    fi
}

build() {
    local out_types=$1
    local sources=$2

    for source in $sources; do
        local example_name=$(resolve_example_name_from_source $source);

        echo_vv -e "Building \`$example_name\` outputs ($source)\n" | theme

        initialize_example $source $example_name

        for out_type in $out_types; do
            do_build $example_name $out_type || (echo "The output $out_type could not be built for $source" && exit 1)
        done

        if [[ $VERBOSITY_LEVEL -ge 3 ]]; then
            execute "Listing the output files" "ls $SCRIPT_OUT_DIR_RELATIVE/$example_name/*"
        fi
    done
}

do_build() {
    local example_name=$1
    local target=$2

    local example_output_dir_relative="$SCRIPT_OUT_DIR_RELATIVE/$example_name"
    local preprocessed_path="$example_output_dir_relative/$example_name.sql.pre"

    case "$target" in
        c)
        # if $default_c_client empty, then default to ./default_c_client.c

            execute "The 'c' output" "$CQL \\
    --nolines \\
    --in $preprocessed_path \\
    --cg \\
        $example_output_dir_relative/$example_name.h \\
        $example_output_dir_relative/$example_name.c \\
        $example_output_dir_relative/${example_name}_imports.sql \\
    --generate_exports"
            execute "The 'c' binary output" "cc --debug \\
    -DEXAMPLE_HEADER_NAME='\"$example_name.h\"' \\
    -I$CQL_ROOT_DIR -I$SCRIPT_DIR_RELATIVE -I$example_output_dir_relative \\
    $example_output_dir_relative/$example_name.c \\
    $DEFAULT_C_CLIENT \\
    $CQL_ROOT_DIR/cqlrt.c \\
    --output $example_output_dir_relative/$example_name \\
    -lsqlite3"
            execute "Clean noise" "rm -rf $example_output_dir_relative/$example_name.dSYM"
            ;;

        query_plan)
            execute "" "$CQL --nolines --in $preprocessed_path --rt query_plan --cg $example_output_dir_relative/query_plan.sql"
            execute "" "$CQL --dev \\
    --in $example_output_dir_relative/query_plan.sql \\
    --cg $example_output_dir_relative/query_plan.h $example_output_dir_relative/query_plan.c"
            execute "Compile query_plan.o" "cc --compile -I$CQL_ROOT_DIR -I$SCRIPT_DIR_RELATIVE -I$example_output_dir_relative $example_output_dir_relative/query_plan.c -o $example_output_dir_relative/query_plan.o"
            execute "Compile query_plan_test.o" "cc --compile -I$CQL_ROOT_DIR -I$SCRIPT_DIR_RELATIVE -I$example_output_dir_relative $CQL_ROOT_DIR/query_plan_test.c -o $example_output_dir_relative/query_plan_test.o"
            execute "Compile query_plan" "cc --debug --optimize \\
    -I$CQL_ROOT_DIR -I$SCRIPT_DIR_RELATIVE -I$example_output_dir_relative \\
    $example_output_dir_relative/query_plan.o \\
    $example_output_dir_relative/query_plan_test.o \\
    $CQL_ROOT_DIR/cqlrt.c \\
    --output $example_output_dir_relative/query_plan \\
    -lsqlite3"
            execute "" "rm -rf $example_output_dir_relative/query_plan.dSYM"
            ;;

        lua)
            execute "The 'lua' output" \
                "$CQL --in $preprocessed_path --rt lua --cg $example_output_dir_relative/$example_name.lua"

            execute "Inlining the default Lua client in the lua output" \
                "cat $SCRIPT_DIR_RELATIVE/default_client.lua >> $example_output_dir_relative/$example_name.lua"

            execute "Copy Lua runtime (cqlrt.lua)" \
                "cp \"$CQL_ROOT_DIR/cqlrt.lua\" $example_output_dir_relative/cqlrt.lua"
            ;;

        schema_upgrade)
            execute "The 'schema_upgrade' output" \
                "$CQL --in $preprocessed_path --rt schema_upgrade --cg $example_output_dir_relative/schema_upgrade.sql --global_proc entrypoint"
            ;;
        json_schema)
            execute "The 'json_schema' output" \
                "$CQL --in $preprocessed_path --rt json_schema --cg $example_output_dir_relative/json_schema.json"
            ;;
        schema)
            execute "The 'schema' output" \
                "$CQL --in $preprocessed_path --rt schema --cg $example_output_dir_relative/schema.sql"
            ;;
        stats)
            execute "The 'stats' output" \
                "$CQL --in $preprocessed_path --rt stats --cg $example_output_dir_relative/stats.csv"
            ;;
        ast)
            execute "The 'ast' output" \
                "$CQL --in $preprocessed_path --sem --ast > $example_output_dir_relative/ast.txt"
            ;;
        ast_dot)
            execute  "The 'ast_dot' output"  "$CQL --in $preprocessed_path --dot > $example_output_dir_relative/ast.dot"
            ;;
        ast_dot_png)
            if type "dot" > /dev/null 2>&1; then
                execute "The 'ast_dot_png' output" "dot $example_output_dir_relative/ast.dot -Tpng -o $example_output_dir_relative/ast.dot.png"
            fi
            ;;
        *)
            echo "Unknown build target: $target"
            return 1
            ;;
    esac
}

run() {
    local out_types="$1";
    local sources="$2";

    if "$force_rebuild"; then
        build "$out_types" "$sources"
        echo_vv -e ""
    fi

    for source in $sources; do
        local example_name=$(resolve_example_name_from_source $source);

        echo_vv -e "Running \`$example_name\` outputs ($source)\n" | theme

        for out_type in $out_types; do
            do_run $example_name $out_type
        done
    done
}

do_run() {
    local example_name=$1
    local target=$2

    local example_output_dir_relative="$SCRIPT_OUT_DIR_RELATIVE/$example_name"

    case "$target" in
        c)              execute "The 'c' output"               "$example_output_dir_relative/$example_name -vvv";;
        lua)            execute "The 'lua' output"             "echo \"$ (cd $example_output_dir_relative/ ; lua $example_name.lua)\"" ;;
        query_plan)     execute "The 'query_plan' output"      "$example_output_dir_relative/query_plan" ;;
        schema_upgrade) execute "The 'schema_upgrade' output"  "cat $example_output_dir_relative/schema_upgrade.sql" ;;
        json_schema)    execute "The 'json_schema' output"     "cat $example_output_dir_relative/json_schema.json" ;;
        schema)         execute "The 'schema' output"          "cat $example_output_dir_relative/schema.sql" ;;
        stats)          execute "The 'stats' output"           "cat $example_output_dir_relative/stats.csv" ;;
        ast)            execute "The 'ast' output"             "cat $example_output_dir_relative/ast.txt" ;;
        ast_dot)        execute "The 'ast_dot' output"         "cat $example_output_dir_relative/ast.dot" ;;
        ast_dot_png)    execute "The 'ast_dot_png' output"     "echo \"$ open $example_output_dir_relative/ast.dot.png\"" ;;
        *)
            echo "Unknown target: $target"
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
    initialize_example $source $example_name
    do_build $example_name c

    echo_vv -e ""

    echo_vv -e "Related Files

    The c file performing the data access
        $DEFAULT_C_CLIENT
    
    The sql file being used
        $source

    The compiled binary
        $SCRIPT_OUT_DIR_RELATIVE/$example_name/$example_name

Executing the demonstration
" | theme
    do_run $example_name c
}

watch() {
    local sources="$1";
    local rest="$2"
    rest="${rest/--watch/}" # avoids infinite loops

    if ! type "entr" > /dev/null 2>&1; then
        echo "WARNING: You must install entr to use the --watch option" | theme
        echo "NOTE: Falling back to standard execution" | theme
        echo
        
        $SCRIPT_DIR_RELATIVE/playground.sh $rest

        exit $?
    fi

    echo_vvv -e "WARNING: Make the output less noisy with the \`-v\` option\n" | theme
    echo_vv -e "Watching file(s): $sql_files\n"

    ls -d $sources | SHELL="/bin/bash" entr -s "./playground.sh $rest --rebuild"
}

clean() {
    execute "Clean all generated files" "rm -rf $SCRIPT_OUT_DIR_RELATIVE/*"
    echo -e "\nPlayground: Done"
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

    # if very verbose and description is not empty print the command:
    if [[ $VERBOSITY_LEVEL -ge 3 && -n "$description" ]]; then
        echo -e "\n# $description" | theme >&2
    fi

    if [[ $VERBOSITY_LEVEL -ge 2 && -n "$description" ]]; then
        echo "COMMAND: $command" | theme >&2
    fi

    eval "$command"

    if [[ $? -ne 0 ]]; then
        echo -e "ERROR: The command failed" | theme >&2
        echo -e "NOTE: If there is \"No such file or directory\", try with --rebuild" | theme

        if [[ $VERBOSITY_LEVEL -lt 2 ]]; then
            echo "COMMAND: $command" | theme >&2
        fi

        exit 1
    fi
}

is_dependency_satisfied() {
    for dependency in "$@"; do
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
 
            *)
                echo "Unknown dependency: $1";
                exit 1
                ;;
        esac
    done
}

guard_against_unsatisfied_required_dependencies() {
    if ! is_dependency_satisfied cql_compiler; then
        hello
        exit 1
    fi
}

initialize_example() {
    local source=$1
    local example_name=$2
    local example_output_dir_relative="$SCRIPT_OUT_DIR_RELATIVE/$example_name"

    execute "Create the output directory if it doesn't exist" \
        "mkdir -p $example_output_dir_relative"
    
    execute "Clean the content of the output directory" \
        "rm -rf $example_output_dir_relative/*"
    
    execute "Copy the orginal sql file" \
        "cp $source $example_output_dir_relative/$example_name.sql.original"

    execute "The 'preprocessed' output — Preprocess the sql file (e.g.: apply macros)" \
        "cc --preprocess --language=c $example_output_dir_relative/$example_name.sql.original > $example_output_dir_relative/$example_name.sql.pre"
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

readonly all_output_list="c lua query_plan schema_upgrade json_schema schema stats ast ast_dot ast_dot_png"

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

        preprocessed|c|lua|query_plan|schema_upgrade|json_schema|schema|stats|ast|ast_dot|ast_dot_png)
            if [[ ! $targets =~ (^|[[:space:]])$1($|[[:space:]]) ]]; then
                targets="$targets $1"
            fi
            ;;

        all_outputs) targets="$all_output_list" ;;
        *.sql) sql_files="$sql_files $1" ;;

        --rebuild) force_rebuild=true ;;
        --watch) watch=true ;;
        
        --out-dir)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: You must provide a path for --out-dir" | theme
                exit 1
            else
                SCRIPT_OUT_DIR_RELATIVE="$2"
                shift
            fi
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
    echo "Unknown arguments: $rest"
    exit 1
fi

guard_against_unsatisfied_required_dependencies

case "$sub_command" in
    run)        
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
        if "$watch"; then
            echo_vv -e "CQL Playground — Build (Watching)\n" | theme
            watch "$sql_files" "$initial_parameters"
        else
            echo_vv -e "CQL Playground — Build\n" | theme
            build "$targets" "$sql_files"

            echo -e "\nPlayground: Done"
        fi
        ;;

    exit_with_help_message)
        exit_with_help_message 1
        ;;

    hello|clean|run_data_access_demo|build_cql_compiler|build_everything) $sub_command ;;
    
    *) echo "Unknown sub-command: $sub_command"; exit 1;
esac
