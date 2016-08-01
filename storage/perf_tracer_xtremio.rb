#!/usr/bin/env ruby
# Captures Xtremio performance metrics and sends to InfluxDB.
# rubocop:disable Metrics/LineLength

require 'csv'
require 'json'
require 'influxdb'
require 'stoarray'

conf     = JSON.parse(File.read("/u01/app/prd/xtm_stats/xtremio_stats.json"))
database = conf['database']
host     = conf['db_host']
username = conf['db_user']
password = Base64.decode64(conf['db_pass'])
measure  = 'performance' # The metric

influxdb = InfluxDB::Client.new database, username: username,
                                          password: password,
                                          host: host

def kibibytes_to_mb(metric)
  metric.to_i / 1_024
end

def micro_to_milli(metric)
  (metric.to_f / 1000).round(3)
end

conf['arrays'].each do |key, val|
  base_url = 'https://' + key + '.nordstrom.net/api/json/v2/types/'
  headers = conf['headers']
  headers['authorization'] = val
  ray = key.sub('xms', 'xtm')
  url = base_url + 'clusters?name=' + ray
  capacity = Stoarray.new(headers: headers, meth: 'Get', params: {}, url: url).array
  tags = { array: ray, type: 'Xtremio' }
  values = {}
  values['writes_per_sec'] = capacity['response']['content']['wr-iops'].to_f.round(3)
  values['reads_per_sec'] = capacity['response']['content']['rd-iops'].to_f.round(3)
  values['ms_per_read_op'] = micro_to_milli(capacity['response']['content']['rd-latency'])
  values['ms_per_write_op'] = micro_to_milli(capacity['response']['content']['wr-latency'])
  values['input_per_sec'] = kibibytes_to_mb(capacity['response']['content']['wr-bw'])
  values['output_per_sec'] = kibibytes_to_mb(capacity['response']['content']['rd-bw'])
  data = {
    values: values,
    tags: tags
  }
  puts
  puts data
  puts
  influxdb.write_point(measure, data)
  sleep(0.5)
end
