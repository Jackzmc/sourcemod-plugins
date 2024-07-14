The editor lets you move, rotate, color, an existing entity or create new ones from the prop spawner.

# Modes

There are 3 modes:

- Move & Rotate

    - The main mode, the entity will move to your cursor location, and can be rotated.

    - Tools:

        - Stacker Tool - Let's you automatically snap the next prop you spawn to the specified side of the previously spawned item. This lets you build a fence, automatically setting the next prop to the right

        - Collision Rotation - Let's you have entities change their rotation to be off the normal vector of your cursor's location. This means when you looking at a wall, our a ceiling, the prop will act like that surface is the ground.

- Color

    - Lets you change the color of the entity

- Scale (Wall Editor only)

    - Let's you change the dimensions of the invisible wall

- Free Look

    - Lets you freely use your weapons and move around, to confirm the placement of your entity.

# Controls

The controls differ for each mode

### Global (all modes)

- Done / Spawn - `Use (E)`

- Cancel - `Walk (SHIFT) + Use (E)`

- Change Mode - `Zoom (MIDDLE MOUSE)`

### Move & Rotate

- Change spawn type (dynamic -> physics -> dynamic non-solid) - `Duck (CTRL) + Use (E)`

- Rotate - Hold `Reload (R)`

    - Move `mouse left/right` to change heading (or roll if axis changed)

    - Move `mouse up/down` to change pitch

    - While holding, `Left Mouse` to cycle axis from heading/pitch to roll

    - While holding, `Right Mouse` to cycle through snap angles

    - While holding, `Jump (SPACE)` to cycle the stacker tool

    - While holding, `Walk (SHIFT)`, to toggle collision

    - While holding, `Crouch (CTRL)`, to toggle collision rotate

- `Left Mouse` to move entity farther away

- `Right Mouse` to move the entity closer

### Color

Color components refer to the letter in RGBA (Red Green Blue Alpha)

- Change color component (R G B A) - `Use (E)`

- Decrease value of color component - `Left Mouse`

- Increase value of color component - `Right Mouse`

### Free Look

No specific controls

### Scale

Only active when editing / creating invisible walls

(broken)




