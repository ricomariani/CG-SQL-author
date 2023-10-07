#!/usr/bin/awk -f

BEGIN {
    RS = "%%";
    FS = "";

    # File format: (1) Definitions Section %% (2) Rules Section %% (3) User Subroutines Section
    RULE_SECTION = 2;

    special["{"] = special["}"] = special["["] = special["]"] = special["'"] = special["\""] = 1;
    quote["'"] = quote["\""] = 1;

    cursor = 0;
}

function take() { return $(++cursor) }
function put(char) { printf "%s", char; }
function skipQuotedString(char) { while ($(++cursor) != char) { } }
function skipLabel() { while ($(++cursor) != "]") { } }

function extract_quoted_string(start_quoting_char) {
    put(start_quoting_char);
    while (1) {
        char = take();
        if (char == "") { return; }

        if (char == start_quoting_char) {
            put(char);
            return;
        }
        put(char);
        if (char == "\\") {
            put(take());
        } 
    }
}

function skipCode() {
    code_depth = 1;
    while (code_depth) {
        char = take();

        if (!(char in special )) { continue; }

        if (char in quote) {
            skipQuotedString(char);
        } else if (char == "{") {
            code_depth++
        } else if (char == "}") {
            code_depth--
        }
    }
}

FNR != RULE_SECTION { next; }

{
    field_length = length($0);

    while (cursor < field_length) {
        char = take();

        if (!(char in special)) { put(char); continue; }

        if (char in quote) {
            extract_quoted_string(char);
        } else if (char == "{") {
            skipCode();
        } else if (char == "[") {
            skipLabel();
        } else {
            put(char);
        }
    }
}
