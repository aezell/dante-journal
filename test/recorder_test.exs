defmodule DanteJournal.RecorderTest do
  use ExUnit.Case, async: true
  alias DanteJournal.Recorder

  @fake Path.expand("support/fake_ear.sh", __DIR__)

  defp start(opts \\ []) do
    opts = Keyword.merge([binary: @fake, sink: {:pid, self()}, name: nil, silence_ms: 150], opts)
    {:ok, pid} = Recorder.start_link(opts)
    assert_receive {:recorder, :ready}, 2_000
    pid
  end

  test "a dictation relays partials and stops itself after silence" do
    recorder = start()
    Recorder.start_recording(recorder, "/tmp/clip.wav")
    assert_receive {:recorder, :started}, 1_000
    assert_receive {:recorder, {:partial, "In Canto 2"}}
    assert_receive {:recorder, {:partial, "In Canto 2, stanza 12, Dante sees the leopard."}}
    # No more partials arrive, so the silence timer stops the recording.
    assert_receive {:recorder,
                    {:stopped,
                     %{text: "In Canto 2, stanza 12" <> _, clip: "/tmp/fake.wav", ms: 4200}}},
                   1_000

    assert Recorder.status(recorder) == :idle
  end

  test "an explicit stop and a file transcription" do
    recorder = start(silence_ms: 60_000)
    Recorder.start_recording(recorder, "/tmp/clip.wav")
    assert_receive {:recorder, :started}, 1_000
    Recorder.stop_recording(recorder)
    assert_receive {:recorder, {:stopped, _}}, 1_000

    Recorder.transcribe_file(recorder, "/tmp/in.aiff")

    assert_receive {:recorder, {:transcript, %{text: "Why does Virgil appear so suddenly?"}}},
                   1_000
  end

  test "starting twice reports an error instead of a second session" do
    recorder = start(silence_ms: 60_000)
    Recorder.start_recording(recorder, "/tmp/a.wav")
    assert_receive {:recorder, :started}, 1_000
    Recorder.start_recording(recorder, "/tmp/b.wav")
    assert_receive {:recorder, {:error, "Already recording."}}
  end

  test "a dictation in which nothing is heard gives up after the idle time" do
    recorder = start(silence_ms: 50, idle_ms: 200)
    Recorder.start_recording(recorder, "/tmp/silent.wav")
    assert_receive {:recorder, :started}, 1_000
    refute_receive {:recorder, {:stopped, _}}, 100
    assert_receive {:recorder, {:stopped, %{text: ""}}}, 1_000
    assert Recorder.status(recorder) == :idle
  end

  test "a hotkey is sent once the helper is ready and its presses are relayed" do
    recorder = start(hotkey: 61)
    assert_receive {:recorder, {:hotkey, {:listening, 61}}}, 1_000
    assert_receive {:recorder, {:hotkey, :down}}
    assert_receive {:recorder, {:hotkey, :up}}

    Recorder.set_hotkey(recorder, 99)
    assert_receive {:recorder, {:hotkey, :denied}}, 1_000
    Recorder.set_hotkey(recorder, nil)
    refute_receive {:recorder, {:hotkey, _}}, 100

    Recorder.learn_hotkey(recorder)
    assert_receive {:recorder, {:hotkey, {:learned, 105}}}, 1_000
  end

  test "a missing helper is reported, not crashed on" do
    {:ok, recorder} =
      Recorder.start_link(binary: "/nonexistent/dante-ear", sink: {:pid, self()}, name: nil)

    assert_receive {:recorder, {:unavailable, "Transcription helper not built" <> _}}
    Recorder.start_recording(recorder, "/tmp/a.wav")
    assert_receive {:recorder, {:error, "The transcription helper isn't available."}}
  end
end
