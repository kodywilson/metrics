#!/usr/bin/env ruby
# Captures Pure performance metrics and sends to InfluxDB.
# rubocop:disable Metrics/LineLength

require 'csv'
require 'json'
require 'influxdb'
require 'stoarray'

conf     = JSON.parse(File.read('pure_stats.json'))
database = conf['database']
host     = conf['db_host']
username = conf['db_user']
password = Base64.decode64(conf['db_pass'])
measure  = 'performance' # The metric

influxdb = InfluxDB::Client.new database, username: username,
                                          password: password,
                                          host: host

def bytes_to_mb(metric)
  metric.to_i / 1_048_576
end

def micro_to_milli(metric)
  (metric.to_f / 1000).round(3)
end

p_conf['arrays'].each do |ray, key|
  base_url = 'https://' + ray + '.nordstrom.net/api/1.4/'
  p_url     = base_url + 'auth/session'
  p_headers = p_conf['headers']
  token     = Base64.decode64(key)
  params    = { api_token: token }
  cookies   = Stoarray.new(headers: p_headers, meth: 'Post', params: params, url: p_url).cookie
  p_headers['Cookie'] = cookies
  p_url = base_url + 'array?action=monitor'
  pstat = Stoarray.new(headers: p_headers, meth: 'Get', params: {}, url: p_url).array
  tags = { array: ray, type: 'Pure' }
  values = pstat['response'][0]
  %w(output_per_sec input_per_sec).each do |metric|
    values[metric] = bytes_to_mb(values[metric])
  end
  %w(usec_per_write_op usec_per_read_op).each do |metric|
    values[metric] = micro_to_milli(values[metric])
  end
  %w(writes_per_sec reads_per_sec queue_depth).each do |metric|
    values[metric] = values[metric].to_i
  end
  values.delete('time') # Removing timestamp and changing usec to ms
  values['ms_per_write_op']    = values.delete('usec_per_write_op')
  values['ms_per_read_op']     = values.delete('usec_per_read_op')
  data = {
    values: values,
    tags: tags
  }
  influxdb.write_point(measure, data)
  sleep(0.5)
end
