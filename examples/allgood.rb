check "We have an active database connection" do
  make_sure ActiveRecord::Base.connection.connect!.active?
end

check "The database can perform a simple query" do
  make_sure ActiveRecord::Base.connection.execute("SELECT 1 LIMIT 1").any?
end

check "The database can perform writes" do
  table_name = "allgood_health_check_#{Time.now.to_i}"
  random_id = rand(1..999999)

  result = ActiveRecord::Base.connection.execute(<<~SQL)
    DROP TABLE IF EXISTS #{table_name};
    CREATE TEMPORARY TABLE #{table_name} (id integer);
    INSERT INTO #{table_name} (id) VALUES (#{random_id});
    SELECT id FROM #{table_name} LIMIT 1;
  SQL

  ActiveRecord::Base.connection.execute("DROP TABLE #{table_name}")

  make_sure result.present? && result.first["id"] == random_id, "Able to write to temporary table"
end

check "The database connection pool is healthy" do
  pool = ActiveRecord::Base.connection_pool

  used_connections = pool.connections.count
  max_connections = pool.size
  usage_percentage = (used_connections.to_f / max_connections * 100).round

  make_sure usage_percentage < 90, "Pool usage at #{usage_percentage}% (#{used_connections}/#{max_connections})"
end

check "Database migrations are up to date" do
  make_sure ActiveRecord::Migration.check_all_pending! == nil
end

check "Disk space usage is below 90%" do
  usage = `df -h / | tail -1 | awk '{print $5}' | sed 's/%//'`.to_i
  expect(usage).to_be_less_than(90)
end

check "Memory usage is below 90%" do
  usage = `free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1`.to_i
  expect(usage).to_be_less_than(90)
end

check "Cache is accessible and functioning" do
  cache_value = "allgood_#{Time.now.to_i}"
  Rails.cache.write("allgood_health_check_test", cache_value, expires_in: 1.minute)
  make_sure Rails.cache.read("allgood_health_check_test") == cache_value, "The `allgood_health_check_test` key in the cache should return the string `#{cache_value}`"
end
