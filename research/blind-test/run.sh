#!/bin/bash
# Blind test: can a model that knows nothing about AInnotator tell the user's marks from the screen's own content?
# Each model gets one image from an otherwise empty folder and the words "Please implement."
#
#   card         card.png         the card as AInnotator renders it
#   marks-only   marks-only.png   the same picture with legend and footer cut off
#
# usage: research/blind-test/run.sh <work-dir>     answers land in <work-dir>/<condition>-<model>.txt
#
# Needs the Claude Code and Codex command line tools. Claude runs without the user's own settings and instruction
# files, so nothing but the image and the question reaches the model.
set -u
here=$(cd "$(dirname "$0")" && pwd -P)
work=${1:?work dir}
mkdir -p "$work"
work=$(cd "$work" && pwd -P)

prompt='A user sent you the image file image.png and wrote only: "Please implement."

Look only at the file image.png in this folder; do not read or change anything else and do not run anything. You are not supposed to implement anything, only to show how you understand the image. Answer briefly:

1. List point by point what the user wants from you and which element of the screen each point refers to.
2. List what else you see in the image that looks like a hint or a highlight but that you deliberately do NOT treat as a wish of the user, with a short reason.
3. Name the places where you are unsure.'

for condition in card marks-only; do
  mkdir -p "$work/$condition"
  cp "$here/$condition.png" "$work/$condition/image.png"
  for model in haiku opus; do
    ( cd "$work/$condition" && claude -p "$prompt" --model "$model" --setting-sources project --allowedTools Read --max-turns 4 \
        > "$work/$condition-$model.txt" 2> "$work/$condition-$model.err" ) &
  done
  # The prompt comes before -i, which otherwise takes it for another image.
  ( cd "$work/$condition" && codex exec --skip-git-repo-check -s read-only "$prompt" -i image.png \
      < /dev/null > "$work/$condition-codex.txt" 2> "$work/$condition-codex.err" ) &
done
wait
wc -c "$work"/*.txt
