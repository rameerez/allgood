require 'open-uri'
require 'vips'
require 'image_processing/vips'

TEST_IMAGE = URI.open("https://picsum.photos/id/237/536/354").read

# --- ACTIVE RECORD ---

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

# --- IMAGE PROCESSING ---

check "Vips (libvips) is installed on Linux" do
  if Rails.env.production?
    output = `ldconfig -p | grep libvips`
    make_sure output.present? && output.include?("libvips.so") && output.include?("libvips-cpp.so"), "Vips is installed on Linux"
  else
    make_sure true, "Not a Linux production environment, skipping (#{Rails.env.to_s})"
  end
end

check "Vips is available to Rails" do
  make_sure Vips::VERSION.present?, "Vips available with version #{Vips::VERSION}"
end

check "Vips can perform operations on images" do
  url = "https://picsum.photos/id/237/536/354"
  image = Vips::Image.new_from_buffer(TEST_IMAGE, "")
  processed_image = image
    .gaussblur(10)                   # Apply Gaussian blur with sigma 10
    .linear([1.2], [0])              # Increase brightness
    .invert                          # Invert colors for a wild effect
    .sharpen                         # Apply sharpening
    .resize(0.5)

  make_sure processed_image.present? && processed_image.width == 268 && processed_image.height == 177, "If we input an image of 536x354, and we apply filters and a 0.5 resize, we should get an image of 268x177"
end

check "ImageProcessing::Vips is available to Rails" do
  make_sure ImageProcessing::Vips.present?, "ImageProcessing::Vips available"
end

check "ImageProcessing can perform operations on images" do
  url = "https://picsum.photos/id/237/536/354"
  image_processing_image = ImageProcessing::Vips
    .source(Vips::Image.new_from_buffer(TEST_IMAGE, ""))
    .resize_to_limit(123, 123)        # Resize to fit within 500x500
    .convert("webp")                  # Convert to webp format
    .saver(strip: true)               # Strip metadata
    .call
  processed_image = Vips::Image.new_from_file(image_processing_image.path)

  make_sure processed_image.present? && processed_image.width == 123 && processed_image.get("vips-loader") == "webpload" && !processed_image.get_fields.include?("exif-data"), "ImageProcessing can resize, remove metadata, and convert to webp"
end

# --- CACHE ---

check "Cache is accessible and functioning" do
  cache_value = "allgood_#{Time.now.to_i}"
  Rails.cache.write("allgood_health_check_test", cache_value, expires_in: 1.minute)
  make_sure Rails.cache.read("allgood_health_check_test") == cache_value, "The `allgood_health_check_test` key in the cache should return the string `#{cache_value}`"
end

# --- SYSTEM ---

check "Disk space usage is below 90%" do
  usage = `df -h / | tail -1 | awk '{print $5}' | sed 's/%//'`.to_i
  expect(usage).to_be_less_than(90)
end

check "Memory usage is below 90%" do
  usage = `free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1`.to_i
  expect(usage).to_be_less_than(90)
end
