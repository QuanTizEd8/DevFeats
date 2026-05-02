# Bash Library

This section provides a reference for the library of bash functions used in features.


::::{grid} 1
:gutter: 3

|{% for module_name, module_summary in lib_modules.items()|sort() %}|
:::{grid-item-card} `|{{ module_name }}|`
:class-title: sd-text-center
:link: /library/|{{ module_name }}|
:link-type: doc
|{{ module_summary }}|
:::
|{% endfor %}|

::::
