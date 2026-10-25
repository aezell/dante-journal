defmodule DanteJournal.FormTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Form

  test "spoken fillers are dropped from dictated notes but not typed ones" do
    assert Form.tidy(
             "We hear about a she wolf, uh, just after, uh, Dante tells us, um, about a lion. Hmm, why?",
             :dictation
           ) ==
             "We hear about a she wolf, just after, Dante tells us, about a lion. why?"

    assert Form.tidy("Uh oh, the umbrella and the Uhlan.", :dictation) ==
             "oh, the umbrella and the Uhlan."

    assert Form.tidy("uh, kept as typed", :typed) == "uh, kept as typed"
  end
end
