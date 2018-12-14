#!/bin/bash
rm -f logstash-filter-transaction_time-1.0.6.gem &&
bundle exec rspec &&
gem build logstash-filter-transaction_time &&
cp logstash-filter-transaction_time-1.0.6.gem /home/twelleby/dev/docker/ELK/logstash &&
cd /home/twelleby/dev/docker/ELK &&
docker-compose up -d --build logstash
#docker restart logstash &&
#docker logs -f logstash
