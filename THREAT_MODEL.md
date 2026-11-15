# Threat model

AInnotator freezes your screen, lets you mark it, and puts one image on the clipboard. This page says what it guards, where hostile input can come in, how each way in is closed, and what is out of reach. To report a problem, see [SECURITY.md](SECURITY.md).

## What is worth protecting

- **Your screen.** A capture can show customer data, tokens or someone else's mail. It should go where you paste it and nowhere else.
- **What you redacted.** Once an area is blacked out, its pixels must be gone from everything the app writes.
- **The release signature.** Official builds are signed with the maker's Developer ID. A copy signed by anyone else is not an official build.

## Where hostile input can come in, and how it is closed

| Way in | What could go wrong | What stops it |
|---|---|---|
| What is on the screen | A page or document shows content built to make the app do something | The app treats the screen as pixels. It reads no text from them and decides nothing by them |
| Window titles, page addresses, repository and branch names | A crafted name turns into a command or breaks the output | They are only ever drawn as text into the footer and written as JSON strings. No shell is involved; the only helpers the app starts are `/usr/bin/osascript`, with fixed arguments, and, for a confirmed machine, `/usr/bin/ssh`, covered below. A page address loses its query and fragment first, so tokens in a link don't travel |
| Other apps, through Automation | The app drives a browser or terminal it should not | Six fixed requests and nothing else: the address of the front tab from Safari, Chrome or Arc, and the terminal device of the front window from Ghostty, Terminal or iTerm. The request texts are constants in the code. The app types nothing and clicks nothing. Decline the permission and the footer simply leaves these out |
| The project lookup | Reading the wrong files, or running git on a hostile folder | The app runs no git. It looks up the working folder of the terminal's foreground process and reads the `.git` files there for the repository name and branch |
| The capture folder | Another user reads your captures | `~/.ainnotator` is created for you alone, each file too. Names are reserved without overwriting, files appear only when complete, and captures are deleted after 1, 7 or 30 days |
| Redaction | A blacked-out area survives in a file | Redacted pixels are overwritten in the app's own copy before anything is written, edges are widened to whole pixels, and the unredacted capture is never saved. The capture the app takes at start, after wake and after unlock, to be fast later, is thrown away |
| The network | A capture leaves your Mac | The app makes no network calls of its own: it loads no web content and has no updater. The one way out is the copy below, made by `/usr/bin/ssh` and only for a machine you confirmed. A runtime check of the app itself saw no internet socket |
| The copy to another machine | A capture goes to a machine you didn't mean, or the `ssh` call that carries it runs a command | It starts only for a machine you confirmed in the receipt, one machine at a time; without that yes no connection is made. The app reuses only a fixed list of options of the running `ssh` call (host, user, port, config file, jump host, key file, shared connection) and drops everything else, above all options that can run a command, such as `ProxyCommand` or `LocalCommand`. The only command it runs on the other machine is a fixed one that writes the file and removes this app's own older cards; the file name is the one part that varies, and it holds nothing but letters, digits, dots, dashes and underscores. It asks nothing: a password, a passphrase or a confirmation makes the copy fail at once, and the capture stays local. The card is written into `~/.ainnotator` on the other machine, created for you alone, never over a file that is already there, and only the finished, redacted card goes. Your SSH configuration counts as if you had typed the call yourself: host keys, jump hosts and shared connections are yours. Settings turn it off and forget the confirmed machines |
| Downloads | A modified copy poses as AInnotator | Developer ID signature, hardened runtime whose only entitlement is Apple Events for the requests above, notarization. Official copies come only from the releases of this repository; `codesign -dv` shows the team |
| The repository | A contribution or workflow reaches the maker's keys | CI runs with a read-only token and no secrets. Signing and notarization happen only on the maker's Mac, never in CI, and pull requests are not accepted for now |

## Out of reach

- **Programs already running as you.** They can read the capture folder and the clipboard like you do.
- **Administrators, root and physical access** to your Mac.
- **Wherever you paste.** The card goes to the app or service you paste it into, with everything visible on it. Redact first.
- **What a model makes of the picture.** A screen can show text written to steer a model. The card's legend says which marks are yours and that everything else belongs to the screen, and in a small blind test that was enough. It is a guide, not a wall.
- **Clipboard managers.** They may keep a copy of anything you copy, this included.
- **The machine you copy to.** Once the card is there it is under that machine's rules: its administrators and anyone with access to your account on it can read it. Older cards are removed when the next one is copied, but a backup over there is out of the app's hands. Redact first.

## What stays visible

Captures stay in `~/.ainnotator` until their time is up. The JSON file next to each one holds the name of the app in front, its window title if you have granted Accessibility access (the app never asks for it), the page address without query and fragment, and the repository and branch. The system log gets timings and error codes, never screen content. If you copy to another machine, the finished card (no JSON file) stays there in `~/.ainnotator` until a later copy removes it as too old, and that machine's own logs may show that a file arrived.
