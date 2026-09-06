module Allgood
  class Engine < ::Rails::Engine
    isolate_namespace Allgood

    config.after_initialize do
      config_file = Rails.root.join("config", "allgood.rb")
      if File.exist?(config_file)
        begin
          Allgood.configure do |config|
            config.instance_eval(File.read(config_file))
          end
        rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
          Rails.logger.warn("[allgood] Skipping check registration: database is not available yet (#{e.class}). " \
                            "Checks will register on the next request once the database is ready.")
        end
      end
    end
  end
end
