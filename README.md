Dash - Write configurations in Bash
-------------------------------------

```
- defaults:        ; defaults=$DASH_TOP
  - port=5432
  - username=dev
  - encoding=utf8
---

- staging:         ; staging=$DASH_TOP
  + "$defaults"
  - password=abc123
  - database=staging_db
  - host=10.1.2.10
---

- production:
  + "$defaults"
  - password=ADFASj1ADF814
  - database=production_db
  - host=production-db.example.com
---

= qa "$staging"
---

- users:
  - pparker
  - bwayne
  - tstark
---
```

Yes, I'm aware there's a POSIX shell named, dash(the Debian Almquist shell).    

Hope you find this tool useful.
Pull requests, bug reports, and suggestions, are always welcome.


Table of Contents
-------------------
  * [Introduction](#introduction)
  * [Creating Hash Nodes](#creating-hash-nodes)
  * [Adding String Items](#adding-string-items)
  * [Creating Array Nodes](#creating-array-nodes)
  * [Leaving the Current Node](#leaving-the-current-node)
  * [Copying and Aliasing Nodes](#copying-and-aliasing-node)
  * [Getting Items From Nodes](#getting-items-from-nodes)
  * [Escaping Special Characters](#escaping-special-characters)
  * [Traversing the Nodes](#traversing-the-nodes)
  * [Handling Errors](#handling-errors)
  * [Global Variables](#global-variables)


Introduction
---------------
In _Dash_ you work with nodes, adding items to them and nesting nodes within nodes.

An item is either a string(_value_), or a node that is added to a node, under a _name_,
which can be any string without the newline character.

There are two types of nodes: _hash nodes_(associative arrays) and _array nodes_(
indexed arrays). *_Dash_ decides the type of node to create, based on the first argument.*

At any moment, you are working under a _current node_, which will be the parent of the
items you specify with the `-` command.


Creating Hash Nodes
---------------------
A hash node is created like this:

        - database:

Notice that it has a single argument to `-` that ends with a colon(`:`).
A hash node like this creates an associative array and makes it the _current node_.

In this case, the name of the node is `database` under its parent(which is also a
hash node, and is actually a nameless global/root node), and the value is the name
of the Bash associative array that _Dash_ created for you.


Adding String Items
----------------------
String items can be added using the `-` command with `name`=`value`
arguments:

        - name1=value1 name2=value2 name3

Here because the first argument has an unescaped `=` in it, a `name`=`value`
argument will add the `value` under the `name` in the current hash node.
Moreover, if `name` is omitted then the `value` will be used as the `name`.
(second or later arguments can also omit the `=` when omitting `name`).

Alternatively, you can add implicitly named/indexed items:

        - this is value 1   # index 0
        - this is value 2   # index 1

In this case, because the first argument has no `=` nor `:` at the end, it's
considered an indexed item. The current *max index + 1* will be used as the name
of the item. Index in each hash node starts from `0`.

Note that you can mix indexed and named string items in a hash node. For example:

        - name1=value1
        - value2          # index 0
        - name3=value3
        - value4          # index 1


Creating Array Nodes
----------------------
There are two ways to create an indexed array under a hash node:

The first way does it in one `-` command, and doesn't start a new context(i.e.,
doesn't make it the current node):

        - fruits: apple banana coconut

This creates an indexed array with three values(`apple`, `banana` and `coconut`)
under the name, `fruits`, in the current node.

Notice that the syntax is similar to creating a hash node, except that there
are more arguments, which are taken as the members of the array, after the
first argument.

The second way is exactly the same as a hash node:

        - fruits:
          - apple     # index 0
          - banana    # index 1
          - coconut   # index 2
          - :         # index 3
            - red     # index 0 under index 3 of fruits
            - yello   # index 1 under index 3 of fruits
            - green   # index 2 under index 3 of fruits

As long as you don't add any named items (`name`=`value` items or named nodes)
under a hash node, _Dash_ will automatically convert it to an array node upon
leaving the hash node context.

NOTE:
> Incidentally, `- name: value` is similar to `- name=value` but different in that
the former creates an one element indexed array, holding `value`, under `name` in
the current node; while the later directly puts `value` under `name` in the current
node. Although, as we'll see later, it might not matter, depends on how you get the
value, because referencing an indexed array element without an explicit index is
equivalent to referencing its first element.


Leaving the Current Node
-------------------------
Whenever you create a node with the `-` command, _Dash_ automatically makes it the
_current node_. The `---` command leaves the current node and makes the previous
_current node_ the current _current node_.

There is also a `-cd` _item-path_ command that allows you to make any node the _current node_:

        - node1:              # enters node1
          - node2:            # in node2
		    - name1=value1
          ---                 # back to node1
          - node3:            # enters node3
            - item1
            - item2

        -cd /node2; - name2=value2    # go directly to node2 and add one more item
        -cd /node3; - item3           # go directly to node3 and add another item
        -cd /



Getting Items From Nodes
--------------------------
There are three ways to get to the items you've created with _Dash_.

* `-cat` _item-path_ ...

    Prints the value of an item to stdout. If _item-path_ refers to a node, then
the name of the idexed/associative array representing that node is printed.


* `-set` _var-name=item-path_ ...

    Similar to `-cat`, but instead of printing to stdout, the value of the node or
item referred to by _item_path_ is assigned to the _var-name_ variable. Note that,
to bind a variable to a node, you can declare it with `declare -n` first. For example:

    ```
        - path:
          - to:
            - something=somevalue
            - the:
              - node:
                - name1=value1
        -cd /

        declare -n mynode
        -set something=/path/to/something mynode=/path/to/the/node
        mynode[name2]=123

        echo "$something"             # prints 'somevalue'
        -cat /path/to/the/node/name2  # prints '123'
    ```

    Notice that we use `/` to separate items in a path. It's also possible to use
another character as the separator with the `-s` option, which should be available
to all dash commands taking an _item path_. For example:

        -cat -s . .path.to.the.node.name1

    Moreover, you can use relative path by omitting the leading path separator, and
in which case, the path will be relative to the _current node_.


* `-do() { ... }; -with` _var-name=item-path_ ...

    You can declare a function named, `-do`, to work with the items and nodes you want,
and then immediately calls it via `-with`. When calling, `-with`, specify
`var1=path1 var2=path2 ...`, and _Dash_ will make the item at `path1` available as
`$var1`, and so on. If the item referred to by a path is actually a node, then the
array representing that node will be bound to the var. Example:

    ```
        - node1:
          - item 1
          - item 2
        ---
        - node2:
          - item 2-1
          - node3:
            - name1: value1
            - name2=value2
          ---
        ---

        -do() {
            node1[0]=111             
            echo "$item"       # prints 'item 2-1'
            echo "$name1"      # same as ${name1[0]}, prints 'value1'
            node3[name2]=222

        }; -with item=/node2/0            \
                 node3=/node2/node3       \
                 name1=/node2/node3/name1 \
                 node1                        # same as 'node1=node1'

        -cat /node1/0         # prints '111'
        -cat /node3/name2     # prints '222'
   
    ```

Escaping Special Characters
----------------------------
There are two characters that are considered special in the *first argument*
to the `-` command. In precedence, they are:

1. The first unescaped `=` character.
2. The last character that is an unescaped `:`.

The two special characters can be escaped with `\`(which needs to be esacped
or quoted in bash first), and `\` can be escaped with itself(i.e., `\\` becomes
`\`, but only before a special character).

Let's see some examples:

        - name1=value1     # '=' unescaped, so this is a named string item
        - name1\\=value1   # '=' escaped with '\', so this becomes an indexed string item
        - name1: value1    # ':' unescaped, this is an array with an element, 'value1'
        - "name1: value1"  # an indexed string item, 'name1: value1'
        - name1\\:         # ':' escaped with '\', so this is an indexed string item, 'name1:'
        - name1=value1:    # a named string item, name is 'name1' and value is 'value1:'
        - 'name1\=value1:' # '=' is escaped, so this becomes a node due to the ':' at the end.
        - 'name1=value1\:' # a named string item, value is 'value1\:'

        # a named string item. name is '\name1=\' and value is 'value\\'
        - '\\name1\=\\=value\\'

Here's how it works.
The `-` command scan its first argument for the special characters from left to right,
collapsing double `\`'s into single `\`'s until an unescaped special character is
determined. Then, the rest of the argument is then taken literally as is, without
any further processing. If, from the first argument, it's determined that we are
creating a node or an indexed item, then we're done. Otherwise, it's dealing with
a named string item. Then, the same escape processing logic is applied to the rest
of `name=value` arguments.


Copying and Aliasing Nodes
-----------------------------
When creating a node, it's possible to, instead, reference an already created node
under the new name, or copy the contents and children an existing node to the new node.
For example:

```
        - a node: ; HERE=$DASH_TOP   # save the path of the current node
          - name1=value1
          - name2=value2
        ---
        - another node:
          = a-node "$HERE"           # and reference it here under a new name "a-node"
                                     # as a child of "another node".
        ---
        - third:
          + "$HERE"                  # copy its children here
          - name1=111
        ---

        -cd "/another node/a-node"
        - name2=222
        -cd /

        -cat "/a node/name1"     # prints value1
        -cat "/a node/name2"     # prints 222
        -cat "/third/name1"      # prints 111
        
```        
        


Traversing the Nodes
-----------------------
FIXME

Handling Errors
------------------
Each dash command returns a non-zero status if there's an error.
The last error message is stored in the `DASH_ERROR` global variable.
_Dash_ should work with or without `set -eu`


Global Variables
------------------

Variable  | Description
----------|--------------------------------------------------------------------------------|
DASH_TOP  | Path to the _current node_. Expansion of this variable should always be quoted.|
DASH_NODE | Name of the Bash array representing the _current node_.                        |
DASH_ROOT | The array representing the global/nameless root node in _Dash_.                |
DASH_ERROR| The last _Dash_ error message.                                                 |

