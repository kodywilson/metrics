#!/usr/bin/env ruby
# Processes csv files containing historical Pure array capacity data.

require 'csv'
require 'json'
require 'influxdb'

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

def bytes_to_tb(metric) # Pure reports capacity in bytes
  (metric.to_f / 1_099_511_627_776).round(3)
end

count = 0
Dir.glob("#{base_dir}log_capacity/*.csv") do |file|
  # break if count == 20000 #uncomment to restrict number of files processed
  if File.zero?(file) # Ignore empty files and move them to "bad" directory
    puts
    puts 'Empty, moving to bad directory, file: ' + file
    puts
    File.rename(file, "#{base_dir}bad/#{File.basename(file)}.empty")
    next
  end
  timey = DateTime.parse(File.basename(file)[/_(.*)\./, 1]).strftime('%s')
  ray   = File.basename(file)[/^(.*)_/, 1]
  case ray.downcase
  when /^sa0\d{3}ps\d{2}/
    tags = { array: ray, type: 'Pure' }
  when /^sa0\d{3}xms\d{2}/
    tags = { array: ray, type: 'Xtremio' }
  when /^1306/, /^1765/, /^1835/
    tags = { array: ray, type: 'Vmax' }
  end
  values = {}
  CSV.foreach(file) do |row|
    values[row[0]] = row[1]
  end
  x = values['total'].to_f / values['capacity'].to_f
  values['pct_used'] = (x * 100.00).round(3)
  %w(capacity system snapshots volumes total shared_space).each do |metric|
    values[metric] = bytes_to_tb(values[metric])
  end
  %w(data_reduction thin_provisioning total_reduction).each do |metric|
    values[metric] = values[metric].to_f.round(3)
  end
  data = {
    values: values,
    tags: tags,
    timestamp: timey
  }
  begin
    influxdb.write_point(measure, data)
  rescue
    puts
    puts 'Unable to push to database, moving to bad directory, file: ' + file
    puts
    File.rename(file, "#{base_dir}bad/#{File.basename(file)}.dbad")
    next
  end
  sleep(0.5)
  File.rename(file, "#{base_dir}old/#{File.basename(file)}")
  count += 1
  print count.to_s + '.'
end
puts
puts 'Processed ' + count.to_s + ' files.'
