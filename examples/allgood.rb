require 'open-uri'
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

check "Vips (libvips) is installed on Linux", except: :development do
  output = `ldconfig -p | grep libvips`
  make_sure output.present? && output.include?("libvips.so") && output.include?("libvips-cpp.so"), "libvips is found in the Linux system's library cache"
end

check "Vips is available to Rails" do
  throw "ImageProcessing::Vips is not available" if !ImageProcessing::Vips.present? # Need this line to load `Vips`

  make_sure Vips::VERSION.present?, "Vips available with version #{Vips::VERSION}"
end

check "Vips can perform operations on images" do
  throw "ImageProcessing::Vips is not available" if !ImageProcessing::Vips.present? # Need this line to load `Vips`

  image = Vips::Image.new_from_buffer(TEST_IMAGE, "")
  processed_image = image
    .gaussblur(10)                   # Apply Gaussian blur with sigma 10
    .linear([1.2], [0])              # Increase brightness
    .invert                          # Invert colors for a wild effect
    .sharpen                         # Apply sharpening
    .resize(0.5)

  make_sure processed_image.present? && processed_image.width == 268 && processed_image.height == 177, "If we input an image of 536x354px, and we apply filters and a 0.5 resize, we should get an image of 268x177px"
end

check "ImageProcessing::Vips is available to Rails" do
  make_sure ImageProcessing::Vips.present?
end

check "ImageProcessing can perform operations on images" do
  image_processing_image = ImageProcessing::Vips
    .source(Vips::Image.new_from_buffer(TEST_IMAGE, ""))
    .resize_to_limit(123, 123)        # Resize to fit within 500x500
    .convert("webp")                  # Convert to webp format
    .call
  processed_image = Vips::Image.new_from_file(image_processing_image.path)

  make_sure processed_image.present? && processed_image.width == 123 && processed_image.get("vips-loader") == "webpload", "ImageProcessing can resize and convert to webp"
end

# --- ACTIVE STORAGE ---

check "Active Storage is available to Rails" do
  make_sure ActiveStorage.present?
end

check "Active Storage tables are present in the database" do
  make_sure ActiveRecord::Base.connection.table_exists?("active_storage_attachments") && ActiveRecord::Base.connection.table_exists?("active_storage_blobs")
end

check "Active Storage has a valid client configured" do
  service = ActiveStorage::Blob.service
  service_name = service&.class&.name&.split("::")&.last&.split("Service")&.first

  if !service_name.downcase.include?("disk")
    make_sure service.present? && service.respond_to?(:client) && service.client.present?, "Active Storage service has a valid #{service_name} client configured"
  else
    make_sure !Rails.env.production? && service.present?, "Active Storage using #{service_name} service in #{Rails.env.to_s}"
  end
end

check "ActiveStorage can store images, retrieve them, and purge them" do
  blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(TEST_IMAGE), filename: "allgood-test-image-#{Time.now.to_i}.jpg", content_type: "image/jpeg")
  make_sure blob.persisted? && blob.service.exist?(blob.key) && blob.purge, "Image was successfully stored, retrieved, and purged from #{ActiveStorage::Blob.service.class.name}"
end

# --- CACHE ---

check "Cache is accessible and functioning" do
  cache_value = "allgood_#{Time.now.to_i}"
  Rails.cache.write("allgood_health_check_test", cache_value, expires_in: 1.minute)
  make_sure Rails.cache.read("allgood_health_check_test") == cache_value, "The `allgood_health_check_test` key in the cache should return the string `#{cache_value}`"
end

# --- SOLID QUEUE ---

check "SolidQueue is available to Rails" do
  make_sure SolidQueue.present?
end

check "We have an active SolidQueue connection to the database" do
  make_sure SolidQueue::Job.connection.connect!.active?
end

check "SolidQueue tables are present in the database" do
  make_sure SolidQueue::Job.connection.table_exists?("solid_queue_jobs") && SolidQueue::Job.connection.table_exists?("solid_queue_failed_executions") && SolidQueue::Job.connection.table_exists?("solid_queue_semaphores")
end

check "The percentage of failed jobs in the last 24 hours is less than 1%", only: :production do
  failed_jobs = SolidQueue::FailedExecution.where(created_at: 24.hours.ago..Time.now).count
  all_jobs = SolidQueue::Job.where(created_at: 24.hours.ago..Time.now).count

  if all_jobs > 10
    percentage = all_jobs > 0 ? (failed_jobs.to_f / all_jobs.to_f * 100) : 0
    make_sure percentage < 1, "#{percentage.round(2)}% of jobs are failing"
  else
    make_sure true, "Not enough jobs to calculate meaningful failure rate (only #{all_jobs} jobs in last 24h)"
  end
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

# --- USAGE-DEPENDENT CHECKS ---

check "SolidQueue has processed jobs in the last 24 hours", only: :production do
  make_sure SolidQueue::Job.where(created_at: 24.hours.ago..Time.now).order(created_at: :desc).limit(1).any?
end

# --- PAY / STRIPE ---

# TODO: no error webhooks in the past 24 hours, new sales in the past few hours, etc.
