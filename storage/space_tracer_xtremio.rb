#!/usr/bin/env ruby
# Captures Xtremio capacity metrics and sends to InfluxDB.
# rubocop:disable Metrics/LineLength

require 'csv'
require 'json'
require 'influxdb'
require 'stoarray'

conf     = JSON.parse(File.read(File.join(File.dirname(__FILE__), "xtremio_stats.json")))
database = conf['database']
host     = conf['db_host']
username = conf['db_user']
password = Base64.decode64(conf['db_pass'])
measure  = 'capacity' # The metric

influxdb = InfluxDB::Client.new database, username: username,
                                          password: password,
                                          host: host

def kibi_to_tibi(metric)
  (metric.to_f / 1_073_741_824).round(3)
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
  values['data_reduction']    = (capacity['response']['content']['logical-space-in-use'].to_f / capacity['response']['content']['ud-ssd-space-in-use'].to_f).round(3)
  values['pct_used']          = ((capacity['response']['content']['ud-ssd-space-in-use'].to_f / capacity['response']['content']['ud-ssd-space'].to_f) * 100.00).round(3)
  values['total_free_tb']     = kibi_to_tibi(capacity['response']['content']['ud-ssd-space'].to_f - capacity['response']['content']['ud-ssd-space-in-use'].to_f)
  values['total_used_tb']     = kibi_to_tibi(capacity['response']['content']['ud-ssd-space-in-use'])
  values['total_capacity_tb'] = kibi_to_tibi(capacity['response']['content']['ud-ssd-space'])
  data = {
    values: values,
    tags: tags
  }
  influxdb.write_point(measure, data)
  sleep(0.1)
end
