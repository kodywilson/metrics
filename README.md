metrics
========

Scripts for gathering infrastructure metrics.

Please see https://confluence.nordstrom.net/display/UCG/Metrics for more info.

## Installation
Clone the repo, create reasonable json files, install required gems.

```sh
git clone https://git.nordstrom.net/scm/ucg/metrics.git
cd metrics
vim pure_stats.json
gem install stoarray influxdb
```

## Usage
space_tracer_xxxxxx.rb - captures capacity metrics
perf_tracer_xxxxxx.rb  - captures performance metrics

Test the scripts, put in cron. Comment out the csv and db writes for testing.
We run the perf scripts every minute and capacity every 30 minutes.

```sh
sudo crontab -e
```

### Example cron entries

```sh
# Gather stats from storage arrays
*/30 * * * * /opt/chef/embedded/bin/ruby /u01/app/prd/pure_stats/space_tracer_pure.rb > /dev/null 2>&1
*/30 * * * * /opt/chef/embedded/bin/ruby /u01/app/prd/vmax_stats/space_tracer_vmax.rb > /dev/null 2>&1
*/1 * * * * /opt/chef/embedded/bin/ruby /u01/app/prd/pure_stats/perf_tracer_pure.rb > /dev/null 2>&1
```

## JSON configuration file examples
---------------------------

### Pure:
```json
    {
      "base_dir": "/u01/app/prd/pure_stats/",
      "database": "nameofyourdatabase",
      "db_host": "databasehost.nordstrom.net",
      "db_user": "putdatabaseuserhere",
      "db_pass": "base64encodeddatabaseuserspassword",
      "headers": { "Content-Type": "application/json" },
      "arrays": {
        "array01": "BASE64ENDCODEDPUREAPITOKEN4ARRAY01XXXXXXXXXXXXXX",
        "array02": "BASE64ENDCODEDPUREAPITOKEN4ARRAY02XXXXXXXXXXXXXX",
        "array03": "BASE64ENDCODEDPUREAPITOKEN4ARRAY03XXXXXXXXXXXXXX",
        "array04": "BASE64ENDCODEDPUREAPITOKEN4ARRAY04XXXXXXXXXXXXXX"
      }
    }
```

+ base_dir - Directory to start in.
+ database - Name of the database you are connecting.
+ db_host  - Fully qualified host name of database server.
+ db_user  - Database user.
+ db_pass  - Database user's password.
+ arrays   - Name of array with base64 encoded token.

### Vmax:
```json
    {
      "base_dir": "/u01/app/prd/vmax_stats/",
      "database": "nameofyourdatabase",
      "db_host": "databasehost.nordstrom.net",
      "db_user": "putdatabaseuserhere",
      "db_pass": "base64encodeddatabaseuserspassword",
      "headers": { "Content-Type": "application/json" }
    }
```

### Xtremio:
```json
    {
      "base_dir": "/u01/app/prd/xtremio_stats/",
      "database": "nameofyourdatabase",
      "db_host": "databasehost.nordstrom.net",
      "db_user": "putdatabaseuserhere",
      "db_pass": "base64encodeddatabaseuserspassword",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      "arrays": {
        "xtremio01": "Basic base64encodeuser:passforxtremio01",
        "xtremio02": "Basic base64encodeuser:passforxtremio02",
        "xtremio03": "Basic base64encodeuser:passforxtremio03"
      }
    }
```

## Troubleshooting

Nothing to mention yet.

## Development

Clone, hack, submit a pull request!

## Contributing

Bug reports and pull requests are welcome on Stash at https://git.nordstrom.net/scm/ucg/metrics.git. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The scripts are available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
