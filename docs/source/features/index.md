# Feature Reference

<br>

::::{grid} 1
:gutter: 3

|{% for feat_id, feat in feats.items()|sort(attribute='1.name') %}|
:::{grid-item-card} |{{ feat.name }}|
:class-title: sd-text-center
:link: |{{ feat_id }}|
:link-type: doc
|{{ feat.description }}|
:::
|{% endfor %}|

::::
