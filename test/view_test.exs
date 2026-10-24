defmodule DanteJournal.ViewTest do
  use GPUI.Test, async: true
  alias DanteJournal.{State, View}

  test "the sidebar selects cantos and the shortcuts step through them" do
    runtime = start_runtime!(DanteJournal.Desktop, args: State.initial())
    assert %{cantica: :inferno, canto: 1} = assigns(runtime)

    click(runtime, "select:purgatorio:9")
    assert %{cantica: :purgatorio, canto: 9, status: "Purgatorio · Canto IX"} = assigns(runtime)

    command(runtime, "previous-canto")
    assert %{canto: 8} = assigns(runtime)

    state = State.initial() |> State.select(:inferno, 34) |> State.next_canto()
    assert {:purgatorio, 1} = {state.cantica, state.canto}
    assert %{cantica: :inferno, canto: 1} = State.initial() |> State.previous_canto()

    assert %{cantica: :paradiso, canto: 33} =
             State.initial() |> State.select(:paradiso, 33) |> State.next_canto()
  end

  test "the reader lists every tercet, toggles Italian and selects a tercet" do
    runtime = start_runtime!(DanteJournal.Desktop, args: State.initial())
    tree = View.render(assigns(runtime))
    assert GPUI.Tree.find!(tree, id: "reader-inferno-1")
    assert GPUI.Tree.find!(tree, id: "tercet-46")
    refute GPUI.Tree.find(tree, id: "tercet-47")

    click(runtime, "tercet:12")
    assert %{tercet: 12} = assigns(runtime)

    payload =
      View.render(assigns(runtime)) |> GPUI.Element.to_payload() |> inspect(limit: :infinity)

    assert payload =~ "Inf. 1.34–36"

    command(runtime, "toggle-italian")
    assert %{italian: true} = assigns(runtime)

    payload =
      View.render(assigns(runtime)) |> GPUI.Element.to_payload() |> inspect(limit: :infinity)

    assert payload =~ "Nel mezzo del cammin di nostra vita"
    assert payload =~ "Midway upon the journey of our life"
  end

  test "theme tokens are resolved before the tree reaches a display" do
    tree = View.render(State.initial())
    refute inspect(tree, limit: :infinity) =~ ":theme"
    assert GPUI.Tree.find!(tree, id: "status")
  end
end
