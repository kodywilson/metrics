#!/usr/bin/env ruby
# Captures Pure capacity metrics and sends to InfluxDB.
# rubocop:disable Metrics/LineLength

require 'csv'
require 'json'
require 'influxdb'
require 'stoarray'

conf     = JSON.parse(File.read('/u01/app/prd/pure_stats/pure_stats.json'))
base_dir = conf['base_dir']
database = conf['database']
host     = conf['db_host']
username = conf['db_user']
password = Base64.decode64(conf['db_pass'])
measure  = 'capacity' # The metric

influxdb = InfluxDB::Client.new database, username: username,
                                          password: password,
                                          host: host

def bytes_to_tb(metric)
  (metric.to_f / 1_099_511_627_776).round(3)
end

conf['arrays'].each do |ray, key|
  base_url = 'https://' + ray + '.nordstrom.net/api/1.4/'
  p_url     = base_url + 'auth/session'
  p_headers = conf['headers']
  token     = Base64.decode64(key)
  params    = { api_token: token }
  cookies   = Stoarray.new(headers: p_headers, meth: 'Post', params: params, url: p_url).cookie
  p_headers['Cookie'] = cookies
  p_url = base_url + 'array?space=true'
  astat = Stoarray.new(headers: p_headers, meth: 'Get', params: {}, url: p_url).array
  CSV.open("#{base_dir}log_capacity/#{ray}_#{Time.now.strftime('%Y%m%d%H%M%S')}.csv", 'wb') { |csv| astat['response'].to_a.each { |elem| csv << elem } }
  tags = { array: ray, type: 'Pure' }
  values = {}
  astat['response'].to_a.each do |row|
    values[row[0]] = row[1]
  end
  values['pct_used'] = ((values['total'].to_f / values['capacity'].to_f) * 100.00).round(3)
  %w(capacity system snapshots volumes total shared_space ).each do |metric|
    values[metric] = bytes_to_tb(values[metric])
  end
  %w(data_reduction thin_provisioning total_reduction).each do |metric|
    values[metric] = values[metric].to_f.round(3)
  end
  values['total_used_tb']     = values['total']
  values['total_free_tb']     = (values['capacity'] - values['total']).round(3)
  values['total_capacity_tb'] = values['capacity']
  data = {
    values: values,
    tags: tags
  }
  influxdb.write_point(measure, data)
  sleep(0.1)
end
