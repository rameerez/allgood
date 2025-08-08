# frozen_string_literal: true

require_relative "../test_helper"

class VersionTest < Minitest::Test
  def test_version_defined
    assert defined?(Allgood::VERSION), "Allgood::VERSION must be defined"
    assert_kind_of String, Allgood::VERSION
    refute_empty Allgood::VERSION
  end

  def test_version_semver_like
    assert_match(/\A\d+\.\d+\.\d+\z/, Allgood::VERSION)
  end
end