# Blind test: can a model tell your marks from the screen?

A screenshot with arrows on it has a problem: the app in the picture may have arrows of its own. This test checks whether a model that knows nothing about AInnotator can tell what the user marked from what the screen already showed.

## The setup

`screen.swift` draws an invented order dashboard that is built to mislead. All of this belongs to the app in the picture:

- a red hint arrow with the text "New: CSV export", pointing at the Export button
- a purple focus outline around one card
- a yellow ring on another card
- a red validation border around a quantity of -4
- numbered step chips 01, 02, 03
- a striped loading bar where a customer name is still missing

On top of that screen are five marks made with AInnotator, and one redaction:

| # | Mark | Intent | Note |
|---|---|---|---|
| 01 | box around the Export button | change | Move the Export button next to the search field |
| 02 | arrow to a total | bug | Total is net, should be gross |
| 03 | oval around the Cancelled card | question | none |
| 04 | box around the step bar | keep | none |
| 05 | point on the footer line | change | Font too small here |

Two pictures came out of it:

- `card.png` is the card as AInnotator renders it, with legend and footer.
- `marks-only.png` is the same picture with legend and footer cut off.

## The question

Each model got one picture from an otherwise empty folder and this message: *A user sent you the image file image.png and wrote only: "Please implement."* It was then asked to list what the user wants, what else looks like a hint but isn't one, and where it is unsure. The full wording is in `run.sh`.

## The result

One run per model and picture, on 14 November 2026: Claude Haiku and Claude Opus through Claude Code 2.1.325, and Codex CLI 0.167.0 with its default model. Claude Code ran without the user's own settings and instruction files. Codex ran with its default configuration; asked beforehand, it reported no standing instructions from the user.

| Picture | Marks read with their intent | Screen content taken for a request |
|---|---|---|
| `marks-only.png` | none of the notes can be read, so none | all three models: "add a CSV export", from the app's own hint |
| `card.png` | 5 of 5 by all three models, the two without a note included | none |

Every answer is in `answers/`.

## What this does not show

- It is one screen and one run per model. Models answer differently from run to run.
- The question itself asks what is not a request. Nobody asks that in daily use, so real results will be less tidy.
- Two of the three models took the striped loading bar for a second redaction; one of them then noticed that the footer names only one. No wrong request came from it.
- The card is a guide for the model, not a guarantee.

## Run it again

You need the Claude Code and Codex command line tools.

```sh
research/blind-test/run.sh /tmp/blind
```

To rebuild the two pictures from the code, follow the comment at the top of `render-card.swift`.
