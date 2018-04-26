# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

# The TransactionTime filter measures the time between two events in a transaction
#
# This filter is supposed to be used instead of logstash-filters-elapsed
# when you know that the order of a transaction cannot be guaranteed.
# Which is most likely the case if you are using multiple workers and 
# a big amount of events are entering the pipeline in a rapid manner.
#
# # The configuration looks like this:
# [source,ruby]
#     filter {
#       transaction_time {
#         uid_field => "Transaction-unique field"
#         timeout => seconds
#         timestamp_tag => "name of timestamp"
#         replace_timestamp => ['keep', 'oldest', 'newest']
#         filter_tag => "transaction tag"
#         attach_event => ['first','last','oldest','newest','none']
#       }
#     }
#
#
# The only required parameter is "uid_field" which is used to identify
# the events in a transaction. A transaction is concidered complete 
# when two events with the same UID has been captured. 
# It is when a transaction completes that the transaction time is calculated.
# 
# The timeout parameter determines the maximum length of a transaction. 
# It is set to 300 (5 minutes) by default. 
# The transaction will not be recorded if timeout duration is exceeded.
# The value of this parameter will have an impact on the memory footprint of the plugin.
#
# The timestamp_tag parameter may be used to select a specific field in the events to use
# when calculating the transaction time. The default field is @timestamp.
# 
# The new event created when a transaction completes may set its own timestamp (default)
# to when it completes or it may use the timestamp of one of the events in the transaction.
# The parameter replace_timestamp is used specify this behaviour.
#
# Since this plugin exclusivly calculates the time between events in a transaction,
# it may be wise to filter out the events that are infact not transactions.
# This will help reduce both the memory footprint and processing time of this plugin, 
# especially if the pipeline receives a lot of non-transactional events.
# You could use grok and/or mutate to apply this filter like this:
# [source,ruby]
#     filter {
#       grok{
#         match => { "message" => "(?<message_type>.*)\t(?<msgbody>.*)\t+UID:%{UUID:uid}" }
#       }
#       if [message_type] in ["MaterialIdentified","Recipe","Result"."ReleaseMaterial"]{
#         mutate {
#           add_tag => "Transaction"
#         }
#       }
#       transaction_time {
#         uid_field => "Transaction-unique field"
#         filter_tag => "transaction tag"
#       }
#     }
#
# In the example, grok is used to identify the message_type and then the tag "transaction"
# is added for a specific set of messages. 
# This tag is then used in the transaction_time as filter_tag. 
# Only the messages with this tag will be evaluated.
#
# The attach_event parameter can be used to append information from one of the events to the
# new transaction_time event. The default is to not attach anything. 
# The memory footprint is kept to a minimum by using the default value.

