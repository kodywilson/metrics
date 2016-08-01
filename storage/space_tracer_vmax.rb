#!/usr/bin/env ruby
# Captures Vmax capacity metrics and sends to InfluxDB.
# rubocop:disable Metrics/LineLength

require 'csv'
require 'json'
require 'influxdb'
require 'nokogiri'

conf     = JSON.parse(File.read('/u01/app/prd/vmax_stats/vmax_stats.json'))
base_dir = conf['base_dir']
database = conf['database']
host     = conf['db_host']
username = conf['db_user']
password = Base64.decode64(conf['db_pass'])
measure  = 'capacity' # The metric

influxdb = InfluxDB::Client.new database, username: username,
                                          password: password,
                                          host: host

%w(1306 1765 1835).each do |ray|
  xmsmell = Nokogiri::XML(`/opt/emc/SYMCLI/bin/symcfg -sid #{ray} list -thin -gb -detail -gb -pool -output xml`)
  CSV.open("#{base_dir}/log_capacity/#{ray}_#{Time.now.strftime('%Y%m%d%H%M%S')}.csv", 'wb') do |csv|
    csv << xmsmell.at('Totals').search('*').map(&:name)
    xmsmell.search('Totals').each do |x|
      csv << x.search('*').map(&:text)
    end
  end
  tags = { array: ray, type: 'Vmax' }
  values = {}
  values['pct_used'] = xmsmell.search('Totals').search('percent_full').text.to_f.round(3)
  values['subs_percent'] = xmsmell.search('Totals').search('subs_percent').text.to_f.round(3)
  values['total_used_tb'] = xmsmell.search('Totals').search('total_used_tracks_tb').text.to_f.round(3)
  values['total_free_tb'] = xmsmell.search('Totals').search('total_free_tracks_tb').text.to_f.round(3)
  values['total_capacity_tb'] = xmsmell.search('Totals').search('total_usable_tracks_tb').text.to_f.round(3)
  data = {
    values: values,
    tags: tags
  }
  influxdb.write_point(measure, data)
  sleep(0.5)
end
