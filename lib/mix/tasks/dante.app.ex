defmodule Mix.Tasks.Dante.App do
  @shortdoc "Builds Dante Journal.app, a self-contained macOS app"
  @moduledoc """
  Builds a macOS app that runs without Elixir, Erlang, Rust or Swift installed:

      MIX_ENV=prod mix dante.app
      MIX_ENV=prod mix dante.app --output ~/Desktop

  It writes `Dante Journal.app` and `DanteJournal-VERSION-macos-arm64.zip` to
  `dist/` (or `--output`). The bundle holds a release of this project with its
  own Erlang runtime, the precompiled GPUI library, the `dante-ear` helper
  built from `native/dante-ear`, and the OpenSSL library Erlang's crypto
  needs. Runs on Macs with this one's architecture.

  The app is signed with the "Dante Journal Developer" certificate when
  `macos/make_signing_cert.sh` has created it (or with `$DANTE_SIGN_IDENTITY`),
  so macOS keeps its microphone and Input Monitoring grants across rebuilds;
  otherwise ad hoc. Either way another Mac blocks the first launch until it's
  allowed under System Settings → Privacy & Security. Opened from Finder it logs to `~/Library/Logs/Dante Journal/`.
  """
  use Mix.Task

  @app_name "Dante Journal"
  @bundle_id "com.alexezell.dante-journal"
  @release "dante_journal"
  @portable_library_prefixes [
    "/usr/lib/",
    "/System/",
    "@rpath/",
    "@loader_path/",
    "@executable_path/"
  ]

  @impl true
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [output: :string])
    if rest != [], do: Mix.raise("Unexpected arguments. See mix help dante.app.")

    unless match?({:unix, :darwin}, :os.type()),
      do: Mix.raise("Dante Journal.app builds on macOS.")

    unless Mix.env() == :prod, do: Mix.raise("Build the app in prod: MIX_ENV=prod mix dante.app")

    out = Path.expand(opts[:output] || "dist")
    app = Path.join(out, @app_name <> ".app")
    contents = Path.join(app, "Contents")
    release = Path.join(contents, "Resources/release")
    version = Mix.Project.config()[:version]

    build_helper!()
    Mix.Task.run("compile")

    File.rm_rf!(app)
    File.mkdir_p!(Path.join(contents, "MacOS"))
    Mix.Task.run("release", [@release, "--path", release, "--overwrite", "--quiet"])

    helper = Path.join([release, "lib", "#{@release}-#{version}", "priv", "bin", "dante-ear"])
    unless File.exists?(helper), do: Mix.raise("The release is missing priv/bin/dante-ear.")
    File.chmod!(helper, 0o755)

    File.cp!("macos/AppIcon.icns", Path.join(contents, "Resources/AppIcon.icns"))
    launcher = Path.join([contents, "MacOS", "DanteJournal"])
    File.write!(launcher, launcher())
    File.chmod!(launcher, 0o755)

    binaries = mach_o_files(contents)
    bundle_homebrew_libraries!(binaries)
    binaries = mach_o_files(contents)
    check_portable!(binaries, contents)
    minimum = minimum_macos(binaries)
    File.write!(Path.join(contents, "Info.plist"), info_plist(version, minimum))
    sign!(app, binaries)

    zip = Path.join(out, "DanteJournal-#{version}-macos-#{arch()}.zip")
    File.rm(zip)
    cmd!("ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app, zip])

    Mix.shell().info("""
    Built #{app} (minimum macOS #{minimum})
    Share #{zip} (#{megabytes(zip)} MB)
    """)
  end

  defp build_helper! do
    Mix.shell().info("Building dante-ear…")

    case System.cmd("sh", ["native/dante-ear/build.sh"], stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, status} -> Mix.raise("native/dante-ear/build.sh failed (#{status}):\n#{out}")
    end
  end

  # Opened from Finder, nothing reads stdout, so it goes to a log file. The
  # release writes nothing inside the bundle, which may be read-only.
  defp launcher do
    """
    #!/bin/sh
    contents=$(cd "$(dirname "$0")/.." && pwd)
    logs="$HOME/Library/Logs/#{@app_name}"
    mkdir -p "$logs"
    export RELEASE_TMP="${TMPDIR:-/tmp}/dante-journal"
    export ERL_CRASH_DUMP="$logs/erl_crash.dump"
    if [ -t 1 ]; then
      exec "$contents/Resources/release/bin/#{@release}" eval "DanteJournal.CLI.main(System.argv())" "$@"
    fi
    exec "$contents/Resources/release/bin/#{@release}" eval "DanteJournal.CLI.main(System.argv())" "$@" >> "$logs/dante-journal.log" 2>&1
    """
  end

  defp info_plist(version, minimum) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleDevelopmentRegion</key><string>en</string>
      <key>CFBundleDisplayName</key><string>#{@app_name}</string>
      <key>CFBundleExecutable</key><string>DanteJournal</string>
      <key>CFBundleIconFile</key><string>AppIcon</string>
      <key>CFBundleIdentifier</key><string>#{@bundle_id}</string>
      <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
      <key>CFBundleName</key><string>#{@app_name}</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>#{version}</string>
      <key>CFBundleVersion</key><string>#{version}</string>
      <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
      <key>LSMinimumSystemVersion</key><string>#{minimum}</string>
      <key>NSHighResolutionCapable</key><true/>
      <key>NSPrincipalClass</key><string>NSApplication</string>
      <key>NSMicrophoneUsageDescription</key><string>Dante Journal listens while you dictate a note, and transcribes it on this Mac.</string>
      <key>NSSpeechRecognitionUsageDescription</key><string>Dante Journal turns your dictated notes into text on this Mac; nothing is sent anywhere.</string>
    </dict>
    </plist>
    """
  end

  # Erlang's crypto NIF from asdf links Homebrew's OpenSSL, which other Macs
  # don't have. Copy each such library beside the binary that loads it and
  # point the load command at it.
  defp bundle_homebrew_libraries!(binaries) do
    for path <- binaries,
        library <- linked_libraries(path),
        String.starts_with?(library, ["/opt/homebrew/", "/usr/local/"]) do
      name = Path.basename(library)
      copy = Path.join(Path.dirname(path), name)

      unless File.exists?(copy) do
        File.cp!(library, copy)
        File.chmod!(copy, 0o755)
        cmd!("install_name_tool", ["-id", "@loader_path/#{name}", copy])
      end

      cmd!("install_name_tool", ["-change", library, "@loader_path/#{name}", path])
      Mix.shell().info("Bundled #{name} for #{Path.basename(path)}")
    end
  end

  # Every executable and native library in the bundle, by Mach-O magic.
  defp mach_o_files(dir) do
    for path <- Path.wildcard(Path.join(dir, "**"), match_dot: true),
        File.lstat!(path).type == :regular,
        mach_o?(path),
        do: path
  end

  defp mach_o?(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 4)) do
      {:ok, <<0xCF, 0xFA, 0xED, 0xFE>>} -> true
      {:ok, <<0xCA, 0xFE, 0xBA, 0xBE>>} -> true
      _other -> false
    end
  end

  # Every library a bundled binary loads must ship with macOS or inside the app.
  defp check_portable!(binaries, contents) do
    foreign =
      for path <- binaries,
          library <- linked_libraries(path),
          not String.starts_with?(library, @portable_library_prefixes),
          do: "#{Path.relative_to(path, contents)} loads #{library}"

    if foreign != [] do
      Mix.raise("""
      The app would only run on this Mac. Bundled binaries load libraries outside macOS:

        #{Enum.join(Enum.uniq(foreign), "\n  ")}
      """)
    end
  end

  # The libraries a binary loads, from its load commands.
  defp linked_libraries(path) do
    {out, 0} = System.cmd("otool", ["-l", path])

    ~r/cmd LC_(?:LOAD|LOAD_WEAK|REEXPORT|LAZY_LOAD|LOAD_UPWARD)_DYLIB\n\s+cmdsize \d+\n\s+name (\S+)/
    |> Regex.scan(out, capture: :all_but_first)
    |> List.flatten()
  end

  # The newest macOS any bundled binary was built for.
  defp minimum_macos(binaries) do
    binaries
    |> Enum.flat_map(fn path ->
      {out, 0} = System.cmd("otool", ["-l", path])
      Regex.scan(~r/^\s*minos (\d+(?:\.\d+)*)$/m, out, capture: :all_but_first)
    end)
    |> Enum.map(fn [version] -> Version.parse!(normalize(version)) end)
    |> Enum.max(Version, fn -> Version.parse!("11.0.0") end)
    |> then(&"#{&1.major}.#{&1.minor}")
  end

  defp normalize(version) do
    case String.split(version, ".") do
      [major] -> "#{major}.0.0"
      [major, minor] -> "#{major}.#{minor}.0"
      [major, minor, patch | _] -> "#{major}.#{minor}.#{patch}"
    end
  end

  @signing_name "Dante Journal Developer"

  # Nested code first, then the bundle, which seals everything else. Signs with
  # the "Dante Journal Developer" certificate from macos/make_signing_cert.sh
  # (or $DANTE_SIGN_IDENTITY) when present, so the app keeps one code identity
  # and macOS remembers its permissions across rebuilds; ad hoc otherwise.
  defp sign!(app, binaries) do
    identity = signing_identity()
    Mix.shell().info("Signing as #{if identity == "-", do: "ad hoc", else: identity}")
    for path <- binaries, do: cmd!("codesign", ["--force", "--sign", identity, path])
    cmd!("codesign", ["--force", "--sign", identity, app])
    cmd!("codesign", ["--verify", "--deep", "--strict", app])
  end

  defp signing_identity do
    case System.get_env("DANTE_SIGN_IDENTITY") do
      nil ->
        {out, 0} = System.cmd("security", ["find-identity", "-v", "-p", "codesigning"])
        if String.contains?(out, "\"#{@signing_name}\""), do: @signing_name, else: "-"

      identity ->
        identity
    end
  end

  defp arch do
    case :erlang.system_info(:system_architecture) |> to_string() do
      "aarch64" <> _ -> "arm64"
      "arm64" <> _ -> "arm64"
      "x86_64" <> _ -> "x86_64"
      other -> other
    end
  end

  defp cmd!(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, status} -> Mix.raise("#{command} failed (#{status}):\n#{out}")
    end
  end

  defp megabytes(path), do: Float.round(File.stat!(path).size / 1_000_000, 1)
end
