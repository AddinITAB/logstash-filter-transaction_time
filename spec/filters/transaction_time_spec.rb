# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/transaction_time"


describe LogStash::Filters::TransactionTime do
  UID_FIELD = "uniqueIdField"

  TIMEOUT = 30


  describe "Set to Hello World" do
    let(:config) do <<-CONFIG
      filter {
        transaction_time {
          timestamp_tag => "@timestamp"
          uid_field => "uid"
        }
      }
    CONFIG
    end

    sample("timestamp_tag" => "testing") do
      expect(subject).to include("timestamp_tag")
      expect(subject.get('timestamp_tag')).to eq('testing')
    end

    sample("uid_field" => "uid") do
      expect(subject).to include("uid_field")
      expect(subject.get('uid_field')).to eq('uid')
    end
  end

  def event(data)
    data["message"] ||= "Log message"
    LogStash::Event.new(data)
  end

  before(:each) do
    setup_filter()
  end

  def setup_filter(config = {})
    @config = {"uid_field" => UID_FIELD, "timeout" => TIMEOUT, "attach_event" => 'first'}
    @config.merge!(config)
    @filter = LogStash::Filters::TransactionTime.new(@config)
    @filter.register
  end

  context "Testing Hash with UID. " do
    describe "Receiving" do
      uid = "D7AF37D9-4F7F-4EFC-B481-06F65F75E8C0"
      uid2 = "5DE49829-5CD3-4103-8062-781AC63BE4F5"
      describe "one event" do
        it "records the transaction" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          #insist { @filter.events[uid] } == "HEJ"
          insist { @filter.transactions.size } == 1
          insist { @filter.transactions[uid].firstEvent } != nil
          insist { @filter.transactions[uid].lastEvent } == nil
        end
      end
      describe "and events with the same UID" do
        it "completes and removes transaction" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          insist { @filter.transactions.size } == 0
          insist { @filter.transactions[uid] } == nil
        end
      end
      describe "and events with different UID" do
        it "increases the number of transactions to two" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid2))
          insist { @filter.transactions.size } == 2
          insist { @filter.transactions[uid].firstEvent } != nil
          insist { @filter.transactions[uid].lastEvent } == nil
          insist { @filter.transactions[uid2].firstEvent } != nil
          insist { @filter.transactions[uid2].lastEvent } == nil
        end
      end
    end
  end

  context "Testing TransactionTime. " do
    describe "Receiving" do
      uid = "D7AF37D9-4F7F-4EFC-B481-06F65F75E8CC"
      describe "two events with the same UID in cronological order" do
        it "calculates TransactionTime with last presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("transaction_time") } == 1.0
          end
          insist { @filter.transactions.size } == 0
          insist { @filter.transactions[uid] } == nil
        end
        it "calculates TransactionTime with ms presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.001+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("transaction_time") } == 0.999
          end
          insist { @filter.transactions.size } == 0
          insist { @filter.transactions[uid] } == nil
        end
      end
      describe "two events with the same UID in REVERSED cronological order" do
        it "calculates TransactionTime with last presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.000+0100"))do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("transaction_time") } == 1.0
          end
          insist { @filter.transactions.size } == 0
          insist { @filter.transactions[uid] } == nil
        end
        it "calculates TransactionTime with ms presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.001+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("transaction_time") } == 0.999
          end
          insist { @filter.transactions.size } == 0
          insist { @filter.transactions[uid] } == nil
        end
      end
    end
  end #end context Testing TransactionTime

  context "Testing flush. " do
    uid = "D7AF37D9-4F7F-4EFC-B481-06F65F75E8CC"
    uid2 = "C27BBC4C-6456-4581-982E-7497B4C7E754"
    describe "Call flush enough times" do
      it "flushes all old transactions" do
        @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 1
        @filter.filter(event("message" => "Log message", UID_FIELD => uid2, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 2
        ((TIMEOUT/5)-1).times do
          @filter.flush()
        end 
        insist { @filter.transactions.size } == 2
        @filter.flush()
        insist { @filter.transactions.size } == 0
      end
      it "releases the transactions to output" do
        @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 1
        @filter.filter(event("message" => "Log message", UID_FIELD => uid2, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 2
        ((TIMEOUT/5)-1).times do
          @filter.flush()
        end 
        counter = 0
        @filter.flush().each do |event|
          counter+=1
          #print(event)
        end
        insist { counter } == 2
      end
      it "does not flush newer transactions" do
        @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 1
        ((TIMEOUT/5)-1).times do
          @filter.flush()
        end 
        @filter.filter(event("message" => "Log message", UID_FIELD => uid2, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 2
        @filter.flush()
        insist { @filter.transactions.size } == 1
      end
    end
    describe "Setup release_expired = false" do
      it "never releases any expired events when flush is called" do
        config = {"release_expired" => false}
        @config.merge!(config)

        @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 1
        @filter.filter(event("message" => "Log message", UID_FIELD => uid2, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        insist { @filter.transactions.size } == 2

        #Looks like flush doesn't have config-scope. Setting release_expired hard instead of by config. Will it work like intended when using only config?
        @filter.release_expired = false
        ((TIMEOUT/5)+1).times do
          flushRes = @filter.flush({"from" => "test" })
          insist { (flushRes.any?) } == false
          #insist { @filter.flush().nil? }
        end 
        insist { @filter.transactions.size } == 0
      end
    end
  end

  context "Testing Timestamp Override." do
    uid = "D7AF37D9-4F7F-4EFC-B481-06F65F75E8CC"
    describe "Two events with the same UID" do
      describe "When config set to replace_timestamp => oldest" do
        it "sets the timestamp to the oldest" do
          config = {"replace_timestamp" => 'oldest'}
          @config.merge!(config)


          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("@timestamp").to_s } == LogStash::Timestamp.parse_iso8601("2018-04-22T09:46:22.000+0100").to_s
          end
        end
      end
      describe "When config set to replace_timestamp => newest" do
        it "sets the timestamp to the newest" do
          config = {"replace_timestamp" => 'newest'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("@timestamp").to_s } == LogStash::Timestamp.parse_iso8601("2018-04-22T09:46:22.100+0100").to_s
          end
        end
      end
    end
  end

  context "Testing filter_tag." do
    uid = "D7AF37D9-4F7F-4EFC-B481-06F65F75E8CC"
    uid2 = "58C8B705-49C5-4269-92D9-2C959599534C"
    describe "Incoming events with different UID" do
      describe "only two tagged with specified 'filter_tag'" do
        it "registers only two transactions" do
          config = {"filter_tag" => 'transaction'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          insist { @filter.transactions.size } == 0
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100", "tags" => ['transaction']))
          insist { @filter.transactions.size } == 1
          @filter.filter(event("message" => "Log message", UID_FIELD => uid2, "@timestamp" => "2018-04-22T09:46:22.100+0100"))
          insist { @filter.transactions.size } == 1
          @filter.filter(event("message" => "Log message", UID_FIELD => uid2, "@timestamp" => "2018-04-22T09:46:22.100+0100", "tags" => ['unrelated']))
          insist { @filter.transactions.size } == 1
          @filter.filter(event("message" => "Log message", UID_FIELD => uid2, "@timestamp" => "2018-04-22T09:46:22.100+0100", "tags" => ['transaction']))
          insist { @filter.transactions.size } == 2
        end
      end
    end
  end

  context "Testing attach_event." do
    uid = "9ACCA7B7-D0E9-4E52-A023-9D588E5BE42C"
    describe "Config attach_event" do
      describe "with 'first'" do
        it "attaches info from first event in transaction" do
          config = {"attach_event" => 'first'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "first", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "last", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } != nil
            insist { new_event.get("message") } == "first"
          end
        end
      end
      describe "with 'last'" do
        it "attaches info from last event in transaction" do
          config = {"attach_event" => 'last'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "first", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "last", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } != nil
            insist { new_event.get("message") } == "last"
          end
        end
      end
      describe "with 'oldest'" do
        it "attaches info from oldest event in transaction" do
          config = {"attach_event" => 'oldest'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "oldest", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "newest", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } != nil
            insist { new_event.get("message") } == "oldest"
          end
        end
      end
      describe "with 'newest'" do
        it "attaches info from newest event in transaction" do
          config = {"attach_event" => 'newest'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "oldest", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "newest", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } != nil
            insist { new_event.get("message") } == "newest"
          end
        end
      end
      describe "with 'none'" do
        it "attaches no info from any event in transaction" do
          config = {"attach_event" => 'none'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "oldest", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "newest", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } == nil
          end
        end
      end
      describe "with 'newest' when timestamps are equal" do
        it "attaches info from the first event in transaction" do
          config = {"attach_event" => 'newest'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "first", UID_FIELD => uid, "@timestamp" => "2019-01-23T09:46:22.000+0100"))
          @filter.filter(event("message" => "second", UID_FIELD => uid, "@timestamp" => "2019-01-23T09:46:22.000+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } == "first"
          end
        end
      end
      describe "with 'oldest' when timestamps are equal" do
        it "attaches info from the second event in transaction" do
          config = {"attach_event" => 'oldest'}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "first", UID_FIELD => uid, "@timestamp" => "2019-01-23T09:46:22.000+0100"))
          @filter.filter(event("message" => "second", UID_FIELD => uid, "@timestamp" => "2019-01-23T09:46:22.000+0100")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } == "second"
          end
        end
      end
    end
  end

  context "Testing store_data." do
    uid = "9ACCA7B7-D0E9-4E52-A023-9D588E5BE42C"
    describe "Config store_data_oldest" do
      it "attaches data from oldest event into transaction" do
        config = {"store_data_oldest" => ["datafield1"]}
        @config.merge!(config)

        @filter = LogStash::Filters::TransactionTime.new(@config)
        @filter.register

        @filter.filter(event("message" => "first", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100", "datafield1" => "OldestData"))
        @filter.filter(event("message" => "last", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100", "datafield1" => "NewestData")) do | new_event |
          insist { new_event } != nil
          insist { new_event.get("tags").include?("TransactionTime") }
          insist { new_event.get("message") } != nil
          insist { new_event.get("message") } == "first"
          insist { new_event.get("transaction_data") } != nil
          insist { new_event.get("transaction_data")["oldest"]["datafield1"] } != nil
          insist { new_event.get("transaction_data")["oldest"]["datafield1"] } == "OldestData"
        end
      end

      describe "and store_data_newest" do
        it "attaches data from both newest and oldest event into transaction" do
          config = {"store_data_newest" => ["datafield1"], "store_data_oldest" => ["datafield1"]}
          @config.merge!(config)

          @filter = LogStash::Filters::TransactionTime.new(@config)
          @filter.register

          @filter.filter(event("message" => "first", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100", "datafield1" => "OldestData"))
          @filter.filter(event("message" => "last", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100", "datafield1" => "NewestData")) do | new_event |
            insist { new_event } != nil
            insist { new_event.get("tags").include?("TransactionTime") }
            insist { new_event.get("message") } != nil
            insist { new_event.get("message") } == "first"
            insist { new_event.get("transaction_data") } != nil
            insist { new_event.get("transaction_data")["newest"]["datafield1"] } != nil
            insist { new_event.get("transaction_data")["newest"]["datafield1"] } == "NewestData"
            insist { new_event.get("transaction_data")["oldest"]["datafield1"] } != nil
            insist { new_event.get("transaction_data")["oldest"]["datafield1"] } == "OldestData"
          end
        end
      end
    end
  end
  context "Testing ignore_uids." do
    nokUid = "Erroneous UID"
    uid = "9ACCA7B7-D0E9-4E52-A023-9D588E5BE42C"
    describe "Config ignore_uids set" do
      it "will not accept events with specified uid as transactions" do
        config = {"ignore_uids" => ["Erroneous UID"]}
        @config.merge!(config)

        @filter = LogStash::Filters::TransactionTime.new(@config)
        @filter.register

        @filter.filter(event("message" => "first", UID_FIELD => nokUid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        @filter.filter(event("message" => "last", UID_FIELD => nokUid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
          insist { new_event } == nil
        end
      end
      it "will accept other events as transactions" do
        config = {"ignore_uids" => ["Erroneous UID"]}
        @config.merge!(config)

        @filter = LogStash::Filters::TransactionTime.new(@config)
        @filter.register

        @filter.filter(event("message" => "first", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
        @filter.filter(event("message" => "last", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.100+0100")) do | new_event |
          insist { new_event } != nil
        end
      end
    end
  end
end
