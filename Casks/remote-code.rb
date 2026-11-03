# Homebrew cask for the Remote Code Mac app.
#
#   brew tap ardasnturk/remote-code https://github.com/ardasnturk/remote-code
#   brew install --cask remote-code
#
# `version` and `sha256` are updated by scripts/prepare-release.sh.
cask "remote-code" do
  version "1.5.1"
  sha256 "5f0d9b7ab8942451c8d42e59716002c78ab80126ade170efad987487fd0fd2cf"

  url "https://github.com/ardasnturk/remote-code/releases/download/v#{version}/RemoteCode-#{version}.dmg"
  name "Remote Code"
  desc "Drive Claude Code, Codex and Gemini CLI on your Mac from iPhone and iPad"
  homepage "https://github.com/ardasnturk/remote-code"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "Remote Code.app"

  uninstall quit:      "com.ardasenturk.Pilothouse.Mac",
            launchctl: "com.ardasenturk.Pilothouse.Helper"

  # Data, keychain and identifiers keep the old name so pairings survive the rename.
  zap trash: [
    "~/Library/Application Support/Pilothouse",
    "~/Library/Caches/com.ardasenturk.Pilothouse.Mac",
    "~/Library/HTTPStorages/com.ardasenturk.Pilothouse.Mac",
    "~/Library/Preferences/com.ardasenturk.Pilothouse.Mac.plist",
  ]

  caveats <<~EOS
    Remote Code needs at least one agent CLI on this Mac, signed in with your
    own account: Claude Code, Codex or Gemini CLI.
      https://docs.claude.com/en/docs/claude-code/setup

    The pairing keys live in your login keychain ("Pilothouse identity key");
    `brew uninstall --zap` does not remove them. Delete them in Keychain Access
    if you want a completely clean uninstall.
  EOS
end
