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
#         release_expired => [true,false]
#         store_data_oldest => []
#         store_data_newest => []
#         periodic_flush => [true,false]
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
#         uid_field => "UID"
#         filter_tag => "Transaction"
#       }
#     }
#
# In the example, grok is used to identify the message_type and then the tag "transaction"
# is added for a specific set of messages. 
# This tag is then used in the transaction_time as filter_tag. 
# Only the messages with this tag will be evaluated.
# Note: Do not use reserved name "TransactionTime" 
#       which is added to all events created by this plugin
#
# The attach_event parameter can be used to append information from one of the events to the
# new transaction_time event. The default is to not attach anything. 
# The memory footprint is kept to a minimum by using the default value.
#
# The release_expired parameter determines if the first event in an expired transactions 
# should be released or not. Defaults to true
#
# The parameters store_data_oldest and store_data_newest are both used in order to attach 
# specific fields from oldest respectively newest event. An example of this could be:
# 
#    store_data_oldest => ["@timestamp", "work_unit", "work_center", "message_type"]
#    store_data_newest => ["@timestamp", "work_unit", "work_center", "message_type"]
# 
# Which will result in the genereated transaction event inluding the specified fields from 
# oldest and newest events in a hashmap named oldest/newest under the hash named "transaction_data"
# Example of output data:
# "transaction_data" => {
#        "oldest" => {
#            "message_type" => "MaterialIdentified",
#              "@timestamp" => 2018-10-31T07:36:23.072Z,
#               "work_unit" => "WT000743",
#             "work_center" => "WR000046"
#        },
#        "newest" => {
#            "message_type" => "Recipe",
#              "@timestamp" => 2018-10-31T07:36:28.188Z,
#               "work_unit" => "WT000743",
#             "work_center" => "WR000046"
#        }
#    }



