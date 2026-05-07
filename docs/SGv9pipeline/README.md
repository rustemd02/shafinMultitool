# SG v9 Pipeline

Версия `v9` вынесена из `SGv7pipeline`, чтобы slot-event код, документация и run-артефакты не смешивались с `v7`.

- implementation and docs: [v9/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/v9)
- run artifacts: [runs/](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv9pipeline/runs)

`v9` сохраняет dependency на `v8` compiler path для deterministic fallback/benchmark comparison, поэтому `docs/SGv8pipeline` должен оставаться рядом в `docs`.
