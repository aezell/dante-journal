defmodule DanteJournal.View do
  @moduledoc "The root view: canto sidebar on the left, the poem in the middle."
  use GPUI.View
  alias GPUI.UI
  alias DanteJournal.{State, Tercet, Text, Theme, UIKit}

  @impl true
  def render(assigns) do
    ~GPUI"""
    <div class="flex flex-row w-full h-full text-[13px]" style={[background: {:theme, :canvas}, color: {:theme, :text}]}>
      {sidebar(assigns)}
      <div class="flex flex-col flex-1 min-w-0 h-full">
        {toolbar(assigns)}
        {reader(assigns)}
        {status_bar(assigns)}
      </div>
    </div>
    """
    |> Theme.resolve(assigns.theme)
  end

  # `<.action>` in templates resolves to a local function.
  def action(assigns), do: UIKit.action(assigns)

  # -- Sidebar -----------------------------------------------------------------

  defp sidebar(assigns) do
    ~GPUI"""
    <div class="relative flex flex-col w-[220px] shrink-0 h-full" style={[background: {:theme, :sidebar}]}>
      {UIKit.vertical_rule()}
      <div window_control="drag" class="relative flex flex-row items-center h-[38px] shrink-0 px-4">
        {UIKit.rule()}
        <div class="w-[62px] shrink-0" />
        <text class="font-semibold" style={[color: {:theme, :accent}]}>Dante Journal</text>
      </div>
      <scroll id="canto-list" class="flex-1 min-h-0 w-full">
        <div class="flex flex-col w-full pb-4">
          {Enum.map(Text.cantiche(), &cantica_section(&1, assigns))}
        </div>
      </scroll>
    </div>
    """
  end

  defp cantica_section(cantica, state) do
    assigns = %{cantica: cantica, state: state, count: Text.canto_count(cantica)}

    ~GPUI"""
    <div class="flex flex-col w-full">
      <div class="flex flex-row items-center px-4 pt-4 pb-1 gap-2">
        {UIKit.heading(Tercet.name(assigns.cantica))}
        <text class="text-[10px]" style={[color: {:theme, :muted}]}>{assigns.count} cantos</text>
      </div>
      {Enum.map(1..assigns.count, &canto_row(assigns.cantica, &1, assigns.state))}
    </div>
    """
  end

  defp canto_row(cantica, canto, state) do
    assigns = %{
      id: "canto-#{cantica}-#{canto}",
      event: "select:#{cantica}:#{canto}",
      label: "Canto #{Tercet.roman(canto)}",
      selected: state.cantica == cantica and state.canto == canto,
      notes: Map.get(state.note_counts, {cantica, canto}, 0)
    }

    ~GPUI"""
    <.action id={assigns.id} phx-click={assigns.event} accessibility_label={assigns.label}
      class="flex flex-row items-center w-full h-[26px] px-4 gap-2 cursor-pointer"
      style={[background: if(assigns.selected, do: {:theme, :surface}, else: ~RGBA"00000000")]}>
      <text class="text-[12px]" style={[color: if(assigns.selected, do: {:theme, :accent}, else: {:theme, :text})]}>{assigns.label}</text>
      <div class="flex-1" />
      {note_badge(assigns.notes)}
    </.action>
    """
  end

  defp note_badge(0), do: []

  defp note_badge(count) do
    assigns = %{count: count}

    ~GPUI"""
    <text class="text-[10px]" style={[color: {:theme, :muted}]}>{assigns.count}</text>
    """
  end

  # -- Reader ------------------------------------------------------------------

  defp toolbar(assigns) do
    ~GPUI"""
    <div window_control="drag" class="relative flex flex-row items-center h-[38px] shrink-0 px-4 gap-2">
      {UIKit.rule()}
      <text class="font-semibold">{Tercet.name(assigns.cantica)}</text>
      <text style={[color: {:theme, :muted}]}>Canto {Tercet.roman(assigns.canto)}</text>
      <text class="text-[11px]" style={[color: {:theme, :muted}]}>· {Text.translation_name(assigns.english)}{if assigns.italian, do: " + Petrocchi", else: ""}</text>
      <div class="flex-1" />
      <UI.button id="previous-canto" label="‹" size="xs" variant="ghost" phx-click="previous-canto" />
      <UI.button id="next-canto" label="›" size="xs" variant="ghost" phx-click="next-canto" />
      <UI.button id="toggle-italian" label={if assigns.italian, do: "Hide Italian", else: "Italian"} size="xs" variant={if assigns.italian, do: "primary", else: "ghost"} phx-click="toggle-italian" />
    </div>
    """
  end

  defp reader(assigns) do
    tercets = Text.tercets(assigns.english, assigns.cantica, assigns.canto)

    italian =
      if assigns.italian,
        do:
          Text.tercets(:petrocchi, assigns.cantica, assigns.canto)
          |> Map.new(&{&1.number, &1.lines}),
        else: %{}

    assigns = Map.merge(assigns, %{tercets: tercets, italian_lines: italian})

    ~GPUI"""
    <UI.virtual_collection id={"reader-#{assigns.cantica}-#{assigns.canto}"} label={"#{Tercet.name(assigns.cantica)} canto #{assigns.canto}"}
      overdraw={400} class="flex-1 min-h-0 w-full px-8 py-6">
      {Enum.map(assigns.tercets, &tercet_item(&1, Map.get(assigns.italian_lines, &1.number), assigns))}
    </UI.virtual_collection>
    """
  end

  defp tercet_item(tercet, italian, state) do
    assigns = %{
      tercet: tercet,
      italian: italian,
      selected: state.tercet == tercet.number,
      event: "tercet:#{tercet.number}"
    }

    UI.virtual_item(%{
      id: "tercet-#{tercet.number}",
      revision: if(italian, do: 1, else: 0),
      children: [tercet_row(assigns)]
    })
  end

  defp tercet_row(assigns) do
    ~GPUI"""
    <.action id={"pick-tercet-" <> Integer.to_string(assigns.tercet.number)} phx-click={assigns.event}
      accessibility_label={"Tercet " <> Integer.to_string(assigns.tercet.number)}
      class="flex flex-row w-full items-start gap-4 px-3 py-2 rounded-md cursor-pointer"
      style={[background: if(assigns.selected, do: {:theme, :surface}, else: ~RGBA"00000000")]}>
      <text class="w-8 shrink-0 text-right text-[11px] pt-[3px]" style={[color: if(assigns.selected, do: {:theme, :accent}, else: {:theme, :muted})]}>{if rem(assigns.tercet.number, 2) == 0 or assigns.selected, do: Integer.to_string(assigns.tercet.from), else: ""}</text>
      <div class="flex flex-col flex-1 min-w-0 gap-[2px]">
        {Enum.map(assigns.tercet.lines, &line(&1, :english))}
      </div>
      {italian_column(assigns.italian)}
    </.action>
    """
  end

  defp italian_column(nil), do: []

  defp italian_column(lines) do
    assigns = %{lines: lines}

    ~GPUI"""
    <div class="flex flex-col flex-1 min-w-0 gap-[2px]">
      {Enum.map(assigns.lines, &line(&1, :italian))}
    </div>
    """
  end

  defp line(text, language) do
    assigns = %{text: text, language: language}

    ~GPUI"""
    <text class="text-[15px] leading-[22px]" style={[color: if(assigns.language == :italian, do: {:theme, :muted}, else: {:theme, :text})]}>{assigns.text}</text>
    """
  end

  defp status_bar(assigns) do
    ~GPUI"""
    <div class="relative flex flex-row items-center h-7 shrink-0 px-4 gap-3">
      {UIKit.rule_top()}
      <text id="status" class="text-[11px]" style={[color: {:theme, :muted}]}>{assigns.status}</text>
      <div class="flex-1" />
      <text class="text-[11px]" style={[color: {:theme, :muted}]}>{selection_label(assigns)}</text>
    </div>
    """
  end

  defp selection_label(%{tercet: nil}), do: "No tercet selected"

  defp selection_label(%{tercet: n, english: english, cantica: cantica, canto: canto}) do
    {from, to} = Tercet.range(n, Text.line_count(english, cantica, canto))
    Tercet.label(cantica, canto, from, to)
  end

  # -- Events ------------------------------------------------------------------

  @impl true
  def handle_event("select:" <> rest, _event, state) do
    [cantica, canto] = String.split(rest, ":")
    {:noreply, State.select(state, String.to_existing_atom(cantica), String.to_integer(canto))}
  end

  def handle_event("tercet:" <> n, _event, state),
    do: {:noreply, State.select_tercet(state, String.to_integer(n))}

  def handle_event("next-canto", _event, state), do: {:noreply, State.next_canto(state)}
  def handle_event("previous-canto", _event, state), do: {:noreply, State.previous_canto(state)}

  def handle_event("toggle-italian", _event, state),
    do: {:noreply, %{state | italian: not state.italian}}

  def handle_event("toggle-theme", _event, state),
    do: {:noreply, %{state | theme: if(state.theme == :dark, do: :light, else: :dark)}}

  def handle_event(_other, _event, state), do: {:noreply, state}
end
