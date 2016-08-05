#!/usr/bin/env ruby
# Captures Vmax performance metrics and sends to InfluxDB.
# Some code is from Craig Smith's VMAX-Graphite repo, link below:
# https://github.com/nctiggy/VMAX-Graphite/blob/master/collector.rb
# rubocop:disable Metrics/LineLength

require 'crack'
require 'influxdb'
require 'json'
require 'open3'
require 'stoarray'
require 'rest-client'

conf     = JSON.parse(File.read(File.join(File.dirname(__FILE__), "vmax_stats.json")))
database = conf['database']
host     = conf['db_host']
username = conf['db_user']
password = Base64.decode64(conf['db_pass'])
measure  = 'performance' # The metric

influxdb = InfluxDB::Client.new database, username: username,
                                          password: password,
                                          host: host

# Begin code from Craig Smith's VMAX-Graphite
####################################################################################
# Method: Read's the Unisphere XSD file and gets all Metrics for the specified scope
####################################################################################
def get_metrics(param_type,xsd)
  output = Array.new
  JSON.parse(xsd)['xs:schema']['xs:simpleType'].each do |type|
    if type['name'] == "#{param_type}Metric"
      type['xs:restriction']['xs:enumeration'].each do |metric|
        output.push(metric['value']) if metric['value'] == metric['value'].upcase
      end
    end
  end
  return output
end

#####################################
# Method: Reutrns keys for all scopes
#####################################
def get_keys(unisphere,payload,monitor,auth)
  if monitor['scope'].downcase == "array"
    rest = rest_get("https://#{unisphere['ip']}:#{unisphere['port']}/univmax/restapi/performance/#{monitor['scope']}/keys", auth)
  else
    rest = rest_post(payload.to_json,"https://#{unisphere['ip']}:#{unisphere['port']}/univmax/restapi/performance/#{monitor['scope']}/keys", auth)
  end
  componentId = get_component_id_payload(monitor['scope'])
  output = rest["#{componentId}Info"]
  return output
end

##################################################
# Method: Find differences in the key payload
##################################################
def diff_key_payload(incoming_payload,parent_id=nil)
  baseline_keys=["firstAvailableDate","lastAvailableDate"]
  incoming_keys=incoming_payload.keys
  return incoming_keys-baseline_keys
end

##################################################
# Method: Build the Key Payload
##################################################
def build_key_payload(unisphere,symmetrix,monitor,key=nil,parent_id=nil)
  payload = { "symmetrixId" => symmetrix['sid']}
  extra_payload = {parent_id[0] => key[parent_id[0]]} if parent_id
  payload.merge!(extra_payload) if parent_id
  return payload
end

##################################################
# Method: Build the Metric Payload
##################################################
def build_metric_payload(unisphere,monitor,symmetrix,metrics,key=nil,parent_id=nil,child_key=nil,child_id=nil)
  payload = { "symmetrixId" => symmetrix['sid'], "metrics" => metrics}
  parent_payload = { parent_id[0] => key[parent_id[0]] } unless monitor['scope'] == "Array"
  payload.merge!(parent_payload) unless monitor['scope'] == "Array"
  child_payload = { child_id[0] => child_key[child_id[0]], "startDate" => child_key['lastAvailableDate'], "endDate" => child_key['lastAvailableDate'] } if child_key
  payload.merge!(child_payload) if child_key
  timestamp_payload = { "startDate" => key['lastAvailableDate'], "endDate" => key['lastAvailableDate'] } unless child_key
  payload.merge!(timestamp_payload) unless child_key
  uni8_payload = { "dataFormat" => "Average" }
  payload.merge!(uni8_payload)
  return payload
end

################################################################################
# Method: Returns Metrics for all component scopes. Helper for building payloads
################################################################################
def get_perf_metrics(unisphere,payload,monitor,auth)
  rest = rest_post(payload.to_json,"https://#{unisphere['ip']}:#{unisphere['port']}/univmax/restapi/performance/#{monitor['scope']}/metrics", auth)
  output = rest['resultList']['result'][0]
  return output
end

#########################
# Method: API Post Method
#########################
def rest_post(payload, api_url, auth, cert=nil)
  JSON.parse(RestClient::Request.execute(
    method: :post,
    url: api_url,
    verify_ssl: false,
    payload: payload,
    headers: {
      authorization: auth,
      content_type: 'application/json',
      accept: :json
    }
  ))
end

