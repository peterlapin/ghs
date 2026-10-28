class Ghs < Formula
  desc "Short command aliases for GitHub Stack"
  homepage "https://ghstacked.com"
  url "https://github.com/peterlapin/ghs/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "7941d80f0189940145bdcaebb89f5bd1c8b26856421e24d45c9ab1c6f3014797"
  license "MIT"

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
