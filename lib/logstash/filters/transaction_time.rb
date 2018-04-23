# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

# This  filter will replace the contents of the default 
# message field with whatever you specify in the configuration.
#
# It is only intended to be used as an .
class LogStash::Filters::TransactionTime < LogStash::Filters::Base

  # Setting the config_name here is required. This is how you
  # configure this filter from your Logstash config.
  #
  # filter {
  #    {
  #     message => "My message..."
  #   }
  # }
  #
  config_name "transaction_time"
  
  # The name of the UID-field used to identify transaction-pairs
  config :uid_field, :validate => :string, :required => true
  # The amount of time (in seconds) before a transaction is dropped. Defaults to 5 minutes
  config :timout, :validate => :number, :default => 300
  # What tag to use as timestamp when calculating the elapsed transaction time. Defaults to @timestamp
  config :timestamp_tag, :validate => :string, :default => "@timestamp"
  

  public
  def register
    # Add instance variables 
  end # def register

  public
  def filter(event)

    if @timestamp_tag
      # Replace the event message with our message as configured in the
      # config file.
      event.set("timestamp_tag", @timestamp_tag)
      event.set("uid_field", @uid_field)
    end

    # filter_matched should go in the last line of our successful code
    filter_matched(event)
  end # def filter
end # class LogStash::Filters::TransactionTime
