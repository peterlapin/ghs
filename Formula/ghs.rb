class Ghs < Formula
  desc "Short command aliases for GitHub Stack"
  homepage "https://ghstacked.com"
  version "0.2.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/peterlapin/ghs/releases/download/v0.2.0/ghs-0.2.0-darwin-arm64.tar.gz"
      sha256 "aed574646e1625646493704d70649d8cd1c4b48390148b87e0b0ae3e5b65003e"
    end
    on_intel do
      url "https://github.com/peterlapin/ghs/releases/download/v0.2.0/ghs-0.2.0-darwin-amd64.tar.gz"
      sha256 "fbe179dc73aa533f08c8aad6cc4a4b16d63ca53280fde734188cfa9412b69576"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/peterlapin/ghs/releases/download/v0.2.0/ghs-0.2.0-linux-arm64.tar.gz"
      sha256 "bbc9e54da25d75659924d553ec1768212d5e241e68f63ca7b349d0e13dadc650"
    end
    on_intel do
      url "https://github.com/peterlapin/ghs/releases/download/v0.2.0/ghs-0.2.0-linux-amd64.tar.gz"
      sha256 "9ad6f0c49de7216bb6faf5b0fb05a71b8d81023e4fc67899a815e1a7dedc9f56"
    end
  end

  def install
    bin.install "bin/ghs"
  end

  def caveats
    <<~EOS
      GitHub CLI (gh) and the github/gh-stack extension must already be installed.
      If gh is installed but not yet configured, run these separately:
        gh auth login
        gh extension install github/gh-stack
      GHS compatibility follows your installed gh-stack extension.
    EOS
  end

  test do
    assert_equal "ghs #{version}\n", shell_output("#{bin}/ghs --version")
    assert_match "Usage: ghs", shell_output("#{bin}/ghs --help")
    (testpath/"fake-bin").mkpath
    (testpath/"fake-bin/gh").write <<~SH
      #!/bin/bash
      printf '<%s>\\n' "$@"
    SH
    chmod 0755, testpath/"fake-bin/gh"
    ENV.prepend_path "PATH", testpath/"fake-bin"
    assert_equal "<stack>\n<add>\n<two words>\n<>\n<$literal>\n",
                 shell_output("#{bin}/ghs create 'two words' '' '$literal'")
    assert_equal "<stack>\n<rebase>\n<--no-trunk>\n<--help>\n",
                 shell_output("#{bin}/ghs restack --help")
  end
end
