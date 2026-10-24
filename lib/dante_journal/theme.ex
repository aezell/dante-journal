defmodule DanteJournal.Theme do
  @moduledoc "Warm paper and ink surfaces; a single ember accent for active state."

  @palettes %{
    dark: %{
      canvas: 0x1B1917,
      sidebar: 0x221F1C,
      text: 0xEDE6DA,
      muted: 0x9C9184,
      border: 0x332E29,
      accent: 0xE0933A,
      surface: 0x27231F,
      recording: 0xE05A4F,
      question: 0x6FA8DC,
      insight: 0x8AC6A0,
      reference: 0xB69AF8,
      quote: 0xD9B46B,
      todo: 0xE58585
    },
    light: %{
      canvas: 0xFBF7F0,
      sidebar: 0xF2ECE1,
      text: 0x2B2622,
      muted: 0x7C7266,
      border: 0xE3DACB,
      accent: 0xB8641C,
      surface: 0xFFFFFF,
      recording: 0xC2453D,
      question: 0x2F6FA8,
      insight: 0x3B8861,
      reference: 0x7746CB,
      quote: 0x9A6A12,
      todo: 0xC2453D
    }
  }

  def color(mode, token), do: {:rgb, Map.fetch!(@palettes[mode], token)}

  @doc "Replaces every `{:theme, token}` style value in an element tree."
  def resolve(%GPUI.Element{} = element, mode) do
    attrs =
      Keyword.update(element.attrs, :style, [], fn styles ->
        Enum.map(styles, fn
          {key, {:theme, token}} -> {key, color(mode, token)}
          other -> other
        end)
      end)

    %{element | attrs: attrs, children: Enum.map(element.children, &resolve(&1, mode))}
  end

  def resolve(other, _mode), do: other
end
