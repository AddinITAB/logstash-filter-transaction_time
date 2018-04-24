# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

# This  filter will replace the contents of the default 
# message field with whatever you specify in the configuration.
#
# It is only intended to be used as an .
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
  config :attach_event, :validate => ['first','second','oldest','newest','none'], :default => 'none'

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
    return firstTimestamp.nil? || secondTimestamp.nil? || @firstEvent.nil? || @lastEvent.nil?
  end

  def calculateDiff()
    if invalidTransaction()
      return nil
    end

    return getNewestTimestamp() - getOldestTimestamp()
  end
end
