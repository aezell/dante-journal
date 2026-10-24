defmodule DanteJournal.State do
  @moduledoc "The workspace state map and its pure transitions."
  alias DanteJournal.Text

  def initial(opts \\ []) do
    %{
      theme: Keyword.get(opts, :theme, :dark),
      english: Keyword.get(opts, :english, Text.default_english()),
      italian: false,
      cantica: :inferno,
      canto: 1,
      # The tercet dictation falls back to when no anchor is spoken.
      tercet: nil,
      # `{cantica, canto} => count`, filled by the notes store later.
      note_counts: %{},
      status: "Inferno · Canto I"
    }
  end

  def select(state, cantica, canto) do
    if cantica in Text.cantiche() and canto in 1..Text.canto_count(cantica) do
      %{state | cantica: cantica, canto: canto, tercet: nil}
      |> put_status()
    else
      state
    end
  end

  def next_canto(%{cantica: cantica, canto: canto} = state) do
    cond do
      canto < Text.canto_count(cantica) -> select(state, cantica, canto + 1)
      cantica == :inferno -> select(state, :purgatorio, 1)
      cantica == :purgatorio -> select(state, :paradiso, 1)
      true -> state
    end
  end

  def previous_canto(%{cantica: cantica, canto: canto} = state) do
    cond do
      canto > 1 -> select(state, cantica, canto - 1)
      cantica == :paradiso -> select(state, :purgatorio, 33)
      cantica == :purgatorio -> select(state, :inferno, 34)
      true -> state
    end
  end

  def select_tercet(state, n), do: %{state | tercet: if(state.tercet == n, do: nil, else: n)}

  defp put_status(state) do
    %{
      state
      | status:
          "#{DanteJournal.Tercet.name(state.cantica)} · Canto #{DanteJournal.Tercet.roman(state.canto)}"
    }
  end
end
