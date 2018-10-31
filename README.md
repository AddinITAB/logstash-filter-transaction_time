# About
This plugin is a substitute for the [logstash-filter-elapsed](https://www.elastic.co/guide/en/logstash/current/plugins-filters-elapsed.html) plugin. 
The elapsed-plugin requires a transaction to be executed in a specified order and then decorates the last part of the transaction (or creates a new event) with the elapsed time.
The order of which the parts of a transaction is received cannot always be predicted when using multiple workers for a pipeline.
Hence the need for this plugin.
This plugin, like elapsed, uses a unique identifier to pair events in a transaction.
But instead of defining a start and an end for a transaction - only the unique identifier is used. 
Per default the transaction time is stored together with the unique identifier in a new event, which may be stored in the same or another index.
The information from the first, last, oldest or newest event may be attached with the new transaction_time event.

# Usage

 The TransactionTime filter measures the time between two events in a transaction

 This filter is supposed to be used instead of logstash-filters-elapsed
 when you know that the order of a transaction cannot be guaranteed.
 Which is most likely the case if you are using multiple workers and 
 a big amount of events are entering the pipeline in a rapid manner.

 ## The configuration:
 ```ruby
     filter {
       transaction_time {
         uid_field => "Transaction-unique field"
         ignore_uid => []
         timeout => seconds
         timestamp_tag => "name of timestamp"
         replace_timestamp => ['keep', 'oldest', 'newest']
         filter_tag => "transaction tag"
         attach_event => ['first','last','oldest','newest','none']
         release_expired => [true,false]
         store_data_oldest => []
         store_data_newest => []
         periodic_flush => [true,false]
       }
     }
```
- `uid_field`
 The only required parameter is "uid_field" which is used to identify
 the events in a transaction. A transaction is concidered complete 
 when two events with the same UID has been captured. 
 It is when a transaction completes that the transaction time is calculated.

- `ignore_uid`
 The ignore_uid field takes an array of strings. These strings represent specific UIDs
 that should be ignored. This can be useful for ignoring parsing errors.
 Example: 
   ```ruby 
   ignore_uid => ["%{[transactionUID][0]}", ""] 
   ``` 
  Will ignore events having empty string or "%{[transactionUID][0]}" in the uid_field.
 
 - `timeout`
 The timeout parameter determines the maximum length of a transaction. 
 It is set to 300 (5 minutes) by default. 
 The transaction will not be recorded if timeout duration is exceeded.
 The value of this parameter will have an impact on the memory footprint of the plugin.

- `timestamp_tag`
 The timestamp_tag parameter may be used to select a specific field in the events to use
 when calculating the transaction time. The default field is @timestamp.
 
- `replace_timestamp`
  The new event created when a transaction completes may set its own timestamp 
 to when it completes  (default) or it may use the timestamp of one of the events in the transaction.
 The parameter replace_timestamp is used to specify this behaviour.

- `filter_tag`
 Since this plugin exclusivly calculates the time between events in a transaction,
 it may be wise to filter out the events that are infact not transactions.
 This will help reduce both the memory footprint and processing time of this plugin, 
 especially if the pipeline receives a lot of non-transactional events.
 You could use grok and/or mutate to apply this filter like this:
```ruby
     filter {
       grok{
         match => { "message" => "(?<message_type>.*)\t(?<msgbody>.*)\t+UID:%{UUID:uid}" }
       }
       if [message_type] in ["MaterialIdentified","Recipe","Result"."ReleaseMaterial"]{
         mutate {
           add_tag => "Transaction"
         }
       }
       transaction_time {
         uid_field => "UID"
         filter_tag => "Transaction"
       }
     }
```
  In the example, grok is used to identify the message_type and then the tag "transaction" is added for a specific set of messages. This tag is then used in the transaction_time as filter_tag.  Only the messages with this tag will be evaluated.
  > **Note**: Do not use reserved name "_TransactionTime_" which is added to all events created by this plugin

- `attach_event`
 The attach_event parameter can be used to append information from one of the events to the
 new transaction_time event. The default is to not attach anything. 
 The memory footprint is kept to a minimum by using the default value.

- `release_expired`
 The release_expired parameter determines if the first event in an expired transactions 
 should be released or not. Defaults to true

- `store_data_oldest/store_data_newest`
The parameters store_data_oldest and store_data_newest are both used in order to attach 
specific fields from oldest respectively newest event. An example of this could be:
 ```ruby
    store_data_oldest => ["@timestamp", "work_unit", "work_center", "message_type"]
    store_data_newest => ["@timestamp", "work_unit", "work_center", "message_type"]
 ```
  Which will result in the genereated transaction event inluding the specified fields from oldest and newest events in a hashmap named oldest/newest under the hash named "transaction_data"
  Example of output data:
 ```
 "transaction_data" => {
        "oldest" => {
            "message_type" => "MaterialIdentified",
              "@timestamp" => 2018-10-31T07:36:23.072Z,
               "work_unit" => "WT000743",
             "work_center" => "WR000046"
        },
        "newest" => {
            "message_type" => "Recipe",
              "@timestamp" => 2018-10-31T07:36:28.188Z,
               "work_unit" => "WT000743",
             "work_center" => "WR000046"
        }
    }
```

# Logstash Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## Documentation

Logstash provides infrastructure to automatically generate documentation for this plugin. We use the asciidoc format to write documentation so any comments in the source code will be first converted into asciidoc and then into html. All plugin documentation are placed under one [central location](http://www.elastic.co/guide/en/logstash/current/).

- For formatting code or config example, you can use the asciidoc `[source,ruby]` directive
- For more asciidoc formatting tips, see the excellent reference here https://github.com/elastic/docs#asciidoc-guide

## Need Help?

Need help? Try #logstash on freenode IRC or the https://discuss.elastic.co/c/logstash discussion forum.

## Developing

### 1. Plugin Developement and Testing

#### Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Create a new plugin or clone and existing from the GitHub [logstash-plugins](https://github.com/logstash-plugins) organization. We also provide [example plugins](https://github.com/logstash-plugins?query=example).

- Install dependencies
```sh
bundle install
```

#### Test

- Update your dependencies

```sh
bundle install
```

- Run tests

```sh
bundle exec rspec
```

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-filter-awesome", :path => "/your/local/logstash-filter-awesome"
```
- Install plugin
```sh
bin/logstash-plugin install --no-verify
```
- Run Logstash with your plugin
```sh
bin/logstash -e 'filter {awesome {}}'
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-filter-awesome.gemspec
```
- Install the plugin from the Logstash home
```sh
bin/logstash-plugin install /your/local/plugin/logstash-filter-awesome.gem
```
- Start Logstash and proceed to test the plugin

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elastic/logstash/blob/master/CONTRIBUTING.md) file.
