# ruby-version-min: 1.8.7

require "minitest/autorun"

class TestApt < Minitest::Test
  def setup
    skip "APT contract applies to GNU images" unless ENV["IMAGE_LIBC"] == "gnu"
  end

  def test_https_sources
    # Let APT parse both .list and deb822 .sources without fetching anything.
    output = `apt-get --print-uris update 2>&1`
    assert($?.success?, output)
    uris = output.scan(/^'([^']+)'/).flatten
    refute_empty(uris, output)
    uris.each { |uri| assert_match(/\Ahttps:\/\//, uri) }
    assert(File.size?("/etc/ssl/certs/ca-certificates.crt"), "missing CA bundle")
  end

  def test_tls_verification
    output = `apt-config dump 2>&1`
    assert($?.success?, output)
    refute_match(/Acquire::https::.*Verify-(?:Peer|Host)\s+"(?:false|0|no)"/i, output)
  end

  def test_retries_require_patched_apt
    output = `apt-config shell retries Acquire::Retries 2>&1`
    assert($?.success?, output)
    return if output.strip == "retries='0'"

    # Fixed versions are distribution-specific; unknown releases must disable retries.
    release = File.read("/etc/os-release")
    id = release[/^ID="?([^"\n]+)"?$/, 1]
    codename = release[/^VERSION_CODENAME="?([^"\n]+)"?$/, 1]
    fixed = {
      ["debian", "bookworm"] => "2.6.2",
      ["debian", "trixie"] => "3.0.4",
      ["ubuntu", "jammy"] => "2.4.15ubuntu0.1"
    }[[id, codename]]
    refute_nil(fixed, "disable APT retries on #{id} #{codename}")

    version = `dpkg-query -W -f='${Version}' apt`.strip
    assert($?.success?, "could not query APT version")
    assert(system("dpkg", "--compare-versions", version, "ge", fixed), "APT #{version} predates #{fixed}")
  end
end
