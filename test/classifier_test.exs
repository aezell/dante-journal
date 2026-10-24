defmodule DanteJournal.ClassifierTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Classifier

  test "questions, references, todos, quotes, insights, summaries, plain notes" do
    assert Classifier.classify("Why does Virgil appear so suddenly?") == :question
    assert Classifier.classify("I wonder whether the leopard is lust") == :question
    assert Classifier.classify("This echoes the Aeneid book six") == :reference
    assert Classifier.classify("Look up who Celestine the fifth was") == :todo
    assert Classifier.classify("Love the line about the path that does not stray") == :quote
    assert Classifier.classify("I think the dark wood is midlife itself") == :insight
    assert Classifier.classify("In this canto Dante meets the three beasts") == :summary
    assert Classifier.classify("Dante sees the leopard") == :note
  end
end
