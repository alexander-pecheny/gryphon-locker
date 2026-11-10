# Gryphon Locker

A macOS menu-bar app that decides whether an iFi xDSD Gryphon plays from this Mac.

The Gryphon links to several sources at once but streams audio to only one, and it keeps that source until the source disconnects. When the app is locked, it connects the Gryphon whenever the Gryphon is free and holds it, so another device cannot take the audio. When the app is unlocked, it drops any connection the Mac makes to the Gryphon.

To hand the Gryphon from an iPhone to the Mac, disconnect it on the iPhone and then click Lock.

While the Gryphon is busy with another device, a locked Mac keeps retrying. After 5 minutes it retries only once every 5 minutes.

Build and install into `/Applications` with `./build.sh`. The app finds the device by its Bluetooth name, `iFi Hi-Res Audio`.

To see what the app has been doing, run `/usr/bin/log show --last 1d --predicate 'subsystem == "me.pecheny.gryphon-locker"' --style compact`.
