module Allgood
  class Engine < ::Rails::Engine
    isolate_namespace Allgood

    initializer "allgood.load_configuration" do
      config_file = Rails.root.join("config", "allgood.rb")
      load config_file if File.exist?(config_file)
    end
  end
end
