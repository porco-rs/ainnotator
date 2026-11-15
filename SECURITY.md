# Security

AInnotator sees your screen and holds macOS permissions, so security reports matter here, and thank you for sending one.

## Reporting a problem

Please report privately through [GitHub's private vulnerability reporting](https://github.com/porco-rs/ainnotator/security/advisories/new), not in a public issue.

So I can reproduce it, please include:

- the version you tested and your macOS version
- the steps, what you expected, and what happened
- what an attacker needs first, and what they gain

Please use an invented screen for your example, not a capture of your own.

Reports found with AI tools are welcome if you have verified them yourself. There is no bug bounty.

This is a one-person project. I try to answer within seven days. We then agree on timing, I fix it privately, and I publish the affected and fixed versions together with credit if you want it.

## Supported versions

Only the latest release receives fixes.

## What AInnotator protects against, and what it doesn't

- **In scope:** whatever is on your screen, in a window title, a page address, a branch name or the command line of your terminal must not make the app run commands, write outside its own folder or send anything anywhere. The one exception is a capture you let it copy to the machine your terminal is connected to, after you confirmed that machine; only the finished card goes, through your own `ssh`, into `~/.ainnotator` there. Nothing in what the app reads may add an option to that call that runs a command, or send it anywhere else. A redacted area must not survive in any file the app writes, on either machine, or in what it puts on the clipboard.
- **Not in scope:** malware already running under your user account. It can read the same files and the same clipboard as you, and the app cannot stop it. What an AI tool does with an image you paste into it is that tool's business; the legend on the card helps a model tell your marks from the screen, but it is a guide, not a wall. The same goes for the machine you copy to: once the card is there, it is under that machine's own rules and its administrators.

Each way in and how it is closed: [threat model](THREAT_MODEL.md).

## Official downloads

Official releases come only from [the releases of this repository](https://github.com/porco-rs/ainnotator/releases). They are signed with Developer ID by Leon Schwahn, team `DLYUZB2S4C`, and notarized by Apple. To check a copy:

```sh
codesign -dv /Applications/AInnotator.app
```

It should show `TeamIdentifier=DLYUZB2S4C`. If a copy that presents itself as this AInnotator shows another team, or a site offers it as an official download somewhere else, please don't run it, and tell me through the private report above.
