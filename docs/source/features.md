# Features

This section provides a reference for all available features, with detailed documentation on their options, behavior, and installation instructions. For general guidance on installing and using features, see the [User Guide](user-guide.md).

::::{grid} 1
:gutter: 3

|{% for feat_id, feat in feats.items()|sort(attribute='1.name') %}|
:::{grid-item-card} |{{ feat.name }}|
:class-title: sd-text-center
:link: /features/|{{ feat_id }}|
:link-type: doc
|{{ feat.description }}|
:::
|{% endfor %}|

::::
