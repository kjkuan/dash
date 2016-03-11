#!/usr/bin/env bash
#

_dash_init() {
    # global data stack for passing results between functions
    declare -g _DASH_DS=()

    # A dash node is either an indexed array or an associative array.
    # It is dynamically created by dash, and has a randomly generated, hopefululy
    # unique, name.
    #
    # This is where we map a path that uniquely identifies a node to the array
    # that represents that node.
    #
    declare -Ag _DASH_NODES=()

    # NOTE: a node-path is always aboslute. There's no path that represents
    # the current node nor path that represents the parent node.
    #
    # i.e., There's no . or .. equivalent found in file systems.
    # However, there is the concept of the current node, and its path is
    # always ${_DASH_STACK[-1]}.
    #
    # Moreover, there's a -cd function that allows one to go up(..) one level
    # from the current node. Also, there's a --- function to go to the node.

    # For creating unique array names for nodes.
    declare -gi _DASH_NEXT_NODE_NUM=0

    # For checking if a dash node is an indexed array or not.
    declare -gA _DASH_INDEXED_ARRAY=()

    # dash node path separator. Think of it as / used for file pathes.
    declare -g DASH_SEP=$'\n'  # must be a single char
    # NOTE: we choose newline instead of / so we can use pathes as keys.

    # Creates the root context node, which is the parent for all top-level nodes.
    _dash_new_node "$DASH_SEP" || return $?
    local root=${_DASH_DS[-1]}; unset '_DASH_DS[-1]'
    declare -g -n DASH_ROOT=$root  # the root node


    # node-path -> a list of space separated integer indexes, sorted in
    # ascending order. 
    #
    # This is to track the indexes when treating a dash node that is an
    # associative array as an indexed array.
    #
    declare -Ag _DASH_INDEXES=()

    # A stack of dash node pathes. top item is the path to the node
    # that is the current context(parent node) for subsequent dash(-)
    # commands.
    #
    declare -g _DASH_STACK=("$DASH_SEP")
    __dash_update_top_node || return $?

    # The last error message set by dash.
    declare -g DASH_ERROR=


    # For generating space characters for indentations.
    printf -v _DASH_SPACES "%s" '                        '{,,,,,,,,,,,,,,,,,,,,,,,,,,}
}

# Create an array(default to associative array) to represent a dash node.
#
# Arguments:
#
#   $1 - the node path for the new node.
#
# On return, pushes the name of the new node to _DASH_DS.
#
_dash_new_node() {  # <node_path> [args for declare]
    local node_path=$1; shift
    local node=dnode_${RANDOM}_$(( _DASH_NEXT_NODE_NUM++ ))
    declare -g "${@:--A}" "$node=()"
    _DASH_NODES[$node_path]=$node
    _DASH_DS+=($node)
}

__dash_update_top_node() {
    # shortcut for the node path of the current node
    declare -g DASH_TOP=${_DASH_STACK[-1]}

    # array name of the current node
    declare -g DASH_NODE=${_DASH_NODES[$DASH_TOP]}
}