##################################################################################
# Method: To correctly format scope for JSON
##################################################################################
def get_component_id_payload(scope)
  s = scope.split /(?=[A-Z])/
  i = 0
  if s[-1].capitalize == "Pool"
    new_scope = "pool"
  else
    while i < s.length
      s[i] = s[i].downcase if s[i] == s[i].upcase
      s[i] = s[i].downcase if i == 0 && s[i] == s[i].capitalize
      i += 1
    end
    new_scope = s.join
  end
  return new_scope
end

########################
# Method: API GET Method
########################
def rest_get(api_url, auth, cert=nil)
  JSON.parse(RestClient::Request.execute(method: :get,
    url: api_url,
    verify_ssl: false,
    headers: {
      authorization: auth,
      accept: :json
    }
  ))
end

conf['unisphere'].each do |unisphere|
  ## Read the appropriate XSD file based on unisphere version ##
  myparams = Crack::XML.parse(File.read(File.join(File.dirname(__FILE__), "unisphere#{unisphere['version']}.xsd"))).to_json
  ## Build the Base64 auth string ##
  auth = Base64.strict_encode64("#{unisphere['user']}:#{unisphere['password']}")
  ## Loop through each symmetrix in the current unisphere ##
  unisphere['symmetrix'].each do |symmetrix|
    output_payload = {}
    ## Loop through each component on the current symmetrix ##
    conf['monitor'].each do |monitor|
      ## If the component is not enabled i.e. false then skip. If the parent is false it will skip the children ##
      next unless monitor['enabled']
      metrics_param = get_metrics(monitor['scope'],myparams)
      key_payload = build_key_payload(unisphere,symmetrix,monitor)
      keys = get_keys(unisphere,key_payload,monitor,auth)
      keys.each do |key|
        parent_ids = diff_key_payload(key)
        if monitor.key?("children")
          if monitor['children'][0]['enabled']
            child_payload = build_key_payload(unisphere,symmetrix,monitor['children'][0],key,parent_ids)
            child_keys = get_keys(unisphere,child_payload,monitor['children'][0],auth)
            child_keys.each do |child_key|
              child_ids = diff_key_payload(child_key)
              metrics_param = get_metrics(monitor['children'][0]['scope'],myparams)
              metric_payload = build_metric_payload(unisphere,monitor,symmetrix,metrics_param,key,parent_ids,child_key,child_ids)
              metrics = get_perf_metrics(unisphere,metric_payload,monitor['children'][0],auth)
              metrics_param.each do |metric|
                output_payload[(conf['graphite']['prefix'] ? "#{conf['graphite']['prefix']}." : "") + "symmetrix.#{symmetrix['sid']}.#{monitor['scope']}.#{key[parent_ids[0]]}.#{child_key[child_ids[0]]}.#{metric}"] = metrics[metric]
              end
            end
          end
        end
        if (monitor['scope'] != "Array") || (monitor['scope'] == "Array" && key['symmetrixId'] == symmetrix['sid'])
          metrics_param = get_metrics(monitor['scope'],myparams)
          metric_payload = build_metric_payload(unisphere,monitor,symmetrix,metrics_param,key,parent_ids)
          metrics = get_perf_metrics(unisphere,metric_payload,monitor,auth)
          metrics_param.each do |metric|
            output_payload[metric] = metrics[metric] if monitor['scope'] == "Array"
            output_payload[(conf['graphite']['prefix'] ? "#{conf['graphite']['prefix']}." : "") + "symmetrix.#{symmetrix['sid']}.#{monitor['scope']}.#{key[parent_ids[0]]}.#{metric}"] = metrics[metric] unless monitor['scope'] == "Array"
          end
        end
      end
    end
    # End of code from Craig Smith's VMAX-Graphite. Thank you sir!
    values = {}
    tags = { array: symmetrix['sid'][-4..-1], type: 'Vmax' }
    values['writes_per_sec']  = output_payload['WRITES'].to_f.round(3)
    values['reads_per_sec']   = output_payload['READS'].to_f.round(3)
    values['ms_per_read_op']  = output_payload['RESPONSE_TIME_READ'].to_f.round(3)
    values['ms_per_write_op'] = output_payload['RESPONSE_TIME_WRITE'].to_f.round(3)
    values['input_per_sec']   = output_payload['MB_WRITE_PER_SEC'].to_f.round(3)
    values['output_per_sec']  = output_payload['MB_READ_PER_SEC'].to_f.round(3)
    values['pct_cache_used']  = output_payload['TOTAL_CACHE_UTILIZATION'].to_f.round(3)
    data = {
      values: values,
      tags: tags
    }
    influxdb.write_point(measure, data)
    sleep(0.1)
  end
end
