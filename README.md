# CounterCastProbe

Opt-in experimental nameplate interaction probe for CounterCast.

**WoW Forever · Interface 16001 · 0.1.8-experimental**

Experimental diagnostic addon; opt in deliberately and keep it separate from CounterCast.


## Installation

Copy the `CounterCastProbe` folder into your WoW Forever `Interface/AddOns` directory, then restart or reload the client. Alternatively, run `python tools/build_local.py` to create an installable ZIP under `dist/`.

Open the addon with `/ccprobe`.

## Verification

```sh
python tools/build_local.py --verify-only
```

This checks the published runtime bytes against the reviewed source manifest. For repositories with external files, add `--local-addon` to verify the complete build. It is a source-integrity check, not live-game certification.

## Related addons

- [ProfPaden](https://github.com/paden1991/ProfPaden)
- [ProfPadenRoutes](https://github.com/paden1991/ProfPadenRoutes)
- [ProfPadenClams](https://github.com/paden1991/ProfPadenClams)
- [CounterCast](https://github.com/paden1991/CounterCast)
- [RAID](https://github.com/paden1991/RAID)

## Ownership and provenance

Public visibility does not assign a new open-source license. Existing third-party notices and applicable data licenses remain in force. Do not assume that excluded dependencies may be redistributed. No account SavedVariables, personal settings, raw research archives, credentials, or prior packaged releases are included.