class LogStash::Filters::TransactionTime < LogStash::Filters::Base

  HOST_FIELD = "host"
  TRANSACTION_TIME_TAG = "TransactionTime"
  TRANSACTION_TIME_DATA = "transaction_data"
  TRANSACTION_TIME_EXPIRED_TAG = "TransactionTimeExpired"
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
  # Do not use reserved tag name "TransactionTime"
  config :filter_tag, :validate => :string
  # Whether or not to attach one or none of the events in a transaction to the output event. 
  # Defaults to 'none' - which reduces memory footprint by not adding the event to the transactionlist.
  config :attach_event, :validate => ['first','last','oldest','newest','none'], :default => 'none'
  # Wheter or not to release the first event in expired transactions
  config :release_expired, :validate => :boolean, :default => true

  # Store data from the oldest message. Specify array of keys to store.
  config :store_data_oldest, :validate => :array, :default => []
  # Store data from the newest message. Specify array of keys to store
  config :store_data_newest, :validate => :array, :default => []

  # This filter must have its flush function called periodically to be able to purge
  # expired stored start events.
  config :periodic_flush, :validate => :boolean, :default => true

  public
  def register
    # Add instance variables 
    @transactions = Hash.new
    @mutex = Mutex.new
    @attachData = (!@store_data_oldest.nil? && @store_data_oldest.any?) || (!@store_data_newest.nil? && @store_data_newest.any?)
    @storeEvent = (!(@attach_event.eql?"none") || @attachData)
    @@timestampTag = @timestamp_tag
    @logger.info("Setting up INFO")
    @logger.debug("Setting up DEBUG")
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


    #Dont use filter-plugin on events created by this filter-plugin
    #Dont use filter on anything else but events with the filter_tag if specified
    if (!uid.nil? && (event.get("tags").nil? || !event.get("tags").include?(TRANSACTION_TIME_TAG)) && 
      (event.get("tags").nil? || !event.get("tags").include?(TRANSACTION_TIME_EXPIRED_TAG)) &&
      (@filter_tag.nil? || (!event.get("tags").nil? && event.get("tags").include?(@filter_tag))))
      

      @mutex.synchronize do
        if(!@transactions.has_key?(uid))
          @transactions[uid] = LogStash::Filters::TransactionTime::Transaction.new(event, uid, @storeEvent)

        else #End of transaction
          @transactions[uid].addSecond(event,@storeEvent)
          transaction_event = new_transactiontime_event(@transactions[uid], @attachData)
          filter_matched(transaction_event)
          yield transaction_event if block_given?
          @transactions.delete(uid)
        end
      end
    end
    #Always forward original event
    filter_matched(event) 
    return event

  end # def filter


  # The method is invoked by LogStash every 5 seconds.
  def flush(options = {})
    expired_elements = []
    #@logger.info("FLUSH")
    @mutex.synchronize do
      increment_age_by(5)
      expired_elements = remove_expired_elements()
    end

    expired_elements.each do |element|
      filter_matched(element)
    end
    return expired_elements
    #yield expired_elements if block_given?
    #return create_expired_events_from(expired_elements)
  end

  private
  def increment_age_by(seconds)
    @transactions.each_pair do |key, transaction|
      transaction.age += seconds
    end
  end

  # Remove the expired "events" from the internal
  # buffer and return them.
  def remove_expired_elements()
    expired = []
    @transactions.delete_if do |key, transaction|
      if(transaction.age >= @timeout)
        #print("Deleting expired_elements")
        transaction.tag(TRANSACTION_TIME_EXPIRED_TAG)
        (expired << transaction.getEvents()).flatten!
        next true
      end
      next false
    end
    return expired
  end

  def new_transactiontime_event(transaction, attachData)


      case @attach_event
      when 'oldest'
        transaction_event = transaction.getOldestEvent()
      when 'first'
        transaction_event = transaction.firstEvent
      when 'newest'
        transaction_event = transaction.getNewestEvent()
      when 'last'
        transaction_event = transaction.lastEvent
      else
        transaction_event = LogStash::Event.new
      end
      transaction_event.set(HOST_FIELD, Socket.gethostname)


      transaction_event.tag(TRANSACTION_TIME_TAG)
      transaction_event.set(TRANSACTION_TIME_FIELD, transaction.diff)
      transaction_event.set(TRANSACTION_UID_FIELD, transaction.uid)
      transaction_event.set(TIMESTAMP_START_FIELD, transaction.getOldestTimestamp())

      #Attach transaction data if any
      if(attachData)
        transaction_data = transaction.getData(store_data_oldest,store_data_newest)
        transaction_event.set(TRANSACTION_TIME_DATA,transaction_data)
      end

      if(@replace_timestamp.eql?'oldest')
        transaction_event.set("@timestamp", transaction.getOldestTimestamp())
      elsif (@replace_timestamp.eql?'newest')
        transaction_event.set("@timestamp", transaction.getNewestTimestamp())
      end

      return transaction_event
  end


end # class LogStash::Filters::TransactionTime







class LogStash::Filters::TransactionTime::Transaction
  attr_accessor :firstEvent, :lastEvent,:firstTimestamp, :secondTimestamp, :uid, :age, :diff, :data

  def initialize(firstEvent, uid, storeEvent = false)
    if(storeEvent)
      @firstEvent = firstEvent
    end
    @firstTimestamp = firstEvent.get(LogStash::Filters::TransactionTime.timestampTag)
    @uid = uid
    @age = 0
  end

  def getData(oldestKeys, newestKeys)
    if(oldestKeys.any?)
      storeData("oldest",oldestKeys,getOldestEvent())
    end
    if(newestKeys.any?)
      storeData("newest",newestKeys,getNewestEvent())
    end
    return @data
  end

  def storeData(subDataName, dataKeys, dataEvent)
    if(@data.nil?)
      @data = Hash.new
    end

    if(@data[subDataName].nil?)
      hashData = Hash.new
    else
      hashData = @data.get(subDataName)
    end

    dataKeys.each do |dataKey|
      hashData[dataKey] = dataEvent.get(dataKey)
      @data[subDataName] = hashData
    end
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

  def tag(value)
    if(!firstEvent.nil?)
      firstEvent.tag(value)
    end
    if(!lastEvent.nil?)
      lastEvent.tag(value)
    end
  end

  def getEvents()
    events = []
    if(!firstEvent.nil?)
      events << firstEvent
    end
    if(!lastEvent.nil?)
      events << lastEvent
    end
    return events
  end
end
