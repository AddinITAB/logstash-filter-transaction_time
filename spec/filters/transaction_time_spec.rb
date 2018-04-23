# encoding: utf-8
require_relative '../spec_helper'
require "logstash/filters/transaction_time"

describe LogStash::Filters::TransactionTime do
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

    sample("timestamp_tag" => "some text") do
      expect(subject).to include("timestamp_tag")
      expect(subject.get('timestamp_tag')).to eq('@timestamp')
    end

    sample("uid_field" => "some text") do
      expect(subject).to include("uid_field")
      expect(subject.get('uid_field')).to eq('uid')
    end
  end
end
