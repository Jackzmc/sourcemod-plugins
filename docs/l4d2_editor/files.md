These are information about the files in `&lt;sourcemod&gt;/data/prop_spawner`:

## models

This contains the data for every prop spawning category. All \*.txt files will be read as categories, where the first line will be the name of the category.

The prop spawner also folders, including nested folders. The name of the folder will be displayed as `[Folder Name]`.

Categories can also contain some extras, such as `Type:` to specify some custom spawning behaviors (example: items, bodies).

## saves

This contains all saved scenes (all props spawned in session) for a map. These files will be saved in a folder, with the current map's id. The file's default name is a timestamp of format `YYYY-MM-DD_HH-mm-DD.txt`. The file is a comma-separated (CSV) file. The format is, in order from left to right:

| **Field**                                                                                               | Type                                                                                                    | Description                                                                                             |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| model path                                                                                              | string                                                                                                  | The path to the entity's model, or in case of weapons, their id's                                       |
| type                                                                                                    | int                                                                                                     | The type of the prop, 0 being `prop_dynamic`, 1 being `prop_physics`, and `prop_dynamic` but non-solid. |
| origin[3]                                                                                               | float array                                                                                             | The coordinates to spawn the entity.                                                                    |
| angles[3]                                                                                               | float array                                                                                             | The angles to spawn the entity with.                                                                    |
| color[3]                                                                                                | float array                                                                                             | The color to spawn the entity with                                                                      |




