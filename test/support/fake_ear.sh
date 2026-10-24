#!/bin/sh
# Stands in for dante-ear in tests: speaks the same JSON line protocol with
# canned transcripts and no microphone.
echo '{"event":"ready","locale":"en_US"}'
while IFS= read -r line; do
  case "$line" in
    *'"start"'*silent*)
      echo '{"event":"started"}'
      ;;
    *'"start"'*)
      echo '{"event":"started"}'
      echo '{"event":"partial","text":"In Canto 2"}'
      echo '{"event":"partial","text":"In Canto 2, stanza 12, Dante sees the leopard."}'
      heard=yes
      ;;
    *'"stop"'*)
      if [ "$heard" = "yes" ]; then
        echo '{"event":"stopped","text":"In Canto 2, stanza 12, Dante sees the leopard.","clip":"/tmp/fake.wav","ms":4200}'
      else
        echo '{"event":"stopped","text":"","clip":"/tmp/silent.wav","ms":300}'
      fi
      ;;
    *'"file"'*)
      echo '{"event":"transcript","text":"Why does Virgil appear so suddenly?","path":"/tmp/in.aiff"}'
      ;;
    *'"quit"'*) exit 0 ;;
    *'"crash"'*) exit 7 ;;
  esac
done
