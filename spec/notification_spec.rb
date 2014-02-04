require 'spec_helper'
require 'securerandom'
require 'ostruct'

module ActiveRecord; class RecordNotFound < RuntimeError; end; end
class NestedException < StandardError; attr_accessor :original_exception; end
class BugsnagTestExceptionWithMetaData < Exception; include Bugsnag::MetaData; end

class Ruby21Exception < RuntimeError
  attr_accessor :cause
  def self.raise!(msg)
    e = new(msg)
    e.cause = $!
    raise e
  end
end

describe Bugsnag::Notification do
  it "should contain an api_key if one is set" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      payload[:apiKey].should be == "c9d60ae4c7e70c4b6c4ebd3e8056d2b8"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should not notify if api_key is not set" do
    Bugsnag.configuration.api_key = nil

    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should not notify if api_key is empty" do
    Bugsnag.configuration.api_key = ""

    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should use the env variable apiKey" do
    ENV["BUGSNAG_API_KEY"] = "c9d60ae4c7e70c4b6c4ebd3e8056d2b9"

    Bugsnag.instance_variable_set(:@configuration, Bugsnag::Configuration.new)
    Bugsnag.configure do |config|
      config.release_stage = "production"
    end

    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      payload[:apiKey].should be == "c9d60ae4c7e70c4b6c4ebd3e8056d2b9"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should allow overriding the api key" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      payload[:apiKey].should be == "0354ec4440b40aadb2d0ec22ccd1c1780c42dbb5"
    end

    Bugsnag.configuration.with_api_key("0354ec4440b40aadb2d0ec22ccd1c1780c42dbb5") do
      Bugsnag.notify(BugsnagTestException.new("It crashed"))
    end

    # TODO: assert the api key is reset
  end

  it "should have the right exception class" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:errorClass].should be == "BugsnagTestException"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should have the right exception message" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:message].should be == "It crashed"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should have a valid stacktrace" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:stacktrace].length.should be > 0
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should accept tabs in overrides and add them to metaData" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData][:some_tab].should_not be_nil
      event[:metaData][:some_tab][:info].should be == "here"
      event[:metaData][:some_tab][:data].should be == "also here"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :some_tab => {
        :info => "here",
        :data => "also here"
      }
    })
  end

  it "should accept non-hash overrides and add them to the custom tab in metaData" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData][:custom].should_not be_nil
      event[:metaData][:custom][:info].should be == "here"
      event[:metaData][:custom][:data].should be == "also here"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :info => "here",
      :data => "also here"
    })
  end

  it "should accept meta data from an exception that mixes in Bugsnag::MetaData" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData][:some_tab].should_not be_nil
      event[:metaData][:some_tab][:info].should be == "here"
      event[:metaData][:some_tab][:data].should be == "also here"
    end

    exception = BugsnagTestExceptionWithMetaData.new("It crashed")
    exception.bugsnag_meta_data = {
      :some_tab => {
        :info => "here",
        :data => "also here"
      }
    }

    Bugsnag.notify(exception)
  end
  
  it "should accept meta data from an exception that mixes in Bugsnag::MetaData, but override using the overrides" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData][:some_tab].should_not be_nil
      event[:metaData][:some_tab][:info].should be == "overridden"
      event[:metaData][:some_tab][:data].should be == "also here"
    end

    exception = BugsnagTestExceptionWithMetaData.new("It crashed")
    exception.bugsnag_meta_data = {
      :some_tab => {
        :info => "here",
        :data => "also here"
      }
    }

    Bugsnag.notify(exception, {:some_tab => {:info => "overridden"}})
  end
  
  it "should accept user_id from an exception that mixes in Bugsnag::MetaData" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:user][:id].should be == "exception_user_id"
    end

    exception = BugsnagTestExceptionWithMetaData.new("It crashed")
    exception.bugsnag_user_id = "exception_user_id"

    Bugsnag.notify(exception)
  end
  
  it "should accept user_id from an exception that mixes in Bugsnag::MetaData, but override using the overrides" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:user][:id].should be == "override_user_id"
    end

    exception = BugsnagTestExceptionWithMetaData.new("It crashed")
    exception.bugsnag_user_id = "exception_user_id"

    Bugsnag.notify(exception, {:user_id => "override_user_id"})
  end
  
  it "should accept context from an exception that mixes in Bugsnag::MetaData" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:context].should be == "exception_context"
    end

    exception = BugsnagTestExceptionWithMetaData.new("It crashed")
    exception.bugsnag_context = "exception_context"

    Bugsnag.notify(exception)
  end
  
  it "should accept context from an exception that mixes in Bugsnag::MetaData, but override using the overrides" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:context].should be == "override_context"
    end

    exception = BugsnagTestExceptionWithMetaData.new("It crashed")
    exception.bugsnag_context = "exception_context"

    Bugsnag.notify(exception, {:context => "override_context"})
  end

  it "should accept meta_data in overrides (for backwards compatibility) and merge it into metaData" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData][:some_tab].should_not be_nil
      event[:metaData][:some_tab][:info].should be == "here"
      event[:metaData][:some_tab][:data].should be == "also here"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :meta_data => {
        :some_tab => {
          :info => "here",
          :data => "also here"
        }
      }
    })
  end

  it "should truncate large meta_data before sending" do
    Bugsnag::Notification.should_receive(:post) do |endpoint, opts|
      # Truncated body should be no bigger than
      # 2 truncated hashes (4096*2) + rest of payload (5000)
      opts[:body].length.should be < 4096*2 + 5000
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :meta_data => {
        :some_tab => {
          :giant => SecureRandom.hex(500_000/2),
          :mega => SecureRandom.hex(500_000/2)
        }
      }
    })
  end

  it "should accept a severity in overrides" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:severity].should be == "info"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :severity => "info"
    })
  end

  it "should default to error severity" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:severity].should be == "error"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should not accept a bad severity in overrides" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:severity].should be == "error"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :severity => "infffo"
    })
  end

  it "should autonotify fatal errors" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:severity].should be == "fatal"
    end

    Bugsnag.auto_notify(BugsnagTestException.new("It crashed"))
  end

  it "should accept a context in overrides" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:context].should be == "test_context"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :context => "test_context"
    })
  end

  it "should accept a user_id in overrides" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:user][:id].should be == "test_user"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {
      :user_id => "test_user"
    })
  end

  it "should not send a notification if auto_notify is false" do
    Bugsnag.configure do |config|
      config.auto_notify = false
    end

    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    Bugsnag.auto_notify(BugsnagTestException.new("It crashed"))
  end

  it "should contain a release_stage" do
    Bugsnag.configure do |config|
      config.release_stage = "production"
    end

    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:app][:releaseStage].should be == "production"
    end

    Bugsnag.auto_notify(BugsnagTestException.new("It crashed"))
  end

  it "should respect the notify_release_stages setting by not sending in development" do
    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    Bugsnag.configuration.notify_release_stages = ["production"]
    Bugsnag.configuration.release_stage = "development"
    
    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should respect the notify_release_stages setting when set" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
    end

    Bugsnag.configuration.release_stage = "development"
    Bugsnag.configuration.notify_release_stages = ["development"]
    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should use the http://notify.bugsnag.com endpoint by default" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      endpoint.should be == "http://notify.bugsnag.com"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should use ssl when use_ssl is true" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      endpoint.should start_with "https://"
    end

    Bugsnag.configuration.use_ssl = true
    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should not use ssl when use_ssl is false" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      endpoint.should start_with "http://"
    end

    Bugsnag.configuration.use_ssl = false
    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should not use ssl when use_ssl is unset" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      endpoint.should start_with "http://"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should not mark the top-most stacktrace line as inProject if out of project" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:stacktrace].should have_at_least(1).items
      exception[:stacktrace].first[:inProject].should be_nil
    end

    Bugsnag.configuration.project_root = "/Random/location/here"
    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should mark the top-most stacktrace line as inProject if necessary" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:stacktrace].should have_at_least(1).items
      exception[:stacktrace].first[:inProject].should be == true
    end

    Bugsnag.configuration.project_root = File.expand_path File.dirname(__FILE__)
    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should add app_version to the payload if it is set" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:app][:version].should be == "1.1.1"
    end

    Bugsnag.configuration.app_version = "1.1.1"
    Bugsnag.notify(BugsnagTestException.new("It crashed"))
  end

  it "should filter params from all payload hashes if they are set in default params_filters" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData].should_not be_nil
      event[:metaData][:request].should_not be_nil
      event[:metaData][:request][:params].should_not be_nil
      event[:metaData][:request][:params][:password].should be == "[FILTERED]"
      event[:metaData][:request][:params][:other_password].should be == "[FILTERED]"
      event[:metaData][:request][:params][:other_data].should be == "123456"
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {:request => {:params => {:password => "1234", :other_password => "12345", :other_data => "123456"}}})
  end

  it "should filter params from all payload hashes if they are added to params_filters" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData].should_not be_nil
      event[:metaData][:request].should_not be_nil
      event[:metaData][:request][:params].should_not be_nil
      event[:metaData][:request][:params][:password].should be == "[FILTERED]"
      event[:metaData][:request][:params][:other_password].should be == "[FILTERED]"
      event[:metaData][:request][:params][:other_data].should be == "[FILTERED]"
    end

    Bugsnag.configuration.params_filters << "other_data"
    Bugsnag.notify(BugsnagTestException.new("It crashed"), {:request => {:params => {:password => "1234", :other_password => "123456", :other_data => "123456"}}})
  end

  it "should not filter params from payload hashes if their values are nil" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:metaData].should_not be_nil
      event[:metaData][:request].should_not be_nil
      event[:metaData][:request][:params].should_not be_nil
      event[:metaData][:request][:params].should have_key(:nil_param)
    end

    Bugsnag.notify(BugsnagTestException.new("It crashed"), {:request => {:params => {:nil_param => nil}}})
  end

  it "should not notify if the exception class is in the default ignore_classes list" do
    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    Bugsnag.notify_or_ignore(ActiveRecord::RecordNotFound.new("It crashed"))
  end

  it "should not notify if the non-default exception class is added to the ignore_classes" do
    Bugsnag.configuration.ignore_classes << "BugsnagTestException"

    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    Bugsnag.notify_or_ignore(BugsnagTestException.new("It crashed"))
  end

  it "should not notify if the exception is matched by an ignore_classes lambda function" do
    Bugsnag.configuration.ignore_classes << lambda {|e| e.message =~ /crashed/}

    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    Bugsnag.notify_or_ignore(BugsnagTestException.new("It crashed"))
  end

  it "should not notify if the user agent is present and matches a regex in ignore_user_agents" do
    Bugsnag.configuration.ignore_user_agents << %r{BugsnagUserAgent}

    Bugsnag::Notification.should_not_receive(:deliver_exception_payload)

    ((Thread.current["bugsnag_req_data"] ||= {})[:rack_env] ||= {})["HTTP_USER_AGENT"] = "BugsnagUserAgent"

    Bugsnag.notify_or_ignore(BugsnagTestException.new("It crashed"))
  end

  it "should send the cause of the exception" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:exceptions].should have(2).items
    end

    begin
      begin
        raise "jiminey"
      rescue
        Ruby21Exception.raise! "cricket"
      end
    rescue
      Bugsnag.notify $!
    end
  end

  it "should not unwrap the same exception twice" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:exceptions].should have(1).items
    end

    ex = NestedException.new("Self-referential exception")
    ex.original_exception = ex

    Bugsnag.notify_or_ignore(ex)
  end

  it "should not unwrap more than 5 exceptions" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      event = get_event_from_payload(payload)
      event[:exceptions].should have(5).items
    end

    first_ex = ex = NestedException.new("Deep exception")
    10.times do |idx|
      ex = ex.original_exception = NestedException.new("Deep exception #{idx}")
    end

    Bugsnag.notify_or_ignore(first_ex)
  end

  it "should call to_exception on i18n error objects" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:errorClass].should be == "BugsnagTestException"
      exception[:message].should be == "message"
    end

    Bugsnag.notify(OpenStruct.new(:to_exception => BugsnagTestException.new("message")))
  end

  it "should generate runtimeerror for non exceptions" do
    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:errorClass].should be == "RuntimeError"
      exception[:message].should be == "test message"
    end

    Bugsnag.notify("test message")
  end

  it "should support unix-style paths in backtraces" do
    ex = BugsnagTestException.new("It crashed")
    ex.set_backtrace([
      "/Users/james/app/spec/notification_spec.rb:419",
      "/Some/path/rspec/example.rb:113:in `instance_eval'"
    ])

    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:stacktrace].length.should be == 2

      line = exception[:stacktrace][0]
      line[:file].should be == "/Users/james/app/spec/notification_spec.rb"
      line[:lineNumber].should be == 419
      line[:method].should be nil

      line = exception[:stacktrace][1]
      line[:file].should be == "/Some/path/rspec/example.rb"
      line[:lineNumber].should be == 113
      line[:method].should be == "instance_eval"
    end

    Bugsnag.notify(ex)
  end

  it "should support windows-style paths in backtraces" do
    ex = BugsnagTestException.new("It crashed")
    ex.set_backtrace([
      "C:/projects/test/app/controllers/users_controller.rb:13:in `index'",
      "C:/ruby/1.9.1/gems/actionpack-2.3.10/filters.rb:638:in `block in run_before_filters'"
    ])

    Bugsnag::Notification.should_receive(:deliver_exception_payload) do |endpoint, payload|
      exception = get_exception_from_payload(payload)
      exception[:stacktrace].length.should be == 2

      line = exception[:stacktrace][0]
      line[:file].should be == "C:/projects/test/app/controllers/users_controller.rb"
      line[:lineNumber].should be == 13
      line[:method].should be == "index"

      line = exception[:stacktrace][1]
      line[:file].should be == "C:/ruby/1.9.1/gems/actionpack-2.3.10/filters.rb"
      line[:lineNumber].should be == 638
      line[:method].should be == "block in run_before_filters"
    end

    Bugsnag.notify(ex)
  end

  it "should use a proxy host if configured" do
    Bugsnag.configure do |config|
      config.proxy_host = "host_name"
    end

    Bugsnag::Notification.should_receive(:http_proxy) do |*args|
      args.length.should be == 4
      args[0].should be == "host_name"
      args[1].should be == nil
      args[2].should be == nil
      args[3].should be == nil
    end

    Bugsnag.notify("test message")
  end

  it "should use a proxy host/port if configured" do
    Bugsnag.configure do |config|
      config.proxy_host = "host_name"
      config.proxy_port = 1234
    end

    Bugsnag::Notification.should_receive(:http_proxy) do |*args|
      args.length.should be == 4
      args[0].should be == "host_name"
      args[1].should be == 1234
      args[2].should be == nil
      args[3].should be == nil
    end

    Bugsnag.notify("test message")
  end

  it "should use a proxy host/port/user/pass if configured" do
    Bugsnag.configure do |config|
      config.proxy_host = "host_name"
      config.proxy_port = 1234
      config.proxy_user = "user"
      config.proxy_password = "password"
    end

    Bugsnag::Notification.should_receive(:http_proxy) do |*args|
      args.length.should be == 4
      args[0].should be == "host_name"
      args[1].should be == 1234
      args[2].should be == "user"
      args[3].should be == "password"
    end

    Bugsnag.notify("test message")
  end

  it "should set the timeout time to the value in the configuration" do |*args|
    Bugsnag.configure do |config|
      config.timeout = 10
    end

    Bugsnag::Notification.should_receive(:default_timeout) do |*args|
      args.length.should be == 1
      args[0].should be == 10
    end

    Bugsnag.notify("test message")
  end
end
