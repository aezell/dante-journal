#!/bin/sh
# Stands in for Apple's fm command in tests: canned answers keyed on the
# schema title and words in the prompt.
case "$1" in
  available) exit 0 ;;
  respond) ;;
  *) echo "unknown"; exit 2 ;;
esac
schema=""; prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --schema) schema="$2"; shift 2 ;;
    -i) shift 2 ;;
    --no-stream|-g) shift ;;
    *) prompt="$1"; shift ;;
  esac
done
if [ -n "$schema" ] && grep -q NoteClassification "$schema"; then
  case "$prompt" in
    *"look up"*|*"Look up"*) echo '{"type":"todo","title":"Celestine the fifth","tags":["celestine","popes"]}' ;;
    *echoes*) echo '{"type":"reference","title":"Aeneas and the unburied","tags":["aeneid","virgil"]}' ;;
    *) echo '{"type":"insight","title":"A canned reading","tags":["canned"]}' ;;
  esac
elif [ -n "$schema" ] && grep -q PlaceInPoem "$schema"; then
  case "$prompt" in
    *"second canto of Purgatory"*) echo '{"cantica":"purgatorio","canto":2,"unit":"stanza","from":4,"to":4}' ;;
    *"canto thirty four"*) echo '{"cantica":"inferno","canto":34,"unit":"line","from":133,"to":139}' ;;
    *"line nine hundred"*) echo '{"cantica":"inferno","canto":1,"unit":"line","from":900,"to":900}' ;;
    *) echo '{"cantica":"inferno","canto":0,"unit":"none","from":0,"to":0}' ;;
  esac
elif [ -n "$schema" ]; then
  echo "unexpected schema" >&2; exit 3
else
  case "$prompt" in
    *slow*) sleep 3; echo "late" ;;
    *) echo "Note [3] is about the heart. [1] is about death." ;;
  esac
fi
