# Features

::::{grid} 2
:gutter: 3

|{% for feat in feats.values()|sort(attribute='id') %}|
:::{grid-item-card} |{{ feat.name }}|
:class-title: sd-text-center
:link: |{{ feat.id }}|
:link-type: doc
|{{ feat.description }}|
:::
|{% endfor %}|

::::
