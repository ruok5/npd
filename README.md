# npd

A small now-playing daemon for macOS Music.app. Subscribes to the
`com.apple.Music.playerInfo` distributed notification, writes the current
track to `~/.nowplaying.json` on every play / pause / track change, and gets
out of your way.

Bring-your-own consumer. The included [`np.pl`](np.pl) is an irssi `/np`
script — point any other tool you want at the JSON.

```json
{
  "state": "playing",
  "title": "Dog's Life",
  "artist": "Pulley",
  "album": "@#!*",
  "albumArtist": "Pulley",
  "genre": "Alternative",
  "duration": 142.467,
  "persistentId": "03617BC374EEE933",
  "source": "Music",
  "updatedAt": "2026-05-02T16:42:10Z"
}
```

## Install

Requires macOS, Swift, and Music.app.

```sh
make install
```

That builds `npd`, drops the binary at `~/bin/npd`, materializes the
LaunchAgent plist into `~/Library/LaunchAgents/org.fyvm.npd.plist`, and
bootstraps it. `make uninstall` reverses everything.

**First run** triggers an Automation TCC prompt — macOS will ask whether
`npd` may control Music.app. Allow it once; the seed-on-startup query
needs it. Notifications themselves don't require any permission.

Logs: `make tail` (or `~/Library/Logs/npd.log`).

## irssi `/np`

```sh
ln -s ~/development/npd/np.pl ~/.irssi/scripts/np.pl
ln -s ../np.pl ~/.irssi/scripts/autorun/np.pl
```

Then in a running irssi: `/script load np`. `/np` in any window emits:

```
* you is listening to "Dog's Life" by Pulley from @#!*
```

Edit the format string in `np.pl` to taste.

## How it works

`com.apple.Music.playerInfo` is a `DistributedNotificationCenter` event
that Music.app posts on every state transition. The `userInfo` dict
already contains all the track metadata, so the daemon does no polling
and barely registers in `top` when idle. AppleScript is used exactly
once at startup to seed initial state, since notifications are events,
not state.

## License

[WTFPL](LICENSE).
