# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/transaction_time"

describe LogStash::Filters::TransactionTime do
  UID_FIELD = "uniqueIdField"


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

    sample("uid_field" => "some text") do
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
    @config = {"uid_field" => UID_FIELD}
    @config.merge!(config)
    @filter = LogStash::Filters::TransactionTime.new(@config)
    @filter.register
  end

  context "Testing Hash with UID" do
    describe "Receiving" do
      uid = "D7AF37D9-4F7F-4EFC-B481-06F65F75E8C0"
      uid2 = "5DE49829-5CD3-4103-8062-781AC63BE4F5"
      describe "one event" do
        it "records the transaction" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          #insist { @filter.events[uid] } == "HEJ"
          insist { @filter.transactions.size } == 1
          insist { @filter.transactions[uid].a } != nil
          insist { @filter.transactions[uid].b } == nil
        end
      end
      describe "and events with the same UID" do
        it "there is still one transaction" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          insist { @filter.transactions.size } == 1
          insist { @filter.transactions[uid].a } != nil
          insist { @filter.transactions[uid].b } != nil
        end
      end
      describe "and events with different UID" do
        it "there is now two transaction" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid2))
          insist { @filter.transactions.size } == 2
          insist { @filter.transactions[uid].a } != nil
          insist { @filter.transactions[uid].b } == nil
          insist { @filter.transactions[uid2].a } != nil
          insist { @filter.transactions[uid2].b } == nil
        end
      end
    end
  end

  context "Testing TransactionTime" do
    describe "Receiving" do
      uid = "D7AF37D9-4F7F-4EFC-B481-06F65F75E8CC"
      describe "two events with the same UID in cronological order" do
        it "the TransactionTime have been calculated with second presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          insist { @filter.transactions.size } == 1
          insist { @filter.transactions[uid].a } != nil
          insist { @filter.transactions[uid].b } != nil
          insist { @filter.transactions[uid].diff } == 1.0
        end
        it "the TransactionTime have been calculated with ms presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.001+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          insist { @filter.transactions.size } == 1
          insist { @filter.transactions[uid].a } != nil
          insist { @filter.transactions[uid].b } != nil
          insist { @filter.transactions[uid].diff } == 0.999
        end
      end
      describe "two events with the same UID in REVERSED cronological order" do
        it "the TransactionTime have been calculated with second presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.000+0100"))
          insist { @filter.transactions.size } == 1
          insist { @filter.transactions[uid].a } != nil
          insist { @filter.transactions[uid].b } != nil
          insist { @filter.transactions[uid].diff } == 1.0
        end
        it "the TransactionTime have been calculated with ms presicion" do
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:22.000+0100"))
          @filter.filter(event("message" => "Log message", UID_FIELD => uid, "@timestamp" => "2018-04-22T09:46:21.001+0100"))
          insist { @filter.transactions.size } == 1
          insist { @filter.transactions[uid].a } != nil
          insist { @filter.transactions[uid].b } != nil
          insist { @filter.transactions[uid].diff } == 0.999
        end
      end
    end
  end
end