# Print the dash stack. Used for debugging.
-ps() {
    local i len=${#_DASH_STACK[*]} path
    echo '---------------------------------<<<---Top'
    for ((i=-1; 0-i <= len; i--)); do
        path=${_DASH_STACK[i]}
        printf "%d (%s): %s\n" $((len + i)) "${_DASH_NODES[$path]}" "${path//"$DASH_SEP"//}"
    done
    echo '---------------------------------<<<---Bottom'
}

# Set the current node to the previous current node before this one.
---() {
    if (( ${#_DASH_STACK[*]} > 1 )); then
        __dash_hash_node_to_array_node "$DASH_TOP"
        unset '_DASH_STACK[-1]'
        __dash_update_top_node || return $?
        # NOTE: we want to keep the root dash node always at the bottom of the
        #       stack as the default context.
    fi
}

__dash_hash_node_to_array_node() {
    local node_path=$1
    local node_name=${_DASH_NODES[$node_path]}
    [[ ${_DASH_INDEXED_ARRAY[$node_name]:-} ]] && return

    local -n node=$node_name
    local indexes=(${_DASH_INDEXES[$node_path]:-})

    # if the node contains only indexed items then convert it to an indexed array
    if [[ ${#node[*]} -gt 0 && ${#node[*]} == ${#indexes[*]} ]]; then
        _dash_new_node "$node_path" -a || return $?
        local name=${_DASH_DS[-1]}; unset '_DASH_DS[-1]'
        _DASH_INDEXED_ARRAY[$name]=1
        local -n new_node=$name 
        local i
        for i in ${!node[*]}; do
            new_node[$i]=${node[$i]}
        done
        unset "_DASH_INDEXES[$node_path]"
        unset node

        local parent=${node_path%"$DASH_SEP"*}
        [[ $parent ]] || parent=$DASH_SEP
        local -n parent=${_DASH_NODES[$parent]}
        parent[${node_path##*"$DASH_SEP"}]=$name
    fi
}



-() {
    local -n CUR_NODE=$DASH_NODE

    # Create node or items depending on what $1 looks like

    # handle common cases via fast path
    if [[ ${1:-} == *=* ]]; then
        if [[ ${1:-} != *\\* ]]; then
            __dash_set_named_items "${1%%=*}" "${1#*=}" "${@:2}" || return $?
            return
        fi
    elif [[ ${1:-} == *: ]]; then
        if [[ ${1:-} != *\\* ]]; then
            __dash_set_new_node "$@" || return $?
            return
        fi
    else
        __dash_set_indexed_item "$@" || return $?
        return
    fi

    # first arg has '\', handle escapes...

    local name value

    if __dash_split_set_name_value "${1:-}"; then  # found name=value in $1
        __dash_set_named_items "${name:-}" "${value:-}" "${@:2}" || return $?
        return
    fi

    # else either there's no ='s or all ='s are escaped in the first arg!
    name=$value  # this is $1 with escapes collapsed before the last '='.

    local is_indexed_item

    # See if it ends with an escaped ':'
    [[ ${name:-} =~ (\\*):$ ]] || true
    if (( ${#BASH_REMATCH[1]} % 2 != 0 )); then
        # either the regex didn't match(i.e., not ending with ':' or there's
        # an odd number of \'s, which means the ':' is escaped. In any case,
        # this means it's an indexed item.
        is_indexed_item=1

        if [[ ${BASH_REMATCH[0]:-} ]]; then
            name=${name%\\:}:  # remove the escaping '\'.
        fi
    fi

    # any \'s before the last '=' should have been collapsed by
    # __dash_split_set_name_value(), so here we only deal with the rest.
    local s1=${name##*=}; s1=${s1//\\\\/\\}
    local s2=${name%=*}
    if [[ $s2 != "$name" ]]; then
        name=$s2=$s1
    else
        name=$s1
    fi

    if [[ ${is_indexed_item:-} ]]; then
        __dash_set_indexed_item "$name" "${@:2}" || return $?
    else
        __dash_set_new_node "$name" "${@:2}" || return $?
    fi
}

__dash_set_named_items() {
    local name=$1 value=$2; shift 2
    __dash_set_named_item "$name" "$value" || return $?

    local item
    for item in "$@"; do
        # if no escapes, do the fast path
        if [[ ${item:-} != *\\* ]]; then
            __dash_set_named_item "${item%%=*}" "${item#*=}" || return $?
            continue
        fi
        __dash_split_set_name_value "$item" || return $?
        __dash_set_named_item "$name" "$value" || return $?
    done
}
__dash_set_named_item() {
    local name=$1 value=$2
    __dash_check_name || return $?

    # if empty name or no '=' then use value as name.
    if [[ ! ${name:-} ]]; then
        name=$value
    fi
    CUR_NODE[$name]=$value

    # if name is an integer index, we need to track it
    if [[ $name =~ ^(0|[1-9][0-9]*)$ ]]; then
        _dash_update_indexes "$DASH_TOP" $name || return $?
    fi
}
__dash_check_name() {
    if [[ $name == *"$DASH_SEP"* ]]; then
        DS_ERROR="Invalid name for a dash node or item: $name"
        return 1
    fi
}
_dash_update_indexes() {
    local indexes=(${_DASH_INDEXES[$1]:-} $2)
    indexes=$(IFS=$'\n'; LC_ALL=C sort -nu <<<"${indexes[*]}") || return $?
    _DASH_INDEXES[$1]=${indexes//$'\n'/ }
}


__dash_set_new_node() {
    local name=${1%%:*}; __dash_check_name || return $?
    if [[ ! ${name:-} ]]; then  # - : 
        # empty name, use max index + 1 as name
        __dash_set_name_to_index || return $?
    fi
    if [[ $name =~ ^(0|[1-9][0-9]*)$ ]]; then  # track the index
        _dash_update_indexes "$DASH_TOP" $name || return $?
    fi

    local node_path=${DASH_TOP%"$DASH_SEP"}${DASH_SEP}${name}
    local is_indexed_array; if (( $# > 1 )); then is_indexed_array=-a; fi

    if [[ ${_DASH_NODES[$node_path]:-} ]]; then
        DASH_ERROR="Node(${node_path//"$DASH_SEP"//}) already exists!"
        return 1
    fi
    # create a new node, which will be indexed by its path and
    # also available under $name in the current node.
    _dash_new_node "$node_path" ${is_indexed_array:-} || return $?
    local node=${_DASH_DS[-1]}; unset '_DASH_DS[-1]'
    CUR_NODE[$name]=$node

    if [[ ${is_indexed_array:-} ]]; then
        # just create an indexed array for the items without
        # entering a new node.
        _DASH_INDEXED_ARRAY[$node]=1
        local -n node=$node
        node=("${@:2}")
    else
        # enter the new node/context.
        _DASH_STACK+=("$node_path")
        __dash_update_top_node || return $?
    fi
}
__dash_set_name_to_index() {
    # use the last integer index + 1 as the node name
    name=${_DASH_INDEXES[$DASH_TOP]:--1}
    name=$(( ${name##* } + 1 ))
}


__dash_set_indexed_item() {
    if [[ ${_DASH_INDEXED_ARRAY[$DASH_NODE]:-} ]]; then
        CUR_NODE+=("$*")
    else
        local name
        __dash_set_name_to_index || return $?
        CUR_NODE[$name]="$*"
        _dash_update_indexes "$DASH_TOP" $name || return $?
    fi
}



# Find the left-most, unescaped, '=', and deal with any
# escaping \'s beofre it (note: anything after it is treated as
# unescaped).
#
# Arguments:
#
#   $1 - an item argument passed to the dash(-) function.
#
# If an unescaped '=' is found, sets parent 'name' and 'value' variables
# such that 'name' gets whatever(with double \'s collapsed into single \'s)'s
# to the left of the '=', and 'value' gets whatever's to the right.
#
# If no unescaped '=' is found then sets parent variables, 'name' to '', and
# 'value' to the passed in $1, but with all double \'s to the left of the
# last '=' collapsed into single \'s. Also, return 1 in this case.
#
# Example: a\=b\\\=c\\\\=d\\\\\=e=
#
# In the above example, 'name' should be 'a=b\=c\\' and 'value' should
# be 'd\\\\\=e='.
#
__dash_split_set_name_value() {
    # First we split on ='s into an array.
    # The appended '=x', and later removed with unset, is to ensure
    # that the split doesn't miss any trailing ='s.
    #
    local oIFS=$IFS; IFS==
    local part=${1}=x
    local parts=($part); unset 'parts[-1]'
    IFS=$oIFS

    # we don't need to deal with escapes in the last part since there's no '='
    # after it, thus, it will always be a value, which we always treated as
    # unescaped.
    local last=${parts[-1]}; unset 'parts[-1]'

    local i=0 len=0 found
    if (( ${#parts[*]} )); then 
        for part in "${parts[@]}"; do

            if [[ $part =~ (\\*)$ ]]; then
                # if this part has an odd number of \'s just before the
                # '=' we splited on, then the '=' sign following it is
                # escaped, and it is part of whatever that's on the left
                # of the unescaped '='.
                if (( ${#BASH_REMATCH[1]} % 2 != 0 )); then
                    part=${part%\\}  # remove the escaping \

                else # all \'s just before the '=' in this part are escaped.
                     # so, the '=' is not escaped, and we've found the
                     # left most unescaped '='.
                    found=1
                fi
            fi
            # collapse any double \'s to single \'s.
            part=${part//\\\\/\\}
            parts[$((i++))]=$part
            len=$(( len + ${#part} + 1))

            if [[ ${found:-} ]]; then break; fi
        done
    fi

    # done dealing with escapes, now put the parts back together
    parts+=("$last")
    IFS==; parts="${parts[*]}"; IFS=$oIFS

    if [[ ${found:-} ]]; then
        name=${parts:0:len-1}; value=${parts:len}
    else
        name=; value=$parts
        return 1
    fi
}

# Assign a previously allocated dash node under the current node,
# either under a new name or as an indexed node.
#
# Case 1: = <name> <saved_node_path>
#
# Case 2: = <saved_node_path>
#
=() {
    local name ref_node

    if (( $# > 1 )); then
        name=$1; __dash_check_name || return $?
        ref_node=${_DASH_NODES[$2]:-}; shift
        if [[ $name =~ ^(0|[1-9][0-9]*)$ ]]; then
            _dash_update_indexes "$DASH_TOP" $name || return $?
        fi
    else
        ref_node=${_DASH_NODES[$1]:-}
        __dash_set_name_to_index || return $?
        _dash_update_indexes "$DASH_TOP" $name || return $?
    fi

    if [[ ! ${ref_node:-} ]]; then
        DASH_ERROR="Referenced dash node doesn't exist: $1"
        return 1
    fi
    local -n cur_node=$DASH_NODE
    cur_node[$name]=$ref_node
    local new_path=${DASH_TOP%"$DASH_SEP"}${DASH_SEP}$name

    local node_crumbs=()
    __dash_add_new_referenced_pathes "$1" "$new_path" || return $?
}

# recursively add all descendant nodes of a given path to _DASH_NODES
# under a new path.
#
__dash_add_new_referenced_pathes() {
    local old_root=$1 new_root=$2
    local node_name=${_DASH_NODES[$old_root]}
    if [[ " ${node_crumbs[*]:-} " == *" $node_name "* ]]; then
        DASH_ERROR="Cycle detected for path ${old_root//"$DASH_SEP"/\/}"
        return 1
    else
        node_crumbs+=($node_name)
    fi
    local -n old_node=$node_name
    local name old_path new_path

    _DASH_NODES[$new_root]=${_DASH_NODES[$old_root]}
    if [[ ${_DASH_INDEXES[$old_root]:-} ]]; then
        _DASH_INDEXES[$new_root]=${_DASH_INDEXES[$old_root]}
    fi

    for name in "${!old_node[@]}"; do
        old_path=${old_root%"$DASH_SEP"}$DASH_SEP$name
        if [[ ${_DASH_NODES[$old_path]:-} ]]; then
            new_path=${new_root%"$DASH_SEP"}$DASH_SEP$name
            __dash_add_new_referenced_pathes "$old_path" "$new_path" || return $?
        fi
    done
}

# Like '=' but instead of creating an alias, it copies everything under the specified path($1)
# over.
+ () {
    #FIXME? I'm lazy..., this is slow but works for now.
    source <(__dash_dump_from_node_path 0 "$1") || return $?
}


-cd() {  # <node-path>
    local sep=/ option
    OPTIND=1
    while getopts ':s:' option "$@"; do
        case $option in
            s) sep=${OPTARG:0:1} ;;
            :) DASH_ERROR="Missing option argument for -$OPTARG"; return 1 ;;
           \?) DASH_ERROR="Unknown option: -$OPTARG"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    local path=$1

    if [[ $path = .. ]]; then
        local cur_path=${_DASH_STACK[-1]}
        ---
        cur_path=${cur_path%"$DASH_SEP"*}
        _DASH_STACK+=("${cur_path:-$DASH_SEP}")
        __dash_update_top_node || return $?
        return
    fi
    __dash_set_path_to_absolute || return $?

    local node_path=${path//"$sep"/$DASH_SEP}

    if [[ ${_DASH_NODES[$node_path]:-} ]]; then
        if [[ ${_DASH_STACK[-1]} != "$node_path" ]]; then
            local i len=${#_DASH_STACK[*]} path
            for ((i=-1; 0-i < len; i--)); do
                __dash_hash_node_to_array_node "${_DASH_STACK[i]}" || return $?
            done
            _DASH_STACK=("$DASH_SEP" "$node_path")
            __dash_update_top_node || return $?
        fi
    else
        DASH_ERROR="Path not found: $path"
        return 1
    fi
}
__dash_set_path_to_absolute() {
    # remove extra path separators
    local oIFS=$IFS oSet=$-; set -f; IFS=$sep;
    local parts=($path) i=0 part
    path=; [[ ${parts[0]} ]] || path=$sep
    for part in "${parts[@]}"; do
        [[ $part ]] || unset "parts[$i]"; ((++i))
    done
    path="$path${parts[*]:-}"
    IFS=$oIFS; set -$oSet

    # if path is relative, make it absolute
    if [[ $path != "$sep"* ]]; then
        local dir=${_DASH_STACK[-1]//"$DASH_SEP"/$sep}
        path=${dir%"$sep"}$sep${path}
    fi
}
-up() { -cd .. || return $?; }  #FIXME: allow '-up N' to go up N levels ?


-dump() {  # <node_path>
    local sep=/ option
    OPTIND=1
    while getopts ':s:' option "$@"; do
        case $option in
            s) sep=${OPTARG:0:1} ;;
            :) DASH_ERROR="Missing option argument for -$OPTARG"; return 1 ;;
           \?) DASH_ERROR="Unknown option: -$OPTARG"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    local path=$1; __dash_set_path_to_absolute || return $?
    path=${path//"$sep"/$DASH_SEP}

    if [[ ! ${_DASH_NODES[$path]:-} ]]; then
        DASH_ERROR="Path not found: $1"
        return 1
    fi
    local node_crumbs=()
    __dash_dump_from_node_path 0 "$path" || return $?
}

__dash_dump_from_node_path() { # <level> <node_path>
    local level=$1
    local cur_path=${2:-"$DASH_SEP"}
    local node_name=${_DASH_NODES[$cur_path]:-}

    if [[ " ${node_crumbs[*]:-} " == *" $node_name "* ]]; then
        DASH_ERROR="Cycle detected for path ${cur_path//"$DASH_SEP"/\/}"
        return 1
    else
        node_crumbs+=($node_name)
    fi

    local -n cur_node=$node_name

    local indent=$(( level * 2 ))
    indent="${_DASH_SPACES:0:indent}"

    local path value

    # If the node has integer indexed entries, then print them in
    # ascending order first. Moreover, entries with consecutive indexes
    # are printed without explicit indexes.
    #
    local idx prev_idx=-1

    if [[ ${_DASH_INDEXED_ARRAY[${node_name:-}]:-} ]]; then
        local indexes=${!cur_node[*]}
    else
        local indexes=${_DASH_INDEXES[$cur_path]:-};
    fi

    for idx in $indexes; do
        path=${cur_path%$DASH_SEP}${DASH_SEP}${idx}
        value=${cur_node[$idx]}

        if (( idx - prev_idx == 1 )); then
            if [[ ${_DASH_NODES[$path]:-} ]]; then
                __dash_print_node_or_item : || return $?
            else
                if [[ $value == *:* || $value == *=* ]]; then
                    __dash_print_node_or_item || return $?
                else
                    printf "%s- %q\n" "$indent" "$value"
                fi
            fi
        else
            __dash_print_node_or_item || return $?
        fi
        prev_idx=$idx
    done

    for idx in "${!cur_node[@]}"; do
        [[ $idx =~ ^(0|[1-9][0-9]*)$ ]] && continue
        path=${cur_path%$DASH_SEP}${DASH_SEP}${idx}
        value=${cur_node[$idx]}
        idx=${idx//\\/\\\\}; idx=${idx//=/\\=}
        __dash_print_node_or_item || return $?
    done
}

__dash_print_node_or_item() {
    printf "%s- " "$indent"

    if [[ ${_DASH_NODES[$path]:-} ]]; then

# FIXME: commented out because this tries to print an indexed array
#        as one line, but failed to consider the case that we can also
#        have a node in the array.
#
#        if [[ ${_DASH_INDEXED_ARRAY[$value]:-} ]]; then
#            printf "%q " "${1:-$idx:}"
#
#            local -n node=${_DASH_NODES[$path]}
#            printf "%q " "${node[@]:-}"
#            echo
#        else
            printf "%q\n" "${1:-$idx:}"

            __dash_dump_from_node_path $((level+1)) "$path" || return $?
            unset 'node_crumbs[-1]'
            printf "%s  ---\n" "$indent"
#        fi
    else
        printf "%q=%q\n" "$idx" "$value"
    fi
}



-reset() {
    local name
    for name in "${_DASH_NODES[@]}"; do
        unset -v "$name"
    done
    _dash_init
}
    

-do() { :; }
-with() {
    __dash_push_var_cmds "$@" || return $?
    shift $((OPTIND - 1))

    while (( $# )); do
        eval "${_DASH_DS[-1]}" || return $?
        unset '_DASH_DS[-1]'
        shift
    done
    -do
    unset -f -- -do
}

-set() {
    set -- -g "$@"
    __dash_push_var_cmds "$@" || return $?
    shift $((OPTIND - 1))

    while (( $# )); do
        eval "${_DASH_DS[-1]}" || return $?
        unset '_DASH_DS[-1]'
        shift
    done
}

__dash_push_var_cmds() {
    local sep=/ use_local=1
    local opiton
    OPTIND=1
    while getopts ':s:g' option "$@"; do
        case $option in
            s) sep=${OPTARG:0:1} ;;
            g) use_local= ;;
            :) DASH_ERROR="Missing option argument for -$OPTARG"; return 1 ;;
           \?) DASH_ERROR="Unknown option: -$OPTARG"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))

    local i name path node parent varcmd basename

    for (( i=$#; i > 0; i-- )); do
        name=${1%%=*}; path=${1#*=}; shift
        __dash_set_path_to_absolute || return $?

        node=${_DASH_NODES[${path//"$sep"/$DASH_SEP}]:-}

        if [[ ${node:-} ]]; then
            printf -v varcmd "${use_local:+"local -n -- "}%s=%q" "$name" "$node"
        else
            node=${path%"$sep"*}; [[ ${node:-} ]] || node=$sep
            node=${_DASH_NODES[${node//"$sep"/$DASH_SEP}]:-}
            if [[ ! ${node:-} ]]; then
                DASH_ERROR="Path not found: $path"
                return 1
            fi
            basename=${path##*"$sep"}
            local -n parent=$node
            if [[ ! ${parent[$basename]:-} ]]; then
                DASH_ERROR="Path not found: $path"
                return 1
            fi
            printf -v varcmd "${use_local:+"local -- "}%s=%q" "$name" "${parent[$basename]:-}"
        fi
        _DASH_DS+=("$varcmd")
    done
}

-cat() {
    local sep=/ option
    OPTIND=1
    while getopts ':s:' option "$@"; do
        case $option in
            s) sep=${OPTARG:0:1} ;;
            :) DASH_ERROR="Missing option argument for -$OPTARG"; return 1 ;;
           \?) DASH_ERROR="Unknown option: -$OPTARG"; return 1 ;;
        esac
    done
    shift $((OPTIND - 1))
      
    local path parent
    for path in "$@"; do
        __dash_set_path_to_absolute || return $?

        parent=${path%"$sep"*}; parent=${parent:-"$sep"}
        parent=${parent//"$sep"/$DASH_SEP}
        if [[ ! ${_DASH_NODES[$parent]:-} ]]; then
            DASH_ERROR="Path not found: $path"
            return 1
        fi
        if [[ $path == "$sep" ]]; then
            printf "%s\n" "${_DASH_NODES[$DASH_SEP]}"
        else
            local -n node=${_DASH_NODES[$parent]}
            printf "%s\n" "${node[${path##*"$sep"}]:-}"
        fi
    done

}


_dash_init
