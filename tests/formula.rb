# Run with `brew ruby tests/formula.rb` after scripts/package.sh.
# Exercise Homebrew's DSL and install method, then test the installed wrapper.
# Fetching the public release and brew's full installer still require publication.
require "formula"
require "tmpdir"

root = Pathname.new(__dir__).parent
load root/"dist/ghs.rb"
formula = Ghs.new("ghs", root/"dist/ghs.rb", :stable)
raise "GHS must not install prerequisites" unless formula.deps.empty?

Dir.mktmpdir("ghs-formula-") do |directory|
  temporary = Pathname.new(directory)
  archive = root/"dist"/File.basename(formula.stable.url)
  formula.stable.verify_download_integrity(archive)
  raise "Extraction failed" unless system("tar", "-xzf", archive.to_s, "-C", directory)

  formula.define_singleton_method(:prefix) { |*| temporary/"prefix" }
  Dir.chdir(temporary/archive.basename(".tar.gz")) { formula.install }
  test_env = { "GHS_UNDER_TEST" => (formula.bin/"ghs").to_s }
  passed = system(test_env,
                  "/bin/bash", (root/"tests/ghs.sh").to_s)
  raise "Installed wrapper tests failed" unless passed
  passed = system(test_env,
                  "/bin/bash", (root/"tests/add.sh").to_s)
  raise "Installed guided add tests failed" unless passed
end
puts "Homebrew install method and installed-wrapper tests passed in a temporary prefix."
