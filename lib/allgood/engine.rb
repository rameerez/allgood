module Allgood
  class Engine < ::Rails::Engine
    isolate_namespace Allgood

    config.after_initialize do
      config_file = Rails.root.join("config", "allgood.rb")
      if File.exist?(config_file)
        Allgood.configure do |config|
          config.instance_eval(File.read(config_file))
        end
      end
    end
  end
end
