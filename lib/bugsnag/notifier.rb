module Bugsnag
  class Notifier
    def initialize(configuration)
      @configuration = configuration
    end

    def deliver_or_ignore(exception, overrides = nil, request_data = nil)
      notification = Notification.new(exception, @configuration, overrides, request_data)

      unless notification.ignore?
        notification.deliver
        notification
      else
        false
      end
    end

    def deliver(exception, overrides = nil, request_data = nil)
      Notification.new(exception, @configuration, overrides, request_data).deliver
    end
  end
end
