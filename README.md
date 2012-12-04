Mobilize
========

Mobilize is an end-to-end data transfer workflow manager with:
* a Google Spreadsheets UI through [google-drive-ruby][google_drive_ruby];
* a queue manager through [Resque][resque];
* a persistent caching / database layer through [Mongoid][mongoid];
* gems for data transfers to/from Hive, mySQL, and HTTP endpoints
  (coming soon).

Mobilize-Base includes all the core scheduling and processing
functionality, allowing you to:
* put workers on the Mobilize Resque queue.
* create [Users](#section_Start_Users_User) and their associated Google Spreadsheet [Runners](#section_Start_Users_Runner);
* poll for [Jobs](#section_Job) on Runners (currently gsheet to gsheet only) and add them to Resque;
* monitor the status of Jobs on a rolling log.

Table Of Contents
-----------------
* [Overview](#section_Overview)
* [Install](#section_Install)
  * [Redis](#section_Install_Redis)
  * [MongoDB](#section_Install_MongoDB)
  * [Mobilize-Base](#section_Install_Mobilize-Base)
  * [Default Folders and Files](#section_Install_Folders_and_Files)
* [Configure](#section_Configure)
  * [Google Drive](#section_Configure_Google_Drive)
  * [Jobtracker](#section_Configure_Jobtracker)
  * [Mongoid](#section_Configure_Mongoid)
  * [Resque](#section_Configure_Resque)
* [Start](#section_Start)
  * [Start resque-web](#section_Start_Start_resque-web)
  * [Set Environment](#section_Start_Set_Environment)
  * [Create User](#section_Start_Create_User)
  * [Start Workers](#section_Start_Start_Workers)
  * [View Logs](#section_Start_View_Logs)
  * [Start Jobtracker](#section_Start_Start_Jobtracker)
  * [Create Job](#section_Start_Create_Job)
  * [Run Test](#section_Start_Run_Test)
* [Meta](#section_Meta)
* [Author](#section_Author)

<a name='section_Overview'></a>
Overview
-----------

* Mobilize is a script deployment and data visualization framework with
a Google Spreadsheets UI.
* Mobilize uses Resque for parallelization and queueuing, MongoDB for caching,
and Google Drive for hosting, user input and display.
* The [mobilize-ssh][mobilize-ssh] gem allows you to run scripts and
copy files between different machines, and have output directed to a
spreadsheet for viewing and processing.
* The platform is easily extensible: add your own rake tasks and
handlers by following a few simple conventions, and you can have your own
Mobilize gem up and running in no time.

<a name='section_Install'></a>
Install
------------

Mobilize requires Ruby 1.9.3, and has been tested on OSX and Ubuntu.

[RVM][rvm] is great for managing your rubies. 

<a name='section_Install_Redis'></a>
### Redis

Redis is a pre-requisite for running Resque. 

Please refer to the [Resque Redis Section][redis] for complete
instructions.

<a name='section_Install_MongoDB'></a>
### MongoDB

MongoDB is used to persist caches between reads and writes, keep track
of Users and Jobs, and store Datasets that map to endpoints.

Please refer to the [MongoDB Quickstart Page][mongodb_quickstart] to get started.

The settings for database and port are set in config/mongoid.yml
and are best left as default. Please refer to [Configure
Mongoid](#section_Configure_Mongoid) for details.

<a name='section_Install_Mobilize-Base'></a>
### Mobilize-Base

Mobilize-Base contains all of the gems it needs to run. 

add this to your Gemfile:

``` ruby
gem "mobilize-base", "~>1.0"
```

or do

  $ gem install mobilize-base

for a ruby-wide install.

<a name='section_Install_Folders_and_Files'></a>
### Folders and Files

Mobilize requires a config folder and a log folder. 

If you're on Rails, it will use the built-in config and log folders. 

Otherwise, it will use log and config folders in the project folder (the
same one that contains your Rakefile)

### Rakefile

Inside the Rakefile in your project's root folder, make sure you have:

``` ruby
require 'mobilize-base/rakes'
```

This defines rake tasks essential to run the environment.

### Config and Log Folders

run 

  $ rake mobilize_base:setup

Mobilize will create config/mobilize/ and log/ folders at the project root
level. (same as the Rakefile). 

(You can override these by passing
MOBILIZE_CONFIG_DIR and/or MOBILIZE_LOG_DIR arguments to the command.
All directories must end with a '/'.)

The script will also create samples for all required config files, which are detailed below.

Resque will create a mobilize-resque-`<environment>`.log in the log folder,
and loop over 10 files, 10MB each.

<a name='section_Configure'></a>
Configure
------------

All Mobilize configurations live in files in `config/mobilize/*.yml` by
default. Samples can
be found below or on github in the [lib/samples][git_samples] folder.

<a name='section_Configure_Google_Drive'></a>
### Configure Google Drive

gdrive.yml needs:
* a domain, which can be gmail.com but may be different depending on
your organization. All gdrive accounts should have
the same domain, and all Users should have emails in this domain.
* an owner name and password. You can set up separate owners
  for different environments as in the below file, which will keep your
mission critical workers from getting rate-limit errors.
* one or more admins with email attributes -- these will be for people
  who should be given write permissions to all Mobilize books in the
environment for maintenance purposes.
* one or more workers with name and pw attributes -- they will be used
  to queue up google reads and writes. This can be the same as the owner
account for testing purposes or low-volume environments. 

__Mobilize only allows one Resque
worker at a time to use a Google drive worker account for
reading/writing, which is called a gdrive_slot.__

Sample gdrive.yml:

``` yml
development:
  domain: 'host.com'
  owner:
    name: 'owner_development'
    pw: "google_drive_password"
  admins:
    - {name: 'admin'}
  workers:
    - {name: 'worker_development001', pw: "worker001_google_drive_password"}
    - {name: 'worker_development002', pw: "worker002_google_drive_password"}
test:
  domain: 'host.com'
  owner:
    name: 'owner_test'
    pw: "google_drive_password"
  admins:
    - {name: 'admin'}
  workers:
    - {name: 'worker_test001', pw: "worker001_google_drive_password"}
    - {name: 'worker_test002', pw: "worker002_google_drive_password"}
production:
  domain: 'host.com'
  owner:
    name: 'owner_production'
    pw: "google_drive_password"
  admins:
    - {name: 'admin'}
  workers:
    - {name: 'worker_production001', pw: "worker001_google_drive_password"}
    - {name: 'worker_production002', pw: "worker002_google_drive_password"}
```

<a name='section_Configure_Jobtracker'></a>
### Configure Jobtracker

The Jobtracker sits on your Resque and does 2 things:
* check for Users that are due for polling;
* send out notifications when:
  * there are failed jobs on Resque;
  * there are jobs on Resque that have run beyond the max run time.

Emails are sent using ActionMailer, through the owner Google Drive
account.

To this end, it needs these parameters, for which there is a sample
below and in the [lib/samples][git_samples] folder:

``` yml
development:
  cycle_freq: 10 #time between Jobtracker sweeps
  notification_freq: 3600 #1 hour between failure/timeout notifications
  runner_read_freq: 300 #5 min between runner reads
  max_run_time: 14400 # if a job runs for 4h+, notification will be sent
  admins: #emails to send notifications to
  - {'email': 'admin@host.com'}
test:
  cycle_freq: 10 #time between Jobtracker sweeps
  notification_freq: 3600 #1 hour between failure/timeout notifications
  runner_read_freq: 300 #5 min between runner reads
  max_run_time: 14400 # if a job runs for 4h+, notification will be sent
  admins: #emails to send notifications to
  - {'email': 'admin@host.com'}
production:
  cycle_freq: 10 #time between Jobtracker sweeps
  notification_freq: 3600 #1 hour between failure/timeout notifications
  runner_read_freq: 300 #5 min between runner reads
  max_run_time: 14400 # if a job runs for 4h+, notification will be sent
  admins: #emails to send notifications to
  - {'email': 'admin@host.com'}
```

<a name='section_Configure_Resque'></a>
### Configure Resque

Resque keeps track of Jobs, Workers and logging.

It needs the below parameters, which can be found in the [lib/samples][git_samples] folder. 

* queue_name - the name of the Resque queue where you would like the Jobtracker and Resque Workers to
  run. Default is mobilize.
* max_workers - the total number of simultaneous workers you would like
  on your queue. Default is 4 for development and test, 36 in
production, but feel free to adjust depending on your hardware.
* redis_port - you should probably leave this alone, it specifies the
  default port for dev and prod and a separate one for testing.

``` yml
development:
  queue_name: 'mobilize'
  max_workers: 4
  redis_port: 6379
test:
  queue_name: 'mobilize'
  max_workers: 4
  redis_port: 9736
production:
  queue_name: 'mobilize'
  max_workers: 36
  redis_port: 6379
```

<a name='section_Configure_Mongoid'></a>
### Configure Mongoid

Mongoid is the abstraction layer on top of MongoDB so we can interact
with it in an ActiveRecord-like fashion. 

It needs the below parameters, which can be found in the [lib/samples][git_samples] folder. 

You shouldn't need to change anything in this file.

``` yml
development:
  sessions:
    default:
      database: mobilize-development
      persist_in_safe_mode: true
      hosts:
        - 127.0.0.1:27017
test:
  sessions:
    default:
      database: mobilize-test
      persist_in_safe_mode: true
      hosts:
        - 127.0.0.1:27017
production:
  sessions:
    default:
      database: mobilize-production
      persist_in_safe_mode: true
      hosts:
        - 127.0.0.1:27017
```

<a name='section_Start'></a>
Start
-----

A Mobilize instance can be considered "started" or "running" when you have:

1. Resque workers running on the Mobilize queue;
2. A Jobtracker running on one of the Resque workers;
3. One or more Users created in your MongoDB;
4. One or more Jobs created in a User's Runner;

<a name='section_Start_Start_resque-web'></a>
### Start resque-web

To start resque-web, which is a kickass UI layer built in Sinatra,
you'll need to install the resque gem explicitly, as in

``` ruby
gem install resque
```

then, you can do 

  $ resque-web

and it'll start an instance on 127.0.0.1:5678

You'll want to keep an eye on this as it tracks your workers in real
time and allows you to keep track of failed jobs. More detail on the
[Resque Standalone section][resque-web].

<a name='section_Start_Set_Environment'></a>
### Set Environment

Mobilize takes the environment from your Rails.env if you're running
Rails, or assumes "development." You can specify "development", "test",
or "production," as per the yml files.

Otherwise, it takes it from MOBILIZE_ENV parameter, set from irb, as in:

``` ruby
> ENV['MOBILIZE_ENV'] = 'production'
> require 'mobilize-base'
```
This affects all parameters as set in the yml files, including the
database.

<a name='section_Start_Create_User'></a>
### Create User

Users are people who use the Mobilize service to move data from one
endpoint to another. They each have a Runner, which is a google sheet
that contains one or more Jobs.

To create a requestor, use the User.find_or_create_by_name
command in irb (replace the user with your own name, or any name
in your domain).

``` ruby
> User.find_or_create_by_name("user_name")
```

<a name='section_Start_Start_Workers'></a>
### Start Workers

Workers are rake tasks that load the Mobilize environment and allow the
processing of the Jobtracker, Users and Jobs.

These will start as many workers as are defined in your resque.yml.

To start workers, do:

``` ruby
> Jobtracker.prep_workers
```

if you have workers already running and would like to kill and refresh
them, do:

``` ruby
> Jobtracker.restart_workers!
```

Note that this will kill any workers on the Mobilize queue.

<a name='section_Start_View_Logs'></a>
### View Logs

at this point, you'll want to start viewing the logs for the Resque
workers -- they will be stored under your log folder. You can do:

  $ tail -f log/mobilize-`<environment>`.log

to view them.

<a name='section_Start_Start_Jobtracker'></a>
### Start Jobtracker

Once the Resque workers are running, and you have at least one User
set up, it's time to start the Jobtracker:

``` ruby
> Jobtracker.start
``` 

The Jobtracker will automatically enqueue any Users that have not
been processed in the requestor_refresh period defined in the
jobtracker.yml, and create their Runners if they do not exist. You can
see this process on your Resque UI and in the log file.

<a name='section_Start_Create_Job'></a>
### Create Job

Now it's time to go onto the Runner and add a Job to be processed.

To do this, you should log into your Google Drive with either the
owner's account, an admin account, or the Runner User's account. These
will be the accounts with edit permissions to a given Runner.

Navigate to the Jobs tab on the Runner `(denoted by Runner(<requestor
name>))` and enter values under each header:

* name	This is the name of the job you would like to add. Names must be unique across all your jobs, otherwise you will get an error
	
* active	set this to blank or FALSE if you want to turn off a job
	
* schedule	This uses human readable syntax to schedule jobs. It accepts the following:
  * every `<integer>` hour --	fire the job at increments of `<integer>` hours, minimum of 1 hour
  * every `<integer>` day	-- fire the job at increments of `<integer>` days, minimum of 1
  * every `<integer>` day after <HH:MM>	-- fire the job at increments of <integer> days, after HH:MM UTC time
  * every `<integer>` day_of_week after <HH:MM>	-- fire the job on specified day of week, after HH:MM UTC time; 1=Sunday
  * every `<integer>` day_of_month after <HH:MM> -- fire the job on specified day of month, after HH:MM UTC time
  * once -- fire the job once if active is set to TRUE, set active to FALSE right after
	* after `<jobname>` -- fire the job after the job named `<jobname>`

* status	Mobilize writes this field with the last status returned by the job

* last_error Mobilize writes any errors to this field, and wipes it if
  the job completes successfully.

* destination_url	Mobilize writes this field with a link to the last dataset returned by the job, blank if none
	
* tasks Comma-separated list of steps to be performed by the job. For
mobilize base, you can enter "gsheet.read, gsheet.write" (no quotes).
These

* datasets Comma-delimited list of datasets to be cached in mongo and
relayed to the job.
  For mobilize-base, the format is `<google docs book>/<google docs sheet>`, so if you
wanted to read from the "output" sheet on the "monthly_results" book you
would write in `monthly_results/output`. For a sheet in the Runner
itself you could write simply `output`.

* params This is a hash of data, expressed in a JSON, which can be used
for parameters.

* destination This is the destination for the data, relayed to the job.
  For gsheet.write, this would be the name of the sheet to be
written to, similar to datasets.

<a name='section_Start_Run_Test'></a>
### Run Test

To run tests, you will need to 

1) clone the repository 

From the project folder, run

2) rake mobilize_base:setup

and populate the "test" environment in the config files with the
necessary details.

3) $ rake test

This will create a test Runner with a sample job. These will run off a
test redis instance which will be killed once the tests finish.

<a name='section_Meta'></a>
Meta
----

* Code: `git clone git://github.com/ngmoco/mobilize-base.git`
* Home: <https://github.com/ngmoco/mobilize-base>
* Bugs: <https://github.com/ngmoco/mobilize-base/issues>
* Gems: <http://rubygems.org/gems/mobilize-base>

<a name='section_Author'></a>
Author
------

Cassio Paes-Leme :: cpaesleme@ngmoco.com :: @cpaesleme

<a name='section_Special_Thanks'></a>
Special Thanks
--------------

* Al Thompson and Sagar Mehta for awesome design advice and discussions
* Elliott Clark for enlightening me to the wonders of Resque
* Bob Colner for pointing me to google-drive-ruby when I tried to
reinvent the wheel
* ngmoco:) and DeNA Global for supporting and adopting the Mobilize
platform
* gimite, defunkt, 10gen, and countless other github heroes

[google_drive_ruby]: https://github.com/gimite/google-drive-ruby
[resque]: https://github.com/defunkt/resque
[mongoid]: http://mongoid.org/en/mongoid/index.html
[resque_redis]: https://github.com/defunkt/resque#section_Installing_Redis
[mongodb_quickstart]: http://www.mongodb.org/display/DOCS/Quickstart
[git_samples]: https://github.ngmoco.com/Ngpipes/mobilize-base/tree/master/lib/samples
[rvm]: https://rvm.io/
[resque-web]: https://github.com/defunkt/resque#standalone
[mobilize-ssh]: https://github.com/ngmoco/mobilize-ssh
