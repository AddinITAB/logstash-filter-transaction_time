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
    @transactions = Hash.new
    @mutex = Mutex.new
  end # def register

  def transactions
      @transactions
  end

  public
  def filter(event)
    
    uid = event.get(@uid_field)
    #return if uid.nil?

    @logger.debug("Received UID", uid: uid)
    @mutex.synchronize do
        if(!@transactions.has_key?(uid))
          @transactions[uid] = LogStash::Filters::TransactionTime::Transaction.new(event)
        else
          @transactions[uid].addSecond(event)
          
          #@transactions.delete(uid)
        end

    end

    event.set("uid_field", @uid_field)
    if @timestamp_tag
      # Replace the event message with our message as configured in the
      # config file.
      event.set("timestamp_tag", @timestamp_tag)
    end

    # filter_matched should go in the last line of our successful code
    filter_matched(event)
  end # def filter
end # class LogStash::Filters::TransactionTime


class LogStash::Filters::TransactionTime::Transaction
  attr_accessor :a, :b, :age, :diff

  def initialize(firstEvent)
    @a = firstEvent
    @age = 0
  end

  def addSecond(secondEvent)
    @b = secondEvent
    @diff = calculateDiff()
  end

  def calculateDiff()
    elapsed = @b.get("@timestamp") - @a.get("@timestamp")
    return elapsed
  end
end


#Hashmap of transactions. Key: UID, Value: Transaction
#Transaction. Element a, Element b, age
#Element. event


#Look for transaction UID in hash.
# Not there? Create one. Set age = now. Add first element to transaction
# There? Add second element to transaction, calculate diff.