# Allgood

Add quick health checks to your Rails application.

You to define custom health checks (like: are there any new users in the past 24 hours, does the last post have all the attributes we expect, etc.) – and provides a `/healthcheck` endpoint that displays the results.

You can use that endpoint to monitor the health of your application via UptimeRobot, Pingdom, etc.

## Installation

Add this line to your application's Gemfile:
```ruby
gem 'allgood'
```

Then run `bundle install`.

## Usage

### Mounting the Engine

In your `config/routes.rb` file, mount the Allgood engine:
```ruby
mount Allgood::Engine => '/healthcheck'
```

You can now navigate to `/healthcheck` to see the health check results.


### Configuring Health Checks

Create a file `config/allgood.rb` in your Rails application. This is where you'll define your health checks:
```ruby
check "We have an active database connection" do
  make_sure ActiveRecord::Base.connection.active?
end

check "There's been new signups in the past 24 hours" do
  count = Guess.where(created_at: 24.months.ago..Time.now).count
  expect(count).to_be_greater_than(0)
end

check "The last created Order has a valid total" do
  last_order = Order.order(created_at: :desc).limit(1).first
  make_sure last_order.total.is_a?(Numeric), "Order total should be a number"
  expect(last_order.total).to_be_greater_than(0)
end
```


### Available Check Methods

- `make_sure(condition, message = nil)`: Ensures that the given condition is true.
- `expect(actual).to_eq(expected)`: Checks if the actual value equals the expected value.
- `expect(actual).to_be_greater_than(expected)`: Checks if the actual value is greater than the expected value.

You can add more expectation methods as needed in the `Expectation` class.

### Viewing Health Check Results

Once configured, you can view your health check results by visiting `/healthcheck` in your browser. The page will display the status of each check, including any error messages for failed checks.

## Customization

### Timeout

By default, each check has a timeout of 10 seconds.


## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/allgood Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).