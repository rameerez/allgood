# ✅ Allgood - Rails gem for health checks

Add quick, simple and beautiful health checks to your Rails application.

`allgood` allows you to define custom, business-oriented health checks (like: are there any new users in the past 24 hours, are they posting, does the last post have all the attributes we expect, etc.) in a very intuitive way that reads just like English – and provides a `/healthcheck` endpoint that displays the results in a beautiful page.

You can then use that endpoint to monitor the health of your application via UptimeRobot, Pingdom, etc. These services will load your `/healthcheck` page every few minutes, so all checks will be run when UptimeRobot fetches the page.

![alt text](allgood.jpeg)

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

The `/healthcheck` page returns a `200` HTTP code if all checks are successful – and error `503 Service Unavailable` otherwise.

`allgood` is also a nice replacement for the default `/up` Rails action, so Kamal to also checks things like if the database connection is good. Just change the mounting route to `/up` instead of `/healthcheck`


### Configuring Health Checks

Create a file `config/allgood.rb` in your Rails application. This is where you'll define your health checks:
```ruby
# config/allgood.rb

check "We have an active database connection" do
  make_sure ActiveRecord::Base.connection.active?
end
```

As you can see, there's a very simple DSL (Domain-Specific Language) you can use to define health checks. It reads almost like natural English, and allows you to define powerful yet simple checks to make sure your app is healthy.

Other than checking for an active database connection, it's useful to check whether your app has gotten any new users in the past 24 hours (to make sure your signup flow is not broken), check whether there has been any new posts / records created recently (to make sure your users are performing the actions you'd expect them to do in your app), check for external API connections, check whether new records contain values within expected range, etc.

Some other health check examples that you'd need to adapt to the specifics of your particular app:
```ruby
check "The Redis connection replies to 'ping' with 'PONG'" do
  make_sure ActiveRecord::Base.connection.active?
end

check "There's been new signups in the past 24 hours" do
  count = User.where(created_at: 24.hours.ago..Time.now).count
  expect(count).to_be_greater_than(0)
end

check "The last created Purchase has a valid total" do
  last_purchase = Purchase.order(created_at: :desc).limit(1).first
  make_sure last_purchase.total.is_a?(Numeric), "Purchase total should be a number"
  expect(last_purchase.total).to_be_greater_than(0)
end
```

Make sure to restart the Rails server every time you modify the `config/allgood.rb` file for the config to reload so the changes apply.


### Available Check Methods

- `make_sure(condition, message = nil)`: Ensures that the given condition is true.
- `expect(actual).to_eq(expected)`: Checks if the actual value equals the expected value.
- `expect(actual).to_be_greater_than(expected)`: Checks if the actual value is greater than the expected value.

Please help us develop by adding more expectation methods in the `Expectation` class!

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