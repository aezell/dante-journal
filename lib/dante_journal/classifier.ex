defmodule DanteJournal.Classifier do
  @moduledoc """
  Guesses a note's type from its words. Rules only, for now; an on-device
  model can take over later behind the same `classify/1`. The guess is
  advisory and always editable.
  """

  @types [:question, :insight, :reference, :summary, :quote, :todo, :note]

  def types, do: @types

  def label(:question), do: "Question"
  def label(:insight), do: "Insight"
  def label(:reference), do: "Reference"
  def label(:summary), do: "Summary"
  def label(:quote), do: "Quote"
  def label(:todo), do: "To do"
  def label(:note), do: "Note"

  @doc "The type a transcript most likely is."
  def classify(text) when is_binary(text) do
    t = String.downcase(text)

    cond do
      String.contains?(t, "?") ->
        :question

      Regex.match?(
        ~r/\b(i wonder|why (does|did|is|do|would)|is this|does this|what does|how does|who is|which|could this be)\b/,
        t
      ) ->
        :question

      Regex.match?(
        ~r/\b(look up|check|find out|remember to|need to|should (re)?read|to ?do|follow up)\b/,
        t
      ) ->
        :todo

      Regex.match?(
        ~r/\b(echo(es)?|remind(s|ed)? me|reference to|refers to|alludes? to|allusion|compare|cf\.?|like in|as in|same as|callback to|parallels?|foreshadow)/,
        t
      ) ->
        :reference

      Regex.match?(
        ~r/\b(the line|the phrase|the image|quote|quoting|beautiful line|love the line|favorite line|favourite line)\b/,
        t
      ) ->
        :quote

      Regex.match?(
        ~r/\b(in summary|to sum up|basically|the canto (is|covers|describes)|here dante|in this canto|this canto)\b/,
        t
      ) ->
        :summary

      Regex.match?(
        ~r/\b(i think|i feel|it seems|seems like|the point is|this means|this shows|this suggests|interesting that|realized|realised|insight)\b/,
        t
      ) ->
        :insight

      true ->
        :note
    end
  end

  def color(:question), do: :question
  def color(:insight), do: :insight
  def color(:reference), do: :reference
  def color(:summary), do: :muted
  def color(:quote), do: :quote
  def color(:todo), do: :todo
  def color(:note), do: :accent
end