class LogStash::Filters::TransactionTime < LogStash::Filters::Base

  HOST_FIELD = "host"
  TRANSACTION_TIME_TAG = "TransactionTime"
  TRANSACTION_TIME_FIELD = "transaction_time"
  TRANSACTION_UID_FIELD = "transaction_uid"
  TIMESTAMP_START_FIELD = "timestamp_start"

  config_name "transaction_time"
  
  # The name of the UID-field used to identify transaction-pairs
  config :uid_field, :validate => :string, :required => true
  # The amount of time (in seconds) before a transaction is dropped. Defaults to 5 minutes
  config :timeout, :validate => :number, :default => 300
  # What tag to use as timestamp when calculating the elapsed transaction time. Defaults to @timestamp
  config :timestamp_tag, :validate => :string, :default => "@timestamp"
  # Override the new events timestamp with the oldest or newest timestamp or keep the new one (set when logstash has processed the event)
  config :replace_timestamp, :validate => ['keep', 'oldest', 'newest'], :default => 'keep'
  # Tag used to identify transactional events. If set, only events tagged with the specified tag attached will be concidered transactions and be processed by the plugin
  config :filter_tag, :validate => :string
  # Whether or not to attach one or none of the events in a transaction to the output event. 
  # Defaults to 'none' - which reduces memory footprint by not adding the event to the transactionlist.
  config :attach_event, :validate => ['first','last','oldest','newest','none'], :default => 'none'

  public
  def register
    # Add instance variables 
    @transactions = Hash.new
    @mutex = Mutex.new
    @storeEvent = !(@attach_event.eql?"none")
    @@timestampTag = @timestamp_tag
  end # def register

  def transactions
      @transactions
  end
  def self.timestampTag
    @@timestampTag
  end

  public
  def filter(event)
    
    uid = event.get(@uid_field)
    #return if uid.nil?

    @logger.debug("Received UID", uid: uid)

    if (@filter_tag.nil? || (!event.get("tags").nil? && event.get("tags").include?(@filter_tag)))
      @mutex.synchronize do
        if(!@transactions.has_key?(uid))
          @transactions[uid] = LogStash::Filters::TransactionTime::Transaction.new(event, uid, @storeEvent)
        else #End of transaction
          @transactions[uid].addSecond(event,@storeEvent)
          transaction_event = new_transactiontime_event(@transactions[uid])
          filter_matched(transaction_event)
          yield transaction_event if block_given?
          @transactions.delete(uid)
        end
      end
    end

    event.set("uid_field", @uid_field)

    # filter_matched should go in the last line of our successful code
    filter_matched(event)
  end # def filter


  # The method is invoked by LogStash every 5 seconds.
  def flush(options = {})
    expired_elements = []

    @mutex.synchronize do
      increment_age_by(5)
      expired_elements = remove_expired_elements()
    end

    #return create_expired_events_from(expired_elements)
  end

  private
  def increment_age_by(seconds)
    @transactions.each_pair do |key, transaction|
      transaction.age += seconds
    end
  end

  # Remove the expired "start events" from the internal
  # buffer and return them.
  def remove_expired_elements()
    expired = []
    @transactions.delete_if do |key, transaction|
      if(transaction.age >= @timeout)
        expired << transaction
        next true
      end
      next false
    end
    return expired
  end

  def new_transactiontime_event(transaction)
      case @attach_event
      when 'oldest'
        event = transaction.getOldestEvent()
      when 'first'
        event = transaction.firstEvent
      when 'newest'
        event = transaction.getNewestEvent()
      when 'last'
        event = transaction.lastEvent
      else 
        event = LogStash::Event.new
      end
      event.set(HOST_FIELD, Socket.gethostname)

      event.tag(TRANSACTION_TIME_TAG)
      event.set(TRANSACTION_TIME_FIELD, transaction.diff)
      event.set(TRANSACTION_UID_FIELD, transaction.uid)
      event.set(TIMESTAMP_START_FIELD, transaction.getOldestTimestamp())

      if(@replace_timestamp.eql?'oldest')
        event.set("@timestamp", transaction.getOldestTimestamp())
      elsif (@replace_timestamp.eql?'newest')
        event.set("@timestamp", transaction.getNewestTimestamp())
      end
          

      return event
  end


end # class LogStash::Filters::TransactionTime







class LogStash::Filters::TransactionTime::Transaction
  attr_accessor :firstEvent, :lastEvent,:firstTimestamp, :secondTimestamp, :uid, :age, :diff

  def initialize(firstEvent, uid, storeEvent = false)
    if(storeEvent)
      @firstEvent = firstEvent
    end
    @firstTimestamp = firstEvent.get(LogStash::Filters::TransactionTime.timestampTag)
    @uid = uid
    @age = 0
  end

  def addSecond(lastEvent,storeEvent = false)
    if(storeEvent)
      @lastEvent = lastEvent
    end
    @secondTimestamp = lastEvent.get(LogStash::Filters::TransactionTime.timestampTag)
    @diff = calculateDiff()
  end

  #Gets the first (based on timestamp) event
  def getOldestEvent() 
    if invalidTransaction()
      return nil
    end

    if(@firstTimestamp < @secondTimestamp)
      return @firstEvent
    else
      return @lastEvent
    end
  end

  def getOldestTimestamp()
    return [@firstTimestamp,@secondTimestamp].min
  end

  #Gets the last (based on timestamp) event
  def getNewestEvent() 
    if invalidTransaction()
      return nil
    end
    if(@firstTimestamp > @secondTimestamp)
      return @firstEvent
    else
      return @lastEvent
    end
  end

  def getNewestTimestamp()
    return [@firstTimestamp,@secondTimestamp].max
  end

  def invalidTransaction()
    return firstTimestamp.nil? || secondTimestamp.nil?
  end

  def calculateDiff()
    if invalidTransaction()
      return nil
    end

    return getNewestTimestamp() - getOldestTimestamp()
  end
end
