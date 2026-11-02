# Copyright (c) Rico Mariani
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


def cql_identifier(name, reserved_words=()):
    # Decide whether encoding is needed before escaping X; an ordinary XName
    # stays unchanged, but X_ is reserved for encoded identifiers.
    if (name and not name.startswith("X_") and not name[0].isdigit()
            and name not in reserved_words
            and all(ch.isascii() and (ch.isalnum() or ch == "_")
                    for ch in name)):
        return name
    result = []
    for ch in name.encode("utf-8"):
        if (ord("a") <= ch <= ord("z")
                or ord("A") <= ch <= ord("Z") and ch != ord("X")
                or ord("0") <= ch <= ord("9") or ch == ord("_")):
            result.append(chr(ch))
        else:
            result.append(f"X{ch:02x}")
    return "X_" + "".join(result)


def projection_member_names(projection, reserved=(), reserved_words=()):
    # Choose names together: encoding and reserved wrapper members can collide
    # with other columns. Keep each chosen name paired with its original ordinal.
    used = set(reserved)
    result = []
    for col, projected_column in enumerate(projection):
        base = cql_identifier(projected_column["name"], reserved_words)
        candidate = base
        if candidate in used:
            candidate = f"{base}_{col}"
            while candidate in used:
                candidate += "_"
        used.add(candidate)
        result.append(candidate)
    return result


def objc_projection_names(proc):
    # Selector arity matters: the handle setter collides with a row getter,
    # whereas count and the other zero-argument helpers collide with OUT getters.
    reserved = ("count", "hasIdentityColumns", "result_set_ref",
                "dealloc") if proc.get("hasOutResult") else (
                    "setResult_set_ref", )
    # Unlike get_<name> methods, single-row properties are bare C identifiers.
    keywords = (
        "_Alignas _Alignof _Atomic _Bool _Complex _Generic _Imaginary "
        "_Noreturn _Static_assert _Thread_local auto break case char const "
        "continue default do double else enum extern float for goto if inline "
        "int long register restrict return short signed sizeof static struct "
        "switch typedef union unsigned void volatile while"
    ).split() if proc.get("hasOutResult") else ()
    return projection_member_names(proc["projection"], reserved, keywords)
