# ManualAttach for Farming Simulator 25

![For Farming Simulator 25](https://img.shields.io/badge/Farming%20Simulator-25-F.svg) [![Releases](https://img.shields.io/github/release/stijnwop/manualAttach.svg)](https://github.com/stijnwop/manualAttach/releases) [![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)


## Warning!
Please be aware that this is a ***DEVELOPMENT VERSION***!
* The development version can break the game or your savegame!
* The development version doesn´t support the full feature package yet!

## Documentation

### Attach/Detach implements
When attaching an implement the script forces the implement to stay at it's lowered state. There are some exceptions made for frontloaders, skidsteers, shovels, telehandlers, combines and hooklift implements. You're still able to attach and detach those implements without having to leave your vehicle.
*Note: The connection hoses and power take off still require to be attached manually for those implements.*
In order to detach, the implement needs to be lowered first! Also make sure that the power take off and connection hoses are detached before detaching the implement.

The mod disables attaching and detaching from inside the vehicle (exceptions are mentioned above). Like the mod title already suggests it’s not possible anymore to do the quick switches between implements.. get out that vehicle for real this time!

### Attach/Detach power take off
Hit `Z` in order to attach/detach the power take off.

Keep in mind that a tool needs a power take off, otherwise it can't be turned on!

### Attach/Detach connection hoses
Hold `Z` (for a short amount of time) in order to attach/detach the connection hoses.

Without attached connection hoses the following can occur:
- You won't be able to control hydraulics (e.g. moving parts, folding, use ridge markers etc)
- You won't be able to use the lights.
- Brakes will be blocked.

## Mod support
When creating or modding vehicles and implements, the connection behavior can be controlled using the `attacherJoint` and `inputAttacherJoint` XML entries. You can use the attributes `isManual` and `isAuto` to define how attachments behave in-game.

### Attribute Overview

- `isManual="true/false"` — Forces a **manual attachment**. The player must connect the implement manually; the game will not attach it automatically.
- `isManual="true/false"` — Standard attachment. The implement can be attached directly from the controlled vehicle without additional interaction (does not count for connection hoses and PTO).
- `isAuto="true/false"` — Forces an **automatic attachment**. The implement will attach as soon as it comes within range, regardless of manual settings.

```xml
<!-- Implement side 'manual attachment' -->
<inputAttacherJoint isManual="true" jointType="X" .... />

<!-- Vehicle side  'manual attachment' -->
<attacherJoint isManual="true" jointType="X"  ..... />

<!-- Implement side 'standard attachment' -->
<inputAttacherJoint isManual="false" jointType="X" .... />

<!-- Vehicle side 'standard attachment' -->
<attacherJoint isManual="false" jointType="X"  ..... />

<!-- Implement side 'enable automatic attachment' -->
<inputAttacherJoint isAuto="true" jointType="X" .... />

<!-- Vehicle side 'enable automatic attachment' -->
<attacherJoint isAuto="true" jointType="X"  ..... />

<!-- Implement side 'disable automatic attachment' -->
<inputAttacherJoint isAuto="false" jointType="X" .... />

<!-- Vehicle side 'disable automatic attachment' -->
<attacherJoint isAuto="false" jointType="X"  ..... />
```

## Copyright
Copyright (c) 2019-2025 [Wopster](https://github.com/stijnwop).
All rights reserved.

Special thanks to workflowsen for creating the icon!
